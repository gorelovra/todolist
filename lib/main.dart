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

// --- МОДЕЛЬ ДАННЫХ ---
class Task extends HiveObject {
  String id;
  String title;
  bool isCompleted;
  bool isDeleted;
  DateTime createdAt;
  int urgency;
  int importance;
  int sortIndex; // Добавили для ручной сортировки

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
    // Читаем старые поля по порядку
    final id = reader.readString();
    final title = reader.readString();
    final isCompleted = reader.readBool();
    final isDeleted = reader.readBool();
    final createdAt = DateTime.fromMillisecondsSinceEpoch(reader.readInt());
    final urgency = reader.readInt();
    final importance = reader.readInt();

    // ПРОВЕРКА НА ОБНОВЛЕНИЕ:
    // Если байты кончились (старая версия базы), ставим 0.
    // Если байты есть (новая версия), читаем их.
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
        fontFamily: 'Times New Roman', // Оставляем классику, но чище
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

  // Для отслеживания текущей вкладки и смены темы
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _box = Hive.box<Task>('tasksBox');

    // Слушаем переключение вкладок для смены фона
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

  // --- ЛОГИКА ---

  void _addTask(String title, int urgency, int importance) {
    // Новая задача получает индекс в начало списка (меньше всех)
    final currentMinIndex = _box.values.isEmpty
        ? 0
        : _box.values.map((e) => e.sortIndex).reduce((a, b) => a < b ? a : b);

    final newTask = Task(
      id: const Uuid().v4(),
      title: title,
      createdAt: DateTime.now(),
      urgency: urgency,
      importance: importance,
      sortIndex: currentMinIndex - 1,
    );
    _box.put(newTask.id, newTask);
    setState(() {});
  }

  void _updateTask(Task task) {
    task.save();
    setState(() {});
  }

  void _toggleComplete(Task task) {
    task.isCompleted = !task.isCompleted;
    if (task.isCompleted) {
      task.isDeleted = false;
    }
    task.save();
    setState(() {});
  }

  void _moveToTrash(Task task) {
    task.isDeleted = true;
    task.isCompleted = false;
    task.save();
    setState(() {});
  }

  void _permanentlyDelete(String id) {
    _box.delete(id);
    setState(() {});
  }

  void _restoreTask(Task task) {
    task.isDeleted = false;
    task.save();
    setState(() {});
  }

  // Обновление порядка при перетаскивании
  void _onReorder(int oldIndex, int newIndex, List<Task> currentList) {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final Task item = currentList.removeAt(oldIndex);
    currentList.insert(newIndex, item);

    // Пересчитываем индексы для всей группы
    for (int i = 0; i < currentList.length; i++) {
      currentList[i].sortIndex = i;
      currentList[i].save();
    }
    setState(() {});
  }

  // --- СЧЕТЧИКИ ---
  int get _activeCount =>
      _box.values.where((t) => !t.isDeleted && !t.isCompleted).length;
  int get _completedCount =>
      _box.values.where((t) => t.isCompleted && !t.isDeleted).length;
  int get _deletedCount => _box.values.where((t) => t.isDeleted).length;

  // --- UI ---

  // Определяем фон в зависимости от вкладки
  Color get _backgroundColor {
    if (_currentIndex == 1)
      return const Color(0xFF121212); // Черный для выполненных
    return const Color(0xFFFFFFFF); // Белый для остальных
  }

