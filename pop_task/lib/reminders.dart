import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import 'models.dart';
import 'store.dart';

/// One notification the app wants to fire.
class Alert {
  final int id;
  final DateTime at;
  final String title;
  final String body;
  final Task task;
  const Alert(this.id, this.at, this.title, this.body, this.task);
}

/// Stable 31-bit string hash (String.hashCode isn't stable across runs).
/// Kept below 2^53 at every step so it's identical on native and web.
int stableId(String s) {
  var h = 17;
  for (final c in utf8.encode(s)) {
    h = (h * 31 + c) % 0x7fffffff;
  }
  return h;
}

String formatTime(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return "$h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}";
}

/// "HH:mm" → "5:30 PM"
String formatHm(String hm) {
  final p = hm.split(':');
  final h = int.tryParse(p.first) ?? 0;
  final m = int.tryParse(p.length > 1 ? p[1] : '0') ?? 0;
  return formatTime(DateTime(2000, 1, 1, h, m));
}

/// All alerts for [store] between [from] (exclusive) and [to] (inclusive).
List<Alert> computeAlerts(AppStore store, DateTime from, DateTime to) {
  final out = <Alert>[];
  for (final t in store.aliveTasks) {
    // Repeating time-of-day reminder, fires every day until the task is done
    // (daily tasks: skip the day it was already checked off).
    final hm = t.reminderTime;
    if (hm != null && !(!t.isDaily && t.isCompleted)) {
      final p = hm.split(':');
      final h = int.tryParse(p.first);
      final m = int.tryParse(p.length > 1 ? p[1] : '');
      if (h != null && m != null) {
        for (var d = DateTime(from.year, from.month, from.day); !d.isAfter(to); d = DateTime(d.year, d.month, d.day + 1)) {
          final at = DateTime(d.year, d.month, d.day, h, m);
          if (!at.isAfter(from) || at.isAfter(to)) continue;
          if (t.isDaily && t.lastCompletedDate == dateKey(at)) continue;
          out.add(
            Alert(stableId('${t.id}|r|${at.millisecondsSinceEpoch}'), at, '⏰ H LIST: ${t.title}', t.why.isEmpty ? 'Reminder' : t.why, t),
          );
        }
      }
    }

    // Timed todo: optional heads-up, then "due now".
    final due = t.dueDate;
    if (due != null && !t.isDoneOn(dateKey(due))) {
      if (t.alertBeforeMin > 0) {
        final early = due.subtract(Duration(minutes: t.alertBeforeMin));
        if (early.isAfter(from) && !early.isAfter(to)) {
          out.add(
            Alert(
              stableId('${t.id}|e|${early.millisecondsSinceEpoch}'),
              early,
              '⏳ Due in ${_mins(t.alertBeforeMin)}: ${t.title}',
              'Due at ${formatTime(due)}',
              t,
            ),
          );
        }
      }
      if (due.isAfter(from) && !due.isAfter(to)) {
        out.add(
          Alert(
            stableId('${t.id}|d|${due.millisecondsSinceEpoch}'),
            due,
            '🔔 Due now: ${t.title}',
            t.why.isEmpty ? 'Timed task is due' : t.why,
            t,
          ),
        );
      }
    }
  }
  out.sort((a, b) => a.at.compareTo(b.at));
  return out;
}

String _mins(int m) => m >= 60 && m % 60 == 0 ? '${m ~/ 60}h' : '${m}m';

/// Schedules OS notifications so reminders fire even when the app is closed.
class Reminders {
  Reminders(this._prefs);

  final SharedPreferences _prefs;
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  Timer? _debounce;

  static const _scheduledKey = 'h_list_scheduled_v17';
  static const _horizon = Duration(days: 7);
  static const _maxPending = 50; // iOS caps pending notifications at 64

  /// Platforms where the OS can fire a notification while the app is closed.
  static bool get canSchedule => !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS || Platform.isWindows);

  static const _android = AndroidNotificationDetails(
    'h_list_alarms_v3',
    'Task Reminders & Alarms',
    channelDescription: 'Reminders and due-time alerts for H List tasks',
    importance: Importance.max,
    priority: Priority.high,
    playSound: true,
    sound: RawResourceAndroidNotificationSound('notification'),
  );

  static const _details = NotificationDetails(
    android: _android,
    iOS: DarwinNotificationDetails(),
    macOS: DarwinNotificationDetails(),
    windows: WindowsNotificationDetails(),
  );

  Future<void> init() async {
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(),
          macOS: DarwinInitializationSettings(),
          linux: LinuxInitializationSettings(defaultActionName: 'Open H List'),
          windows: WindowsInitializationSettings(
            appName: 'H List',
            appUserModelId: 'HList.HList.Desktop',
            guid: '6f1c7a8e-2b4d-4f5a-9c3e-8d7b1a2e4f60',
          ),
        ),
      );
      if (!kIsWeb && Platform.isAndroid) {
        await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
      }
      _ready = true;
    } catch (e) {
      debugPrint('H List: notifications unavailable: $e');
    }
  }

  /// Show immediately (used on platforms without scheduling).
  Future<void> showNow(Alert a) async {
    if (!_ready) return;
    try {
      await _plugin.show(id: a.id, title: a.title, body: a.body, notificationDetails: _details);
    } catch (e) {
      debugPrint('H List: show failed: $e');
    }
  }

  void scheduleSoon(AppStore store) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 1), () => reschedule(store));
  }

  Future<void> reschedule(AppStore store) async {
    if (!_ready || !canSchedule) return;
    final now = DateTime.now();
    final wanted = computeAlerts(store, now, now.add(_horizon)).take(_maxPending).toList();
    final wantedIds = {for (final a in wanted) a.id};

    // Previously scheduled: id -> fire time. Only cancel ones still in the
    // future, so already-delivered notifications stay in the tray.
    final prev = <int, int>{};
    try {
      final raw = _prefs.getString(_scheduledKey);
      if (raw != null) {
        (jsonDecode(raw) as Map).forEach((k, v) => prev[int.parse(k as String)] = v as int);
      }
    } catch (_) {}

    AndroidScheduleMode mode = AndroidScheduleMode.inexactAllowWhileIdle;
    if (Platform.isAndroid) {
      final exact = await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.canScheduleExactNotifications();
      if (exact == true) mode = AndroidScheduleMode.exactAllowWhileIdle;
    }

    for (final e in prev.entries) {
      if (e.value > now.millisecondsSinceEpoch && !wantedIds.contains(e.key)) {
        try {
          await _plugin.cancel(id: e.key);
        } catch (_) {}
      }
    }

    final next = <String, int>{};
    for (final a in wanted) {
      next['${a.id}'] = a.at.millisecondsSinceEpoch;
      // Re-scheduling the same id replaces it, which keeps titles fresh.
      try {
        await _plugin.zonedSchedule(
          id: a.id,
          title: a.title,
          body: a.body,
          scheduledDate: tz.TZDateTime.from(a.at.toUtc(), tz.UTC),
          notificationDetails: _details,
          androidScheduleMode: mode,
        );
      } catch (e) {
        debugPrint('H List: schedule failed: $e');
      }
    }
    await _prefs.setString(_scheduledKey, jsonEncode(next));
  }
}
