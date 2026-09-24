import 'package:flutter/material.dart';

import 'models.dart';
import 'reminders.dart';
import 'store.dart';
import 'sync.dart';
import 'theme.dart';

// -----------------------------------------------------------------------------
// Due-time helpers
// -----------------------------------------------------------------------------

const _weekdays = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
const _months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];

String _span(Duration d) {
  if (d.inMinutes < 60) return '${d.inMinutes < 1 ? 1 : d.inMinutes}m';
  if (d.inHours < 24) return '${d.inHours}h';
  return '${d.inDays}d';
}

/// Short label for a due time, e.g. "IN 25m", "TODAY 5:30 PM", "OVERDUE 2h".
String describeDue(DateTime due, DateTime now) {
  if (!due.isAfter(now)) return 'OVERDUE ${_span(now.difference(due))}';
  final diff = due.difference(now);
  if (diff.inMinutes < 60) return 'IN ${_span(diff)}';
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(due.year, due.month, due.day);
  final days = day.difference(today).inDays;
  final time = formatTime(due);
  if (days == 0) return 'TODAY $time';
  if (days == 1) return 'TOMORROW $time';
  if (days < 7) return '${_weekdays[due.weekday - 1]} $time';
  return '${_months[due.month - 1]} ${due.day} $time';
}

Color dueColor(DateTime due, DateTime now) {
  if (!due.isAfter(now)) return kOverdue;
  if (due.difference(now).inHours < 3) return kSun;
  return Colors.white;
}

// -----------------------------------------------------------------------------
// Generic dialogs
// -----------------------------------------------------------------------------

Future<bool> confirm(BuildContext context, String title, String message, {String action = 'DELETE'}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => BrutalDialog(
      title: Text(title),
      content: Text(message, style: const TextStyle(fontWeight: FontWeight.w600)),
      actions: [
        const CancelButton(),
        ElevatedButton(
          style: kPrimaryButton.copyWith(backgroundColor: const WidgetStatePropertyAll(kOverdue)),
          onPressed: () => Navigator.pop(context, true),
          child: Text(action, style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    ),
  );
  return ok == true;
}

/// 12-hour picker in the app's style. Returns "HH:mm" (24h) or null.
Future<String?> pickTime(BuildContext context, {String? initial, String title = 'SET REMINDER TIME'}) {
  var hour = 5, minute = 0;
  var isPm = true;
  if (initial != null) {
    final p = initial.split(':');
    final h = int.tryParse(p.first) ?? 17;
    minute = int.tryParse(p.length > 1 ? p[1] : '0') ?? 0;
    isPm = h >= 12;
    hour = h % 12 == 0 ? 12 : h % 12;
  }
  final minutes = {for (var m = 0; m < 60; m += 5) m, minute}.toList()..sort();

  return showDialog<String>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setTimeState) {
        const big = TextStyle(fontSize: 22, fontWeight: FontWeight.bold);
        return BrutalDialog(
          title: Text(title),
          content: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              DropdownButton<int>(
                value: hour,
                items: [
                  for (var h = 1; h <= 12; h++)
                    DropdownMenuItem(
                      value: h,
                      child: Text(h.toString().padLeft(2, '0'), style: big),
                    ),
                ],
                onChanged: (v) => setTimeState(() => hour = v ?? hour),
              ),
              const Text(' : ', style: big),
              DropdownButton<int>(
                value: minute,
                items: [
                  for (final m in minutes)
                    DropdownMenuItem(
                      value: m,
                      child: Text(m.toString().padLeft(2, '0'), style: big),
                    ),
                ],
                onChanged: (v) => setTimeState(() => minute = v ?? minute),
              ),
              const SizedBox(width: 12),
              ToggleButtons(
                isSelected: [!isPm, isPm],
                onPressed: (i) => setTimeState(() => isPm = i == 1),
                borderRadius: BorderRadius.circular(8),
                selectedColor: Colors.black,
                fillColor: kMint,
                color: Colors.black54,
                constraints: const BoxConstraints(minWidth: 40, minHeight: 38),
                children: const [
                  Text('AM', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  Text('PM', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                ],
              ),
            ],
          ),
          actions: [
            const CancelButton(),
            ElevatedButton(
              style: kPrimaryButton.copyWith(
                shape: WidgetStatePropertyAll(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: const BorderSide(color: Colors.black, width: 2),
                  ),
                ),
              ),
              onPressed: () {
                var h = hour;
                if (isPm && h != 12) h += 12;
                if (!isPm && h == 12) h = 0;
                Navigator.pop(context, '${h.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}');
              },
              child: const Text('ENTER', style: TextStyle(fontWeight: FontWeight.w900)),
            ),
          ],
        );
      },
    ),
  );
}

