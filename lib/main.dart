import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_rustore_update/flutter_rustore_update.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();

  if (!Hive.isAdapterRegistered(0)) {
    Hive.registerAdapter(TaskAdapter());
  }

  await Hive.openBox<Task>('tasksBox');

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  runApp(const TdlRomanApp());
}

// --- МОДЕЛЬ ДАННЫХ ---
class Task extends HiveObject {
  String id;
  String title;
  bool isCompleted;
  bool isDeleted;
  DateTime createdAt;
  int urgency;
  int importance;
  int sortIndex;

  Task({
    required this.id,
    required this.title,
    this.isCompleted = false,
    this.isDeleted = false,
    required this.createdAt,
    this.urgency = 1,
    this.importance = 1,
    this.sortIndex = 0,
  });
}

class TaskAdapter extends TypeAdapter<Task> {
  @override
  final int typeId = 0;

  @override
  Task read(BinaryReader reader) {
    final id = reader.readString();
    final title = reader.readString();
    final isCompleted = reader.readBool();
    final isDeleted = reader.readBool();
    final createdAt = DateTime.fromMillisecondsSinceEpoch(reader.readInt());
    final urgency = reader.readInt();
    final importance = reader.readInt();
    final sortIndex = reader.availableBytes > 0 ? reader.readInt() : 0;

    return Task(
      id: id,
      title: title,
      isCompleted: isCompleted,
      isDeleted: isDeleted,
      createdAt: createdAt,
      urgency: urgency,
      importance: importance,
      sortIndex: sortIndex,
    );
  }

  @override
  void write(BinaryWriter writer, Task obj) {
    writer.writeString(obj.id);
    writer.writeString(obj.title);
    writer.writeBool(obj.isCompleted);
    writer.writeBool(obj.isDeleted);
    writer.writeInt(obj.createdAt.millisecondsSinceEpoch);
    writer.writeInt(obj.urgency);
    writer.writeInt(obj.importance);
    writer.writeInt(obj.sortIndex);
  }
}

class TdlRomanApp extends StatelessWidget {
  const TdlRomanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TDL-Roman',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('ru', 'RU')],
      locale: const Locale('ru', 'RU'),
      theme: ThemeData(
        fontFamily: 'Helvetica',
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF5F5F5),
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.black),
      ),
      home: const SplashScreen(),
    );
  }
}

