// Runs a real hub and client over localhost sockets. Kept separate from
// widget tests because the widget binding mocks out HttpClient.
import 'package:flutter_test/flutter_test.dart';
import 'package:h_list/store.dart';
import 'package:h_list/sync.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A simulated device with its own (fresh) preferences.
Future<(AppStore, SyncService)> device() async {
  SharedPreferences.setMockInitialValues({});
  final store = await AppStore.load();
  final prefs = await SharedPreferences.getInstance();
  return (store, SyncService(store, prefs));
}

void main() {
  test('client and hub converge, including deletes and wrong codes', () async {
    final (hubStore, hub) = await device();
    await hub.init();
    await hub.setMode(SyncMode.hub);
    expect(hub.hubPort, isNotNull);

    final (phoneStore, phone) = await device();
    await phone.init();

    // Wrong code is rejected and nothing merges.
    await phone.connectTo('127.0.0.1:${hub.hubPort}', '000000');
    await phone.syncNow();
    expect(phone.lastError, contains('Wrong pairing code'));

    await phone.connectTo('127.0.0.1:${hub.hubPort}', hub.pairCode);
    // Both start with their own default channels; after sync each has both sets.
    hubStore.addTask(channelId: hubStore.selectedChannel.id, subcategory: 'Desk', title: 'From desktop', why: '', isDaily: false);
    phoneStore.addTask(channelId: phoneStore.selectedChannel.id, subcategory: 'Phone', title: 'From phone', why: '', isDaily: false);
    await phone.syncNow();
    expect(phone.lastError, isNull);

    Set<String> titles(AppStore s) => s.aliveTasks.map((t) => t.title).toSet();
    expect(titles(hubStore), {'From desktop', 'From phone'});
    expect(titles(phoneStore), {'From desktop', 'From phone'});

    // Delete on the hub, edit on the phone: both propagate.
    final desk = hubStore.aliveTasks.firstWhere((t) => t.title == 'From desktop');
    hubStore.deleteTask(desk.id);
    final fromPhone = phoneStore.aliveTasks.firstWhere((t) => t.title == 'From phone');
    await Future.delayed(const Duration(milliseconds: 2));
    phoneStore.updateTask(fromPhone.copyWith(title: 'Edited on phone'));
    await phone.syncNow();

    expect(titles(hubStore), {'Edited on phone'});
    expect(titles(phoneStore), {'Edited on phone'});

    await phone.setMode(SyncMode.off);
    await hub.setMode(SyncMode.off);
  });
}
