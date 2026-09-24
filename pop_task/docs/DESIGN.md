# H List — Design Document

_Status: describes the app as of commit `b06ce03` ("H list basic"), plus proposed changes._

## 1. Overview

H List is a Flutter to-do app built around **channels** (top-level categories such as "Arts" and "Music"). Each channel groups its tasks into **subcategories**. Every task has a "why" (its motivation), and can be set to **reset daily** and to fire a **reminder** at a set time. The visual style is neo-brutalist: 2px black borders, hard offset shadows, a mint accent (`#DAECE0`), a cream background (`#FFFDF5`), a yellow highlight (`#FFDE00`) and the Fredoka font.

### Goals
- Capture a task, its category and its reason in a few taps.
- Build daily habits: daily tasks uncheck themselves each morning.
- Keep a "favorite" channel visible at all times.

### Non-goals (currently)
- Sync, accounts, sharing
- Due dates, priorities, recurrence other than daily

## 2. Architecture

```
main()
 ├─ init FlutterLocalNotificationsPlugin (Android settings only)
 └─ HListApp (MaterialApp, theme)
     └─ HListHomeScreen (StatefulWidget: all state + all UI)
```

All of the app is in `lib/main.dart` (~1,290 lines):

| Concern | Where |
|---|---|
| Model | `Task` class (mutable, JSON serializable) |
| State | `_HListHomeScreenState` fields: `tasks`, `channels`, `_selectedCategoryFilter`, `_favoriteCategory`, `_soundEnabled`, `_collapsedSubcategories` |
| Persistence | `SharedPreferences`. Four keys, each rewritten in full on every change |
| Reminders | `Timer.periodic(5s)` compares `HH:mm` against `task.reminderTime`, then shows a local notification, plays an mp3 and shows a SnackBar |
| Daily reset | Runs on load, on every timer tick and on app resume: if `isDaily && lastCompletedDate != today`, uncheck the task |
| UI | One `build()` method, with dialogs built inline |

### Data model

```dart
Task {
  String id;               // millisecondsSinceEpoch
  String channel;          // channel *name* (foreign key by string)
  String subcategory;      // free text; grouping key
  String title;
  String why;              // defaults to "Build consistency"
  bool isDaily;
  bool isCompleted;
  String? lastCompletedDate;  // "yyyy-MM-dd", daily tasks only
  String? reminderTime;       // "HH:mm", 24h
}
```

Storage keys: `h_list_channels_v16`, `h_list_nested_tasks_v16`, `h_list_favorite_category`, `h_list_sound_enabled`.

### Screen layout (top to bottom)
1. **AppBar**: logo, "H LIST" title, sound toggle.
2. **Fav Spot card**: up to 3 active tasks from the favorite channel, plus "VIEW ALL ➔".
3. **Channel chip bar**: horizontal list of channels. Tap selects a channel, long-press edits it, and "+" adds one.
4. **Task body**: a card grouping active tasks by subcategory (each group collapsible and with its own "ADD" button), then a "Completed (n)" expansion tile. Tapping empty space opens the Add Task dialog, and swiping left or right changes channel.
5. **Floating "FAV" pill** (bottom left): popup menu to change the favorite channel.

## 3. Findings

### 3.1 Bugs (functional)

