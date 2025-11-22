import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

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

// --- МОДЕЛЬ ЗАДАЧИ ---
class Task extends HiveObject {
  String id;
  String title;
  bool isCompleted;
  bool isDeleted;
  DateTime createdAt;
  int urgency; // 1 = обычно, 2 = срочно
  int importance; // 1 = обычно, 2 = важно
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
      theme: ThemeData(
        fontFamily: 'Times New Roman',
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(
          0xFFF5F5F5,
        ), // Чуть серый фон, чтобы белые плашки выделялись
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.black),
      ),
      home: const RomanHomePage(),
    );
  }
}

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

  @override
  void initState() {
    super.initState();
    // 0: Мусорка, 1: Список, 2: Ачивки
    _tabController = TabController(length: 3, vsync: this, initialIndex: 1);
    _box = Hive.box<Task>('tasksBox');

    _tabController.addListener(() {
      if (_tabController.indexIsChanging ||
          _tabController.index != _currentIndex) {
        setState(() {
          _currentIndex = _tabController.index;
        });
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // --- КОПИРОВАНИЕ ---

  String _getTaskEmoji(Task t) {
    if (t.isDeleted) return "❌";
    if (t.isCompleted) return "✅";

    // Активные
    if (t.urgency == 2 && t.importance == 2) return "⚡❗";
    if (t.urgency == 2) return "⚡";
    if (t.importance == 2) return "❗";
    return "▫️";
  }

  String _formatListForClipboard(List<Task> tasks, String headerTitle) {
    if (tasks.isEmpty) return "";
    StringBuffer buffer = StringBuffer();
    buffer.writeln("\n🏛 **$headerTitle**");
    tasks.sort((a, b) => a.sortIndex.compareTo(b.sortIndex));

    for (int i = 0; i < tasks.length; i++) {
      final t = tasks[i];
      final emoji = _getTaskEmoji(t);
      if (t.isDeleted || t.isCompleted) {
        buffer.writeln("$emoji ${t.title}");
      } else {
        buffer.writeln("${i + 1}. $emoji ${t.title}");
      }
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
    buffer.writeln("🏛 **TDL ROMAN REPORT** 🏛");
    buffer.write(_formatListForClipboard(active, "АКТУАЛЬНОЕ"));
    buffer.write(_formatListForClipboard(completed, "ВЫПОЛНЕНО"));
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
                style: TextStyle(
                  fontFamily: "Times New Roman",
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
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
        content: Text(
          message,
          style: const TextStyle(fontFamily: 'Times New Roman'),
        ),
        backgroundColor: Colors.black87,
        duration: const Duration(seconds: 1),
      ),
    );
  }

  // --- ЛОГИКА СПИСКОВ ---
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
    int importance, {
    bool toTop = true,
  }) {
    final newIndex = toTop
        ? _getTopIndexForState()
        : _getBottomIndexForActive();
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
    int importance, {
    int? moveDirection,
  }) {
    task.urgency = urgency;
    task.importance = importance;
    if (moveDirection == 1)
      task.sortIndex = _getTopIndexForState();
    else if (moveDirection == 2)
      task.sortIndex = _getBottomIndexForActive();
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

  // --- UI СТРАНИЦЫ ---

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
          ? FloatingActionButton(
              onPressed: () => _showTaskDialog(context),
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.zero,
              ),
              child: const Icon(Icons.add),
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
                  fontFamily: 'Times New Roman',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // --- ЗНАЧКИ ПРИОРИТЕТОВ (В КРУГАХ) ---

  Widget _buildPriorityBadge(int urgency, int importance) {
    if (urgency == 1 && importance == 1) return const SizedBox.shrink();

    IconData icon;
    Color bgColor;
    Color iconColor = Colors.white;
    bool isDouble = false;

    if (urgency == 2 && importance == 2) {
      // И то и то
      isDouble = true;
      icon = Icons.bolt;
      bgColor = const Color(0xFFB71C1C); // Насыщенный красный
    } else if (urgency == 2) {
      // Только срочно (Молния)
      icon = Icons.bolt;
      bgColor = const Color(0xFFCD7F32); // Бронза
    } else {
      // Только важно (Восклицательный знак) - ТЕПЕРЬ ЖЕЛТЫЙ (Золотой)
      icon = Icons.priority_high;
      bgColor = const Color(0xFFFFD700); // Золотой/Желтый
    }

    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bgColor,
        shape: BoxShape.circle,
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 2, offset: Offset(0, 1)),
        ],
      ),
      child: isDouble
          ? Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.bolt, size: 14, color: Colors.white),
                Icon(Icons.priority_high, size: 14, color: Colors.white),
              ],
            )
          : Icon(icon, size: 18, color: iconColor),
    );
  }

  // --- ДЕКОРАТОРЫ (СТИЛЬ ПЛАШЕК) ---

  BoxDecoration _getTaskDecoration(Task task) {
    // 1. Ачивки (Выполнено)
    if (task.isCompleted && !task.isDeleted) {
      if (task.urgency == 2 && task.importance == 2) {
        return BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFBF953F), Color(0xFFFCF6BA), Color(0xFFAA771C)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(8),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        );
      }
      if (task.importance == 2) {
        return BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFE0E0E0), Color(0xFFFFFFFF), Color(0xFFAAAAAA)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(8),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        );
      }
      if (task.urgency == 2) {
        return BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFCD7F32), Color(0xFFFFCC99), Color(0xFFA0522D)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(8),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        );
      }
      // Обычное выполненное - Дерево
      return BoxDecoration(
        color: const Color(0xFF8D6E63),
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
        ],
      );
    }

    // 2. Удаленное (Мусорка) - Серая плашка
    if (task.isDeleted) {
      return BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 2, offset: Offset(0, 1)),
        ],
      );
    }

    // 3. Активное - Белая плашка
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      boxShadow: const [
        BoxShadow(color: Colors.black12, blurRadius: 3, offset: Offset(0, 2)),
      ],
    );
  }

  // --- ЕДИНЫЙ ВИДЖЕТ ЗАДАЧИ ---
  Widget _buildTaskItem(Task task, {bool showBadge = true}) {
    // Определяем цвет текста
    Color textColor = Colors.black87;
    if (task.isCompleted && !task.isDeleted) {
      // В ачивках, если это "обычная" (дерево) или "бронза", текст должен быть белым/светлым?
      // Пользователь просил шрифт как был. Оставим черный везде кроме Дерева (темный фон)
      if (task.urgency == 1 && task.importance == 1)
        textColor = Colors.white;
      else
        textColor = Colors.black87;
    } else if (task.isDeleted) {
      textColor = Colors.grey;
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
      decoration: _getTaskDecoration(task),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        title: Text(
          task.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 18,
            color: textColor,
            height: 1.2,
            fontWeight: (task.importance > 1 && !task.isDeleted)
                ? FontWeight.bold
                : FontWeight.normal,
            fontFamily: 'Times New Roman',
            // Убрано decoration: TextDecoration.lineThrough для выполненных
            decoration: task.isDeleted
                ? TextDecoration.lineThrough
                : TextDecoration.none,
            decorationColor: Colors.grey,
          ),
        ),
        trailing: showBadge
            ? _buildPriorityBadge(task.urgency, task.importance)
            : null,
      ),
    );
  }

  // --- ЦЕНТР: СПИСОК ---
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
        return Dismissible(
          key: Key(task.id),
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
            if (direction == DismissDirection.startToEnd)
              _completeTask(task);
            else
              _moveToTrash(task);
            return false;
          },
          child: GestureDetector(
            onDoubleTap: () => _showTaskDialog(context, task: task),
            child: _buildTaskItem(task),
          ),
        );
      },
    );
  }

  // --- СПРАВА: АЧИВКИ ---
  Widget _buildCompletedTasksList() {
    final tasks = _box.values
        .where((t) => t.isCompleted && !t.isDeleted)
        .toList();
    tasks.sort((a, b) => a.sortIndex.compareTo(b.sortIndex));

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 10),
      itemCount: tasks.length,
      itemBuilder: (context, index) {
        final task = tasks[index];
        return Dismissible(
          key: Key(task.id),
          background: Container(
            margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.only(left: 24),
            child: const Icon(Icons.delete_outline, color: Colors.white),
          ),
          secondaryBackground: Container(
            margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 24),
            child: const Icon(Icons.restore, color: Colors.black),
          ),
          confirmDismiss: (direction) async {
            if (direction == DismissDirection.startToEnd)
              _moveToTrash(task);
            else
              _restoreToActive(task);
            return false;
          },
          child: _buildTaskItem(
            task,
            showBadge: false,
          ), // В ачивках сам фон говорит о ранге, бейдж дублирует
        );
      },
    );
  }

  // --- СЛЕВА: МУСОРКА ---
  Widget _buildDeletedTasksList() {
    final tasks = _box.values.where((t) => t.isDeleted).toList();
    tasks.sort((a, b) => a.sortIndex.compareTo(b.sortIndex));
    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 10),
      itemCount: tasks.length,
      itemBuilder: (context, index) {
        final task = tasks[index];
        return Dismissible(
          key: Key(task.id),
          background: Container(
            margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.green,
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.only(left: 24),
            child: const Icon(Icons.restore, color: Colors.white),
          ),
          secondaryBackground: Container(
            margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.red,
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 24),
            child: const Icon(Icons.delete_forever, color: Colors.white),
          ),
          confirmDismiss: (direction) async {
            if (direction == DismissDirection.startToEnd) {
              _restoreToActive(task);
              return false;
            } else {
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
            }
          },
          onDismissed: (direction) {
            if (direction == DismissDirection.endToStart)
              _permanentlyDelete(task.id);
          },
          child: _buildTaskItem(task, showBadge: true),
        );
      },
    );
  }

  // --- ДИАЛОГИ ---

  void _showTaskDialog(BuildContext context, {Task? task}) {
    final titleController = TextEditingController(text: task?.title ?? '');
    int urgency = task?.urgency ?? 1;
    int importance = task?.importance ?? 1;
    final int oldUrgency = task?.urgency ?? 1;
    final int oldImportance = task?.importance ?? 1;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          // Виджет для кнопки состояния (Молния / Знак)
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
                width: 40, // Чуть меньше, чтобы не занимать много места
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.transparent, // Фон всегда прозрачный
                  shape: BoxShape.circle,
                  border: Border.all(
                    // Если активно - цветное, если нет - бледно серое
                    color: isActive
                        ? activeColor
                        : Colors.grey.withOpacity(0.3),
                    width: 2,
                  ),
                ),
                child: Icon(
                  icon,
                  // Если активно - цветное, если нет - бледно серое
                  color: isActive ? activeColor : Colors.grey.withOpacity(0.3),
                  size: 24,
                ),
              ),
            );
          }

          return AlertDialog(
            backgroundColor: Colors.white,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.zero,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 20,
            ),
            // Ограничиваем высоту контента, чтобы клавиатура не ломала верстку и был скролл
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Поле ввода с ползунком (ScrollBar) и ограничением высоты
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxHeight: 150,
                    ), // Макс высота 150 пикселей
                    child: Scrollbar(
                      thumbVisibility: true, // Ползунок всегда виден
                      child: SingleChildScrollView(
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
                          minLines: 2,
                          maxLines:
                              null, // Бесконечное поле, но внутри ScrollView
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 15),
                  const Divider(),
                  const SizedBox(height: 10),
                  // Кнопки настроек
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // СРОЧНО
                      Column(
                        children: [
                          buildStateButton(
                            icon: Icons.bolt,
                            isActive: urgency == 2,
                            activeColor: Colors.red, // Красный для срочного
                            onTap: () => setDialogState(
                              () => urgency = (urgency == 1 ? 2 : 1),
                            ),
                          ),
                          const SizedBox(height: 5),
                          const Text(
                            "Срочно",
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                      const SizedBox(width: 30),
                      // ВАЖНО
                      Column(
                        children: [
                          buildStateButton(
                            icon: Icons.priority_high,
                            isActive: importance == 2,
                            activeColor: Colors.orange, // Оранжевый для важного
                            onTap: () => setDialogState(
                              () => importance = (importance == 1 ? 2 : 1),
                            ),
                          ),
                          const SizedBox(height: 5),
                          const Text(
                            "Важно",
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actionsAlignment: MainAxisAlignment.spaceEvenly,
            actions: [
              // ОК (Сохранить)
              _buildSquareButton(
                icon: Icons.check,
                color: Colors.black,
                onTap: () {
                  if (titleController.text.trim().isNotEmpty) {
                    if (task == null) {
                      Navigator.pop(ctx);
                      if (urgency == 2 && importance == 2) {
                        _saveNewTask(
                          titleController.text,
                          urgency,
                          importance,
                          toTop: true,
                        );
                      } else if (urgency == 2) {
                        _saveNewTask(
                          titleController.text,
                          urgency,
                          importance,
                          toTop: true,
                        );
                      } else if (importance == 2) {
                        _showPositionDialog(
                          context,
                          titleController.text,
                          urgency,
                          importance,
                        );
                      } else {
                        _saveNewTask(
                          titleController.text,
                          urgency,
                          importance,
                          toTop: false,
                        );
                      }
                    } else {
                      Navigator.pop(ctx);
                      bool statusChanged =
                          (urgency != oldUrgency) ||
                          (importance != oldImportance);
                      if (statusChanged) {
                        _showEditPositionDialog(
                          context,
                          task,
                          titleController.text,
                          urgency,
                          importance,
                        );
                      } else {
                        task.title = titleController.text;
                        _updateTaskAndMove(
                          task,
                          urgency,
                          importance,
                          moveDirection: 0,
                        );
                      }
                    }
                  }
                },
              ),
              // ОТМЕНА
              _buildSquareButton(
                icon: Icons.close,
                color: Colors.black54,
                onTap: () => Navigator.pop(ctx),
              ),
              // КОПИРОВАТЬ
              _buildSquareButton(
                icon: Icons.copy,
                color: Colors.black,
                onTap: () {
                  if (titleController.text.trim().isNotEmpty) {
                    final tempTask = Task(
                      id: 't',
                      title: titleController.text,
                      createdAt: DateTime.now(),
                      urgency: urgency,
                      importance: importance,
                      isCompleted: task?.isCompleted ?? false,
                      isDeleted: task?.isDeleted ?? false,
                    );
                    Clipboard.setData(
                      ClipboardData(
                        text: "${_getTaskEmoji(tempTask)} ${tempTask.title}",
                      ),
                    );
                    _showSnackBar("Текст скопирован");
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }

  // Диалоги выбора позиции
  void _showPositionDialog(
    BuildContext context,
    String title,
    int urgency,
    int importance,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: const Text('Куда добавить?', textAlign: TextAlign.center),
        actionsAlignment: MainAxisAlignment.spaceEvenly,
        actions: [
          Column(
            children: [
              IconButton(
                iconSize: 48,
                icon: const Icon(Icons.arrow_upward, color: Colors.red),
                onPressed: () {
                  _saveNewTask(title, urgency, importance, toTop: true);
                  Navigator.pop(ctx);
                },
              ),
              const Text(
                "В начало",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          Column(
            children: [
              IconButton(
                iconSize: 48,
                icon: const Icon(Icons.arrow_downward, color: Colors.black),
                onPressed: () {
                  _saveNewTask(title, urgency, importance, toTop: false);
                  Navigator.pop(ctx);
                },
              ),
              const Text(
                "В конец",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showEditPositionDialog(
    BuildContext context,
    Task task,
    String newTitle,
    int newUrgency,
    int newImportance,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: const Text('Статус изменен', textAlign: TextAlign.center),
        content: const Text('Переместить задачу?', textAlign: TextAlign.center),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Column(
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.arrow_upward,
                      color: Colors.red,
                      size: 32,
                    ),
                    onPressed: () {
                      task.title = newTitle;
                      _updateTaskAndMove(
                        task,
                        newUrgency,
                        newImportance,
                        moveDirection: 1,
                      );
                      Navigator.pop(ctx);
                    },
                  ),
                  const Text("Вверх"),
                ],
              ),
              Column(
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.location_on,
                      color: Colors.blue,
                      size: 32,
                    ),
                    onPressed: () {
                      task.title = newTitle;
                      _updateTaskAndMove(
                        task,
                        newUrgency,
                        newImportance,
                        moveDirection: 0,
                      );
                      Navigator.pop(ctx);
                    },
                  ),
                  const Text("Оставить"),
                ],
              ),
              Column(
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.arrow_downward,
                      color: Colors.black,
                      size: 32,
                    ),
                    onPressed: () {
                      task.title = newTitle;
                      _updateTaskAndMove(
                        task,
                        newUrgency,
                        newImportance,
                        moveDirection: 2,
                      );
                      Navigator.pop(ctx);
                    },
                  ),
                  const Text("Вниз"),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSquareButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: 50,
      height: 50,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: color, width: 2),
              borderRadius: BorderRadius.circular(4),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: color, size: 28),
          ),
        ),
      ),
    );
  }
}
