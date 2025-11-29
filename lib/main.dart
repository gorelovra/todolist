import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';

// Импорт виджетов и новых сервисов
import 'widgets.dart';
import 'dialogs.dart';
import 'services/notifications.dart';
import 'services/clipboard_parser.dart';
import 'services/update_service.dart';
import 'repositories/task_repository.dart';

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

  await NotificationService().initialize();

  runApp(const TdlRomanApp(home: RomanHomePage()));
}

class RomanHomePage extends StatefulWidget {
  const RomanHomePage({super.key});

  @override
  State<RomanHomePage> createState() => _RomanHomePageState();
}

class _RomanHomePageState extends State<RomanHomePage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late TabController _tabController;
  late Box<Task> _box;
  late TaskRepository _taskRepository;

  final ScrollController _scrollController = ScrollController();
  final NotificationService _notificationService = NotificationService();
  final UpdateService _updateService = UpdateService();

  int _currentIndex = 1;

  String? _expandedTaskId;
  String? _selectedTaskId;
  String? _highlightTaskId;
  String? _menuOpenTaskId;

  final Set<String> _openFolders = {};
  OverlayEntry? _toastEntry;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabController = TabController(length: 3, vsync: this, initialIndex: 1);

    _box = Hive.box<Task>('tasksBox');
    _taskRepository = TaskRepository(_box);

    // Лечим "сирот" при старте
    if (_taskRepository.fixOrphans()) {
      setState(() {});
    }

    _scheduleDailyNotification();

    _tabController.addListener(() {
      if (_tabController.indexIsChanging ||
          _tabController.index != _currentIndex) {
        setState(() {
          _currentIndex = _tabController.index;
          _expandedTaskId = null;
          _selectedTaskId = null;
          _menuOpenTaskId = null;
        });
      }
    });

    _checkUpdates();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabController.dispose();
    _scrollController.dispose();
    _toastEntry?.remove();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _schedulePauseNotification();
    } else if (state == AppLifecycleState.resumed) {
      _notificationService.cancel(1);
    }
  }

  void _schedulePauseNotification() async {
    final activeTasks = _box.values
        .where((t) => !t.isDeleted && !t.isCompleted && t.parentId == null)
        .toList();

    if (activeTasks.isEmpty) return;
    activeTasks.sort((a, b) => a.sortIndex.compareTo(b.sortIndex));

    await _notificationService.schedulePauseReminder(activeTasks.first.title);
  }

  void _scheduleDailyNotification() async {
    final activeTasks = _box.values
        .where((t) => !t.isDeleted && !t.isCompleted && t.parentId == null)
        .toList();

    if (activeTasks.isEmpty) {
      await _notificationService.cancel(0);
      return;
    }
    activeTasks.sort((a, b) => a.sortIndex.compareTo(b.sortIndex));

    await _notificationService.scheduleDailyMorning(activeTasks.first.title);
  }

  void _checkUpdates() async {
    if (await _updateService.checkUpdateAvailable()) {
      if (!mounted) return;
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
              child: const Text("Позже", style: TextStyle(color: Colors.grey)),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _updateService.performUpdate(
                  _box,
                  onStatusChange: _showTopToast,
                );
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
  }

  void _showTopToast(String message) {
    _toastEntry?.remove();
    OverlayEntry? thisEntry;
    thisEntry = OverlayEntry(
      builder: (context) => _ToastWidget(
        message: message,
        onDismiss: () {
          thisEntry?.remove();
          if (_toastEntry == thisEntry) _toastEntry = null;
        },
      ),
    );
    _toastEntry = thisEntry;
    Overlay.of(context).insert(thisEntry);
  }

  Future<void> _handlePasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;

    if (text == null || text.trim().isEmpty) {
      _showTopToast("Буфер обмена пуст");
      return;
    }

    if (text.contains("TDL ROMAN REPORT") || text.contains("ТАРТАР")) {
      _showTopToast("Нельзя вставить весь отчет. Скопируйте задачу.");
      return;
    }

    // Используем наш новый парсер
    final roots = ClipboardParser.parse(text);

    if (roots.length > 1) {
      _showTopToast("Можно вставить только одну структуру.");
      return;
    }
    if (roots.isEmpty) {
      // Парсер вернул пустоту, хотя текст был (редкий кейс)
      return;
    }

    final candidate = roots.first;

    // Проверка дубликатов (UI логика, оставляем здесь)
    final duplicate = _box.values.firstWhere(
      (t) =>
          t.title == candidate.title &&
          !t.isDeleted &&
          !t.isCompleted &&
          t.parentId == null,
      orElse: () => Task(id: '', title: '', createdAt: DateTime.now()),
    );

    if (duplicate.id.isNotEmpty) {
      _scrollToTask(duplicate);
      _highlightTaskId = duplicate.id;
      _triggerBlink();

      final bool? shouldCreate = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.white,
          title: const Text("Обнаружены дубликаты"),
          content: const Text(
            "Такая задача уже есть, я подсветил её.\nВсё равно создать?",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Отмена", style: TextStyle(color: Colors.grey)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text(
                "Дублировать",
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      );

      if (shouldCreate != true) return;
    }

    showSandboxDialog(
      context,
      tempRoot: candidate,
      onImport: (root) {
        _taskRepository.importTaskTree(root);
        // Нам не нужно знать ID для подсветки, если мы импортируем.
        // Хотя в оригинале мы подсвечивали. Можно доработать репозиторий, чтобы он возвращал ID.
        // Для простоты пока просто обновляем UI.
        setState(() {});
        _scheduleDailyNotification();
        _showTopToast("Импортировано!");
      },
    );
  }

  void _scrollToTask(Task target) {
    if (target.parentId != null) {
      if (!_openFolders.contains(target.parentId!)) {
        setState(() => _openFolders.add(target.parentId!));
      }
    }
    // Используем UI-специфичный билдер списка для расчета позиции скролла
    final flatList = _buildHierarchicalList(
      (t) => !t.isDeleted && !t.isCompleted && t.parentId == null,
      (t) => !t.isDeleted,
    );
    final index = flatList.indexWhere((t) => t.id == target.id);
    if (index != -1 && _scrollController.hasClients) {
      double offset = index * 60.0;
      double maxScroll = _scrollController.position.maxScrollExtent;
      double viewport = _scrollController.position.viewportDimension;
      double targetOffset = offset - (viewport / 2) + 30;
      if (targetOffset < 0) targetOffset = 0;
      if (targetOffset > maxScroll) targetOffset = maxScroll;
      _scrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    }
  }

  void _triggerBlink() {
    setState(() {});
  }

  int _countActive() {
    int count = 0;
    for (var task in _box.values) {
      if (task.isDeleted || task.isCompleted) continue;
      if (task.parentId != null) {
        final parent = _box.get(task.parentId);
        if (parent != null && (parent.isDeleted || parent.isCompleted))
          continue;
      }
      count++;
    }
    return count;
  }

  int _countCompleted() {
    int count = 0;
    for (var task in _box.values) {
      if (task.isDeleted) continue;
      if (task.parentId != null) {
        final parent = _box.get(task.parentId);
        if (parent != null && parent.isDeleted) continue;
      }
      if (task.isCompleted) {
        count++;
      } else {
        if (task.parentId != null) {
          final parent = _box.get(task.parentId);
          if (parent != null && parent.isCompleted && !parent.isDeleted)
            count++;
        }
      }
    }
    return count;
  }

  int _countDeletedRoots() =>
      _box.values.where((t) => t.isDeleted && t.parentId == null).length;

  void _toggleExpand(String id) {
    HapticFeedback.selectionClick();
    final task = _box.get(id);
    setState(() {
      if (task != null && task.parentId == null) _openFolders.clear();
      _expandedTaskId = (_expandedTaskId == id) ? null : id;
    });
  }

  void _toggleFolder(String folderId) {
    HapticFeedback.lightImpact();
    setState(() {
      _expandedTaskId = null;
      if (_openFolders.contains(folderId)) {
        _openFolders.remove(folderId);
      } else {
        _openFolders.clear();
        _openFolders.add(folderId);
      }
    });
  }

  void _toggleSelection(String id) {
    final task = _box.get(id);
    if (task != null) {
      if (_currentIndex != 1 && task.parentId != null) return;
    }
    HapticFeedback.mediumImpact();
    setState(() {
      _selectedTaskId = (_selectedTaskId == id) ? null : id;
    });
  }

  // Генерация Markdown списка (UI логика отображения, оставляем здесь)
  String _formatTaskTitle(Task t) {
    String text = t.title;
    if (t.urgency == 2 && t.importance == 2)
      return "***$text***";
    else if (t.importance == 2)
      return "**$text**";
    else if (t.urgency == 2)
      return "*$text*";
    return text;
  }

  String _generateMarkdownList({
    required bool Function(Task) rootFilter,
    required bool Function(Task) childFilter,
  }) {
    StringBuffer buffer = StringBuffer();
    final rootTasks = _box.values.where(rootFilter).toList();
    rootTasks.sort((a, b) => a.sortIndex.compareTo(b.sortIndex));
    int rootCounter = 1;
    for (var task in rootTasks) {
      if (rootCounter > 1) buffer.writeln("");
      buffer.writeln("$rootCounter. ${_formatTaskTitle(task)}");
      if (task.isFolder) {
        final children = _box.values
            .where((t) => t.parentId == task.id && childFilter(t))
            .toList();
        children.sort(
          (a, b) => (a.urgency != b.urgency)
              ? b.urgency.compareTo(a.urgency)
              : a.sortIndex.compareTo(b.sortIndex),
        );
        int childCounter = 1;
        for (var child in children) {
          buffer.writeln(
            "    $rootCounter.$childCounter. ${_formatTaskTitle(child)}",
          );
          childCounter++;
        }
      }
      rootCounter++;
    }
    return buffer.toString();
  }

  void _copySpecificList(int tabIndex) {
    String text = "";
    if (tabIndex == 0) {
      text =
          "🏛 **ТАРТАР (Удаленные)**\n\n${_generateMarkdownList(rootFilter: (t) => t.isDeleted && t.parentId == null, childFilter: (t) => t.isDeleted)}";
    } else if (tabIndex == 1) {
      text =
          "🏛 **СПИСОК ДЕЛ**\n\n${_generateMarkdownList(rootFilter: (t) => !t.isDeleted && !t.isCompleted && t.parentId == null, childFilter: (t) => !t.isDeleted && !t.isCompleted)}";
    } else {
      text =
          "🏛 **ТРИУМФЫ (Выполнено)**\n\n${_generateMarkdownList(rootFilter: (t) => t.isCompleted && !t.isDeleted && t.parentId == null, childFilter: (t) => t.isCompleted && !t.isDeleted)}";
    }
    if (text.isEmpty) {
      _showTopToast("Список пуст");
    } else {
      Clipboard.setData(ClipboardData(text: text));
      _showTopToast("Вкладка скопирована!");
    }
  }

  void _copyAllLists() {
    StringBuffer buffer = StringBuffer();
    buffer.writeln("🏛 **TDL ROMAN REPORT** 🏛\n");
    buffer.writeln("АКТУАЛЬНОЕ:");
    buffer.write(
      _generateMarkdownList(
        rootFilter: (t) => !t.isDeleted && !t.isCompleted && t.parentId == null,
        childFilter: (t) => !t.isDeleted && !t.isCompleted,
      ),
    );
    buffer.write("\n-------------------\n");
    buffer.writeln("ВЫПОЛНЕНО:");
    buffer.write(
      _generateMarkdownList(
        rootFilter: (t) => t.isCompleted && !t.isDeleted && t.parentId == null,
        childFilter: (t) => t.isCompleted && !t.isDeleted,
      ),
    );
    buffer.write("\n-------------------\n");
    buffer.writeln("УДАЛЕНО:");
    buffer.write(
      _generateMarkdownList(
        rootFilter: (t) => t.isDeleted && t.parentId == null,
        childFilter: (t) => t.isDeleted,
      ),
    );
    Clipboard.setData(ClipboardData(text: buffer.toString()));
    _showTopToast("ВСЕ списки скопированы!");
  }

  void _copySingleTaskTree(Task rootTask) {
    StringBuffer buffer = StringBuffer();
    buffer.writeln("1. ${_formatTaskTitle(rootTask)}");
    if (rootTask.isFolder) {
      bool Function(Task) childFilter =
          (!rootTask.isDeleted && !rootTask.isCompleted)
          ? (t) => !t.isDeleted && !t.isCompleted
          : (t) => !t.isDeleted;
      final children = _box.values
          .where((t) => t.parentId == rootTask.id && childFilter(t))
          .toList();
      children.sort(
        (a, b) => (a.urgency != b.urgency)
            ? b.urgency.compareTo(a.urgency)
            : a.sortIndex.compareTo(b.sortIndex),
      );
      int childCounter = 1;
      for (var child in children) {
        buffer.writeln("    1.$childCounter. ${_formatTaskTitle(child)}");
        childCounter++;
      }
    }
    Clipboard.setData(ClipboardData(text: buffer.toString()));
    _showTopToast("Задача скопирована!");
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
                "МЕНЮ",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  if (tabIndex == 1)
                    _buildCopyActionButton("ВСТАВИТЬ", Icons.paste, () {
                      Navigator.pop(ctx);
                      _handlePasteFromClipboard();
                    }),
                  _buildCopyActionButton("БЭКАП", Icons.save, () {
                    Navigator.pop(ctx);
                    _updateService
                        .createBackup(_box)
                        .catchError((e) => _showTopToast("Ошибка: $e"));
                  }),
                  _buildCopyActionButton("ВЕСЬ ОТЧЕТ", Icons.copy_all, () {
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

  void _showItemContextMenu(Task task) {
    setState(() => _menuOpenTaskId = task.id);
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
              Text(
                task.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  if (!task.isDeleted && !task.isCompleted)
                    _buildCopyActionButton("РЕДАКТИРОВАТЬ", Icons.edit, () {
                      Navigator.pop(ctx);
                      _showTaskDialogWrapped(task: task);
                    }),
                  _buildCopyActionButton("КОПИРОВАТЬ", Icons.copy, () {
                    Navigator.pop(ctx);
                    _copySingleTaskTree(task);
                  }),
                ],
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    ).whenComplete(() {
      if (mounted) setState(() => _menuOpenTaskId = null);
    });
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
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  // UI логика построения списка (Flattened Tree) - оставляем в UI слое
  List<Task> _buildHierarchicalList(
    bool Function(Task) filterRoots,
    bool Function(Task) filterChildren,
  ) {
    List<Task> flatList = [];
    final rootTasks = _box.values.where(filterRoots).toList();
    rootTasks.sort((a, b) => a.sortIndex.compareTo(b.sortIndex));

    for (var task in rootTasks) {
      flatList.add(task);
      if (task.isFolder && _openFolders.contains(task.id)) {
        final children = _box.values
            .where((t) => t.parentId == task.id && filterChildren(t))
            .toList();
        children.sort(
          (a, b) => (a.urgency != b.urgency)
              ? b.urgency.compareTo(a.urgency)
              : a.sortIndex.compareTo(b.sortIndex),
        );
        flatList.addAll(children);
        if (_currentIndex == 1) {
          flatList.add(
            Task(
              id: 'placeholder_${task.id}',
              title: '',
              createdAt: DateTime.now(),
              parentId: task.id,
              isFolder: false,
            ),
          );
        }
      }
    }
    return flatList;
  }

  void _onReorder(int oldIndex, int newIndex) {
    // Внимание: Логика Drag&Drop сильно завязана на визуальном списке.
    // Мы оставляем вычисление "куда упало" в UI, но сохранение делегируем (частично).
    // Полный вынос этой логики в Repository сложен из-за `placeholder_` и `_openFolders`.

    final flatList = _buildHierarchicalList(
      (t) => !t.isDeleted && !t.isCompleted && t.parentId == null,
      (t) => !t.isDeleted,
    );

    if (oldIndex < newIndex) newIndex -= 1;
    final Task item = flatList[oldIndex];
    if (item.id.startsWith('placeholder_')) return;

    flatList.removeAt(oldIndex);
    flatList.insert(newIndex, item);

    // Логика определения нового родителя
    if (item.isFolder) {
      item.parentId = null;
    } else {
      if (newIndex == 0) {
        item.parentId = null;
      } else {
        final neighborAbove = flatList[newIndex - 1];
        if (neighborAbove.id.startsWith('placeholder_')) {
          item.parentId = null;
        } else if (neighborAbove.parentId != null) {
          item.parentId = neighborAbove.parentId;
        } else if (neighborAbove.isFolder &&
            _openFolders.contains(neighborAbove.id)) {
          item.parentId = neighborAbove.id;
        } else {
          item.parentId = null;
        }
      }
    }

    // Логика "заражения" срочностью (бизнес-правило Скрижалей)
    if (item.parentId == null) {
      if (newIndex < flatList.length - 1) {
        final neighborBelow = flatList[newIndex + 1];
        if (!neighborBelow.id.startsWith('placeholder_') &&
            neighborBelow.parentId == null) {
          if (neighborBelow.urgency == 2 && item.urgency != 2) item.urgency = 2;
        }
      }
      if (newIndex > 0) {
        final neighborAbove = flatList[newIndex - 1];
        if (!neighborAbove.id.startsWith('placeholder_') &&
            neighborAbove.parentId == null) {
          if (neighborAbove.urgency != 2 && item.urgency == 2) item.urgency = 1;
        }
      }
    } else {
      // Для подзадач
      if (newIndex < flatList.length - 1) {
        final neighborBelow = flatList[newIndex + 1];
        if (neighborBelow.parentId == item.parentId &&
            !neighborBelow.id.startsWith('placeholder_')) {
          if (neighborBelow.urgency == 2 && item.urgency != 2) item.urgency = 2;
        }
      }
      if (newIndex > 0) {
        final neighborAbove = flatList[newIndex - 1];
        if (neighborAbove.parentId == item.parentId) {
          if (neighborAbove.urgency != 2 && item.urgency == 2) item.urgency = 1;
        }
      }
    }

    item.save();

    // Пересчет индексов (Data Logic, но работает с локальным flatList)
    Map<String?, int> counters = {};
    for (var t in flatList) {
      if (t.id.startsWith('placeholder_')) continue;
      String? pid = t.parentId;
      int currentIndex = counters[pid] ?? 0;
      t.sortIndex = currentIndex;
      t.save();
      counters[pid] = currentIndex + 1;
    }

    _scheduleDailyNotification();
    setState(() {});
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
                onTap: (index) {},
                tabs: [
                  _buildTab(Icons.delete_outline, _countDeletedRoots(), 0),
                  _buildTab(Icons.list_alt, _countActive(), 1),
                  _buildTab(Icons.emoji_events_outlined, _countCompleted(), 2),
                ],
              ),
            ),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () {
                  HapticFeedback.lightImpact();
                  _showClipboardMenu(_currentIndex);
                },
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildDeletedTasksList(),
                    _buildActiveTasksList(),
                    _buildCompletedTasksList(),
                  ],
                ),
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
                  onTap: () {
                    String? targetFolderId;
                    if (_openFolders.isNotEmpty)
                      targetFolderId = _openFolders.first;
                    _showTaskDialogWrapped(
                      task: null,
                      parentId: targetFolderId,
                    );
                  },
                  child: const Icon(Icons.add, color: Colors.black, size: 36),
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildTab(IconData icon, int count, int index) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (_currentIndex == index) {
          HapticFeedback.mediumImpact();
          _showClipboardMenu(index);
        } else {
          _tabController.animateTo(index);
        }
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

  Color get _backgroundColor =>
      _currentIndex == 2 ? const Color(0xFF121212) : const Color(0xFFFFFFFF);
  Color get _textColor => _currentIndex == 2 ? Colors.white : Colors.black87;

  // ... _buildTaskItem и декорации (View Logic) ...
  // Этот код почти не меняется, кроме вызовов репозитория в Dismissible

  Widget _buildTaskItem(
    Task task,
    BuildContext context,
    int index, {
    bool showCup = false,
    bool isReorderable = false,
  }) {
    if (task.id.startsWith('placeholder_')) {
      if (!isReorderable) return const SizedBox();
      return Container(
        key: ValueKey(task.id),
        height: 40,
        margin: const EdgeInsets.fromLTRB(48, 4, 16, 4),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Colors.grey.withOpacity(0.3), width: 2),
          ),
        ),
        alignment: Alignment.centerLeft,
      );
    }
    final isExpanded = _expandedTaskId == task.id;
    final isSelected = _selectedTaskId == task.id;
    final shouldBlink = _highlightTaskId == task.id;
    final isFolderOpen = _openFolders.contains(task.id);
    final isMenuOpen = _menuOpenTaskId == task.id;

    Widget content = TaskItemWidget(
      key: ValueKey(task.id),
      task: task,
      index: index,
      isExpanded: isExpanded,
      isSelected: isSelected,
      showCup: showCup,
      shouldBlink: shouldBlink,
      isFolderOpen: isFolderOpen,
      isMenuOpen: isMenuOpen,
      tabIndex: _currentIndex,
      onBlinkFinished: () {
        if (_highlightTaskId == task.id) _highlightTaskId = null;
      },
      onToggleExpand: () => _toggleExpand(task.id),
      onToggleSelection: () => _toggleSelection(task.id),
      onMenuTap: () {
        HapticFeedback.lightImpact();
        _showItemContextMenu(task);
      },
      onFolderTap: () => _toggleFolder(task.id),
      decorationBuilder: (t) => _getTaskDecoration(t, _currentIndex),
      indicatorBuilder: (t, s) => _buildLeftIndicator(t, s, _currentIndex),
    );

    bool isLockedChild = (_currentIndex != 1) && (task.parentId != null);
    if (isLockedChild) return content;

    Widget background;
    Widget secondaryBackground;
    if (task.parentId != null && !task.isDeleted) {
      if (task.isCompleted) {
        background = _buildSwipeBg(
          const Color(0xFFD4AF37),
          Icons.undo,
          Alignment.centerLeft,
        );
        secondaryBackground = _buildSwipeBg(
          const Color(0xFFD4AF37),
          Icons.undo,
          Alignment.centerRight,
        );
      } else {
        background = _buildSwipeBg(
          Colors.green,
          Icons.check,
          Alignment.centerLeft,
        );
        secondaryBackground = _buildSwipeBg(
          Colors.red,
          Icons.delete,
          Alignment.centerRight,
        );
      }
    } else if (task.isCompleted && !task.isDeleted) {
      background = _buildSwipeBg(
        Colors.black,
        Icons.delete_outline,
        Alignment.centerLeft,
      );
      secondaryBackground = _buildSwipeBg(
        const Color(0xFFD4AF37),
        Icons.list_alt,
        Alignment.centerRight,
      );
    } else if (task.isDeleted) {
      background = _buildSwipeBg(
        const Color(0xFFD4AF37),
        Icons.list_alt,
        Alignment.centerLeft,
      );
      secondaryBackground = _buildSwipeBg(
        Colors.red[900]!,
        Icons.delete_forever,
        Alignment.centerRight,
      );
    } else {
      background = _buildSwipeBg(
        const Color(0xFFD4AF37),
        Icons.emoji_events,
        Alignment.centerLeft,
      );
      secondaryBackground = _buildSwipeBg(
        Colors.black,
        Icons.delete_outline,
        Alignment.centerRight,
      );
    }

    return Dismissible(
      key: Key(task.id),
      direction: isSelected
          ? DismissDirection.horizontal
          : DismissDirection.none,
      background: background,
      secondaryBackground: secondaryBackground,
      confirmDismiss: (direction) async {
        _selectedTaskId = null;
        if (task.parentId != null && !task.isDeleted) {
          if (task.isCompleted) {
            _taskRepository.uncompleteTask(task);
            setState(() {});
            return false;
          } else {
            if (direction == DismissDirection.startToEnd) {
              _taskRepository.completeTask(task);
              _scheduleDailyNotification();
              setState(() {});
              return false;
            } else {
              _taskRepository.moveToTrash(task);
              _scheduleDailyNotification();
              setState(() {});
              return false;
            }
          }
        }
        if (direction == DismissDirection.startToEnd) {
          if (task.isDeleted) {
            _taskRepository.restoreTask(task);
          } else if (task.isCompleted) {
            _taskRepository.moveToTrash(task);
          } else {
            _taskRepository.completeTask(task);
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
                    onPressed: () {
                      Navigator.pop(ctx, true);
                      _taskRepository.permanentlyDelete(task);
                      setState(() {});
                    },
                    child: const Text(
                      'ДА',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ),
            );
          } else if (task.isCompleted) {
            _taskRepository.restoreTask(task);
          } else {
            _taskRepository.moveToTrash(task);
          }
        }
        _scheduleDailyNotification();
        setState(() {});
        return false;
      },
      child: content,
    );
  }

  Widget _buildSwipeBg(Color color, IconData icon, Alignment align) =>
      Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: align,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Icon(icon, color: Colors.white),
      );

  Widget _buildActiveTasksList() {
    final flatList = _buildHierarchicalList(
      (t) => !t.isDeleted && !t.isCompleted && t.parentId == null,
      (t) => !t.isDeleted,
    );
    return ReorderableListView.builder(
      scrollController: _scrollController,
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      padding: EdgeInsets.fromLTRB(
        0,
        10,
        0,
        MediaQuery.of(context).size.height * 0.5,
      ),
      itemCount: flatList.length,
      onReorder: _onReorder,
      proxyDecorator: (child, index, animation) =>
          Material(elevation: 5, color: Colors.transparent, child: child),
      itemBuilder: (context, index) {
        final task = flatList[index];
        return Container(
          key: Key(task.id),
          child: _buildTaskItem(task, context, index, isReorderable: true),
        );
      },
    );
  }

  Widget _buildCompletedTasksList() => _buildReadOnlyList(
    (t) => t.isCompleted && !t.isDeleted && t.parentId == null,
    (t) => t.parentId != null,
  );
  Widget _buildDeletedTasksList() => _buildReadOnlyList(
    (t) => t.isDeleted && t.parentId == null,
    (t) => t.parentId != null,
  );

  Widget _buildReadOnlyList(
    bool Function(Task) rootFilter,
    bool Function(Task) childFilter,
  ) {
    final flatList = _buildHierarchicalList(rootFilter, childFilter);
    return ListView.builder(
      controller: _scrollController,
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        0,
        10,
        0,
        MediaQuery.of(context).size.height * 0.5,
      ),
      itemCount: flatList.length,
      itemBuilder: (context, index) {
        bool showCup = (_currentIndex == 2) && !flatList[index].isFolder;
        if (_currentIndex == 0) showCup = false;
        return _buildTaskItem(
          flatList[index],
          context,
          index,
          showCup: showCup,
          isReorderable: false,
        );
      },
    );
  }

  void _showTaskDialogWrapped({Task? task, String? parentId}) {
    showTaskDialog(
      context,
      task: task,
      parentId: parentId,
      box: _box,
      onToast: _showTopToast,
      onSaveNew: (title, urgency, importance, mode, isFolder, pId) {
        final newTask = _taskRepository.createTask(
          title: title,
          urgency: urgency,
          importance: importance,
          positionMode: mode,
          isFolder: isFolder,
          parentId: pId,
        );
        _highlightTaskId = newTask.id;
        _scheduleDailyNotification();
        setState(() {});
      },
      onUpdate: (task, urgency, importance, mode) {
        _taskRepository.updateTask(
          task,
          urgency: urgency,
          importance: importance,
          positionMode: mode,
        );
        _scheduleDailyNotification();
        setState(() {});
      },
    );
  }

  BoxDecoration _getTaskDecoration(Task task, int tabIndex) {
    BoxShadow? basicShadow = const BoxShadow(
      color: Colors.black12,
      blurRadius: 3,
      offset: Offset(0, 2),
    );
    if (tabIndex == 0)
      return BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(8),
        boxShadow: [basicShadow],
      );
    if (tabIndex == 1)
      return BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: task.isFolder
            ? Border.all(color: Colors.black87, width: 2)
            : null,
        boxShadow: [basicShadow],
      );
    if (tabIndex == 2) {
      if (task.urgency == 2 && task.importance == 2)
        return _grad([
          const Color(0xFFBF953F),
          const Color(0xFFFCF6BA),
          const Color(0xFFAA771C),
        ], basicShadow);
      if (task.importance == 2)
        return _grad([
          const Color(0xFFE0E0E0),
          const Color(0xFFFFFFFF),
          const Color(0xFFAAAAAA),
        ], basicShadow);
      if (task.urgency == 2)
        return _grad([
          const Color(0xFF1A237E),
          const Color(0xFF3949AB),
          const Color(0xFF1A237E),
        ], basicShadow);
      return BoxDecoration(
        color: const Color(0xFF8D6E63),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [basicShadow],
      );
    }
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      boxShadow: [basicShadow],
    );
  }

  BoxDecoration _grad(List<Color> colors, BoxShadow shadow) => BoxDecoration(
    gradient: LinearGradient(
      colors: colors,
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    borderRadius: BorderRadius.circular(8),
    boxShadow: [shadow],
  );

  Widget _buildLeftIndicator(Task task, bool isSelected, int tabIndex) {
    if (isSelected)
      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => _toggleSelection(task.id),
        child: Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(4),
            boxShadow: const [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 2,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: const Icon(Icons.swap_horiz, size: 20, color: Colors.white),
        ),
      );
    if (task.isFolder) {
      IconData? folderOverlayIcon;
      if (tabIndex == 0) folderOverlayIcon = Icons.close;
      if (tabIndex == 2) folderOverlayIcon = Icons.check;
      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => _toggleSelection(task.id),
        child: SizedBox(
          width: 24,
          height: 24,
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Colors.grey.withOpacity(0.5),
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                child: Container(
                  width: 10,
                  height: 6,
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.5),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(3),
                      bottomRight: Radius.circular(3),
                    ),
                  ),
                ),
              ),
              if (folderOverlayIcon != null)
                Center(
                  child: Icon(
                    folderOverlayIcon,
                    size: 16,
                    color: Colors.grey.withOpacity(0.8),
                  ),
                ),
            ],
          ),
        ),
      );
    } else {
      Widget iconWidget;
      IconData? icon;
      if (tabIndex == 0)
        icon = Icons.close;
      else if (tabIndex == 2)
        icon = Icons.check;
      else {
        if (task.isCompleted)
          icon = Icons.check;
        else
          icon = null;
      }
      if (icon != null)
        iconWidget = Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: Colors.transparent,
            border: Border.all(color: Colors.grey.withOpacity(0.5), width: 2),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(icon, color: Colors.grey, size: 18),
        );
      else
        iconWidget = Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: Colors.transparent,
            border: Border.all(color: Colors.grey.withOpacity(0.5), width: 2),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => _toggleSelection(task.id),
        child: iconWidget,
      );
    }
  }
}

class _ToastWidget extends StatefulWidget {
  final String message;
  final VoidCallback onDismiss;
  const _ToastWidget({required this.message, required this.onDismiss});
  @override
  State<_ToastWidget> createState() => _ToastWidgetState();
}

class _ToastWidgetState extends State<_ToastWidget> {
  bool _isVisible = true;
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _isVisible = false);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 60,
      left: 20,
      right: 20,
      child: IgnorePointer(
        child: AnimatedOpacity(
          opacity: _isVisible ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 800),
          curve: Curves.easeOut,
          onEnd: widget.onDismiss,
          child: Material(
            color: Colors.transparent,
            child: Align(
              alignment: Alignment.topCenter,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Text(
                  widget.message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
