import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_localizations/flutter_localizations.dart'; // Для русского меню
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
      // Настройка русского языка для системных меню (Копировать/Вставить)
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

  // --- СОСТОЯНИЯ ИНТЕРФЕЙСА ---
  String? _expandedTaskId; // Какая задача развернута (текст)
  String? _selectedTaskId; // Какая задача выделена (для свайпа)

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
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // --- UI ВЗАИМОДЕЙСТВИЯ ---

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

  // --- КОПИРОВАНИЕ ---

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
    int importance,
    int positionMode,
  ) {
    // positionMode: 0 = Top, 1 = Middle (не применимо для новых, кидаем вниз), 2 = Bottom
    // Для новых Middle = Bottom
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

    // positionMode: 0 = Top, 1 = Stay, 2 = Bottom
    if (positionMode == 0)
      task.sortIndex = _getTopIndexForState();
    else if (positionMode == 2)
      task.sortIndex = _getBottomIndexForActive();
    // if 1 - index doesn't change

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

  // --- UI ---

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
                borderRadius: BorderRadius.circular(8), // Квадратный
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

  // --- ЛЕВЫЙ БЛОК (ЗНАЧОК + НОМЕР) ---
  Widget _buildLeftIndicator(Task task, int index, bool isSelected) {
    IconData icon;
    Color bgColor;
    bool isDouble = false;
    Color iconColor = Colors.white;

    // Если задача выделена для свайпа - кружок черный
    if (isSelected) {
      icon = Icons.swipe; // Или любая другая иконка
      bgColor = Colors.black;
      iconColor = Colors.white;
    } else {
      // Стандартная логика приоритетов
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
        // Обычная задача - пустой кружок
        icon = Icons.circle_outlined; // Пустышка, не рисуем
        bgColor = Colors.transparent;
      }
    }

    return GestureDetector(
      onTap: () => _toggleSelection(task.id), // Клик сюда включает режим свайпа
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
                      Icon(Icons.priority_high, size: 14, color: Colors.white),
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
    );
  }

  // --- ДЕКОРАТОРЫ ---
  BoxDecoration _getTaskDecoration(Task task) {
    // Рамка выделения теперь на значке, саму плашку не меняем

    // 1. Ачивки
    if (task.isCompleted && !task.isDeleted) {
      if (task.urgency == 2 && task.importance == 2)
        return _grad([Color(0xFFBF953F), Color(0xFFFCF6BA), Color(0xFFAA771C)]);
      if (task.importance == 2)
        return _grad([Color(0xFFE0E0E0), Color(0xFFFFFFFF), Color(0xFFAAAAAA)]);
      if (task.urgency == 2)
        return _grad([Color(0xFFCD7F32), Color(0xFFFFCC99), Color(0xFFA0522D)]);
      return BoxDecoration(
        color: const Color(0xFF8D6E63),
        borderRadius: BorderRadius.circular(8),
        boxShadow: _shadow(),
      );
    }
    // 2. Мусорка
    if (task.isDeleted)
      return BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(8),
        boxShadow: _shadow(),
      );
    // 3. Активное
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

  // --- ЕДИНЫЙ ВИДЖЕТ ЗАДАЧИ ---
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
    final isSelected = _selectedTaskId == task.id; // Включен ли режим свайпа

    Widget content = Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
      decoration: _getTaskDecoration(task),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        // ЛЕВАЯ ЧАСТЬ: Значок + Номер
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
        // ПРАВАЯ ЧАСТЬ: Кубок в выполненных (опционально)
        trailing: showCup
            ? const Icon(Icons.emoji_events, color: Colors.white, size: 28)
            : null,
      ),
    );

    // Клик по телу - раскрыть. Двойной клик - редактировать.
    content = GestureDetector(
      onTap: () => _toggleExpand(task.id),
      onDoubleTap: () {
        if (!task.isDeleted && !task.isCompleted)
          _showTaskDialog(context, task: task);
      },
      child: content,
    );

    return Dismissible(
      key: Key(task.id),
      // Свайп работает ТОЛЬКО если задача выделена (нажат значок слева)
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
          if (task.isDeleted)
            _restoreToActive(task);
          else if (task.isCompleted)
            _moveToTrash(task);
          else
            _completeTask(task);
        } else {
          if (task.isDeleted)
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
          else if (task.isCompleted)
            _restoreToActive(task);
          else
            _moveToTrash(task);
        }
        // После действия сбрасываем выделение
        _selectedTaskId = null;
        return false;
      },
      child: content,
    );
  }

  // --- СПИСКИ ---

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

  // --- ДИАЛОГ РЕДАКТИРОВАНИЯ ---

  void _showTaskDialog(BuildContext context, {Task? task}) {
    final titleController = TextEditingController(text: task?.title ?? '');
    int urgency = task?.urgency ?? 1;
    int importance = task?.importance ?? 1;

    // 0=Top, 1=Middle, 2=Bottom
    int positionMode = 1; // По умолчанию - оставить как есть

    // Для анимации кнопки "Вверх"
    bool attentionTop = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          // Метод для кнопок приоритета
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
                width: 40,
                height: 40,
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
                  color: isActive ? activeColor : Colors.grey.withOpacity(0.3),
                  size: 24,
                ),
              ),
            );
          }

          // Метод для кнопок позиции
          Widget buildPosButton({required int mode, required IconData icon}) {
            bool isSel = positionMode == mode;
            // Если активно внимание и это верхняя кнопка
            Color color = isSel ? Colors.blue : Colors.grey.withOpacity(0.3);
            if (mode == 0 && attentionTop)
              color = Colors
                  .blue; // Моргание можно реализовать Timer, но пока просто цвет

            return GestureDetector(
              onTap: () => setDialogState(() => positionMode = mode),
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  border: Border.all(color: color, width: 2),
                  borderRadius: BorderRadius.circular(4),
                  color: isSel
                      ? Colors.blue.withOpacity(0.1)
                      : Colors.transparent,
                ),
                child: Icon(icon, size: 20, color: color),
              ),
            );
          }

          // Логика "внимания"
          void triggerAttention() {
            setDialogState(() {
              positionMode = 0; // Ставим вверх
              attentionTop = true;
            });
            // Моргаем 3 раза
            Timer.periodic(const Duration(milliseconds: 300), (timer) {
              if (!ctx.mounted) {
                timer.cancel();
                return;
              }
              setDialogState(() => attentionTop = !attentionTop);
              if (timer.tick >= 6) {
                timer.cancel();
                setDialogState(() => attentionTop = false);
              }
            });
          }

          return AlertDialog(
            backgroundColor: Colors.white,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.zero,
            ),
            contentPadding: const EdgeInsets.all(16),
            content: SizedBox(
              width: double.maxFinite,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ЛЕВАЯ КОЛОНКА: Текст + Приоритеты
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 120),
                          child: Scrollbar(
                            thumbVisibility: true,
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
                                maxLines: null,
                              ),
                            ),
                          ),
                        ),
                        const Divider(),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Column(
                              children: [
                                buildStateButton(
                                  icon: Icons.bolt,
                                  isActive: urgency == 2,
                                  activeColor: Colors.red,
                                  onTap: () {
                                    setDialogState(
                                      () => urgency = (urgency == 1 ? 2 : 1),
                                    );
                                    if (urgency == 2) triggerAttention();
                                  },
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  "Срочно",
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(width: 20),
                            Column(
                              children: [
                                buildStateButton(
                                  icon: Icons.priority_high,
                                  isActive: importance == 2,
                                  activeColor: Colors.orange,
                                  onTap: () {
                                    setDialogState(
                                      () => importance = (importance == 1
                                          ? 2
                                          : 1),
                                    );
                                    if (importance == 2) triggerAttention();
                                  },
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  "Важно",
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // ПРАВАЯ КОЛОНКА: Кнопки позиции
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(
                        height: 20,
                      ), // Отступ сверху чтобы выровнять с центром
                      buildPosButton(mode: 0, icon: Icons.keyboard_arrow_up),
                      buildPosButton(mode: 1, icon: Icons.stop),
                      buildPosButton(mode: 2, icon: Icons.keyboard_arrow_down),
                    ],
                  ),
                ],
              ),
            ),
            actionsAlignment: MainAxisAlignment.spaceEvenly,
            actions: [
              _buildSquareButtonWithLabel(
                label: "ОК",
                icon: Icons.check,
                color: Colors.black,
                onTap: () {
                  if (titleController.text.trim().isNotEmpty) {
                    if (task == null) {
                      // Новая задача. Если Middle (1), считаем как Bottom (2)
                      _saveNewTask(
                        titleController.text,
                        urgency,
                        importance,
                        positionMode == 1 ? 2 : positionMode,
                      );
                    } else {
                      task.title = titleController.text;
                      _updateTaskAndMove(
                        task,
                        urgency,
                        importance,
                        positionMode,
                      );
                    }
                    Navigator.pop(ctx);
                  }
                },
              ),
              _buildSquareButtonWithLabel(
                label: "Отмена",
                icon: Icons.close,
                color: Colors.black54,
                onTap: () => Navigator.pop(ctx),
              ),
              _buildSquareButtonWithLabel(
                label: "Копия",
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

  Widget _buildSquareButtonWithLabel({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 40,
          height: 40,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(4),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: color, width: 1.5),
                  borderRadius: BorderRadius.circular(4),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: color, size: 22),
              ),
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 9, color: Colors.grey)),
      ],
    );
  }
}
