import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'store.dart';

/// Local-network sync.
///
/// One device (usually the desktop) is the **hub**: it runs a tiny HTTP server
/// and holds the merged copy. Other devices are **clients**: they POST their
/// full data to the hub, the hub merges (last-writer-wins per item) and replies
/// with the merged result, which the client merges back. Clients find the hub
/// with a UDP broadcast and authenticate with a 6-digit pairing code.
enum SyncMode { off, hub, client }

class DiscoveredHub {
  final String name;
  final String address; // host:port
  const DiscoveredHub(this.name, this.address);
}

const int kSyncPort = 47821;
const int kDiscoveryPort = 47822;
const _discoverMsg = 'HLIST_DISCOVER';
const _herePrefix = 'HLIST_HERE|';

const _modeKey = 'h_list_sync_mode';
const _hubAddrKey = 'h_list_sync_hub';
const _clientKeyKey = 'h_list_sync_key';
const _pairCodeKey = 'h_list_sync_pair_code';

class SyncService extends ChangeNotifier {
  SyncService(this.store, this._prefs);

  final AppStore store;
  final SharedPreferences _prefs;

  SyncMode mode = SyncMode.off;

  // Hub state
  HttpServer? _server;
  RawDatagramSocket? _udp;
  late String pairCode;
  List<String> localAddresses = [];
  int? get hubPort => _server?.port;
  final Map<String, DateTime> connectedClients = {};

  // Client state
  String? hubAddress;
  String? clientKey;
  Timer? _pollTimer;
  Timer? _debounce;
  Future<void>? _inflight;
  int _pushedRevision = -1;

  // Shared status
  DateTime? lastSyncAt;
  String? lastError;

  String get deviceName {
    try {
      return Platform.localHostname;
    } catch (_) {
      return 'H List device';
    }
  }

  static bool get isDesktop => !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  Future<void> init() async {
    pairCode = _prefs.getString(_pairCodeKey) ?? _generateCode();
    _prefs.setString(_pairCodeKey, pairCode);
    hubAddress = _prefs.getString(_hubAddrKey);
    clientKey = _prefs.getString(_clientKeyKey);
    final saved = _prefs.getString(_modeKey);
    final initial = SyncMode.values.firstWhere((m) => m.name == saved, orElse: () => SyncMode.off);
    store.addListener(_onStoreChanged);
    await setMode(initial, persist: false);
  }

  String _generateCode() => (Random.secure().nextInt(900000) + 100000).toString();

  Future<void> regeneratePairCode() async {
    pairCode = _generateCode();
    await _prefs.setString(_pairCodeKey, pairCode);
    notifyListeners();
  }

  Future<void> setMode(SyncMode m, {bool persist = true}) async {
    await _stopHub();
    _stopClient();
    mode = m;
    lastError = null;
    if (persist) await _prefs.setString(_modeKey, m.name);
    if (m == SyncMode.hub) await _startHub();
    if (m == SyncMode.client) _startClient();
    notifyListeners();
  }

