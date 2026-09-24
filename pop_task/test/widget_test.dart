import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:h_list/home_screen.dart';
import 'package:h_list/models.dart';
import 'package:h_list/reminders.dart';
import 'package:h_list/store.dart';
import 'package:h_list/sync.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<AppStore> freshStore([Map<String, Object> prefs = const {}]) async {
  SharedPreferences.setMockInitialValues(prefs);
  return AppStore.load();
}

void main() {
  group('migration', () {
    test('v16 data is converted to channel ids and keeps tasks', () async {
      final store = await freshStore({
        'h_list_channels_v16': jsonEncode(['Arts', 'Gym']),
        'h_list_nested_tasks_v16': jsonEncode([
          {
            'id': '1',
            'channel': 'Gym',
            'subcategory': 'Legs',
            'title': 'Squats',
            'why': 'strong',
            'isDaily': true,
            'isCompleted': true,
            'lastCompletedDate': '2000-01-01',
            'reminderTime': '07:30',
          },
          {'id': '2', 'channel': 'Lost', 'subcategory': 'General', 'title': 'Orphan', 'why': '', 'isDaily': false, 'isCompleted': true},
        ]),
      });
      expect(store.aliveChannels.map((c) => c.name), ['Arts', 'Gym', 'Lost']);
      final squats = store.aliveTasks.firstWhere((t) => t.title == 'Squats');
      expect(store.channelById(squats.channelId)!.name, 'Gym');
      expect(squats.isDoneOn(store.today), isFalse, reason: 'daily task from an old day is reset');
      expect(squats.reminderTime, '07:30');
      expect(store.aliveTasks.firstWhere((t) => t.title == 'Orphan').isCompleted, isTrue);
    });
  });

  group('store', () {
    test('deleting a channel cascades to its tasks', () async {
      final store = await freshStore();
      final a = store.addChannel('A')!;
      store.addTask(channelId: a.id, subcategory: '', title: 'x', why: '', isDaily: false);
      store.deleteChannel(a.id);
      expect(store.selectedChannel.id, isNot(a.id));
      expect(store.aliveTasks, isEmpty);
    });

    test('rename rejects duplicates', () async {
      final store = await freshStore();
      final a = store.addChannel('A')!;
      store.addChannel('B');
      expect(store.renameChannel(a.id, 'b'), isFalse);
      expect(store.renameChannel(a.id, 'Alpha'), isTrue);
      expect(store.channelById(a.id)!.name, 'Alpha');
    });

    test('daily tasks count as done only on the day they were checked', () async {
      final store = await freshStore();
      final ch = store.selectedChannel;
      store.addTask(channelId: ch.id, subcategory: 'S', title: 'Walk', why: '', isDaily: true);
      final t = store.aliveTasks.single;
      store.toggleTask(t);
      final done = store.aliveTasks.single;
      expect(done.isDoneOn(store.today), isTrue);
      expect(done.isDoneOn('2999-01-01'), isFalse);
    });

    test('undo restores a deleted task', () async {
      final store = await freshStore();
      store.addTask(channelId: store.selectedChannel.id, subcategory: '', title: 'x', why: '', isDaily: false);
      final removed = store.deleteTask(store.aliveTasks.single.id)!;
      expect(store.aliveTasks, isEmpty);
      store.restoreTask(removed);
      expect(store.aliveTasks.single.title, 'x');
    });
  });

  group('sync merge', () {
    Task task(String id, String title, int updatedAt, {bool deleted = false}) => Task(
      id: id,
      channelId: 'c',
      subcategory: 'General',
      title: title,
      why: '',
      isDaily: false,
      createdAt: 0,
      updatedAt: updatedAt,
      deleted: deleted,
    );

    test('newest edit wins and tombstones propagate', () {
      final a = SyncData(channels: {}, tasks: {'1': task('1', 'old', 1), '2': task('2', 'keep', 5)});
      final b = SyncData(
        channels: {},
        tasks: {'1': task('1', 'new', 2), '2': task('2', 'keep', 9, deleted: true), '3': task('3', 'added', 1)},
      );
      final m = SyncData.merge(a, b);
      expect(m.tasks['1']!.title, 'new');
      expect(m.tasks['2']!.deleted, isTrue);
      expect(m.tasks.keys, containsAll(['1', '2', '3']));
      // Merge is order-independent.
      final m2 = SyncData.merge(b, a);
      expect(jsonEncode(m2.tasks['1']!.toJson()), jsonEncode(m.tasks['1']!.toJson()));
    });

    test('json round trip', () {
      final d = SyncData(
        channels: {'c': const Channel(id: 'c', name: 'Arts', order: 0, updatedAt: 1)},
        tasks: {'1': task('1', 't', 1)},
      );
      final back = SyncData.fromJson(jsonDecode(jsonEncode(d.toJson())) as Map<String, dynamic>);
      expect(back.channels['c']!.name, 'Arts');
      expect(back.tasks['1']!.title, 't');
    });
  });

  group('alerts', () {
    test('timed todo gets heads-up and due alerts, not after completion', () async {
      final store = await freshStore();
      final due = DateTime.fromMillisecondsSinceEpoch(DateTime.now().add(const Duration(hours: 2)).millisecondsSinceEpoch);
      store.addTask(
        channelId: store.selectedChannel.id,
        subcategory: '',
        title: 'Call',
        why: '',
        isDaily: false,
        dueAt: due.millisecondsSinceEpoch,
        alertBeforeMin: 30,
      );
      final now = DateTime.now();
      final alerts = computeAlerts(store, now, now.add(const Duration(days: 1)));
      expect(alerts.length, 2);
      expect(alerts.first.at, due.subtract(const Duration(minutes: 30)));
      store.toggleTask(store.aliveTasks.single);
      expect(computeAlerts(store, now, now.add(const Duration(days: 1))), isEmpty);
    });

    test('daily reminder repeats but skips a day already done', () async {
      final store = await freshStore();
      store.addTask(channelId: store.selectedChannel.id, subcategory: '', title: 'Read', why: '', isDaily: true, reminderTime: '23:59');
      final from = DateTime.now().subtract(const Duration(minutes: 1));
      final to = from.add(const Duration(days: 3));
      final before = computeAlerts(store, from, to).length;
      store.toggleTask(store.aliveTasks.single); // done today
      expect(computeAlerts(store, from, to).length, before - 1);
    });

    test('formatHm uses 12h clock', () {
      expect(formatHm('00:05'), '12:05 AM');
      expect(formatHm('17:30'), '5:30 PM');
    });
  });

  testWidgets('home screen renders and adds a task', (tester) async {
    final store = await freshStore();
    final prefs = await SharedPreferences.getInstance();
    final sync = SyncService(store, prefs);
    await sync.init();

    await tester.pumpWidget(
      MaterialApp(
        home: HListHomeScreen(store: store, sync: sync, reminders: Reminders(prefs)),
      ),
    );
    expect(find.text('H LIST'), findsOneWidget);
    expect(find.textContaining("No tasks in 'Arts'"), findsOneWidget);

    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(1), 'Write tests');
    await tester.tap(find.text('CREATE'));
    await tester.pumpAndSettle();

    expect(find.text('Write tests'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
