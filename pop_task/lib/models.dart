import 'dart:math';

final Random _rng = Random();

/// Globally unique-enough id: time + random suffix, so two devices creating
/// items in the same millisecond don't collide when synced.
String newId() => '${DateTime.now().millisecondsSinceEpoch}-${_rng.nextInt(0x7fffffff).toRadixString(36)}';

int nowMs() => DateTime.now().millisecondsSinceEpoch;

String dateKey(DateTime date) => "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";

class Channel {
  final String id;
  final String name;
  final int order;
  final int updatedAt;
  final bool deleted;

  const Channel({required this.id, required this.name, required this.order, required this.updatedAt, this.deleted = false});

  Channel copyWith({String? name, int? order, bool? deleted}) =>
      Channel(id: id, name: name ?? this.name, order: order ?? this.order, updatedAt: nowMs(), deleted: deleted ?? this.deleted);

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'order': order, 'updatedAt': updatedAt, 'deleted': deleted};

  factory Channel.fromJson(Map<String, dynamic> json) => Channel(
    id: json['id']?.toString() ?? newId(),
    name: json['name']?.toString() ?? 'General',
    order: (json['order'] as num?)?.toInt() ?? 0,
    updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
    deleted: json['deleted'] == true,
  );
}

class Task {
  final String id;
  final String channelId;
  final String subcategory;
  final String title;
  final String why;
  final bool isDaily;

  /// For non-daily tasks: whether it is done.
  final bool isCompleted;

  /// For daily tasks: the day ("yyyy-MM-dd") it was last checked off. A daily
  /// task counts as done only on that day, so resets need no writes (and so
  /// never conflict during sync).
  final String? lastCompletedDate;

  /// Repeating reminder, "HH:mm" 24h.
  final String? reminderTime;

  /// Timed todo: a one-off deadline (ms since epoch).
  final int? dueAt;

  /// Minutes before [dueAt] to send an early heads-up (0 = none).
  final int alertBeforeMin;

  final int createdAt;
  final int? completedAt;
  final int updatedAt;
  final bool deleted;

  const Task({
    required this.id,
    required this.channelId,
    required this.subcategory,
    required this.title,
    required this.why,
    required this.isDaily,
    this.isCompleted = false,
    this.lastCompletedDate,
    this.reminderTime,
    this.dueAt,
    this.alertBeforeMin = 0,
    required this.createdAt,
    this.completedAt,
    required this.updatedAt,
    this.deleted = false,
  });

  bool isDoneOn(String today) => isDaily ? lastCompletedDate == today : isCompleted;

  DateTime? get dueDate => dueAt == null ? null : DateTime.fromMillisecondsSinceEpoch(dueAt!);

  static const _unset = Object();

  Task copyWith({
    String? channelId,
    String? subcategory,
    String? title,
    String? why,
    bool? isDaily,
    bool? isCompleted,
    Object? lastCompletedDate = _unset,
    Object? reminderTime = _unset,
    Object? dueAt = _unset,
    int? alertBeforeMin,
    Object? completedAt = _unset,
    bool? deleted,
  }) => Task(
    id: id,
    channelId: channelId ?? this.channelId,
    subcategory: subcategory ?? this.subcategory,
    title: title ?? this.title,
    why: why ?? this.why,
    isDaily: isDaily ?? this.isDaily,
    isCompleted: isCompleted ?? this.isCompleted,
    lastCompletedDate: identical(lastCompletedDate, _unset) ? this.lastCompletedDate : lastCompletedDate as String?,
    reminderTime: identical(reminderTime, _unset) ? this.reminderTime : reminderTime as String?,
    dueAt: identical(dueAt, _unset) ? this.dueAt : dueAt as int?,
    alertBeforeMin: alertBeforeMin ?? this.alertBeforeMin,
    createdAt: createdAt,
    completedAt: identical(completedAt, _unset) ? this.completedAt : completedAt as int?,
    updatedAt: nowMs(),
    deleted: deleted ?? this.deleted,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'channelId': channelId,
    'subcategory': subcategory,
    'title': title,
    'why': why,
    'isDaily': isDaily,
    'isCompleted': isCompleted,
    'lastCompletedDate': lastCompletedDate,
    'reminderTime': reminderTime,
    'dueAt': dueAt,
    'alertBeforeMin': alertBeforeMin,
    'createdAt': createdAt,
    'completedAt': completedAt,
    'updatedAt': updatedAt,
    'deleted': deleted,
  };

  factory Task.fromJson(Map<String, dynamic> json) => Task(
    id: json['id']?.toString() ?? newId(),
    channelId: json['channelId']?.toString() ?? '',
    subcategory: json['subcategory']?.toString() ?? 'General',
    title: json['title']?.toString() ?? '',
    why: json['why']?.toString() ?? '',
    isDaily: json['isDaily'] == true,
    isCompleted: json['isCompleted'] == true,
    lastCompletedDate: json['lastCompletedDate']?.toString(),
    reminderTime: json['reminderTime']?.toString(),
    dueAt: (json['dueAt'] as num?)?.toInt(),
    alertBeforeMin: (json['alertBeforeMin'] as num?)?.toInt() ?? 0,
    createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
    completedAt: (json['completedAt'] as num?)?.toInt(),
    updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
    deleted: json['deleted'] == true,
  );
}

/// Everything that syncs between devices. Device-local settings (sound,
/// collapsed groups, sync config) live outside this.
class SyncData {
  final Map<String, Channel> channels;
  final Map<String, Task> tasks;

  const SyncData({required this.channels, required this.tasks});

  Map<String, dynamic> toJson() => {
    'schema': 17,
    'channels': channels.values.map((c) => c.toJson()).toList(),
    'tasks': tasks.values.map((t) => t.toJson()).toList(),
  };

  factory SyncData.fromJson(Map<String, dynamic> json) {
    final channels = <String, Channel>{};
    for (final c in (json['channels'] as List? ?? const [])) {
      final ch = Channel.fromJson(Map<String, dynamic>.from(c as Map));
      channels[ch.id] = ch;
    }
    final tasks = <String, Task>{};
    for (final t in (json['tasks'] as List? ?? const [])) {
      final task = Task.fromJson(Map<String, dynamic>.from(t as Map));
      tasks[task.id] = task;
    }
    return SyncData(channels: channels, tasks: tasks);
  }

  /// Last-writer-wins merge per item. Deletions are kept as tombstones so
  /// they propagate instead of being resurrected by the other side.
  static SyncData merge(SyncData a, SyncData b) {
    final channels = Map<String, Channel>.from(a.channels);
    b.channels.forEach((id, c) {
      final mine = channels[id];
      if (mine == null || c.updatedAt > mine.updatedAt) channels[id] = c;
    });
    final tasks = Map<String, Task>.from(a.tasks);
    b.tasks.forEach((id, t) {
      final mine = tasks[id];
      if (mine == null || t.updatedAt > mine.updatedAt) tasks[id] = t;
    });
    return SyncData(channels: channels, tasks: tasks);
  }
}