  @override
  void dispose() {
    store.removeListener(_onStoreChanged);
    _stopHub();
    _stopClient();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Hub
  // ---------------------------------------------------------------------------

  Future<void> _startHub() async {
    for (var port = kSyncPort; port < kSyncPort + 5; port++) {
      try {
        _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
        break;
      } catch (_) {}
    }
    if (_server == null) {
      lastError = 'Could not open a sync port ($kSyncPort–${kSyncPort + 4}).';
      return;
    }
    _server!.listen(_handleRequest, onError: (e) => debugPrint('H List hub: $e'));

    try {
      _udp = await RawDatagramSocket.bind(InternetAddress.anyIPv4, kDiscoveryPort);
      _udp!.listen((event) {
        if (event != RawSocketEvent.read) return;
        final dg = _udp?.receive();
        if (dg == null) return;
        if (utf8.decode(dg.data, allowMalformed: true).trim() == _discoverMsg) {
          final reply = utf8.encode('$_herePrefix$deviceName|${_server!.port}');
          _udp?.send(reply, dg.address, dg.port);
        }
      });
    } catch (e) {
      debugPrint('H List hub: discovery unavailable: $e');
    }

    localAddresses = await _localIPv4s();
  }

  Future<void> _stopHub() async {
    await _server?.close(force: true);
    _server = null;
    _udp?.close();
    _udp = null;
    connectedClients.clear();
  }

  Future<void> _handleRequest(HttpRequest req) async {
    final res = req.response;
    res.headers.contentType = ContentType.json;
    try {
      if (req.method == 'GET' && req.uri.path == '/ping') {
        res.write(jsonEncode({'app': 'hlist', 'name': deviceName}));
      } else if (req.method == 'POST' && req.uri.path == '/sync') {
        if (req.headers.value('x-hlist-key') != pairCode) {
          res.statusCode = HttpStatus.unauthorized;
          res.write(jsonEncode({'error': 'bad pairing code'}));
        } else {
          final body = await utf8.decoder.bind(req).join();
          final json = jsonDecode(body) as Map<String, dynamic>;
          store.applyRemote(SyncData.fromJson(json['data'] as Map<String, dynamic>));
          final who = json['device']?.toString() ?? req.connectionInfo?.remoteAddress.address ?? '?';
          connectedClients[who] = DateTime.now();
          lastSyncAt = DateTime.now();
          res.write(jsonEncode({'data': store.data.toJson()}));
          notifyListeners();
        }
      } else {
        res.statusCode = HttpStatus.notFound;
      }
    } catch (e) {
      res.statusCode = HttpStatus.badRequest;
      res.write(jsonEncode({'error': e.toString()}));
    }
    await res.close();
  }

  static Future<List<String>> _localIPv4s() async {
    try {
      final ifaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      return [
        for (final i in ifaces)
          for (final a in i.addresses)
            if (!a.isLoopback && !a.address.startsWith('169.254')) a.address,
      ];
    } catch (_) {
      return [];
    }
  }

  // ---------------------------------------------------------------------------
  // Client
  // ---------------------------------------------------------------------------

  void _startClient() {
    _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) => syncNow());
    syncNow();
  }

  void _stopClient() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _debounce?.cancel();
  }

  Future<void> connectTo(String address, String key) async {
    hubAddress = address.contains(':') ? address.trim() : '${address.trim()}:$kSyncPort';
    clientKey = key.trim();
    await _prefs.setString(_hubAddrKey, hubAddress!);
    await _prefs.setString(_clientKeyKey, clientKey!);
    await setMode(SyncMode.client);
  }

  void _onStoreChanged() {
    if (mode != SyncMode.client || store.revision == _pushedRevision) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), syncNow);
  }

  /// Called when the app comes back to the foreground.
  void onResumed() {
    if (mode == SyncMode.client) syncNow();
  }

  /// Syncs with the hub. If a sync is already running, returns that one.
  Future<void> syncNow() {
    if (mode != SyncMode.client || hubAddress == null) return Future.value();
    return _inflight ??= _sync().whenComplete(() => _inflight = null);
  }

  Future<void> _sync() async {
    final revAtStart = store.revision;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
    try {
      final req = await client.postUrl(Uri.parse('http://$hubAddress/sync'));
      req.headers.contentType = ContentType.json;
      req.headers.set('x-hlist-key', clientKey ?? '');
      req.write(jsonEncode({'device': deviceName, 'data': store.data.toJson()}));
      final res = await req.close().timeout(const Duration(seconds: 8));
      final body = await utf8.decoder.bind(res).join();
      if (res.statusCode == HttpStatus.unauthorized) {
        lastError = 'Wrong pairing code — check the code on the hub.';
      } else if (res.statusCode != HttpStatus.ok) {
        lastError = 'Hub error (${res.statusCode}).';
      } else {
        final json = jsonDecode(body) as Map<String, dynamic>;
        store.applyRemote(SyncData.fromJson(json['data'] as Map<String, dynamic>));
        _pushedRevision = revAtStart;
        lastSyncAt = DateTime.now();
        lastError = null;
      }
    } on SocketException {
      lastError = 'Hub not reachable. Same Wi-Fi? Is H List open there?';
    } on TimeoutException {
      lastError = 'Hub timed out.';
    } catch (e) {
      lastError = 'Sync failed: $e';
    } finally {
      client.close(force: true);
      notifyListeners();
    }
    // Edits made while the request was in flight still need pushing.
    if (store.revision != _pushedRevision && lastError == null) _onStoreChanged();
  }

  /// Broadcasts on the LAN and collects hub replies for [wait].
  static Future<List<DiscoveredHub>> discover({Duration wait = const Duration(seconds: 2)}) async {
    final found = <String, DiscoveredHub>{};
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final dg = socket?.receive();
        if (dg == null) return;
        final msg = utf8.decode(dg.data, allowMalformed: true);
        if (!msg.startsWith(_herePrefix)) return;
        final parts = msg.substring(_herePrefix.length).split('|');
        final port = parts.length > 1 ? parts[1] : '$kSyncPort';
        final addr = '${dg.address.address}:$port';
        found[addr] = DiscoveredHub(parts.first, addr);
      });
      final payload = utf8.encode(_discoverMsg);
      final targets = <InternetAddress>{InternetAddress('255.255.255.255')};
      // Subnet broadcasts reach more routers than the limited broadcast.
      for (final ip in await _localIPv4s()) {
        final p = ip.split('.');
        if (p.length == 4) targets.add(InternetAddress('${p[0]}.${p[1]}.${p[2]}.255'));
      }
      for (var i = 0; i < 3; i++) {
        for (final t in targets) {
          try {
            socket.send(payload, t, kDiscoveryPort);
          } catch (_) {}
        }
        await Future.delayed(wait ~/ 3);
      }
    } catch (e) {
      debugPrint('H List discovery: $e');
    } finally {
      socket?.close();
    }
    return found.values.toList();
  }
}