| # | Issue | Location | Impact |
|---|---|---|---|
| B1 | **Reminders only fire while the app is open.** They rely on an in-app `Timer`, and nothing is scheduled with the OS. | `main.dart:148`, `:176` | This is the app's main feature, and it doesn't work when the app is backgrounded or closed. |
| B2 | **Muting sound turns off alarms *and* daily resets.** `_checkAlarmsAndResets` returns early when `!_soundEnabled`. | `main.dart:177` | With sound off, daily tasks stay checked across days (until the next cold start) and reminders stop. |
| B3 | **Only one reminder fires per minute.** `_lastTriggeredMinute` is a single value, so a second task at the same time is skipped. | `main.dart:192` | Silently drops reminders. |
| B4 | **The notification sound resource is missing.** `RawResourceAndroidNotificationSound('notification')` needs `android/app/src/main/res/raw/notification.mp3`, and there is no `res/raw` folder. | `main.dart:163` | `show()` throws, and the error is lost because the future isn't awaited, so no system notification appears. |
| B5 | **No notification permission on Android 13+.** The manifest has no `POST_NOTIFICATIONS`, and the app never calls `requestNotificationsPermission()`. | `AndroidManifest.xml` | Notifications are blocked by default on modern Android. |
| B6 | **No iOS/macOS init settings.** `InitializationSettings` only passes `android:`. | `main.dart:17` | Notifications don't work on Apple platforms. `initialize` may also throw at startup. |
| B7 | **Core library desugaring isn't enabled**, and `flutter_local_notifications` ≥10 requires it. | `android/app/build.gradle.kts` | The Android build is likely to fail with "requires core library desugaring". |
| B8 | **Renaming or deleting a channel doesn't update `_favoriteCategory`.** | `main.dart:300-365` | The Fav card then points at a channel that no longer exists and shows "no tasks". |
| B9 | **The default favorite is `'Arts'` even if that channel doesn't exist** (e.g. after a user deletes it, or when data loads with other channels). | `main.dart:246` | Same as B8. |
| B10 | **Notification IDs use `DateTime.now().millisecond`** (0–999). | `main.dart:169` | IDs collide, so one notification replaces another. |
| B11 | **The widget test is broken.** It imports `package:pop_task/main.dart` and `MyApp`, but the package is `h_list` and the widget is `HListApp`. | `test/widget_test.dart` | `flutter test` fails to compile. |
| B12 | **Add-task state leaks across dialogs.** Cancelling leaves `_isDailyTask` and the typed title in shared controllers, so the next "Add" starts pre-filled. | `main.dart:113-117`, `:548` | Confusing. |
| B13 | **Edit allows empty title and subcategory.** An empty subcategory creates a blank `""` group header. | `main.dart:711-717` | Messy data. |
| B14 | **The time picker ignores the existing value.** It always opens at 5:00 PM, even when editing a task that has a reminder. | `main.dart:456` | Annoying to edit. |
| B15 | **A new `AudioPlayer` is created on every click and never disposed.** | `main.dart:221`, `:231` | Native resources leak, and there's lag on low-end devices. |
| B16 | **Dialog `TextEditingController`s are never disposed.** | `:302`, `:417`, `:626-628` | Minor leak. |

### 3.2 UX issues

- **Destructive actions have no confirmation or undo.** The × on each task deletes instantly, and "DELETE" on a channel wipes every task in it. Add an undo SnackBar for tasks and a confirm dialog for channels.
- **Tapping anywhere opens Add Task.** The `GestureDetector` wraps the whole list, so tapping whitespace between tasks or while scrolling opens the dialog by accident. Use a FAB instead, or limit this to the empty state.
- **The edit icon on the selected chip doesn't do anything.** It suggests "tap to edit", but tapping only selects. Long-press is the only way to edit, and nothing tells the user about it. Either make a tap on the selected chip open edit, or drop the icon.
- **"Jump to FAV" is a disabled menu item**, so it can't be tapped. Picking a channel from the menu sets it as favorite *and* navigates there, mixing two actions.
- **The Fav Spot card and the FAV pill overlap.** Both show the favorite channel, and the card takes about 100px of vertical space on every screen. Consider showing the card only when you're not already on the favorite channel, or merging the two.
- **Times are mixed:** reminders are picked in 12h format but shown in 24h. Use `TimeOfDay.format(context)` to follow the device locale.
- **Minutes come in 5-minute steps only.** Consider Flutter's `showTimePicker` styled with the theme.
- **Small touch targets.** The checkbox is 26px, the × is 26px and some labels are 9–10pt. Material's guideline is 48dp targets and at least 12sp text.
- **Checkbox on the right, delete right next to it.** It's easy to hit × when aiming for ✓. Move the checkbox to the left (the usual to-do convention) and move delete into swipe or the edit dialog.
- **Completed tasks pile up forever** for non-daily tasks. Add "Clear completed".
- **Tasks and channels can't be reordered.** Add `ReorderableListView` for channels.
- **Collapsed subcategories aren't saved**, so they re-expand on every launch.
- **The default "why" is "Build consistency"** when left blank, so the task shows a reason the user never wrote. Hide the line when it's empty.
- **Swiping channels has no animation**, so the content just jumps. A `PageView` gives animated swipes and stays in sync with the chips.
- **No dark mode.** Every color is hard-coded (`Colors.black` and hex values).

