import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initializationSettings =
      InitializationSettings(android: initializationSettingsAndroid);
  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  runApp(const HListApp());
}

class HListApp extends StatelessWidget {
  const HListApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'H list',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFFFFDF5),
        primaryColor: const Color(0xFFDAECE0),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFDAECE0),
          primary: const Color(0xFFDAECE0),
          surface: Colors.white,
        ),
        textTheme: GoogleFonts.fredokaTextTheme(
          ThemeData.light().textTheme,
        ),
      ),
      home: const HListHomeScreen(),
    );
  }
}

class Task {
  String id;
  String channel;
  String subcategory;
  String title;
  String why;
  bool isDaily;
  bool isCompleted;
  String? lastCompletedDate;
  String? reminderTime;

  Task({
    required this.id,
    required this.channel,
    required this.subcategory,
    required this.title,
    required this.why,
    required this.isDaily,
    this.isCompleted = false,
    this.lastCompletedDate,
    this.reminderTime,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'channel': channel,
        'subcategory': subcategory,
        'title': title,
        'why': why,
        'isDaily': isDaily,
        'isCompleted': isCompleted,
        'lastCompletedDate': lastCompletedDate,
        'reminderTime': reminderTime,
      };

  factory Task.fromJson(Map<String, dynamic> json) => Task(
        id: json['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
        channel: json['channel']?.toString() ?? 'Arts',
        subcategory: json['subcategory']?.toString() ?? 'General',
        title: json['title']?.toString() ?? '',
        why: json['why']?.toString() ?? '',
        isDaily: json['isDaily'] == true,
        isCompleted: json['isCompleted'] == true,
        lastCompletedDate: json['lastCompletedDate']?.toString(),
        reminderTime: json['reminderTime']?.toString(),
      );
}

class HListHomeScreen extends StatefulWidget {
  const HListHomeScreen({super.key});

  @override
  State<HListHomeScreen> createState() => _HListHomeScreenState();
}

class _HListHomeScreenState extends State<HListHomeScreen> with WidgetsBindingObserver {
  List<Task> tasks = [];
  List<String> channels = ['Arts', 'Music'];
  String _selectedCategoryFilter = 'Arts';
  String _favoriteCategory = 'Arts';

  final Set<String> _collapsedSubcategories = {};

  final TextEditingController _subController = TextEditingController();
  final TextEditingController _taskController = TextEditingController();
  final TextEditingController _whyController = TextEditingController();
  bool _isDailyTask = false;
  String? _reminderTime;
  bool _soundEnabled = true;

  Timer? _alarmTimer;
  String? _lastTriggeredMinute;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadData();
    _startAlarmChecker();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subController.dispose();
    _taskController.dispose();
    _whyController.dispose();
    _alarmTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAlarmsAndResets();
    }
  }

