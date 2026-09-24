import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

const _dataKey = 'h_list_data_v17';
const _legacyChannelsKey = 'h_list_channels_v16';
const _legacyTasksKey = 'h_list_nested_tasks_v16';
const _soundKey = 'h_list_sound_enabled';
const _collapsedKey = 'h_list_collapsed_v17';
const _selectedKey = 'h_list_selected_channel_v17';

const _tombstoneTtl = Duration(days: 90);

/// Single source of truth for app data. UI listens to it; sync and
/// notifications react to [revision] changes.
class AppStore extends ChangeNotifier {
  AppStore(this._prefs);

  final SharedPreferences _prefs;

  SyncData _data = SyncData(channels: {}, tasks: {});
  SyncData get data => _data;

  /// Bumped on every local edit. Sync pushes when this changes.
  int revision = 0;

  bool soundEnabled = true;
  final Set<String> collapsed = {};
  String? _selectedChannelId;

  String get today => dateKey(DateTime.now());

  // ---------------------------------------------------------------------------
  // Loading & migration
  // ---------------------------------------------------------------------------

  static Future<AppStore> load() async {
    final prefs = await SharedPreferences.getInstance();
    final store = AppStore(prefs);
    store._load();
    return store;
  }

  void _load() {
    soundEnabled = _prefs.getBool(_soundKey) ?? true;
    collapsed.addAll(_prefs.getStringList(_collapsedKey) ?? const []);
    _selectedChannelId = _prefs.getString(_selectedKey);

    final raw = _prefs.getString(_dataKey);
    if (raw != null) {
      try {
        _data = SyncData.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (e) {
        // Keep the unreadable blob so it isn't silently lost on next save.
        _prefs.setString('${_dataKey}_corrupt_${nowMs()}', raw);
        debugPrint('H List: failed to decode data: $e');
      }
    } else {
      _data = _migrateFromV16();
    }

    _pruneTombstones();
    if (aliveChannels.isEmpty) {
      _putChannel(Channel(id: newId(), name: 'General', order: 0, updatedAt: nowMs()));
    }
    _persist();
  }

  SyncData _migrateFromV16() {
    final channels = <String, Channel>{};
    final byName = <String, String>{};
    final ts = nowMs();

    List<String> names = ['Arts', 'Music'];
    final chRaw = _prefs.getString(_legacyChannelsKey);
    if (chRaw != null) {
      try {
        names = (jsonDecode(chRaw) as List).map((e) => e.toString()).toList();
      } catch (_) {}
    }
    for (var i = 0; i < names.length; i++) {
      final c = Channel(id: newId(), name: names[i], order: i, updatedAt: ts);
      channels[c.id] = c;
      byName[c.name] = c.id;
    }

    final tasks = <String, Task>{};
    final tRaw = _prefs.getString(_legacyTasksKey);
    if (tRaw != null) {
      try {
        for (final e in jsonDecode(tRaw) as List) {
          final j = Map<String, dynamic>.from(e as Map);
          final chName = j['channel']?.toString() ?? 'General';
          var chId = byName[chName];
          if (chId == null) {
            final c = Channel(id: newId(), name: chName, order: channels.length, updatedAt: ts);
            channels[c.id] = c;
            byName[chName] = chId = c.id;
          }
          final isDaily = j['isDaily'] == true;
          final id = j['id']?.toString() ?? newId();
          tasks[id] = Task(
            id: id,
            channelId: chId,
            subcategory: j['subcategory']?.toString() ?? 'General',
            title: j['title']?.toString() ?? '',
            why: j['why']?.toString() ?? '',
            isDaily: isDaily,
            isCompleted: !isDaily && j['isCompleted'] == true,
            lastCompletedDate: isDaily ? j['lastCompletedDate']?.toString() : null,
            reminderTime: j['reminderTime']?.toString(),
            createdAt: int.tryParse(id) ?? ts,
            updatedAt: ts,
          );
        }
      } catch (e) {
        debugPrint('H List: v16 task migration failed: $e');
      }
    }

    return SyncData(channels: channels, tasks: tasks);
  }

  void _pruneTombstones() {
    final cutoff = nowMs() - _tombstoneTtl.inMilliseconds;
    _data.tasks.removeWhere((_, t) => t.deleted && t.updatedAt < cutoff);
    _data.channels.removeWhere((_, c) => c.deleted && c.updatedAt < cutoff);
  }

  void _persist() {
    _prefs.setString(_dataKey, jsonEncode(_data.toJson()));
  }

  void _changed() {
    revision++;
    _persist();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Queries
  // ---------------------------------------------------------------------------

  List<Channel> get aliveChannels {
    final list = _data.channels.values.where((c) => !c.deleted).toList()
      ..sort((a, b) => a.order != b.order ? a.order.compareTo(b.order) : a.name.compareTo(b.name));
    return list;
  }

  Channel? channelById(String? id) {
    final c = id == null ? null : _data.channels[id];
    return (c == null || c.deleted) ? null : c;
  }

  Channel get selectedChannel => channelById(_selectedChannelId) ?? aliveChannels.first;

  Iterable<Task> get aliveTasks => _data.tasks.values.where((t) => !t.deleted && channelById(t.channelId) != null);

  List<Task> tasksIn(String channelId) => aliveTasks.where((t) => t.channelId == channelId).toList();

  List<String> subcategoriesIn(String channelId) {
    final subs = tasksIn(channelId).map((t) => t.subcategory).toSet().toList()..sort();
    return subs;
  }

  bool channelNameTaken(String name, {String? exceptId}) =>
      aliveChannels.any((c) => c.id != exceptId && c.name.toLowerCase() == name.toLowerCase());

  // ---------------------------------------------------------------------------
  // Local-only settings
  // ---------------------------------------------------------------------------

  void selectChannel(String id) {
    if (_selectedChannelId == id) return;
    _selectedChannelId = id;
    _prefs.setString(_selectedKey, id);
    notifyListeners();
  }

  void setSound(bool on) {
    soundEnabled = on;
    _prefs.setBool(_soundKey, on);
    notifyListeners();
  }

  void toggleCollapsed(String key) {
    if (!collapsed.remove(key)) collapsed.add(key);
    _prefs.setStringList(_collapsedKey, collapsed.toList());
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Synced mutations
  // ---------------------------------------------------------------------------

  void _putChannel(Channel c) => _data.channels[c.id] = c;
  void _putTask(Task t) => _data.tasks[t.id] = t;

  Channel? addChannel(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty || channelNameTaken(trimmed)) return null;
    final maxOrder = aliveChannels.fold<int>(-1, (m, c) => c.order > m ? c.order : m);
    final c = Channel(id: newId(), name: trimmed, order: maxOrder + 1, updatedAt: nowMs());
    _putChannel(c);
    _selectedChannelId = c.id;
    _prefs.setString(_selectedKey, c.id);
    _changed();
    return c;
  }

  bool renameChannel(String id, String name) {
    final trimmed = name.trim();
    final c = channelById(id);
    if (c == null || trimmed.isEmpty || channelNameTaken(trimmed, exceptId: id)) return false;
    _putChannel(c.copyWith(name: trimmed));
    _changed();
    return true;
  }

  void deleteChannel(String id) {
    final c = channelById(id);
    if (c == null) return;
    for (final t in tasksIn(id)) {
      _putTask(t.copyWith(deleted: true));
    }
    _putChannel(c.copyWith(deleted: true));
    if (aliveChannels.isEmpty) {
      _putChannel(Channel(id: newId(), name: 'General', order: 0, updatedAt: nowMs()));
    }
    if (_selectedChannelId == id) _selectedChannelId = aliveChannels.first.id;
    _changed();
  }

  void moveChannel(String id, int delta) {
    final list = aliveChannels;
    final i = list.indexWhere((c) => c.id == id);
    final j = i + delta;
    if (i < 0 || j < 0 || j >= list.length) return;
    final moved = list.removeAt(i);
    list.insert(j, moved);
    for (var k = 0; k < list.length; k++) {
      if (list[k].order != k) _putChannel(list[k].copyWith(order: k));
    }
    _changed();
  }

  void addTask({
    required String channelId,
    required String subcategory,
    required String title,
    required String why,
    required bool isDaily,
    String? reminderTime,
    int? dueAt,
    int alertBeforeMin = 0,
  }) {
    final ts = nowMs();
    _putTask(
      Task(
        id: newId(),
        channelId: channelId,
        subcategory: subcategory.trim().isEmpty ? 'General' : subcategory.trim(),
        title: title.trim(),
        why: why.trim(),
        isDaily: isDaily,
        reminderTime: reminderTime,
        dueAt: dueAt,
        alertBeforeMin: alertBeforeMin,
        createdAt: ts,
        updatedAt: ts,
      ),
    );
    _changed();
  }

  void updateTask(Task t) {
    _putTask(t);
    _changed();
  }

  void toggleTask(Task t) {
    final done = t.isDoneOn(today);
    if (t.isDaily) {
      _putTask(t.copyWith(lastCompletedDate: done ? null : today, completedAt: done ? null : nowMs()));
    } else {
      _putTask(t.copyWith(isCompleted: !done, completedAt: done ? null : nowMs()));
    }
    _changed();
  }

  /// Returns the removed task so the UI can offer undo.
  Task? deleteTask(String id) {
    final t = _data.tasks[id];
    if (t == null || t.deleted) return null;
    _putTask(t.copyWith(deleted: true));
    _changed();
    return t;
  }

  void restoreTask(Task t) {
    _putTask(t.copyWith(deleted: false));
    _changed();
  }

  /// Removes finished one-off tasks. Daily tasks are kept (they come back tomorrow).
  List<Task> clearCompleted(String channelId) {
    final removed = tasksIn(channelId).where((t) => !t.isDaily && t.isCompleted).toList();
    for (final t in removed) {
      _putTask(t.copyWith(deleted: true));
    }
    if (removed.isNotEmpty) _changed();
    return removed;
  }

  void restoreTasks(List<Task> list) {
    for (final t in list) {
      _putTask(t.copyWith(deleted: false));
    }
    if (list.isNotEmpty) _changed();
  }

  /// Merge data received from another device. Does not bump [revision]
  /// unless the merge produced something the remote side doesn't have yet.
  void applyRemote(SyncData remote) {
    final before = jsonEncode(_data.toJson());
    _data = SyncData.merge(_data, remote);
    if (aliveChannels.isEmpty) {
      _putChannel(Channel(id: newId(), name: 'General', order: 0, updatedAt: nowMs()));
    }
    if (jsonEncode(_data.toJson()) != before) {
      _persist();
      notifyListeners();
    }
  }

  /// Call periodically so daily tasks visibly reset at midnight.
  String _lastSeenDay = dateKey(DateTime.now());
  void tick() {
    final d = today;
    if (d != _lastSeenDay) {
      _lastSeenDay = d;
      notifyListeners();
    }
  }
}