### 3.3 Code and maintainability

- **One file and one `State` class hold everything.** Split into `models/`, `services/` (storage, notifications, sound), `screens/` and `widgets/`.
- **Styling is duplicated a lot.** The same dialog shape, `ElevatedButton.styleFrom(...)` and `InputDecoration` appear 4–6 times. `_buildModalTextField` and `_buildCustomField` are almost the same. Move them into a `ThemeData` (`dialogTheme`, `elevatedButtonTheme`, `inputDecorationTheme`) plus shared widgets like `BrutalCard` and `BrutalDialog`.
- **The Add and Edit task dialogs are about 90% the same code.** Make one `TaskFormDialog(initial: Task?)`.
- **Channels are referenced by name.** A rename has to rewrite every task. Give `Channel` an `id`, `name`, `color` and `order`.
- **The `Task` model is mutable and edited in place.** Use immutable models with `copyWith`.
- **State management:** `setState` on one widget rebuilds the whole tree every 5 seconds whenever something changed. A `ChangeNotifier`/`Provider` or Riverpod store would separate logic from UI and make it testable.
- **Persistence:** the full JSON is rewritten on every change, and nothing migrates the `_v16` keys. That's fine at this size. Add a `schemaVersion` key now. Consider `hive`, `isar` or `drift` if the data grows.
- **Errors are swallowed.** `catch (_) {}` around decoding hides data loss: a corrupt blob resets the user's tasks to `[]`, and the next save overwrites the corrupt data. Back up the raw string before overwriting it.
- **Deprecated APIs:** `Color.withOpacity` (use `withValues(alpha:)`), and `.toList()` inside spreads.
- **Project hygiene:**
  - The Android label is `pop_task` and the applicationId is `com.example.pop_task`. Rename to "H List" and a real reverse-DNS ID before publishing.
  - `android/build/reports/problems/problems-report.html` is committed. Add `/android/build/` to `.gitignore` and remove it from git.
  - The README is the Flutter template.
  - `google_fonts` downloads Fredoka at runtime, so the first launch offline uses a fallback font. Bundle the font file as an asset.
  - The `flutter_lints` version is ^3.0 while the SDK is ^3.12. Upgrade to the current lints.

## 4. Proposed design

### 4.1 Target structure

```
lib/
  main.dart                 // bootstrap only
  app.dart                  // MaterialApp + theme
  theme/brutal_theme.dart   // colors, ThemeData, dark variant
  models/task.dart          // immutable + copyWith + json
  models/channel.dart       // id, name, colorValue, order
  data/repository.dart      // load/save, schema migrations
  services/notifications.dart // init, permissions, zonedSchedule, cancel
  services/sound.dart       // single reused AudioPlayer (pooled)
  state/app_state.dart      // ChangeNotifier: all mutations + daily reset
  screens/home_screen.dart
  widgets/ (channel_bar, task_tile, subcategory_group, fav_card,
            task_form_dialog, channel_dialog, brutal_card, ...)
```

### 4.2 Reminders, done properly (fixes B1–B7, B10)