  void _startAlarmChecker() {
    _alarmTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _checkAlarmsAndResets();
    });
  }

  Future<void> _showSystemNotification(String title, String body) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'h_list_alarms_v2',
      'Task Reminders & Alarms',
      channelDescription: 'Notifications for H List Task Alarms with sound',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      sound: RawResourceAndroidNotificationSound('notification'),
    );
    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    await flutterLocalNotificationsPlugin.show(
      DateTime.now().millisecond,
      "⏰ H LIST: $title",
      body,
      platformChannelSpecifics,
    );
  }

  void _checkAlarmsAndResets() {
    if (!_soundEnabled) return;
    final now = DateTime.now();
    final currentTimeStr = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";
    final todayStr = _getDateString(now);

    bool dataChanged = false;

    for (var task in tasks) {
      if (task.isDaily && task.lastCompletedDate != null && task.lastCompletedDate != todayStr) {
        task.isCompleted = false;
        task.lastCompletedDate = null;
        dataChanged = true;
      }

      if (!task.isCompleted && task.reminderTime == currentTimeStr) {
        if (_lastTriggeredMinute != "${todayStr}_$currentTimeStr") {
          _lastTriggeredMinute = "${todayStr}_$currentTimeStr";
          _playNotificationAudio();
          _showSystemNotification(task.title, task.why);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: const Color(0xFFFFDE00),
                content: Text(
                  "🔔 ALARM: ${task.title} (${task.reminderTime})",
                  style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900),
                ),
                duration: const Duration(seconds: 6),
              ),
            );
          }
        }
      }
    }

    if (dataChanged) {
      _saveData();
      setState(() {});
    }
  }

  Future<void> _playNotificationAudio() async {
    try {
      final player = AudioPlayer();
      await player.play(AssetSource('notification.mp3'));
    } catch (_) {
      HapticFeedback.heavyImpact();
    }
  }

  Future<void> _playSound() async {
    if (!_soundEnabled) return;
    try {
      final player = AudioPlayer();
      await player.play(AssetSource('button.mp3'));
    } catch (_) {
      HapticFeedback.lightImpact();
    }
  }

  String _getDateString(DateTime date) {
    return "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    
    _soundEnabled = prefs.getBool('h_list_sound_enabled') ?? true;
    _favoriteCategory = prefs.getString('h_list_favorite_category') ?? 'Arts';

    final String? channelsString = prefs.getString('h_list_channels_v16');
    if (channelsString != null) {
      try {
        List decoded = jsonDecode(channelsString);
        channels = decoded.map((e) => e.toString()).toList();
      } catch (_) {}
    }
    if (channels.isEmpty) channels = ['General'];
    if (!channels.contains(_selectedCategoryFilter)) {
      _selectedCategoryFilter = channels.first;
    }

    final String? tasksString = prefs.getString('h_list_nested_tasks_v16');
    if (tasksString != null) {
      try {
        List decodedTasks = jsonDecode(tasksString);
        tasks = decodedTasks.map((e) => Task.fromJson(e as Map<String, dynamic>)).toList();
        
        String todayStr = _getDateString(DateTime.now());
        for (var task in tasks) {
          if (task.isDaily && task.lastCompletedDate != todayStr) {
            task.isCompleted = false;
            task.lastCompletedDate = null;
          }
        }
      } catch (_) {
        tasks = [];
      }
    }
    setState(() {});
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('h_list_sound_enabled', _soundEnabled);
    await prefs.setString('h_list_favorite_category', _favoriteCategory);
    await prefs.setString('h_list_channels_v16', jsonEncode(channels));
    await prefs.setString('h_list_nested_tasks_v16', jsonEncode(tasks.map((e) => e.toJson()).toList()));
  }

  void _addNewChannel(String channelName) {
    String trimmed = channelName.trim();
    if (trimmed.isEmpty || channels.contains(trimmed)) return;
    _playSound();

    setState(() {
      channels.add(trimmed);
      _selectedCategoryFilter = trimmed;
    });
    _saveData();
  }

  void _editChannel(String oldName) {
    _playSound();
    final TextEditingController editChanController = TextEditingController(text: oldName);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Colors.black, width: 2),
        ),
        title: const Text("Edit or Delete Category", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Colors.black)),
        content: TextField(
          controller: editChanController,
          autofocus: true,
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFFF9FAFB),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFDAECE0), width: 2)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              _playSound();
              setState(() {
                channels.remove(oldName);
                tasks.removeWhere((t) => t.channel == oldName);
                if (channels.isNotEmpty) {
                  _selectedCategoryFilter = channels.first;
                } else {
                  channels.add('General');
                  _selectedCategoryFilter = 'General';
                }
              });
              _saveData();
              Navigator.pop(context);
            },
            child: const Text("DELETE", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDAECE0), foregroundColor: Colors.black, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            onPressed: () {
              _playSound();
              String newName = editChanController.text.trim();
              if (newName.isNotEmpty && !channels.contains(newName)) {
                setState(() {
                  int idx = channels.indexOf(oldName);
                  if (idx != -1) channels[idx] = newName;
                  for (var t in tasks) {
                    if (t.channel == oldName) t.channel = newName;
                  }
                  _selectedCategoryFilter = newName;
                });
                _saveData();
              }
              Navigator.pop(context);
            },
            child: const Text("SAVE", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _addNewTask({String specificSubcategory = 'General'}) {
    if (_taskController.text.trim().isEmpty) return;
    _playSound();

    String targetSub = specificSubcategory.trim().isEmpty ? 'General' : specificSubcategory.trim();

    setState(() {
      tasks.add(Task(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        channel: _selectedCategoryFilter,
        subcategory: targetSub,
        title: _taskController.text.trim(),
        why: _whyController.text.trim().isEmpty ? "Build consistency" : _whyController.text.trim(),
        isDaily: _isDailyTask,
        reminderTime: _reminderTime,
      ));
      _subController.clear();
      _taskController.clear();
      _whyController.clear();
      _isDailyTask = false;
      _reminderTime = null;
    });
    _saveData();
    Navigator.pop(context);
  }

  void _toggleTask(Task task) {
    _playSound();
    setState(() {
      task.isCompleted = !task.isCompleted;
      String todayStr = _getDateString(DateTime.now());
      if (task.isCompleted && task.isDaily) {
        task.lastCompletedDate = todayStr;
      } else if (!task.isCompleted) {
        task.lastCompletedDate = null;
      }
    });
    _saveData();
  }

  void _deleteTask(String id) {
    _playSound();
    setState(() {
      tasks.removeWhere((element) => element.id == id);
    });
    _saveData();
  }

  void _showAddChannelDialog() {
    _playSound();
    final TextEditingController newChannelController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Colors.black, width: 2)),
        title: const Text("New Category Channel", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Colors.black)),
        content: TextField(
          controller: newChannelController,
          autofocus: true,
          onSubmitted: (_) {
            _addNewChannel(newChannelController.text);
            Navigator.pop(context);
          },
          decoration: InputDecoration(
            hintText: "e.g., Fitness, Coding",
            filled: true,
            fillColor: const Color(0xFFF9FAFB),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFDAECE0), width: 2)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCEL", style: TextStyle(color: Colors.black54, fontWeight: FontWeight.bold))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDAECE0), foregroundColor: Colors.black, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            onPressed: () {
              _addNewChannel(newChannelController.text);
              Navigator.pop(context);
            },
            child: const Text("ADD", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showCustomTimePicker(StateSetter setModalState, Function(String) onTimeSelected) {
    int selectedHour = 5;
    int selectedMinute = 0;
    bool isPm = true;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setTimeState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Colors.black, width: 2),
              ),
              title: const Text("SET REMINDER TIME", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      DropdownButton<int>(
                        value: selectedHour,
                        items: List.generate(12, (index) => index + 1).map((val) {
                          return DropdownMenuItem(value: val, child: Text(val.toString().padLeft(2, '0'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)));
                        }).toList(),
                        onChanged: (val) => setTimeState(() => selectedHour = val ?? 5),
                      ),
                      const Text(" : ", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                      DropdownButton<int>(
                        value: selectedMinute,
                        items: [0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55].map((val) {
                          return DropdownMenuItem(value: val, child: Text(val.toString().padLeft(2, '0'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)));
                        }).toList(),
                        onChanged: (val) => setTimeState(() => selectedMinute = val ?? 0),
                      ),
                      const SizedBox(width: 12),
                      ToggleButtons(
                        isSelected: [!isPm, isPm],
                        onPressed: (index) => setTimeState(() => isPm = index == 1),
                        borderRadius: BorderRadius.circular(8),
                        selectedColor: Colors.black,
                        fillColor: const Color(0xFFDAECE0),
                        color: Colors.black54,
                        constraints: const BoxConstraints(minWidth: 40, minHeight: 38),
                        children: const [
                          Text("AM", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          Text("PM", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("CANCEL", style: TextStyle(color: Colors.black54, fontWeight: FontWeight.bold)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFDAECE0),
                    foregroundColor: Colors.black,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: const BorderSide(color: Colors.black, width: 2),
                    ),
                  ),
                  onPressed: () {
                    int finalHour = selectedHour;
                    if (isPm && finalHour != 12) finalHour += 12;
                    if (!isPm && finalHour == 12) finalHour = 0;
                    
                    String formatted = "${finalHour.toString().padLeft(2, '0')}:${selectedMinute.toString().padLeft(2, '0')}";
                    setModalState(() {
                      onTimeSelected(formatted);
                    });
                    Navigator.pop(context);
                  },
                  child: const Text("ENTER", style: TextStyle(fontWeight: FontWeight.w900)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showAddTaskModal({String defaultSubcategory = 'General'}) {
    _playSound();
    _reminderTime = null;
    _subController.text = defaultSubcategory;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Colors.black, width: 2)),
          title: Text("New Task in ➔ $_selectedCategoryFilter", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Colors.black)),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildModalTextField("SUBCATEGORY", _subController, hint: "e.g., General"),
                  const SizedBox(height: 12),
                  _buildModalTextField("TASK", _taskController, hint: "e.g., Code review", onSubmitted: (_) => _addNewTask(specificSubcategory: _subController.text)),
                  const SizedBox(height: 12),
                  _buildModalTextField("WHY", _whyController, hint: "e.g., ship product cleanly", onSubmitted: (_) => _addNewTask(specificSubcategory: _subController.text)),
                  const SizedBox(height: 12),
                  Material(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(8),
                    child: CheckboxListTile(
                      title: const Text("Daily Reset Task?", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      value: _isDailyTask,
                      activeColor: Colors.black,
                      checkColor: const Color(0xFFDAECE0),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      onChanged: (val) {
                        setModalState(() {
                          _isDailyTask = val ?? false;
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Text("Reminder Time:", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: Colors.black87)),
                      const Spacer(),
                      TextButton(
                        onPressed: () => _showCustomTimePicker(setModalState, (time) => _reminderTime = time),
                        child: Text(_reminderTime ?? "Set Time", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black54)),
                      ),
                      if (_reminderTime != null)
                        IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          onPressed: () => setModalState(() => _reminderTime = null),
                        )
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCEL", style: TextStyle(color: Colors.black54, fontWeight: FontWeight.bold))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDAECE0), foregroundColor: Colors.black, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              onPressed: () => _addNewTask(specificSubcategory: _subController.text),
              child: const Text("CREATE", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditTaskModal(Task task) {
    _playSound();
    final TextEditingController editSubController = TextEditingController(text: task.subcategory);
    final TextEditingController editTitleController = TextEditingController(text: task.title);
    final TextEditingController editWhyController = TextEditingController(text: task.why);
    bool editIsDaily = task.isDaily;
    String? editReminder = task.reminderTime;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Colors.black, width: 2)),
          title: const Text("Edit Task", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Colors.black)),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildCustomField("SUBCATEGORY", editSubController),
                  const SizedBox(height: 12),
                  _buildCustomField("TASK", editTitleController, onSubmitted: (_) {
                    setState(() {
                      task.subcategory = editSubController.text.trim();
                      task.title = editTitleController.text.trim();
                      task.why = editWhyController.text.trim();
                      task.isDaily = editIsDaily;
                      task.reminderTime = editReminder;
                    });
                    _saveData();
                    Navigator.pop(context);
                  }),
                  const SizedBox(height: 12),
                  _buildCustomField("WHY", editWhyController),
                  const SizedBox(height: 12),
                  Material(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(8),
                    child: CheckboxListTile(
                      title: const Text("Daily Reset Task?", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      value: editIsDaily,
                      activeColor: Colors.black,
                      checkColor: const Color(0xFFDAECE0),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      onChanged: (val) {
                        setModalState(() {
                          editIsDaily = val ?? false;
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Text("Reminder Time:", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: Colors.black87)),
                      const Spacer(),
                      TextButton(
                        onPressed: () => _showCustomTimePicker(setModalState, (time) => editReminder = time),
                        child: Text(editReminder ?? "Set Time", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black54)),
                      ),
                      if (editReminder != null)
                        IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          onPressed: () => setModalState(() => editReminder = null),
                        )
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                _deleteTask(task.id);
                Navigator.pop(context);
              },
              child: const Text("DELETE", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDAECE0), foregroundColor: Colors.black, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              onPressed: () {
                setState(() {
                  task.subcategory = editSubController.text.trim();
                  task.title = editTitleController.text.trim();
                  task.why = editWhyController.text.trim();
                  task.isDaily = editIsDaily;
                  task.reminderTime = editReminder;
                });
                _saveData();
                Navigator.pop(context);
              },
              child: const Text("SAVE", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModalTextField(String label, TextEditingController controller, {String hint = '', ValueChanged<String>? onSubmitted}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11, color: Colors.black54)),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          autofocus: label == 'TASK',
          onSubmitted: onSubmitted,
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: const Color(0xFFF9FAFB),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.black26)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.black26)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFDAECE0), width: 2)),
          ),
        ),
      ],
    );
  }

  Widget _buildCustomField(String label, TextEditingController controller, {ValueChanged<String>? onSubmitted}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11, color: Colors.black54)),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          onSubmitted: onSubmitted,
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFFF9FAFB),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.black26)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.black26)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFDAECE0), width: 2)),
          ),
        ),
      ],
    );
  }

  void _handleSwipe(DragEndDetails details) {
    int currentIndex = channels.indexOf(_selectedCategoryFilter);
    if (currentIndex == -1) return;

    if (details.primaryVelocity! < 0) {
      if (currentIndex < channels.length - 1) {
        setState(() {
          _selectedCategoryFilter = channels[currentIndex + 1];
        });
        _playSound();
      }
    } else if (details.primaryVelocity! > 0) {
      if (currentIndex > 0) {
        setState(() {
          _selectedCategoryFilter = channels[currentIndex - 1];
        });
        _playSound();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    List<Task> channelTasks = tasks.where((t) => t.channel == _selectedCategoryFilter).toList();
    List<Task> activeTasks = channelTasks.where((t) => !t.isCompleted).toList();
    List<Task> completedTasks = channelTasks.where((t) => t.isCompleted).toList();

    List<Task> favTasks = tasks.where((t) => t.channel == _favoriteCategory && !t.isCompleted).toList();

    Map<String, List<Task>> groupedActive = {};
    for (var task in activeTasks) {
      groupedActive.putIfAbsent(task.subcategory, () => []);
      groupedActive[task.subcategory]!.add(task);
    }

    return Scaffold(
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
                image: const DecorationImage(
                  image: AssetImage('assets/logo.png'),
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              "H LIST",
              style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 22),
            ),
            const Spacer(),
            IconButton(
              icon: Icon(_soundEnabled ? Icons.volume_up_rounded : Icons.volume_off_rounded, color: Colors.black),
              onPressed: () {
                setState(() {
                  _soundEnabled = !_soundEnabled;
                });
                _saveData();
              },
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // In-App Widget listing Favorite Spot Tasks
          Container(
            width: double.infinity,
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFDAECE0).withOpacity(0.5),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.black, width: 2),
              boxShadow: const [
                BoxShadow(color: Colors.black, offset: Offset(2, 2), spreadRadius: 0)
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text("FAV SPOT: ${_favoriteCategory.toUpperCase()}", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.black)),
                    const Spacer(),
                    InkWell(
                      onTap: () {
                        setState(() {
                          _selectedCategoryFilter = _favoriteCategory;
                        });
                        _playSound();
                      },
                      child: const Text("VIEW ALL ➔", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.black54)),
                    )
                  ],
                ),
                const SizedBox(height: 6),
                favTasks.isEmpty
                    ? const Text("No active tasks in your favorite spot.", style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.black54))
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: favTasks.take(3).map((t) => Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text("• ${t.title}", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87)),
                        )).toList(),
                      ),
              ],
            ),
          ),

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
                      String cat = channels[index];
                      bool isSelected = _selectedCategoryFilter == cat;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: InkWell(
                          onLongPress: () => _editChannel(cat),
                          borderRadius: BorderRadius.circular(8),
                          child: ActionChip(
                            label: Text(cat.toUpperCase()),
                            avatar: isSelected ? const Icon(Icons.edit, size: 14, color: Colors.black) : null,
                            backgroundColor: isSelected ? const Color(0xFFDAECE0) : const Color(0xFFF3F4F6),
                            labelStyle: const TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: const BorderSide(color: Colors.black, width: 2),
                            ),
                            onPressed: () {
                              _playSound();
                              setState(() {
                                _selectedCategoryFilter = cat;
                              });
                            },
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 12.0),
                  child: InkWell(
                    onTap: _showAddChannelDialog,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDAECE0),
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

          // Main Tasks List Body with bottom-left favorite shortcut
          Expanded(
            child: Stack(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _showAddTaskModal(defaultSubcategory: 'General'),
                  onHorizontalDragEnd: _handleSwipe,
                  child: channelTasks.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.folder_open_rounded, size: 54, color: Colors.black45),
                              const SizedBox(height: 12),
                              Text("No tasks in '$_selectedCategoryFilter'", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.black87)),
                              const SizedBox(height: 4),
                              const Text("Click anywhere to add • Swipe left/right to change tab", style: TextStyle(color: Colors.black54, fontSize: 12, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.black, width: 2.5),
                                boxShadow: const [
                                  BoxShadow(color: Colors.black, offset: Offset(3, 3), spreadRadius: 0)
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.grid_view_rounded, size: 18, color: Colors.black),
                                      const SizedBox(width: 8),
                                      Text(_selectedCategoryFilter.toUpperCase(), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.black, letterSpacing: 1.2)),
                                      const Spacer(),
                                      InkWell(
                                        onTap: () => _editChannel(_selectedCategoryFilter),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFFFFDF5),
                                            border: Border.all(color: Colors.black, width: 1.5),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: const Text("EDIT CATEGORY", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.black)),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 10.0),
                                    child: Divider(color: Colors.black, height: 1, thickness: 2),
                                  ),
                                  
                                  ...groupedActive.entries.map((subEntry) {
                                    String subName = subEntry.key;
                                    List<Task> subTasks = subEntry.value;
                                    String collapseKey = "$_selectedCategoryFilter:$subName";
                                    bool isCollapsed = _collapsedSubcategories.contains(collapseKey);

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
                                                    setState(() {
                                                      if (isCollapsed) {
                                                        _collapsedSubcategories.remove(collapseKey);
                                                      } else {
                                                        _collapsedSubcategories.add(collapseKey);
                                                      }
                                                    });
                                                  },
                                                  borderRadius: BorderRadius.circular(6),
                                                  child: Padding(
                                                    padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 4.0),
                                                    child: Row(
                                                      children: [
                                                        Icon(isCollapsed ? Icons.chevron_right_rounded : Icons.expand_more_rounded, size: 18, color: Colors.black),
                                                        const SizedBox(width: 4),
                                                        Text(
                                                          subName,
                                                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.black87),
                                                        ),
                                                        const SizedBox(width: 6),
                                                        Text("(${subTasks.length})", style: const TextStyle(fontSize: 12, color: Colors.black54, fontWeight: FontWeight.bold)),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              InkWell(
                                                onTap: () => _showAddTaskModal(defaultSubcategory: subName),
                                                borderRadius: BorderRadius.circular(4),
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFFDAECE0),
                                                    border: Border.all(color: Colors.black, width: 1.5),
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: const Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Icon(Icons.add, size: 12, color: Colors.black),
                                                      SizedBox(width: 2),
                                                      Text("ADD", style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.black)),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          
                                          if (!isCollapsed)
                                            ...subTasks.map((task) {
                                              return InkWell(
                                                onTap: () => _showEditTaskModal(task),
                                                borderRadius: BorderRadius.circular(8),
                                                child: Container(
                                                  margin: const EdgeInsets.only(left: 16, top: 4, bottom: 4),
                                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFFDAECE0).withOpacity(0.35),
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
                                                                if (task.isDaily)
                                                                  Container(
                                                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                                    margin: const EdgeInsets.only(left: 4),
                                                                    decoration: BoxDecoration(
                                                                      color: const Color(0xFFFFDE00),
                                                                      borderRadius: BorderRadius.circular(4),
                                                                      border: Border.all(color: Colors.black, width: 1.5),
                                                                    ),
                                                                    child: const Text("DAILY", style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.black)),
                                                                  ),
                                                              ],
                                                            ),
                                                            const SizedBox(height: 3),
                                                            Text(
                                                              "why: ${task.why}",
                                                              style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, fontWeight: FontWeight.w700, color: Colors.black54),
                                                            ),
                                                            if (task.reminderTime != null) ...[
                                                              const SizedBox(height: 3),
                                                              Row(
                                                                children: [
                                                                  const Icon(Icons.access_time_rounded, size: 11, color: Colors.black54),
                                                                  const SizedBox(width: 4),
                                                                  Text(
                                                                    "Reminder: ${task.reminderTime!}",
                                                                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.black54),
                                                                  ),
                                                                ],
                                                              ),
                                                            ]
                                                          ],
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      InkWell(
                                                        onTap: () => _toggleTask(task),
                                                        borderRadius: BorderRadius.circular(6),
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
                                                      const SizedBox(width: 6),
                                                      IconButton(
                                                        icon: const Icon(Icons.close_rounded, size: 18, color: Colors.black),
                                                        onPressed: () => _deleteTask(task.id),
                                                        padding: EdgeInsets.zero,
                                                        constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              );
                                            }),
                                        ],
                                      ),
                                    );
                                  }),
                                ],
                              ),
                            ),

                            if (completedTasks.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              ExpansionTile(
                                tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                                collapsedBackgroundColor: const Color(0xFFE5E7EB),
                                backgroundColor: const Color(0xFFE5E7EB),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: Colors.black, width: 2)),
                                collapsedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: Colors.black, width: 2)),
                                title: Text("Completed (${completedTasks.length})", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Colors.black)),
                                children: completedTasks.map((task) {
                                  return Container(
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
                                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.black45, decoration: TextDecoration.lineThrough),
                                          ),
                                        ),
                                        InkWell(
                                          onTap: () => _toggleTask(task),
                                          child: Container(
                                            width: 22,
                                            height: 22,
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFDAECE0),
                                              borderRadius: BorderRadius.circular(4),
                                              border: Border.all(color: Colors.black, width: 1.5),
                                            ),
                                            child: const Icon(Icons.check, size: 14, color: Colors.black),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ),
                            ],
                          ],
                        ),
                ),
                
                // Small Clean Floating Bottom-Left Favorite Spot Button
                Positioned(
                  left: 16,
                  bottom: 16,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: Colors.black, width: 2),
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: const [
                        BoxShadow(color: Colors.black, offset: Offset(2, 2), spreadRadius: 0)
                      ],
                    ),
                    child: PopupMenuButton<String>(
                      padding: EdgeInsets.zero,
                      offset: const Offset(0, -90),
                      constraints: const BoxConstraints(minWidth: 120),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text("FAV: ", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.black54)),
                            Text(
                              _favoriteCategory.toUpperCase(),
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.black),
                            ),
                          ],
                        ),
                      ),
                      onSelected: (val) {
                        setState(() {
                          _favoriteCategory = val;
                          _selectedCategoryFilter = val;
                        });
                        _saveData();
                        _playSound();
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          enabled: false,
                          child: Text("Jump to FAV ($_favoriteCategory)", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black54)),
                        ),
                        const PopupMenuDivider(),
                        ...channels.map((c) => PopupMenuItem(value: c, child: Text("Set '$c' as FAV", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)))).toList()
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}