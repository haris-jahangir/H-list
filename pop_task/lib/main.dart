import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'home_screen.dart';
import 'reminders.dart';
import 'store.dart';
import 'sync.dart';
import 'theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final store = await AppStore.load();
  final prefs = await SharedPreferences.getInstance();
  final reminders = Reminders(prefs);
  await reminders.init();
  final sync = SyncService(store, prefs);
  await sync.init();

  runApp(HListApp(store: store, sync: sync, reminders: reminders));
}

class HListApp extends StatelessWidget {
  const HListApp({super.key, required this.store, required this.sync, required this.reminders});

  final AppStore store;
  final SyncService sync;
  final Reminders reminders;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'H List',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: kCream,
        primaryColor: kMint,
        colorScheme: ColorScheme.fromSeed(seedColor: kMint, primary: kMint, surface: Colors.white),
        textTheme: GoogleFonts.fredokaTextTheme(ThemeData.light().textTheme),
      ),
      home: HListHomeScreen(store: store, sync: sync, reminders: reminders),
    );
  }
}