  Color get _textColor {
    if (_currentIndex == 1) return Colors.white;
    return Colors.black87;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      // Анимируем смену цвета статус бара
      appBar: AppBar(
        backgroundColor: _backgroundColor,
        elevation: 0,
        toolbarHeight:
            0, // Скрываем стандартный AppBar, оставляем только TabBar
        systemOverlayStyle: _currentIndex == 1
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Верхняя панель вкладок
            Container(
              height: 60,
              decoration: BoxDecoration(
                color: _backgroundColor,
                border: Border(
                  bottom: BorderSide(
                    color: _currentIndex == 1 ? Colors.white12 : Colors.black12,
                  ),
                ),
              ),
              child: TabBar(
                controller: _tabController,
                indicatorColor: _currentIndex == 1
                    ? const Color(0xFFFFD700)
                    : Colors.black,
                labelColor: _textColor,
                unselectedLabelColor: _currentIndex == 1
                    ? Colors.white38
                    : Colors.black38,
                tabs: [
                  _buildTab(Icons.list_alt, _activeCount),
                  _buildTab(Icons.emoji_events_outlined, _completedCount),
                  _buildTab(Icons.delete_outline, _deletedCount),
                ],
              ),
            ),
            // Контент
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildActiveTasksList(),
                  _buildCompletedTasksList(), // Фон черный, контент золотой
                  _buildDeletedTasksList(),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: _currentIndex == 0
          ? FloatingActionButton(
              onPressed: () => _showTaskDialog(context),
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  Widget _buildTab(IconData icon, int count) {
    return Tab(
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
    );
  }

  // --- СПИСОК АКТИВНЫХ ЗАДАЧ ---
  Widget _buildActiveTasksList() {
    // Получаем список и сортируем вручную по sortIndex
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
      proxyDecorator: (child, index, animation) {
        return Material(elevation: 5, color: Colors.transparent, child: child);
      },
      itemBuilder: (context, index) {
        final task = tasks[index];
        return _buildActiveTaskItem(task);
      },
    );
  }

  Widget _buildActiveTaskItem(Task task) {
    // Определение цвета фона (еле заметный)
    Color itemBgColor;
    if (task.urgency > 1 && task.importance > 1) {
      itemBgColor = Colors.red.withOpacity(0.08); // Срочно+Важно
    } else if (task.urgency > 1) {
      itemBgColor = Colors.orange.withOpacity(0.08); // Срочно
    } else if (task.importance > 1) {
      itemBgColor = Colors.yellow.withOpacity(0.12); // Важно
    } else {
      itemBgColor = Colors.white; // Обычное
    }

    return Dismissible(
      key: Key(task.id),
      background: Container(
        color: const Color(0xFFD4AF37), // Золотой свайп
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 24),
        child: const Icon(Icons.check, color: Colors.white),
      ),
      secondaryBackground: Container(
        color: Colors.black, // Черный свайп удаления
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          _toggleComplete(task);
          return false;
        } else {
          // Удаление
          return await showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: Colors.white,
              title: const Text('В корзину?'),
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
                  child: const Text('ДА', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
          );
        }
      },
      onDismissed: (direction) => _moveToTrash(task),
      child: GestureDetector(
        onDoubleTap: () => _showTaskDialog(context, task: task),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 1, horizontal: 0),
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
              maxLines: 2, // Ограничение строк в списке
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 18,
                color: Colors.black87,
                height: 1.2,
              ),
            ),
            // Если есть метки, показываем маленькие иконки справа
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

  // --- СПИСОК ВЫПОЛНЕННЫХ (ЗОЛОТОЙ РЕЖИМ) ---
  Widget _buildCompletedTasksList() {
    final tasks = _box.values
        .where((t) => t.isCompleted && !t.isDeleted)
        .toList();
    // Сортируем: свежие выполненные сверху
    tasks.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: tasks.length,
      itemBuilder: (context, index) {
        final task = tasks[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            // Настоящий золотой градиент
            gradient: const LinearGradient(
              colors: [
                Color(0xFFBF953F), // Dark Gold
                Color(0xFFFCF6BA), // Light Gold
                Color(0xFFB38728), // Gold
                Color(0xFFFBF5B7), // Light Gold
                Color(0xFFAA771C), // Dark Gold
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
                color: Colors.black, // Черный текст на золоте
                fontWeight: FontWeight.bold,
                fontFamily: 'Times New Roman',
              ),
            ),
          ),
        );
      },
    );
  }

  // --- СПИСОК УДАЛЕННЫХ ---
  Widget _buildDeletedTasksList() {
    final tasks = _box.values.where((t) => t.isDeleted).toList();
    tasks.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: tasks.length,
      itemBuilder: (context, index) {
        final task = tasks[index];
        return Container(
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
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.restore, color: Colors.black),
                  onPressed: () => _restoreTask(task),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.red),
                  onPressed: () => _permanentlyDelete(task.id),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // --- ДИАЛОГ СОЗДАНИЯ/РЕДАКТИРОВАНИЯ ---
  void _showTaskDialog(BuildContext context, {Task? task}) {
    final titleController = TextEditingController(text: task?.title ?? '');
    int urgency = task?.urgency ?? 1;
    int importance = task?.importance ?? 1;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: Colors.white,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.zero,
            ), // Квадратный стиль
            insetPadding: const EdgeInsets.all(20),
            contentPadding: const EdgeInsets.all(20),
            content: SingleChildScrollView(
              // Исправляет "Баннер" оверлоад
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
                    maxLines: 10, // Растет до 10 строк
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
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text(
                  'ОТМЕНА',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.zero,
                  ),
                ),
                onPressed: () {
                  if (titleController.text.trim().isNotEmpty) {
                    if (task == null) {
                      _addTask(titleController.text, urgency, importance);
                    } else {
                      task.title = titleController.text;
                      task.urgency = urgency;
                      task.importance = importance;
                      _updateTask(task);
                    }
                    Navigator.pop(ctx);
                  }
                },
                child: const Text('ЗАПИСАТЬ'),
              ),
            ],
          );
        },
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
          Switch(value: value, activeThumbColor: color, onChanged: onChanged),
        ],
      ),
    );
  }
}