// --- ЭКРАН ПРИВЕТСТВИЯ (SPLASH) ---
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
    _navigateToHome();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _version = "v${info.version}";
      });
    }
  }

  Future<void> _navigateToHome() async {
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const RomanHomePage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Логотип
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 10,
                    offset: Offset(0, 5),
                  ),
                ],
              ),
              child: const Icon(
                Icons.account_balance,
                color: Colors.white,
                size: 60,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              "TDL-ROMAN",
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                letterSpacing: 2.0,
              ),
            ),
            const SizedBox(height: 8),
            // ИСПРАВЛЕНО: Оптимистичная фраза
            const Text(
              "ACTA NON VERBA", // Дела, а не слова
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey,
                fontStyle: FontStyle.italic,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 40),
            // Версия
            Text(
              _version,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.black54,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- ГЛАВНЫЙ ЭКРАН ---
class RomanHomePage extends StatefulWidget {
  const RomanHomePage({super.key});

  @override
  State<RomanHomePage> createState() => _RomanHomePageState();
}

class _RomanHomePageState extends State<RomanHomePage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late Box<Task> _box;
  int _currentIndex = 1;

  String? _expandedTaskId;
  String? _selectedTaskId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this, initialIndex: 1);
    _box = Hive.box<Task>('tasksBox');

    _tabController.addListener(() {
      if (_tabController.indexIsChanging ||
          _tabController.index != _currentIndex) {
        setState(() {
          _currentIndex = _tabController.index;
          _expandedTaskId = null;
          _selectedTaskId = null;
        });
      }
    });

    _checkUpdates();
  }

  void _checkUpdates() {
    RustoreUpdateClient.info()
        .then((info) {
          if (info.updateAvailability == 2) {
            // 2 = UPDATE_AVAILABLE
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                title: const Text("Доступно обновление"),
                content: const Text(
                  "Вышла новая версия TDL-Roman!\nХотите обновиться?",
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text(
                      "Позже",
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      final uri = Uri.parse(
                        "https://apps.rustore.ru/app/ru.gorelovra.tdlroman",
                      );
                      launchUrl(uri, mode: LaunchMode.externalApplication);
                    },
                    child: const Text(
                      "Обновить",
                      style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }
        })
        .catchError((e) {
          debugPrint("Ошибка проверки обновлений: $e");
        });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // --- UI LOGIC ---

  void _toggleExpand(String id) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_expandedTaskId == id) {
        _expandedTaskId = null;
      } else {
        _expandedTaskId = id;
      }
    });
  }

  void _toggleSelection(String id) {
    HapticFeedback.mediumImpact();
    setState(() {
      if (_selectedTaskId == id) {
        _selectedTaskId = null;
      } else {
        _selectedTaskId = id;
      }
    });
  }

  String _getTaskEmoji(Task t) {
    if (t.isDeleted) return "❌";
    if (t.isCompleted) return "✅";
    if (t.urgency == 2 && t.importance == 2) return "⚡❗";
    if (t.urgency == 2) return "⚡";
    if (t.importance == 2) return "❗";
    return "▫️";
  }

  String _formatListForClipboard(List<Task> tasks, String headerTitle) {
    if (tasks.isEmpty) return "";
    StringBuffer buffer = StringBuffer();
    buffer.writeln("🏛 **$headerTitle**\n");
    tasks.sort((a, b) => a.sortIndex.compareTo(b.sortIndex));

    for (int i = 0; i < tasks.length; i++) {
      final t = tasks[i];
      final emoji = _getTaskEmoji(t);
      String line;
      if (t.isDeleted || t.isCompleted) {
        line = "$emoji ${t.title}";
      } else {
        line = "${i + 1}. $emoji ${t.title}";
      }
      buffer.writeln(line);
      buffer.writeln("");
    }
    return buffer.toString();
  }

  void _copySpecificList(int tabIndex) {
    String text = "";
    if (tabIndex == 0) {
      final tasks = _box.values.where((t) => t.isDeleted).toList();
      text = _formatListForClipboard(tasks, "ТАРТАР (Удаленные)");
    } else if (tabIndex == 1) {
      final tasks = _box.values
          .where((t) => !t.isDeleted && !t.isCompleted)
          .toList();
      text = _formatListForClipboard(tasks, "СПИСОК ДЕЛ");
    } else {
      final tasks = _box.values
          .where((t) => t.isCompleted && !t.isDeleted)
          .toList();
      text = _formatListForClipboard(tasks, "ТРИУМФЫ (Выполнено)");
    }

    if (text.isEmpty) {
      _showSnackBar("Список пуст");
    } else {
      Clipboard.setData(ClipboardData(text: text));
      _showSnackBar("Вкладка скопирована!");
    }
  }

  void _copyAllLists() {
    final active = _box.values
        .where((t) => !t.isDeleted && !t.isCompleted)
        .toList();
    final completed = _box.values
        .where((t) => t.isCompleted && !t.isDeleted)
        .toList();
    final deleted = _box.values.where((t) => t.isDeleted).toList();

    StringBuffer buffer = StringBuffer();
    buffer.writeln("🏛 **TDL ROMAN REPORT** 🏛\n");
    buffer.write(_formatListForClipboard(active, "АКТУАЛЬНОЕ"));
    buffer.write("-------------------\n");
    buffer.write(_formatListForClipboard(completed, "ВЫПОЛНЕНО"));
    buffer.write("-------------------\n");
    buffer.write(_formatListForClipboard(deleted, "УДАЛЕНО"));

    Clipboard.setData(ClipboardData(text: buffer.toString()));
    _showSnackBar("ВСЕ списки скопированы!");
  }

  void _showClipboardMenu(int tabIndex) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "КОПИРОВАНИЕ",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildCopyActionButton("ВСЁ", Icons.copy_all, () {
                    Navigator.pop(ctx);
                    _copyAllLists();
                  }),
                  _buildCopyActionButton("ЭТУ ВКЛАДКУ", Icons.tab, () {
                    Navigator.pop(ctx);
                    _copySpecificList(tabIndex);
                  }),
                ],
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCopyActionButton(
    String label,
    IconData icon,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.white, size: 32),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.black87,
        duration: const Duration(seconds: 1),
      ),
    );
  }

  // --- LOGIC TASK ---

  int _getTopIndexForState({bool deleted = false, bool completed = false}) {
    final tasks = _box.values.where((t) {
      if (deleted) return t.isDeleted;
      if (completed) return t.isCompleted && !t.isDeleted;
      return !t.isCompleted && !t.isDeleted;
    });
    if (tasks.isEmpty) return 0;
    return tasks.map((e) => e.sortIndex).reduce(min) - 1;
  }

  int _getBottomIndexForActive() {
    final tasks = _box.values.where((t) => !t.isCompleted && !t.isDeleted);
    if (tasks.isEmpty) return 0;
    return tasks.map((e) => e.sortIndex).reduce(max) + 1;
  }

  void _saveNewTask(
    String title,
    int urgency,
    int importance,
    int positionMode,
  ) {
    int newIndex;
    if (positionMode == 0) {
      newIndex = _getTopIndexForState();
    } else {
      newIndex = _getBottomIndexForActive();
    }

    final newTask = Task(
      id: const Uuid().v4(),
      title: title,
      createdAt: DateTime.now(),
      urgency: urgency,
      importance: importance,
      sortIndex: newIndex,
    );
    _box.put(newTask.id, newTask);
    setState(() {});
  }

  void _updateTaskAndMove(
    Task task,
    int urgency,
    int importance,
    int positionMode,
  ) {
    task.urgency = urgency;
    task.importance = importance;

    if (positionMode == 0) {
      task.sortIndex = _getTopIndexForState();
    } else if (positionMode == 2) {
      task.sortIndex = _getBottomIndexForActive();
    }

    task.save();
    setState(() {});
  }

  void _completeTask(Task task) {
    task.isCompleted = true;
    task.isDeleted = false;
    task.sortIndex = _getTopIndexForState(completed: true);
    task.save();
    setState(() {});
  }

  void _restoreToActive(Task task) {
    task.isCompleted = false;
    task.isDeleted = false;
    task.sortIndex = _getTopIndexForState();
    task.save();
    setState(() {});
  }

  void _moveToTrash(Task task) {
    task.isDeleted = true;
    task.isCompleted = false;
    task.sortIndex = _getTopIndexForState(deleted: true);
    task.save();
    setState(() {});
  }

  void _permanentlyDelete(String id) {
    _box.delete(id);
    setState(() {});
  }

  void _onReorder(int oldIndex, int newIndex, List<Task> currentList) {
    if (oldIndex < newIndex) newIndex -= 1;
    final Task item = currentList.removeAt(oldIndex);
    currentList.insert(newIndex, item);
    for (int i = 0; i < currentList.length; i++) {
      currentList[i].sortIndex = i;
      currentList[i].save();
    }
    setState(() {});
  }

  int get _activeCount =>
      _box.values.where((t) => !t.isDeleted && !t.isCompleted).length;
  int get _completedCount =>
      _box.values.where((t) => t.isCompleted && !t.isDeleted).length;
  int get _deletedCount => _box.values.where((t) => t.isDeleted).length;

  Color get _backgroundColor {
    if (_currentIndex == 2) return const Color(0xFF121212);
    return const Color(0xFFFFFFFF);
  }

  Color get _textColor {
    if (_currentIndex == 2) return Colors.white;
    return Colors.black87;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        backgroundColor: _backgroundColor,
        elevation: 0,
        toolbarHeight: 0,
        systemOverlayStyle: _currentIndex == 2
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              height: 60,
              decoration: BoxDecoration(
                color: _backgroundColor,
                border: Border(
                  bottom: BorderSide(
                    color: _currentIndex == 2 ? Colors.white12 : Colors.black12,
                  ),
                ),
              ),
              child: TabBar(
                controller: _tabController,
                indicatorColor: _currentIndex == 2
                    ? const Color(0xFFFFD700)
                    : Colors.black,
                labelColor: _textColor,
                unselectedLabelColor: _currentIndex == 2
                    ? Colors.white38
                    : Colors.black38,
                tabs: [
                  _buildTab(Icons.delete_outline, _deletedCount, 0),
                  _buildTab(Icons.list_alt, _activeCount, 1),
                  _buildTab(Icons.emoji_events_outlined, _completedCount, 2),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildDeletedTasksList(),
                  _buildActiveTasksList(),
                  _buildCompletedTasksList(),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: _currentIndex == 1
          ? Container(
              height: 60,
              width: 60,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.black, width: 2),
                borderRadius: BorderRadius.circular(8),
                color: Colors.white,
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _showTaskDialog(context),
                  child: const Icon(Icons.add, color: Colors.black, size: 36),
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildTab(IconData icon, int count, int index) {
    return GestureDetector(
      onLongPress: () {
        HapticFeedback.mediumImpact();
        _showClipboardMenu(index);
      },
      child: Container(
        color: Colors.transparent,
        width: double.infinity,
        height: 60,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 26),
            if (count > 0) ...[
              const SizedBox(width: 8),
              Text(
                '$count',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLeftIndicator(Task task, int index, bool isSelected) {
    IconData icon;
    Color bgColor;
    bool isDouble = false;
    Color iconColor = Colors.white;

    if (isSelected) {
      icon = Icons.swipe;
      bgColor = Colors.black;
      iconColor = Colors.white;
    } else {
      if (task.urgency == 2 && task.importance == 2) {
        isDouble = true;
        icon = Icons.bolt;
        bgColor = const Color(0xFFB71C1C);
      } else if (task.urgency == 2) {
        icon = Icons.bolt;
        bgColor = const Color(0xFFCD7F32);
      } else if (task.importance == 2) {
        icon = Icons.priority_high;
        bgColor = const Color(0xFFFFD700);
      } else {
        icon = Icons.circle_outlined;
        bgColor = Colors.transparent;
      }
    }

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => _toggleSelection(task.id),
      child: Container(
        width: 50,
        color: Colors.transparent,
        alignment: Alignment.centerLeft,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: (bgColor == Colors.transparent && !isSelected)
                    ? Colors.white
                    : bgColor,
                shape: BoxShape.circle,
                border: (bgColor == Colors.transparent && !isSelected)
                    ? Border.all(color: Colors.black26, width: 1.5)
                    : null,
                boxShadow: (bgColor != Colors.transparent || isSelected)
                    ? const [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 2,
                          offset: Offset(0, 1),
                        ),
                      ]
                    : null,
              ),
              child: isDouble && !isSelected
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.bolt, size: 14, color: Colors.white),
                        Icon(
                          Icons.priority_high,
                          size: 14,
                          color: Colors.white,
                        ),
                      ],
                    )
                  : (bgColor == Colors.transparent && !isSelected)
                  ? const SizedBox()
                  : Icon(
                      isSelected ? Icons.swap_horiz : icon,
                      size: 18,
                      color: iconColor,
                    ),
            ),
            const SizedBox(height: 4),
            Text(
              "${index + 1}",
              style: TextStyle(
                fontSize: 10,
                color: _currentIndex == 2 ? Colors.white70 : Colors.black54,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  BoxDecoration _getTaskDecoration(Task task) {
    if (task.isCompleted && !task.isDeleted) {
      if (task.urgency == 2 && task.importance == 2) {
        return _grad([Color(0xFFBF953F), Color(0xFFFCF6BA), Color(0xFFAA771C)]);
      }
      if (task.importance == 2) {
        return _grad([Color(0xFFE0E0E0), Color(0xFFFFFFFF), Color(0xFFAAAAAA)]);
      }
      if (task.urgency == 2) {
        return _grad([Color(0xFFCD7F32), Color(0xFFFFCC99), Color(0xFFA0522D)]);
      }
      return BoxDecoration(
        color: const Color(0xFF8D6E63),
        borderRadius: BorderRadius.circular(8),
        boxShadow: _shadow(),
      );
    }
    if (task.isDeleted) {
      return BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(8),
        boxShadow: _shadow(),
      );
    }
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      boxShadow: _shadow(),
    );
  }

  BoxDecoration _grad(List<Color> colors) {
    return BoxDecoration(
      gradient: LinearGradient(
        colors: colors,
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(8),
      boxShadow: _shadow(),
    );
  }

  List<BoxShadow> _shadow() => const [
    BoxShadow(color: Colors.black12, blurRadius: 3, offset: Offset(0, 2)),
  ];

  Widget _buildTaskItem(
    Task task,
    BuildContext context,
    int index, {
    bool showCup = false,
  }) {
    Color textColor = Colors.black87;
    if (task.isCompleted && !task.isDeleted) {
      if (task.urgency == 1 && task.importance == 1) textColor = Colors.white;
    } else if (task.isDeleted) {
      textColor = Colors.grey;
    }

    final isExpanded = _expandedTaskId == task.id;
    final isSelected = _selectedTaskId == task.id;

    Widget content = Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
      decoration: _getTaskDecoration(task),
      child: ListTile(
        contentPadding: const EdgeInsets.only(
          left: 10,
          right: 16,
          top: 8,
          bottom: 8,
        ),
        leading: _buildLeftIndicator(task, index, isSelected),
        title: Text(
          task.title,
          maxLines: isExpanded ? null : 2,
          overflow: isExpanded ? null : TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 18,
            color: textColor,
            height: 1.2,
            fontWeight: (task.importance > 1 && !task.isDeleted)
                ? FontWeight.bold
                : FontWeight.normal,
            decoration: task.isDeleted
                ? TextDecoration.lineThrough
                : TextDecoration.none,
            decorationColor: Colors.grey,
          ),
        ),
        trailing: showCup
            ? const Icon(Icons.emoji_events, color: Colors.white, size: 28)
            : null,
      ),
    );

    content = GestureDetector(
      onTap: () => _toggleExpand(task.id),
      onDoubleTap: () {
        if (!task.isDeleted && !task.isCompleted) {
          _showTaskDialog(context, task: task);
        }
      },
      child: content,
    );

    return Dismissible(
      key: Key(task.id),
      direction: isSelected
          ? DismissDirection.horizontal
          : DismissDirection.none,
      background: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
        decoration: BoxDecoration(
          color: const Color(0xFFD4AF37),
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 24),
        child: const Icon(Icons.emoji_events, color: Colors.white),
      ),
      secondaryBackground: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          if (task.isDeleted) {
            _restoreToActive(task);
          } else if (task.isCompleted) {
            _moveToTrash(task);
          } else {
            _completeTask(task);
          }
        } else {
          if (task.isDeleted) {
            return await showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: Colors.white,
                title: const Text('Удалить навсегда?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text(
                      'НЕТ',
                      style: TextStyle(color: Colors.black),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text(
                      'ДА',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ),
            );
          } else if (task.isCompleted) {
            _restoreToActive(task);
          } else {
            _moveToTrash(task);
          }
        }
        _selectedTaskId = null;
        return false;
      },
      child: content,
    );
  }

  Widget _buildActiveTasksList() {
    final tasks = _box.values
        .where((t) => !t.isDeleted && !t.isCompleted)
        .toList();
    tasks.sort((a, b) => a.sortIndex.compareTo(b.sortIndex));

    return ReorderableListView.builder(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(0, 10, 0, 80),
      itemCount: tasks.length,
      onReorder: (oldIndex, newIndex) => _onReorder(oldIndex, newIndex, tasks),
      proxyDecorator: (child, index, animation) =>
          Material(elevation: 5, color: Colors.transparent, child: child),
      itemBuilder: (context, index) {
        final task = tasks[index];
        return Container(
          key: Key(task.id),
          child: _buildTaskItem(task, context, index),
        );
      },
    );
  }

  Widget _buildCompletedTasksList() {
    final tasks = _box.values
        .where((t) => t.isCompleted && !t.isDeleted)
        .toList();
    tasks.sort((a, b) => a.sortIndex.compareTo(b.sortIndex));
    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 10),
      itemCount: tasks.length,
      itemBuilder: (context, index) =>
          _buildTaskItem(tasks[index], context, index, showCup: true),
    );
  }

  Widget _buildDeletedTasksList() {
    final tasks = _box.values.where((t) => t.isDeleted).toList();
    tasks.sort((a, b) => a.sortIndex.compareTo(b.sortIndex));
    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 10),
      itemCount: tasks.length,
      itemBuilder: (context, index) =>
          _buildTaskItem(tasks[index], context, index),
    );
  }

  // --- ДИАЛОГ ЗАДАЧИ ---
  void _showTaskDialog(BuildContext context, {Task? task}) {
    final titleController = TextEditingController(text: task?.title ?? '');
    int urgency = task?.urgency ?? 1;
    int importance = task?.importance ?? 1;
    int positionMode = 1;
    bool attentionTop = false;
    int blinkStage = 0;
    Timer? attentionTimer;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final double dialogHeight = MediaQuery.of(context).size.height * 0.72;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            void selectPosition(int mode) {
              attentionTimer?.cancel();
              setDialogState(() {
                positionMode = mode;
                attentionTop = false;
              });
            }

            void triggerAttention() {
              attentionTimer?.cancel();
              setDialogState(() {
                positionMode = 0;
                attentionTop = true;
                blinkStage = 1;
              });
              int count = 0;
              attentionTimer = Timer.periodic(
                const Duration(milliseconds: 200),
                (timer) {
                  if (!ctx.mounted) {
                    timer.cancel();
                    return;
                  }
                  setDialogState(() {
                    blinkStage = (blinkStage == 0) ? 1 : 0;
                  });
                  count++;
                  if (count >= 6) {
                    timer.cancel();
                    setDialogState(() => attentionTop = false);
                  }
                },
              );
            }

            Widget buildStateButton({
              required IconData icon,
              required bool isActive,
              required Color activeColor,
              required VoidCallback onTap,
            }) {
              return GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  onTap();
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 45,
                  height: 45,
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isActive
                          ? activeColor
                          : Colors.grey.withOpacity(0.3),
                      width: 2,
                    ),
                  ),
                  child: Icon(
                    icon,
                    color: isActive
                        ? activeColor
                        : Colors.grey.withOpacity(0.3),
                    size: 26,
                  ),
                ),
              );
            }

            Widget buildPosButton(int mode, IconData icon) {
              bool isSel = positionMode == mode;
              bool isBlinking = (mode == 0 && attentionTop);
              Color borderColor;
              Color iconColor;
              Color bgColor;

              if (isBlinking) {
                if (blinkStage == 1) {
                  borderColor = Colors.red;
                  iconColor = Colors.red;
                  bgColor = Colors.red.withOpacity(0.1);
                } else {
                  borderColor = Colors.blue;
                  iconColor = Colors.blue;
                  bgColor = Colors.blue.withOpacity(0.1);
                }
              } else if (isSel) {
                borderColor = Colors.blue;
                iconColor = Colors.blue;
                bgColor = Colors.blue.withOpacity(0.1);
              } else {
                borderColor = Colors.grey.withOpacity(0.3);
                iconColor = Colors.grey.withOpacity(0.3);
                bgColor = Colors.transparent;
              }

              return GestureDetector(
                onTap: () => selectPosition(mode),
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 2),
                  width: 45,
                  height: 38,
                  decoration: BoxDecoration(
                    border: Border.all(color: borderColor, width: 2),
                    borderRadius: BorderRadius.circular(8),
                    color: bgColor,
                  ),
                  child: Icon(icon, size: 24, color: iconColor),
                ),
              );
            }

            void save() {
              if (titleController.text.trim().isNotEmpty) {
                attentionTimer?.cancel();
                if (task == null) {
                  _saveNewTask(
                    titleController.text,
                    urgency,
                    importance,
                    positionMode == 1 ? 2 : positionMode,
                  );
                } else {
                  task.title = titleController.text;
                  _updateTaskAndMove(task, urgency, importance, positionMode);
                }
                Navigator.pop(ctx);
              }
            }

            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
              backgroundColor: Colors.white,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 24,
              ),
              child: SizedBox(
                height: dialogHeight,
                width: double.maxFinite,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      // 1. ТЕКСТОВОЕ ПОЛЕ С МЕНЮ
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Colors.grey.shade300,
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Scrollbar(
                            thumbVisibility: true,
                            child: TextField(
                              controller: titleController,
                              autofocus: true,
                              style: const TextStyle(
                                fontSize: 18,
                                color: Colors.black87,
                              ),
                              decoration: const InputDecoration(
                                hintText: 'Что нужно сделать?',
                                border: InputBorder.none,
                              ),
                              maxLines: null,
                              expands: true,
                              textAlignVertical: TextAlignVertical.top,
                              contextMenuBuilder: (context, editableTextState) {
                                return TextSelectionToolbar(
                                  anchorAbove: editableTextState
                                      .contextMenuAnchors
                                      .primaryAnchor,
                                  anchorBelow: editableTextState
                                      .contextMenuAnchors
                                      .primaryAnchor,
                                  children: [
                                    IconButton(
                                      onPressed: () =>
                                          editableTextState.selectAll(
                                            SelectionChangedCause.toolbar,
                                          ),
                                      icon: const Icon(Icons.select_all),
                                      tooltip: "Выделить всё",
                                    ),
                                    IconButton(
                                      onPressed: () =>
                                          editableTextState.cutSelection(
                                            SelectionChangedCause.toolbar,
                                          ),
                                      icon: const Icon(Icons.content_cut),
                                      tooltip: "Вырезать",
                                    ),
                                    IconButton(
                                      onPressed: () =>
                                          editableTextState.copySelection(
                                            SelectionChangedCause.toolbar,
                                          ),
                                      icon: const Icon(Icons.copy),
                                      tooltip: "Копировать",
                                    ),
                                    IconButton(
                                      onPressed: () =>
                                          editableTextState.pasteText(
                                            SelectionChangedCause.toolbar,
                                          ),
                                      icon: const Icon(Icons.paste),
                                      tooltip: "Вставить",
                                    ),
                                    IconButton(
                                      onPressed: () {
                                        // Здесь можно добавить логику озвучки
                                      },
                                      icon: const Icon(Icons.volume_up),
                                      tooltip: "Озвучить",
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // 2. ПАНЕЛЬ УПРАВЛЕНИЯ
                      SizedBox(
                        height: 120,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            // БОЛЬШОЙ ЛЕВЫЙ БЛОК
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  // РЯД 1: СТАТУС
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      buildStateButton(
                                        icon: Icons.bolt,
                                        isActive: urgency == 2,
                                        activeColor: Colors.red,
                                        onTap: () {
                                          setDialogState(() {
                                            urgency = (urgency == 1 ? 2 : 1);
                                            if (urgency == 2)
                                              triggerAttention();
                                          });
                                        },
                                      ),
                                      const SizedBox(width: 20),
                                      buildStateButton(
                                        icon: Icons.priority_high,
                                        isActive: importance == 2,
                                        activeColor: Colors.orange,
                                        onTap: () {
                                          setDialogState(() {
                                            importance = (importance == 1
                                                ? 2
                                                : 1);
                                            if (importance == 2)
                                              triggerAttention();
                                          });
                                        },
                                      ),
                                    ],
                                  ),

                                  const SizedBox(height: 4),
                                  const Text(
                                    "Статус",
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  const SizedBox(height: 10),

                                  // РЯД 2: КНОПКИ
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceEvenly,
                                    children: [
                                      _buildSquareButtonWithLabel(
                                        label: "Отмена",
                                        icon: Icons.close,
                                        color: Colors.grey,
                                        size: 50,
                                        onTap: () {
                                          attentionTimer?.cancel();
                                          Navigator.pop(ctx);
                                        },
                                      ),
                                      _buildSquareButtonWithLabel(
                                        label: "Копия",
                                        icon: Icons.copy,
                                        color: Colors.black,
                                        size: 50,
                                        onTap: () {
                                          if (titleController.text
                                              .trim()
                                              .isNotEmpty) {
                                            final tempTask = Task(
                                              id: 't',
                                              title: titleController.text,
                                              createdAt: DateTime.now(),
                                              urgency: urgency,
                                              importance: importance,
                                            );
                                            Clipboard.setData(
                                              ClipboardData(
                                                text:
                                                    "${_getTaskEmoji(tempTask)} ${tempTask.title}",
                                              ),
                                            );
                                            _showSnackBar("Текст скопирован");
                                          }
                                        },
                                      ),
                                      _buildSquareButtonWithLabel(
                                        label: "OK",
                                        icon: Icons.check,
                                        color: Colors.black,
                                        size: 50,
                                        onTap: save,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(width: 10),

                            // ПРАВЫЙ СТОЛБИК: ПОЗИЦИЯ
                            SizedBox(
                              width: 50,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  buildPosButton(0, Icons.keyboard_arrow_up),
                                  buildPosButton(1, Icons.stop),
                                  buildPosButton(2, Icons.keyboard_arrow_down),
                                  const SizedBox(height: 4),
                                  const Text(
                                    "Позиция",
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  const SizedBox(height: 18),
                                ],
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
          },
        );
      },
    );
  }

  Widget _buildSquareButtonWithLabel({
    required String label,
    required IconData icon,
    required Color color,
    required double size,
    required VoidCallback onTap,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: color, width: 2),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: color, size: 28),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
      ],
    );
  }
}
