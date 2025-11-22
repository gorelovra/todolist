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
      theme: ThemeData(
        fontFamily: 'Times New Roman',
        useMaterial3: true,
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
  int _currentIndex = 1; // По умолчанию открываем среднюю вкладку (Список)

  @override
  void initState() {
    super.initState();
    // Порядок: Мусорка (0), Список (1), Ачивки (2)
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

  // --- ЛОГИКА КОПИРОВАНИЯ ---

  String _getTaskEmoji(Task t) {
    if (t.isDeleted) return "❌";
    if (t.isCompleted) return "✅";

    // Активные задачи
    if (t.urgency == 2 && t.importance == 2) return "⚡⭐️"; // Император
    if (t.urgency == 2) return "⚡"; // Легионер (Срочно)
    if (t.importance == 2) return "⭐️"; // Сенатор (Важно)
    return "▫️"; // Гражданин
  }

  String _formatListForClipboard(List<Task> tasks, String headerTitle) {
    if (tasks.isEmpty) return "";
    StringBuffer buffer = StringBuffer();
    buffer.writeln("\n🏛 **$headerTitle**");

    // Сортировка по индексу
    tasks.sort((a, b) => a.sortIndex.compareTo(b.sortIndex));

    for (int i = 0; i < tasks.length; i++) {
      final t = tasks[i];
      final emoji = _getTaskEmoji(t);
      // Для удаленных и завершенных просто иконка, для активных - нумерация
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
      // Мусорка
      final tasks = _box.values.where((t) => t.isDeleted).toList();
      text = _formatListForClipboard(tasks, "ТАРТАР (Удаленные)");
    } else if (tabIndex == 1) {
      // Список дел
      final tasks = _box.values
          .where((t) => !t.isDeleted && !t.isCompleted)
          .toList();
      text = _formatListForClipboard(tasks, "СПИСОК ДЕЛ");
    } else {
      // Ачивки
      final tasks = _box.values
          .where((t) => t.isCompleted && !t.isDeleted)
          .toList();
      text = _formatListForClipboard(tasks, "ТРИУМФЫ (Выполнено)");
    }

    if (text.isEmpty) {
      _showSnackBar("Список пуст");
    } else {
      Clipboard.setData(ClipboardData(text: text));
      _showSnackBar("Список скопирован!");
    }
  }

  void _copyAllLists() {
    final active = _box.values
        .where((t) => !t.isDeleted && !t.isCompleted)
        .toList();
    final completed = _box.values
        .where((t) => t.isCompleted && !t.isDeleted)
        .toList();
    // Удаленные копируем опционально, но раз пользователь просил "все три списка", копируем все
    final deleted = _box.values.where((t) => t.isDeleted).toList();

    StringBuffer buffer = StringBuffer();
    buffer.writeln("🏛 **TDL ROMAN REPORT** 🏛");
    buffer.write(_formatListForClipboard(active, "АКТУАЛЬНОЕ"));
    buffer.write(_formatListForClipboard(completed, "ВЫПОЛНЕНО"));
    buffer.write(_formatListForClipboard(deleted, "УДАЛЕНО"));

    Clipboard.setData(ClipboardData(text: buffer.toString()));
    _showSnackBar("Все списки скопированы!");
  }

  void _showClipboardMenu(int tabIndex) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(0)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.copy_all, color: Colors.black),
                title: const Text("Скопировать ВСЕ списки"),
                onTap: () {
                  Navigator.pop(ctx);
                  _copyAllLists();
                },
              ),
              ListTile(
                leading: const Icon(Icons.list, color: Colors.black),
                title: const Text("Скопировать ЭТОТ список"),
                onTap: () {
                  Navigator.pop(ctx);
                  _copySpecificList(tabIndex);
                },
              ),
            ],
          ),
        );
      },
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

  // --- УТИЛИТЫ ИНДЕКСОВ ---

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

  // --- ОПЕРАЦИИ НАД ЗАДАЧАМИ ---

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
    task.title = task.title;
    task.urgency = urgency;
    task.importance = importance;

    if (moveDirection == 1) {
      task.sortIndex = _getTopIndexForState();
    } else if (moveDirection == 2) {
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

  // --- UI HELPERS ---

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
                  _buildDeletedTasksList(), // Слева
                  _buildActiveTasksList(), // Центр
                  _buildCompletedTasksList(), // Справа
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
        _showClipboardMenu(index);
      },
      child: Tab(
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

  // --- ЦЕНТР: ОСНОВНОЙ СПИСОК ---
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
        return _buildActiveTaskItem(task);
      },
    );
  }

  Widget _buildActiveTaskItem(Task task) {
    Color itemBgColor;
    if (task.urgency > 1 && task.importance > 1) {
      itemBgColor = Colors.red.withOpacity(0.08);
    } else if (task.urgency > 1) {
      itemBgColor = Colors.orange.withOpacity(0.08);
    } else if (task.importance > 1) {
      itemBgColor = Colors.yellow.withOpacity(0.12);
    } else {
      itemBgColor = Colors.white;
    }

    return Dismissible(
      key: Key(task.id),
      background: Container(
        color: const Color(0xFFD4AF37),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 24),
        child: const Icon(Icons.emoji_events, color: Colors.white),
      ),
      secondaryBackground: Container(
        color: Colors.black,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          _completeTask(task);
        } else {
          _moveToTrash(task);
        }
        return false;
      },
      child: GestureDetector(
        onDoubleTap: () => _showTaskDialog(context, task: task),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 1),
          decoration: BoxDecoration(
            color: itemBgColor,
            border: Border(
              bottom: BorderSide(color: Colors.grey.withOpacity(0.1)),
            ),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 8,
            ),
            title: Text(
              task.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 18,
                color: Colors.black87,
                height: 1.2,
                fontWeight: task.importance > 1
                    ? FontWeight.bold
                    : FontWeight.normal,
              ),
            ),
            trailing: (task.urgency > 1 || task.importance > 1)
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (task.urgency > 1)
                        const Icon(Icons.bolt, size: 16, color: Colors.red),
                      if (task.importance > 1)
                        const Icon(
                          Icons.star,
                          size: 16,
                          color: Color(0xFFDAA520),
                        ),
                    ],
                  )
                : null,
          ),
        ),
      ),
    );
  }

  // --- СЛЕВА: МУСОРКА ---
  Widget _buildDeletedTasksList() {
    final tasks = _box.values.where((t) => t.isDeleted).toList();
    tasks.sort((a, b) => a.sortIndex.compareTo(b.sortIndex));

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: tasks.length,
      itemBuilder: (context, index) {
        final task = tasks[index];
        return Dismissible(
          key: Key(task.id),
          background: Container(
            color: Colors.green,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.only(left: 24),
            child: const Icon(Icons.restore, color: Colors.white),
          ),
          secondaryBackground: Container(
            color: Colors.red,
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
                  content: const Text('Это действие нельзя отменить.'),
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
            if (direction == DismissDirection.endToStart) {
              _permanentlyDelete(task.id);
            }
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListTile(
              title: Text(
                task.title,
                style: const TextStyle(
                  color: Colors.grey,
                  decoration: TextDecoration.lineThrough,
                ),
              ),
            ),
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
      padding: const EdgeInsets.all(16),
      itemCount: tasks.length,
      itemBuilder: (context, index) {
        final task = tasks[index];
        return Dismissible(
          key: Key(task.id),
          background: Container(
            color: Colors.black,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.only(left: 24),
            child: const Icon(Icons.delete_outline, color: Colors.white),
          ),
          secondaryBackground: Container(
            color: Colors.white,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 24),
            child: const Icon(Icons.restore, color: Colors.black),
          ),
          confirmDismiss: (direction) async {
            if (direction == DismissDirection.startToEnd) {
              _moveToTrash(task);
            } else {
              _restoreToActive(task);
            }
            return false;
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  Color(0xFFBF953F),
                  Color(0xFFFCF6BA),
                  Color(0xFFB38728),
                  Color(0xFFFBF5B7),
                  Color(0xFFAA771C),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                stops: [0.0, 0.25, 0.5, 0.75, 1.0],
              ),
              borderRadius: BorderRadius.circular(8),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black45,
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 12,
              ),
              leading: const Icon(
                Icons.emoji_events,
                color: Colors.black87,
                size: 30,
              ),
              title: Text(
                task.title,
                style: const TextStyle(
                  fontSize: 18,
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Times New Roman',
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // --- ДИАЛОГИ ---

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
        title: const Text('Важное дело', textAlign: TextAlign.center),
        content: const Text('Куда добавить?', textAlign: TextAlign.center),
        actionsAlignment: MainAxisAlignment.spaceEvenly,
        actions: [
          Column(
            mainAxisSize: MainAxisSize.min,
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
            mainAxisSize: MainAxisSize.min,
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
        content: const Text(
          'Переместить задачу или оставить на месте?',
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
                          ); // 0 = Stay
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
        ],
      ),
    );
  }

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
          return AlertDialog(
            backgroundColor: Colors.white,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.zero,
            ),
            insetPadding: const EdgeInsets.all(20),
            contentPadding: const EdgeInsets.all(20),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: titleController,
                    autofocus: true,
                    style: const TextStyle(fontSize: 18, color: Colors.black87),
                    decoration: const InputDecoration(
                      hintText: 'Что нужно сделать?',
                      border: InputBorder.none,
                    ),
                    minLines: 2,
                    maxLines: 10,
                  ),
                  const SizedBox(height: 20),
                  const Divider(),
                  _buildSwitchRow('СРОЧНО', urgency == 2, Colors.red, (val) {
                    setDialogState(() => urgency = val ? 2 : 1);
                  }),
                  _buildSwitchRow(
                    'ВАЖНО',
                    importance == 2,
                    const Color(0xFFDAA520),
                    (val) {
                      setDialogState(() => importance = val ? 2 : 1);
                    },
                  ),
                ],
              ),
            ),
            actionsAlignment: MainAxisAlignment.spaceEvenly,
            actions: [
              // Кнопка ОК (Сохранить) - СЛЕВА
              _buildSquareButton(
                icon: Icons.check,
                color: Colors.black,
                onTap: () {
                  if (titleController.text.trim().isNotEmpty) {
                    if (task == null) {
                      // СОЗДАНИЕ
                      Navigator.pop(ctx);
                      if (urgency == 2) {
                        _saveNewTask(
                          titleController.text,
                          urgency,
                          importance,
                          toTop: true,
                        );
                      } else if (importance == 1) {
                        _saveNewTask(
                          titleController.text,
                          urgency,
                          importance,
                          toTop: false,
                        );
                      } else {
                        _showPositionDialog(
                          context,
                          titleController.text,
                          urgency,
                          importance,
                        );
                      }
                    } else {
                      // РЕДАКТИРОВАНИЕ
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

              // Кнопка ОТМЕНА - ПОСЕРЕДИНЕ
              _buildSquareButton(
                icon: Icons.close,
                color: Colors.black54,
                onTap: () => Navigator.pop(ctx),
              ),

              // Кнопка КОПИРОВАТЬ - СПРАВА
              _buildSquareButton(
                icon: Icons.copy,
                color: Colors.black,
                onTap: () {
                  if (titleController.text.trim().isNotEmpty) {
                    // Создаем временный объект для получения эмодзи
                    final tempTask = Task(
                      id: 'temp',
                      title: titleController.text,
                      createdAt: DateTime.now(),
                      urgency: urgency,
                      importance: importance,
                      isCompleted: task?.isCompleted ?? false,
                      isDeleted: task?.isDeleted ?? false,
                    );

                    final emoji = _getTaskEmoji(tempTask);
                    Clipboard.setData(
                      ClipboardData(text: "$emoji ${tempTask.title}"),
                    );
                    _showSnackBar("Задача скопирована");
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }

  // Виджет квадратной кнопки для диалога
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

  Widget _buildSwitchRow(
    String label,
    bool value,
    Color color,
    Function(bool) onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: value ? color : Colors.grey,
            ),
          ),
          const Spacer(),
          Switch(value: value, activeColor: color, onChanged: onChanged),
        ],
      ),
    );
  }
}