Future<DateTime?> pickDueDateTime(BuildContext context, DateTime? initial) async {
  final now = DateTime.now();
  final start = initial ?? now.add(const Duration(hours: 1));
  final date = await showDatePicker(
    context: context,
    initialDate: start.isBefore(now) ? now : start,
    firstDate: DateTime(now.year, now.month, now.day),
    lastDate: now.add(const Duration(days: 365 * 3)),
    builder: (context, child) => Theme(
      data: Theme.of(context).copyWith(
        colorScheme: Theme.of(context).colorScheme.copyWith(primary: Colors.black, onPrimary: kMint),
      ),
      child: child!,
    ),
  );
  if (date == null || !context.mounted) return null;
  final hm = await pickTime(
    context,
    title: 'DUE TIME',
    initial: '${start.hour.toString().padLeft(2, '0')}:${(start.minute - start.minute % 5).toString().padLeft(2, '0')}',
  );
  if (hm == null) return null;
  final p = hm.split(':');
  return DateTime(date.year, date.month, date.day, int.parse(p[0]), int.parse(p[1]));
}

// -----------------------------------------------------------------------------
// Task form (add + edit)
// -----------------------------------------------------------------------------

/// Disposes [controllers] when the dialog route is actually removed (after
/// its exit animation), not when the dialog's Future completes.
class _DisposeWith extends StatefulWidget {
  const _DisposeWith(this.controllers, {required this.child});
  final List<ChangeNotifier> controllers;
  final Widget child;

  @override
  State<_DisposeWith> createState() => _DisposeWithState();
}

