import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'dialogs.dart';
import 'models.dart';
import 'reminders.dart';
import 'store.dart';
import 'sync.dart';
import 'theme.dart';

class HListHomeScreen extends StatefulWidget {
  const HListHomeScreen({super.key, required this.store, required this.sync, required this.reminders});

  final AppStore store;
  final SyncService sync;
  final Reminders reminders;

  @override
  State<HListHomeScreen> createState() => _HListHomeScreenState();
}

class _HListHomeScreenState extends State<HListHomeScreen> with WidgetsBindingObserver {
  AppStore get store => widget.store;

  // Reused players: creating one per click leaks native resources.
  final AudioPlayer _clickPlayer = AudioPlayer()..setPlayerMode(PlayerMode.lowLatency);
  final AudioPlayer _alarmPlayer = AudioPlayer();

  Timer? _ticker;
  DateTime _lastAlertCheck = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    store.addListener(_onStore);
    widget.sync.addListener(_onSync);
    widget.reminders.scheduleSoon(store);
    _ticker = Timer.periodic(const Duration(seconds: 15), (_) => _tick());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    store.removeListener(_onStore);
    widget.sync.removeListener(_onSync);
    _ticker?.cancel();
    _clickPlayer.dispose();
    _alarmPlayer.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _tick();
      widget.sync.onResumed();
      widget.reminders.scheduleSoon(store);
    }
  }

  void _onStore() {
    widget.reminders.scheduleSoon(store);
    if (mounted) setState(() {});
  }

  void _onSync() {
    if (mounted) setState(() {});
  }

  /// Midnight reset + in-app alerts while the app is open. OS notifications
  /// are scheduled separately, so this only adds the banner and chime (and
  /// the notification itself on platforms that can't schedule).
  void _tick() {
    store.tick();
    final now = DateTime.now();
    final alerts = computeAlerts(store, _lastAlertCheck, now);
    _lastAlertCheck = now;
    if (!mounted) return;
    if (alerts.isEmpty) {
      setState(() {}); // refresh "IN 5m" style labels
      return;
    }
    // Where the OS already delivers a scheduled notification (with its own
    // sound), only add the banner so the alert isn't doubled.
    if (!Reminders.canSchedule) {
      if (store.soundEnabled) _play(_alarmPlayer, 'notification.mp3', HapticFeedback.heavyImpact);
      for (final a in alerts) {
        widget.reminders.showNow(a);
      }
    }
    final a = alerts.last;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: kSun,
        content: Text(
          alerts.length == 1 ? a.title : '${a.title}  (+${alerts.length - 1} more)',
          style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900),
        ),
        duration: const Duration(seconds: 6),
      ),
    );
    setState(() {});
  }

  Future<void> _play(AudioPlayer p, String asset, Future<void> Function() fallback) async {
    try {
      await p.stop();
      await p.play(AssetSource(asset));
    } catch (_) {
      fallback();
    }
  }

  void _playSound() {
    if (store.soundEnabled) _play(_clickPlayer, 'button.mp3', HapticFeedback.lightImpact);
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  void _selectChannel(Channel c) {
    _playSound();
    store.selectChannel(c.id);
  }

  void _openAddTask({String defaultSubcategory = 'General'}) {
    _playSound();
    showTaskForm(context, store: store, channelId: store.selectedChannel.id, defaultSubcategory: defaultSubcategory, onClick: _playSound);
  }

  Future<void> _openEditTask(Task task) async {
    _playSound();
    final deleted = await showTaskForm(context, store: store, channelId: task.channelId, existing: task, onClick: _playSound);
    if (deleted != null) _showUndo('Deleted "${deleted.title}"', () => store.restoreTask(deleted));
  }

  void _toggle(Task t) {
    _playSound();
    HapticFeedback.selectionClick();
    store.toggleTask(t);
  }

  void _delete(Task t) {
    _playSound();
    final removed = store.deleteTask(t.id);
    if (removed != null) _showUndo('Deleted "${removed.title}"', () => store.restoreTask(removed));
  }

  void _clearCompleted() {
    _playSound();
    final removed = store.clearCompleted(store.selectedChannel.id);
    if (removed.isNotEmpty) {
      _showUndo('Cleared ${removed.length} completed', () => store.restoreTasks(removed));
    }
  }

  void _showUndo(String message, VoidCallback undo) {
    final m = ScaffoldMessenger.of(context);
    m.hideCurrentSnackBar();
    m.showSnackBar(
      SnackBar(
        backgroundColor: Colors.black,
        content: Text(message, style: const TextStyle(fontWeight: FontWeight.w800)),
        action: SnackBarAction(label: 'UNDO', textColor: kMint, onPressed: undo),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  void _editChannel(Channel c) {
    _playSound();
    showEditChannel(context, store, c);
  }

  void _shiftChannel(int delta) {
    final list = store.aliveChannels;
    final i = list.indexWhere((c) => c.id == store.selectedChannel.id);
    final j = i + delta;
    if (i == -1 || j < 0 || j >= list.length) return;
    _selectChannel(list[j]);
  }

  void _handleSwipe(DragEndDetails details) {
    final v = details.primaryVelocity ?? 0;
    if (v < -150) _shiftChannel(1);
    if (v > 150) _shiftChannel(-1);
  }

  /// Timed tasks first (soonest due), then oldest first.
  int _taskOrder(Task a, Task b) {
    final da = a.dueAt, db = b.dueAt;
    if (da != null && db != null) return da.compareTo(db);
    if (da != null) return -1;
    if (db != null) return 1;
    return a.createdAt.compareTo(b.createdAt);
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  IconData get _syncIcon {
    final s = widget.sync;
    switch (s.mode) {
      case SyncMode.off:
        return Icons.sync_disabled_rounded;
      case SyncMode.hub:
        return Icons.hub_rounded;
      case SyncMode.client:
        return s.lastError != null ? Icons.sync_problem_rounded : Icons.sync_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = store.today;
    final now = DateTime.now();
    final channels = store.aliveChannels;
    final selected = store.selectedChannel;

    final channelTasks = store.tasksIn(selected.id)..sort(_taskOrder);
    final activeTasks = channelTasks.where((t) => !t.isDoneOn(today)).toList();
    final completedTasks = channelTasks.where((t) => t.isDoneOn(today)).toList()
      ..sort((a, b) => (b.completedAt ?? 0).compareTo(a.completedAt ?? 0));
    final groupedActive = <String, List<Task>>{};
    for (final task in activeTasks) {
      groupedActive.putIfAbsent(task.subcategory, () => []).add(task);
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): _openAddTask,
        const SingleActivator(LogicalKeyboardKey.keyN, meta: true): _openAddTask,
        const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true): () => _shiftChannel(1),
        const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): () => _shiftChannel(-1),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            surfaceTintColor: Colors.transparent,
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(2),
              child: Container(color: Colors.black, height: 2),
            ),
            title: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.black, width: 2),
                    image: const DecorationImage(image: AssetImage('assets/logo.png'), fit: BoxFit.cover),
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'H LIST',
                  style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 22),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Sync devices',
                  icon: Icon(_syncIcon, color: Colors.black),
                  onPressed: () {
                    _playSound();
                    showSyncDialog(context, widget.sync);
                  },
                ),
                IconButton(
                  tooltip: store.soundEnabled ? 'Mute sounds' : 'Unmute sounds',
                  icon: Icon(store.soundEnabled ? Icons.volume_up_rounded : Icons.volume_off_rounded, color: Colors.black),
                  onPressed: () => store.setSound(!store.soundEnabled),
                ),
              ],
            ),
          ),
          body: Column(
            children: [
              // Categories Horizontal Bar
              Container(
                height: 60,
                color: Colors.white,
                child: Row(
                  children: [
                    Expanded(
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        itemCount: channels.length,
                        itemBuilder: (context, index) {
                          final cat = channels[index];
                          final isSelected = selected.id == cat.id;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: GestureDetector(
                              onLongPress: () => _editChannel(cat),
                              onSecondaryTap: () => _editChannel(cat),
                              child: ActionChip(
                                label: Text(cat.name.toUpperCase()),
                                avatar: isSelected ? const Icon(Icons.edit, size: 14, color: Colors.black) : null,
                                tooltip: isSelected ? 'Tap to edit' : 'Long-press to edit',
                                backgroundColor: isSelected ? kMint : kChipOff,
                                labelStyle: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  side: const BorderSide(color: Colors.black, width: 2),
                                ),
                                // The pencil on the selected chip now does what it shows.
                                onPressed: () => isSelected ? _editChannel(cat) : _selectChannel(cat),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 12.0),
                      child: InkWell(
                        onTap: () {
                          _playSound();
                          showAddChannel(context, store);
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: kMint,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.black, width: 2),
                          ),
                          child: const Icon(Icons.add, size: 18, color: Colors.black),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(color: Colors.black, height: 2),

              // Main Tasks List Body
              Expanded(
                child: Stack(
                  children: [
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      // Tap-to-add only on the empty state, so taps between
                      // tasks don't open the dialog by accident.
                      onTap: channelTasks.isEmpty ? () => _openAddTask() : null,
                      onHorizontalDragEnd: _handleSwipe,
                      child: channelTasks.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.folder_open_rounded, size: 54, color: Colors.black45),
                                  const SizedBox(height: 12),
                                  Text(
                                    "No tasks in '${selected.name}'",
                                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.black87),
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    'Tap anywhere to add • Swipe left/right to change tab',
                                    style: TextStyle(color: Colors.black54, fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            )
                          : ListView(
                              padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                              children: [
                                _channelCard(selected, groupedActive, now),
                                if (completedTasks.isNotEmpty) ...[const SizedBox(height: 16), _completedTile(completedTasks)],
                              ],
                            ),
                    ),

                    // Add task button (bottom-right), same brutal style.
                    Positioned(
                      right: 16,
                      bottom: 16,
                      child: Tooltip(
                        message: 'New task (Ctrl+N)',
                        child: InkWell(
                          onTap: _openAddTask,
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: kMint,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.black, width: 2.5),
                              boxShadow: const [BoxShadow(color: Colors.black, offset: Offset(3, 3))],
                            ),
                            child: const Icon(Icons.add_rounded, size: 28, color: Colors.black),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _channelCard(Channel selected, Map<String, List<Task>> groupedActive, DateTime now) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black, width: 2.5),
        boxShadow: const [BoxShadow(color: Colors.black, offset: Offset(3, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.grid_view_rounded, size: 18, color: Colors.black),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  selected.name.toUpperCase(),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.black, letterSpacing: 1.2),
                ),
              ),
              InkWell(
                onTap: () => _editChannel(selected),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: kCream,
                    border: Border.all(color: Colors.black, width: 1.5),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'EDIT CATEGORY',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.black),
                  ),
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10.0),
            child: Divider(color: Colors.black, height: 1, thickness: 2),
          ),
          if (groupedActive.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text(
                'All done here 🎉',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.black54),
              ),
            ),
          ...groupedActive.entries.map((subEntry) {
            final subName = subEntry.key;
            final subTasks = subEntry.value;
            final collapseKey = '${selected.id}:$subName';
            final isCollapsed = store.collapsed.contains(collapseKey);

            return Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () {
                            _playSound();
                            store.toggleCollapsed(collapseKey);
                          },
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.all(4.0),
                            child: Row(
                              children: [
                                Icon(isCollapsed ? Icons.chevron_right_rounded : Icons.expand_more_rounded, size: 18, color: Colors.black),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    subName,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.black87),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '(${subTasks.length})',
                                  style: const TextStyle(fontSize: 12, color: Colors.black54, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: () => _openAddTask(defaultSubcategory: subName),
                        borderRadius: BorderRadius.circular(4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: kMint,
                            border: Border.all(color: Colors.black, width: 1.5),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.add, size: 12, color: Colors.black),
                              SizedBox(width: 2),
                              Text(
                                'ADD',
                                style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.black),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (!isCollapsed) ...subTasks.map((t) => _taskTile(t, now)),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _taskTile(Task task, DateTime now) {
    final due = task.dueDate;
    final overdue = due != null && !due.isAfter(now);
    return InkWell(
      onTap: () => _openEditTask(task),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(left: 16, top: 4, bottom: 4),
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        decoration: BoxDecoration(
          color: overdue ? kOverdue.withValues(alpha: 0.35) : kMint.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.black, width: 2),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          task.title,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Colors.black),
                        ),
                      ),
                      if (due != null) Tag(describeDue(due, now), color: dueColor(due, now), icon: Icons.timer_outlined),
                      if (task.isDaily) const Tag('DAILY'),
                    ],
                  ),
                  if (task.why.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      'why: ${task.why}',
                      style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, fontWeight: FontWeight.w700, color: Colors.black54),
                    ),
                  ],
                  if (task.reminderTime != null) ...[
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(Icons.access_time_rounded, size: 11, color: Colors.black54),
                        const SizedBox(width: 4),
                        Text(
                          'Reminder: ${formatHm(task.reminderTime!)}',
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.black54),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 2),
            // Same 26px box, bigger invisible hit area.
            Tooltip(
              message: 'Mark done',
              child: InkWell(
                onTap: () => _toggle(task),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.black, width: 2),
                    ),
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.close_rounded, size: 18, color: Colors.black),
              onPressed: () => _delete(task),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 40),
            ),
          ],
        ),
      ),
    );
  }

  Widget _completedTile(List<Task> completedTasks) {
    final clearable = completedTasks.where((t) => !t.isDaily).length;
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 12),
      collapsedBackgroundColor: kDoneGrey,
      backgroundColor: kDoneGrey,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Colors.black, width: 2),
      ),
      collapsedShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Colors.black, width: 2),
      ),
      title: Row(
        children: [
          Text(
            'Completed (${completedTasks.length})',
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Colors.black),
          ),
          const Spacer(),
          if (clearable > 0)
            InkWell(
              onTap: _clearCompleted,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: kCream,
                  border: Border.all(color: Colors.black, width: 1.5),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'CLEAR',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.black),
                ),
              ),
            ),
        ],
      ),
      children: completedTasks.map((task) {
        return InkWell(
          onTap: () => _openEditTask(task),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.black, width: 1.5),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    task.title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Colors.black45,
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
                ),
                if (task.isDaily) const Tag('DAILY', color: kChipOff),
                const SizedBox(width: 6),
                Tooltip(
                  message: 'Mark not done',
                  child: InkWell(
                    onTap: () => _toggle(task),
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: kMint,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.black, width: 1.5),
                      ),
                      child: const Icon(Icons.check, size: 14, color: Colors.black),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