1. Add `timezone` and `flutter_timezone`, and call `tz.initializeTimeZones()` at startup.
2. When a task is created, edited or un-completed with a reminder, call `zonedSchedule(id: task.notificationId, ..., matchDateTimeComponents: isDaily ? DateTimeComponents.time : null)`. Cancel it on complete or delete.
3. Derive `notificationId` from a stable hash of `task.id` (e.g. `task.id.hashCode & 0x7fffffff`).
4. Android: add `POST_NOTIFICATIONS`, `SCHEDULE_EXACT_ALARM` (or use inexact), `RECEIVE_BOOT_COMPLETED` and the plugin's receivers. Put `notification.mp3` in `res/raw/`. Enable `isCoreLibraryDesugaringEnabled`.
5. iOS: add `DarwinInitializationSettings` and ask for permission on first reminder.
6. Keep the in-app SnackBar only for the case where the app is in the foreground.
7. Daily reset stays date-based. Run it on resume and on a midnight timer, and never gate it on sound.

### 4.3 Theme

Move the brutal style into `ThemeData`:

```dart
const mint = Color(0xFFDAECE0), cream = Color(0xFFFFFDF5), sun = Color(0xFFFFDE00);
final brutalBorder = RoundedRectangleBorder(
  borderRadius: BorderRadius.circular(12),
  side: const BorderSide(width: 2),
);
ThemeData(
  dialogTheme: DialogThemeData(backgroundColor: Colors.white, shape: brutalBorder),
  elevatedButtonTheme: ..., inputDecorationTheme: ..., chipTheme: ...,
)
```

This removes about 300 lines and makes dark mode (inverted: black surfaces, cream borders) a single variant.

### 4.4 Data migration
`schemaVersion: 17`. On load: read `v16`, convert channels to `{id, name}`, map `task.channel` from name to id, write `v17`, and keep `v16` as a backup for one release.

## 5. Feature ideas (roadmap)

**Quick wins (≤1 day each)**
- Undo SnackBar on delete, and a confirm dialog on channel delete
- FAB for add, replacing tap-anywhere
- Swipe a task right to complete it and left to delete it (`Dismissible`)
- Hide "why" when it's empty, and show reminders in the locale's time format
- "Clear completed" button
- Remember collapsed groups
- Fix the favorite channel when a channel is renamed or deleted

**Medium**
- **Streaks** for daily tasks: store a `completionHistory: List<date>` and show a 🔥 count. This fits the "why" and habit focus.
- Per-channel colors (chip and card tint)
- Reorder channels and tasks
- Search and filter across channels
- A subcategory picker (autocomplete from existing names) instead of free text, to avoid near-duplicates ("Gym" vs "gym ")
- Home-screen widget for the Fav Spot (`home_widget`), which is what the "In-App Widget" comment seems to be aiming for
- Export and import as a JSON backup

**Larger**
- Weekday recurrence (Mon/Wed/Fri) beyond "daily"
- Weekly review screen: completion rate per channel
- Optional cloud sync

## 6. Suggested order of work

1. **Make it build and ship:** fix the test (B11), desugaring (B7), `res/raw` sound (B4), permissions (B5, B6), `.gitignore`, and the app name and ID.
2. **Fix correctness:** decouple mute from resets and alarms (B2), per-task trigger tracking (B3), favorite integrity (B8, B9), dialog state (B12, B13, B14), audio player reuse (B15).
3. **Refactor:** split files, move styling into the theme, merge the Add and Edit dialogs, add `AppState` and a repository with tests.
4. **Real scheduled notifications** (section 4.2).
5. **UX pass:** FAB, undo, swipe actions, touch targets, time format.
6. **Features:** streaks, channel colors, home-screen widget.

## 7. Testing plan

- **Unit:** `Task.fromJson`/`toJson` round trip, the daily-reset rule (across midnight and across multiple days), channel rename and delete cascades (including the favorite), migration from v16 to v17.
- **Widget:** add a task, then check it's grouped under its subcategory; complete it, then check it moves to Completed; delete it, then undo; switch channels by swiping.
- **Manual on device:** a reminder fires with the app killed; after a reboot the reminder is still scheduled; the Android 13 permission prompt appears.