class _DisposeWithState extends State<_DisposeWith> {
  @override
  void dispose() {
    for (final c in widget.controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

Widget _labeled(String label, Widget child) => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Text(label, style: kFieldLabel),
    const SizedBox(height: 4),
    child,
  ],
);

/// Opens the add/edit dialog. Returns the deleted task if the user pressed
/// DELETE (so the caller can offer undo).
Future<Task?> showTaskForm(
  BuildContext context, {
  required AppStore store,
  required String channelId,
  Task? existing,
  String defaultSubcategory = 'General',
  VoidCallback? onClick,
}) {
  final sub = TextEditingController(text: existing?.subcategory ?? defaultSubcategory);
  final title = TextEditingController(text: existing?.title ?? '');
  final why = TextEditingController(text: existing?.why ?? '');
  var isDaily = existing?.isDaily ?? false;
  String? reminder = existing?.reminderTime;
  DateTime? due = existing?.dueDate;
  var alertBefore = existing?.alertBeforeMin ?? 0;
  String? error;
  final suggestions = store.subcategoriesIn(channelId);
  final channelName = store.channelById(channelId)?.name ?? '';

  return showDialog<Task?>(
    context: context,
    builder: (context) => _DisposeWith(
      [sub, title, why],
      child: StatefulBuilder(
        builder: (context, setModalState) {
          void save() {
            if (title.text.trim().isEmpty) {
              setModalState(() => error = 'Give the task a name.');
              return;
            }
            onClick?.call();
            final subName = sub.text.trim().isEmpty ? 'General' : sub.text.trim();
            if (existing == null) {
              store.addTask(
                channelId: channelId,
                subcategory: subName,
                title: title.text,
                why: why.text,
                isDaily: isDaily,
                reminderTime: reminder,
                dueAt: due?.millisecondsSinceEpoch,
                alertBeforeMin: due == null ? 0 : alertBefore,
              );
            } else {
              store.updateTask(
                existing.copyWith(
                  subcategory: subName,
                  title: title.text.trim(),
                  why: why.text.trim(),
                  isDaily: isDaily,
                  reminderTime: reminder,
                  dueAt: due?.millisecondsSinceEpoch,
                  alertBeforeMin: due == null ? 0 : alertBefore,
                ),
              );
            }
            Navigator.pop(context);
          }

          final now = DateTime.now();
          final quickDue = <String, DateTime>{
            'IN 1H': now.add(const Duration(hours: 1)),
            if (now.hour < 20) 'TONIGHT 8PM': DateTime(now.year, now.month, now.day, 20),
            'TOMORROW 9AM': DateTime(now.year, now.month, now.day + 1, 9),
          };

          return BrutalDialog(
            title: Text(existing == null ? 'New Task in ➔ $channelName' : 'Edit Task'),
            content: SizedBox(
              width: 400,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _labeled(
                      'SUBCATEGORY',
                      TextField(
                        controller: sub,
                        decoration: fieldDecoration(hint: 'e.g., General'),
                      ),
                    ),
                    if (suggestions.length > 1 || (suggestions.length == 1 && suggestions.first != sub.text))
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final s in suggestions)
                              InkWell(
                                onTap: () => setModalState(() => sub.text = s),
                                child: Tag(s, color: sub.text == s ? kMint : kChipOff),
                              ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 12),
                    _labeled(
                      'TASK',
                      TextField(
                        controller: title,
                        autofocus: existing == null,
                        onSubmitted: (_) => save(),
                        decoration: fieldDecoration(hint: 'e.g., Code review').copyWith(errorText: error),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _labeled(
                      'WHY',
                      TextField(
                        controller: why,
                        onSubmitted: (_) => save(),
                        decoration: fieldDecoration(hint: 'e.g., ship product cleanly'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Material(
                      color: kChipOff,
                      borderRadius: BorderRadius.circular(8),
                      child: CheckboxListTile(
                        title: const Text('Daily Reset Task?', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                        value: isDaily,
                        activeColor: Colors.black,
                        checkColor: kMint,
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                        onChanged: (v) => setModalState(() => isDaily = v ?? false),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Text(
                          'Reminder Time:',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: Colors.black87),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () async {
                            final t = await pickTime(context, initial: reminder);
                            if (t != null) setModalState(() => reminder = t);
                          },
                          child: Text(
                            reminder == null ? 'Set Time' : formatHm(reminder!),
                            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black54),
                          ),
                        ),
                        if (reminder != null)
                          IconButton(icon: const Icon(Icons.clear, size: 16), onPressed: () => setModalState(() => reminder = null)),
                      ],
                    ),
                    Row(
                      children: [
                        const Text(
                          'Due (timed task):',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: Colors.black87),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () async {
                            final d = await pickDueDateTime(context, due);
                            if (d != null) setModalState(() => due = d);
                          },
                          child: Text(
                            due == null ? 'Set Due' : describeDue(due!, now),
                            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black54),
                          ),
                        ),
                        if (due != null)
                          IconButton(icon: const Icon(Icons.clear, size: 16), onPressed: () => setModalState(() => due = null)),
                      ],
                    ),
                    if (due == null)
                      Wrap(
                        spacing: 6,
                        children: [
                          for (final e in quickDue.entries)
                            InkWell(
                              onTap: () => setModalState(() => due = e.value),
                              child: Tag(e.key, color: kChipOff, icon: Icons.bolt),
                            ),
                        ],
                      )
                    else
                      Row(
                        children: [
                          const Text(
                            'Heads-up:',
                            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: Colors.black87),
                          ),
                          const Spacer(),
                          DropdownButton<int>(
                            value: alertBefore,
                            underline: const SizedBox(),
                            style: Theme.of(
                              context,
                            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold, color: Colors.black54, fontSize: 13),
                            items: const [
                              DropdownMenuItem(value: 0, child: Text('At due time')),
                              DropdownMenuItem(value: 5, child: Text('5 min before')),
                              DropdownMenuItem(value: 15, child: Text('15 min before')),
                              DropdownMenuItem(value: 30, child: Text('30 min before')),
                              DropdownMenuItem(value: 60, child: Text('1 hour before')),
                              DropdownMenuItem(value: 1440, child: Text('1 day before')),
                            ],
                            onChanged: (v) => setModalState(() => alertBefore = v ?? 0),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              if (existing == null)
                const CancelButton()
              else
                TextButton(
                  onPressed: () {
                    store.deleteTask(existing.id);
                    Navigator.pop(context, existing);
                  },
                  child: const Text(
                    'DELETE',
                    style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                  ),
                ),
              ElevatedButton(
                style: kPrimaryButton,
                onPressed: save,
                child: Text(existing == null ? 'CREATE' : 'SAVE', style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    ),
  );
}

// -----------------------------------------------------------------------------
// Channels
// -----------------------------------------------------------------------------

Future<void> showAddChannel(BuildContext context, AppStore store) {
  final c = TextEditingController();
  String? error;
  return showDialog(
    context: context,
    builder: (context) => _DisposeWith(
      [c],
      child: StatefulBuilder(
        builder: (context, setState) {
          void add() {
            if (c.text.trim().isEmpty) return;
            if (store.addChannel(c.text) == null) {
              setState(() => error = 'That category already exists.');
              return;
            }
            Navigator.pop(context);
          }

          return BrutalDialog(
            title: const Text('New Category Channel'),
            content: TextField(
              controller: c,
              autofocus: true,
              onSubmitted: (_) => add(),
              decoration: fieldDecoration(hint: 'e.g., Fitness, Coding').copyWith(errorText: error),
            ),
            actions: [
              const CancelButton(),
              ElevatedButton(
                style: kPrimaryButton,
                onPressed: add,
                child: const Text('ADD', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    ),
  );
}

Future<void> showEditChannel(BuildContext context, AppStore store, Channel channel) {
  final c = TextEditingController(text: channel.name);
  String? error;
  return showDialog(
    context: context,
    builder: (dialogContext) => _DisposeWith(
      [c],
      child: StatefulBuilder(
        builder: (dialogContext, setState) {
          final list = store.aliveChannels;
          final idx = list.indexWhere((x) => x.id == channel.id);
          void save() {
            if (c.text.trim() == channel.name || store.renameChannel(channel.id, c.text)) {
              Navigator.pop(dialogContext);
            } else {
              setState(() => error = c.text.trim().isEmpty ? 'Name can\'t be empty.' : 'That name is taken.');
            }
          }

          return BrutalDialog(
            title: Row(
              children: [
                const Expanded(child: Text('Edit or Delete Category')),
                IconButton(
                  tooltip: 'Move left',
                  icon: const Icon(Icons.chevron_left_rounded),
                  onPressed: idx > 0 ? () => setState(() => store.moveChannel(channel.id, -1)) : null,
                ),
                IconButton(
                  tooltip: 'Move right',
                  icon: const Icon(Icons.chevron_right_rounded),
                  onPressed: idx < list.length - 1 ? () => setState(() => store.moveChannel(channel.id, 1)) : null,
                ),
              ],
            ),
            content: TextField(
              controller: c,
              autofocus: true,
              onSubmitted: (_) => save(),
              decoration: fieldDecoration().copyWith(errorText: error),
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  final count = store.tasksIn(channel.id).length;
                  final ok = await confirm(
                    dialogContext,
                    'Delete "${channel.name}"?',
                    count == 0 ? 'This category is empty.' : 'This also deletes its $count task${count == 1 ? '' : 's'}.',
                  );
                  if (!ok) return;
                  store.deleteChannel(channel.id);
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                },
                child: const Text(
                  'DELETE',
                  style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                ),
              ),
              ElevatedButton(
                style: kPrimaryButton,
                onPressed: save,
                child: const Text('SAVE', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    ),
  );
}

// -----------------------------------------------------------------------------
// Sync
// -----------------------------------------------------------------------------

Future<void> showSyncDialog(BuildContext context, SyncService sync) {
  return showDialog(
    context: context,
    builder: (_) => _SyncDialog(sync: sync),
  );
}

class _SyncDialog extends StatefulWidget {
  const _SyncDialog({required this.sync});
  final SyncService sync;

  @override
  State<_SyncDialog> createState() => _SyncDialogState();
}

class _SyncDialogState extends State<_SyncDialog> {
  late final TextEditingController _addr = TextEditingController(text: widget.sync.hubAddress ?? '');
  late final TextEditingController _code = TextEditingController(text: widget.sync.clientKey ?? '');
  List<DiscoveredHub>? _found;
  bool _scanning = false;
  late bool _clientForm = widget.sync.mode == SyncMode.client;

  bool get _showClient => _clientForm || sync.mode == SyncMode.client;

  SyncService get sync => widget.sync;

  @override
  void initState() {
    super.initState();
    sync.addListener(_refresh);
  }

  @override
  void dispose() {
    sync.removeListener(_refresh);
    _addr.dispose();
    _code.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _scan() async {
    setState(() => _scanning = true);
    final hubs = await SyncService.discover();
    if (!mounted) return;
    setState(() {
      _scanning = false;
      _found = hubs;
      if (hubs.length == 1 && _addr.text.isEmpty) _addr.text = hubs.first.address;
    });
  }

  String _ago(DateTime? t) {
    if (t == null) return 'never';
    final d = DateTime.now().difference(t);
    if (d.inSeconds < 60) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    return formatTime(t);
  }

  Widget _modeButton(SyncMode m, String label) {
    final on = m == SyncMode.client ? _showClient : (sync.mode == m && !_clientForm);
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() => _clientForm = m == SyncMode.client);
          // CONNECT only switches mode once there's a saved hub; otherwise
          // the form is shown and the CONNECT button below starts it.
          if (m != SyncMode.client || sync.hubAddress != null) sync.setMode(m);
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? kMint : kChipOff,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.black, width: 2),
          ),
          child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const note = TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black54);
    const strong = TextStyle(fontSize: 13, fontWeight: FontWeight.w900);

    return BrutalDialog(
      title: const Text('SYNC DEVICES'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Keep this device and your others in sync over the same Wi-Fi. No account needed.', style: note),
              const SizedBox(height: 12),
              Row(
                children: [
                  _modeButton(SyncMode.off, 'OFF'),
                  _modeButton(SyncMode.hub, 'BE THE HUB'),
                  _modeButton(SyncMode.client, 'CONNECT'),
                ],
              ),
              const SizedBox(height: 14),
              if (sync.mode == SyncMode.off && !_showClient)
                Text(
                  SyncService.isDesktop
                      ? 'Tip: make this computer the hub, then tap CONNECT on your phone.'
                      : 'Tip: open H List on your computer, pick BE THE HUB, then CONNECT here.',
                  style: note,
                ),
              if (sync.mode == SyncMode.hub && !_showClient) ...[
                const Text('PAIRING CODE', style: kFieldLabel),
                Row(
                  children: [
                    SelectableText(sync.pairCode, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 6)),
                    const Spacer(),
                    TextButton(
                      onPressed: sync.regeneratePairCode,
                      child: const Text(
                        'NEW CODE',
                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black54),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text('THIS HUB\'S ADDRESS', style: kFieldLabel),
                if (sync.hubPort == null)
                  Text(sync.lastError ?? 'Starting…', style: note)
                else
                  for (final a in sync.localAddresses) SelectableText('$a:${sync.hubPort}', style: strong),
                const SizedBox(height: 8),
                Text(
                  sync.connectedClients.isEmpty
                      ? 'Waiting for devices… (allow H List through your firewall if asked)'
                      : 'Connected: ${sync.connectedClients.keys.join(', ')} • last sync ${_ago(sync.lastSyncAt)}',
                  style: note,
                ),
              ],
              if (_showClient) ...[
                Row(
                  children: [
                    const Text('HUB ADDRESS', style: kFieldLabel),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _scanning ? null : _scan,
                      icon: _scanning
                          ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                          : const Icon(Icons.wifi_find_rounded, size: 16, color: Colors.black),
                      label: const Text(
                        'FIND HUB',
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, color: Colors.black),
                      ),
                    ),
                  ],
                ),
                if (_found != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: _found!.isEmpty
                        ? const Text('No hub found. Type its address instead.', style: note)
                        : Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final h in _found!)
                                InkWell(
                                  onTap: () => setState(() => _addr.text = h.address),
                                  child: Tag(
                                    '${h.name} • ${h.address}',
                                    color: _addr.text == h.address ? kMint : kChipOff,
                                    icon: Icons.computer,
                                  ),
                                ),
                            ],
                          ),
                  ),
                TextField(
                  controller: _addr,
                  decoration: fieldDecoration(hint: 'e.g., 192.168.1.20:$kSyncPort'),
                ),
                const SizedBox(height: 10),
                _labeled(
                  'PAIRING CODE (shown on the hub)',
                  TextField(
                    controller: _code,
                    keyboardType: TextInputType.number,
                    decoration: fieldDecoration(hint: '6 digits'),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        sync.lastError ?? (sync.lastSyncAt == null ? 'Not synced yet' : 'Synced ${_ago(sync.lastSyncAt)}'),
                        style: note.copyWith(color: sync.lastError != null ? Colors.red.shade700 : Colors.black54),
                      ),
                    ),
                    ElevatedButton(
                      style: kPrimaryButton,
                      onPressed: () {
                        if (_addr.text.trim().isEmpty || _code.text.trim().isEmpty) {
                          setState(() => sync.lastError = 'Enter the hub address and pairing code.');
                          return;
                        }
                        sync.connectTo(_addr.text, _code.text);
                      },
                      child: Text(
                        sync.mode == SyncMode.client ? 'SYNC NOW' : 'CONNECT',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: const [CancelButton(label: 'DONE')],
    );
  }
}
