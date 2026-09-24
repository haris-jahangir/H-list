# H List

A categorized to-do app (Flutter) with daily-reset habits, reminders, timed
todos, and Wi-Fi sync between your computer and phone.

## Features
- **Channels → subcategories → tasks**, each with a "why".
- **Daily tasks** uncheck themselves every day.
- **Reminders** (repeat at a time of day) and **timed todos** (a due date/time
  with an optional heads-up) — delivered as OS notifications even when the app
  is closed (Android, iOS, macOS, Windows).
- **Sync**: tap the sync icon → on the computer pick **BE THE HUB**; on the
  phone pick **CONNECT**, tap **FIND HUB** (or type the address) and enter the
  6-digit pairing code. Both devices must be on the same network and H List
  must be open on the hub. Allow H List through the Windows firewall when asked.
- Undo for deletes, Ctrl+N for a new task, Alt+←/→ to switch channels,
  right-click / long-press a channel to edit, reorder or delete it.

## Develop
```bash
flutter pub get
flutter test
flutter run -d windows   # needs Visual Studio "Desktop development with C++"
flutter run -d android   # needs the Android SDK
```

Code map: `lib/models.dart` (data + merge), `lib/store.dart` (state,
persistence, v16 migration), `lib/reminders.dart` (notification scheduling),
`lib/sync.dart` (LAN hub/client), `lib/home_screen.dart` + `lib/dialogs.dart`
(UI), `lib/theme.dart` (shared styles). See `docs/DESIGN.md`.
