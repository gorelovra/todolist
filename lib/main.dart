import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_rustore_update/flutter_rustore_update.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:visibility_detector/visibility_detector.dart';

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

  bool isFolder;
  String? parentId;

  Task({
    required this.id,
    required this.title,
    this.isCompleted = false,
    this.isDeleted = false,
    required this.createdAt,
    this.urgency = 1,
    this.importance = 1,
    this.sortIndex = 0,
    this.isFolder = false,
    this.parentId,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'isCompleted': isCompleted,
    'isDeleted': isDeleted,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'urgency': urgency,
    'importance': importance,
    'sortIndex': sortIndex,
    'isFolder': isFolder,
    'parentId': parentId,
  };
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

    final isFolder = reader.availableBytes > 0 ? reader.readBool() : false;
    String? parentId;
    if (reader.availableBytes > 0) {
      try {
        parentId = reader.readString();
        if (parentId.isEmpty) parentId = null;
      } catch (e) {
        parentId = null;
      }
    }

    return Task(
      id: id,
      title: title,
      isCompleted: isCompleted,
      isDeleted: isDeleted,
      createdAt: createdAt,
      urgency: urgency,
      importance: importance,
      sortIndex: sortIndex,
      isFolder: isFolder,
      parentId: parentId,
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
    writer.writeBool(obj.isFolder);
    writer.writeString(obj.parentId ?? "");
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
            const Text(
              "ACTA NON VERBA",
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey,
                fontStyle: FontStyle.italic,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 40),
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
  String? _highlightTaskId;

  final Set<String> _openFolders = {};

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
                      _performUpdate();
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

  void _performUpdate() {
    RustoreUpdateClient.download()
        .then((value) {
          debugPrint("Загрузка обновления завершена кодом: $value");
        })
        .catchError((e) {
          debugPrint("Ошибка нативной загрузки: $e");
          final uri = Uri.parse(
            "https://apps.rustore.ru/app/ru.gorelovra.tdlroman",
          );
          launchUrl(uri, mode: LaunchMode.externalApplication);
        });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _toggleExpand(String id) {
    HapticFeedback.selectionClick();
    final task = _box.get(id);

    setState(() {
      // ИСПРАВЛЕНО: Если это ребенок, не закрываем папки
      if (task != null && task.parentId == null) {
        _openFolders.clear();
      }

      if (_expandedTaskId == id) {
        _expandedTaskId = null;
      } else {
        _expandedTaskId = id;
      }
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
      if (_currentIndex != 1 && task.parentId != null) {
        return; // Блокировка выделения детей в архивах
      }
    }

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
    if (t.isDeleted) return "☒";
    if (t.isCompleted) return "✅";
    return "☑️";
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

  Future<void> _backupData() async {
    try {
      final tasks = _box.values.map((e) => e.toJson()).toList();
      final jsonString = jsonEncode({'tasks': tasks});

      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/tdl_backup.json');
      await file.writeAsString(jsonString);

      await Share.shareXFiles([XFile(file.path)], text: 'TDL-Roman Backup');
    } catch (e) {
      _showSnackBar("Ошибка бэкапа: $e");
    }
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
                  _buildCopyActionButton("БЭКАП", Icons.save, () {
                    Navigator.pop(ctx);
                    _backupData();
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

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.black87,
        duration: const Duration(seconds: 1),
      ),
    );
  }

  // --- ЛОГИКА ИНДЕКСОВ ---

  void _shiftIndicesDown(int targetIndex) {
    final allActive = _box.values
        .where((t) => !t.isCompleted && !t.isDeleted && t.parentId == null)
        .toList();
    allActive.sort((a, b) => a.sortIndex.compareTo(b.sortIndex));
    for (var t in allActive) {
      if (t.sortIndex >= targetIndex) {
        t.sortIndex += 1;
        t.save();
      }
    }
  }

  void _shiftChildIndicesDown(String parentId, int targetIndex) {
    final children = _box.values
        .where((t) => t.parentId == parentId && !t.isDeleted)
        .toList();
    children.sort((a, b) => a.sortIndex.compareTo(b.sortIndex));
    for (var t in children) {
      if (t.sortIndex >= targetIndex) {
        t.sortIndex += 1;
        t.save();
      }
    }
  }

  int _getTopIndexForState({bool deleted = false, bool completed = false}) {
    final tasks = _box.values.where((t) {
      if (deleted) return t.isDeleted;
      if (completed) return t.isCompleted && !t.isDeleted;
      return !t.isCompleted && !t.isDeleted && t.parentId == null;
    });
    if (tasks.isEmpty) return 0;
    return tasks.map((e) => e.sortIndex).reduce(min) - 1;
  }

  int _getBottomIndexForActive() {
    final tasks = _box.values.where(
      (t) => !t.isCompleted && !t.isDeleted && t.parentId == null,
    );
    if (tasks.isEmpty) return 0;
    return tasks.map((e) => e.sortIndex).reduce(max) + 1;
  }

  int _getTargetIndexForUrgentBottom() {
    final nonUrgentTasks = _box.values
        .where(
          (t) =>
              !t.isCompleted &&
              !t.isDeleted &&
              t.urgency != 2 &&
              t.parentId == null,
        )
        .toList();
    if (nonUrgentTasks.isNotEmpty) {
      final firstNonUrgentIndex = nonUrgentTasks
          .map((e) => e.sortIndex)
          .reduce(min);
      return firstNonUrgentIndex;
    } else {
      return _getBottomIndexForActive();
    }
  }

  int _getTargetIndexForNormalTop() {
    final urgentTasks = _box.values
        .where(
          (t) =>
              !t.isCompleted &&
              !t.isDeleted &&
              t.urgency == 2 &&
              t.parentId == null,
        )
        .toList();
    if (urgentTasks.isNotEmpty) {
      final lastUrgentIndex = urgentTasks.map((e) => e.sortIndex).reduce(max);
      return lastUrgentIndex + 1;
    } else {
      final allActive = _box.values
          .where((t) => !t.isCompleted && !t.isDeleted && t.parentId == null)
          .toList();
      if (allActive.isEmpty) return 0;
      return allActive.map((e) => e.sortIndex).reduce(min);
    }
  }

  int _getChildTopIndex(String parentId) {
    final children = _box.values
        .where((t) => t.parentId == parentId && !t.isDeleted)
        .toList();
    if (children.isEmpty) return 0;
    return children.map((e) => e.sortIndex).reduce(min) - 1;
  }

  int _getChildBottomIndex(String parentId) {
    final children = _box.values
        .where((t) => t.parentId == parentId && !t.isDeleted)
        .toList();
    if (children.isEmpty) return 0;
    return children.map((e) => e.sortIndex).reduce(max) + 1;
  }

  int _getChildTargetIndexForUrgentBottom(String parentId) {
    final nonUrgent = _box.values
        .where((t) => t.parentId == parentId && t.urgency != 2 && !t.isDeleted)
        .toList();
    if (nonUrgent.isNotEmpty) {
      return nonUrgent.map((e) => e.sortIndex).reduce(min);
    }
    return _getChildBottomIndex(parentId);
  }

  int _getChildTargetIndexForNormalTop(String parentId) {
    final urgent = _box.values
        .where((t) => t.parentId == parentId && t.urgency == 2 && !t.isDeleted)
        .toList();
    if (urgent.isNotEmpty) {
      return urgent.map((e) => e.sortIndex).reduce(max) + 1;
    }
    final all = _box.values
        .where((t) => t.parentId == parentId && !t.isDeleted)
        .toList();
    if (all.isEmpty) return 0;
    return all.map((e) => e.sortIndex).reduce(min);
  }

  // --- МЕТОДЫ УПРАВЛЕНИЯ ЗАДАЧАМИ ---

  void _saveNewTask(
    String title,
    int urgency,
    int importance,
    int positionMode,
    bool isFolder,
  ) {
    int newIndex;
    if (urgency == 2) {
      if (positionMode == 0) {
        newIndex = _getTopIndexForState();
      } else {
        newIndex = _getTargetIndexForUrgentBottom();
        _shiftIndicesDown(newIndex);
      }
    } else {
      if (positionMode == 0) {
        newIndex = _getTargetIndexForNormalTop();
        _shiftIndicesDown(newIndex);
      } else {
        newIndex = _getBottomIndexForActive();
      }
    }

    final newTask = Task(
      id: const Uuid().v4(),
      title: title,
      createdAt: DateTime.now(),
      urgency: urgency,
      importance: importance,
      sortIndex: newIndex,
      isFolder: isFolder,
      parentId: null,
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

    int newIndex;

    if (task.parentId != null) {
      String pid = task.parentId!;
      if (task.urgency == 2) {
        if (positionMode == 0)
          newIndex = _getChildTopIndex(pid);
        else {
          newIndex = _getChildTargetIndexForUrgentBottom(pid);
          _shiftChildIndicesDown(pid, newIndex);
        }
      } else {
        if (positionMode == 0) {
          newIndex = _getChildTargetIndexForNormalTop(pid);
          _shiftChildIndicesDown(pid, newIndex);
        } else
          newIndex = _getChildBottomIndex(pid);
      }
    } else {
      if (task.urgency == 2) {
        if (positionMode == 0)
          newIndex = _getTopIndexForState();
        else {
          newIndex = _getTargetIndexForUrgentBottom();
          _shiftIndicesDown(newIndex);
        }
      } else {
        if (positionMode == 0) {
          newIndex = _getTargetIndexForNormalTop();
          _shiftIndicesDown(newIndex);
        } else
          newIndex = _getBottomIndexForActive();
      }

      if (positionMode != 1) {
        task.parentId = null;
      }
    }

    if (positionMode != 1) {
      task.sortIndex = newIndex;
    }

    task.save();
    setState(() {});
  }

  void _completeTask(Task task) {
    task.isCompleted = true;
    task.isDeleted = false;
    if (task.parentId == null) {
      task.sortIndex = _getTopIndexForState(completed: true);
      _highlightTaskId = task.id;
    } else {
      _highlightTaskId = null;
    }

    task.save();
    setState(() {});
  }

  void _uncompleteChild(Task task) {
    task.isCompleted = false;
    task.save();
    setState(() {});
  }

  void _restoreToActive(Task task) {
    task.isCompleted = false;
    task.isDeleted = false;
    task.parentId = null;

    int newIndex;
    if (task.urgency == 2) {
      newIndex = _getTopIndexForState();
    } else {
      newIndex = _getTargetIndexForNormalTop();
      _shiftIndicesDown(newIndex);
    }

    task.sortIndex = newIndex;
    _highlightTaskId = task.id;

    task.save();
    setState(() {});
  }

  void _moveToTrash(Task task) {
    task.isDeleted = true;
    task.isCompleted = false;
    task.parentId = null;
    task.sortIndex = _getTopIndexForState(deleted: true);

    _highlightTaskId = task.id;
    task.save();
    setState(() {});
  }

  Future<void> _permanentlyDelete(Task task) async {
    if (task.isFolder) {
      final children = _box.values.where((t) => t.parentId == task.id).toList();
      for (var child in children) {
        await child.delete();
      }
    }
    await task.delete();
    setState(() {});
  }

  // --- ГЛАВНАЯ ЛОГИКА СПИСКА ---

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

        children.sort((a, b) {
          if (a.urgency != b.urgency) return b.urgency.compareTo(a.urgency);
          return a.sortIndex.compareTo(b.sortIndex);
        });

        flatList.addAll(children);

        // Плейсхолдер ТОЛЬКО в Активном списке (Tab 1)
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
    final flatList = _buildHierarchicalList(
      (t) => !t.isDeleted && !t.isCompleted && t.parentId == null,
      (t) => !t.isDeleted,
    );

    if (oldIndex < newIndex) newIndex -= 1;
    final Task item = flatList[oldIndex];

    if (item.id.startsWith('placeholder_')) return;

    flatList.removeAt(oldIndex);
    flatList.insert(newIndex, item);

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

    // АВТО-СТАТУС
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

    Map<String?, int> counters = {};
    for (var t in flatList) {
      if (t.id.startsWith('placeholder_')) continue;
      String? pid = t.parentId;
      int currentIndex = counters[pid] ?? 0;
      t.sortIndex = currentIndex;
      t.save();
      counters[pid] = currentIndex + 1;
    }

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
                tabs: [
                  _buildTab(
                    Icons.delete_outline,
                    _box.values.where((t) => t.isDeleted).length,
                    0,
                  ),
                  _buildTab(
                    Icons.list_alt,
                    _box.values
                        .where((t) => !t.isDeleted && !t.isCompleted)
                        .length,
                    1,
                  ),
                  _buildTab(
                    Icons.emoji_events_outlined,
                    _box.values
                        .where(
                          (t) =>
                              t.isCompleted &&
                              !t.isDeleted &&
                              t.parentId == null,
                        )
                        .length,
                    2,
                  ),
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

  Color get _backgroundColor {
    if (_currentIndex == 2) return const Color(0xFF121212);
    return const Color(0xFFFFFFFF);
  }

  Color get _textColor {
    if (_currentIndex == 2) return Colors.white;
    return Colors.black87;
  }

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

    Widget content = TaskItemWidget(
      key: ValueKey(task.id),
      task: task,
      index: index,
      isExpanded: isExpanded,
      isSelected: isSelected,
      showCup: showCup,
      shouldBlink: shouldBlink,
      isFolderOpen: isFolderOpen,
      tabIndex: _currentIndex,
      onBlinkFinished: () {
        if (_highlightTaskId == task.id) {
          _highlightTaskId = null;
        }
      },
      onToggleExpand: () => _toggleExpand(task.id),
      onToggleSelection: () => _toggleSelection(task.id),
      onDoubleTap: () {
        // ИСПРАВЛЕНО: Двойной клик разрешен ТОЛЬКО в активном списке (Tab 1)
        if (_currentIndex == 1) {
          if (task.isFolder)
            _toggleFolder(task.id);
          else if (!task.isDeleted && !task.isCompleted)
            _showTaskDialog(context, task: task);
        }
        // В других списках - ТОЛЬКО папки открываются
        else {
          if (task.isFolder) _toggleFolder(task.id);
        }
      },
      onFolderTap: () => _toggleFolder(task.id),
      decorationBuilder: (t) => _getTaskDecoration(t, _currentIndex),
      indicatorBuilder: (t, s) => _buildLeftIndicator(t, s, _currentIndex),
    );

    // БЛОКИРОВКА СВАЙПОВ ДЛЯ ДЕТЕЙ В МУСОРКЕ И ВЫПОЛНЕННЫХ
    bool isLockedChild = (_currentIndex != 1) && (task.parentId != null);
    if (isLockedChild) {
      return content;
    }

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
            _uncompleteChild(task);
            return false;
          } else {
            if (direction == DismissDirection.startToEnd) {
              _completeTask(task);
              return false;
            } else {
              _moveToTrash(task);
              return false;
            }
          }
        }

        if (direction == DismissDirection.startToEnd) {
          if (task.isDeleted)
            _restoreToActive(task);
          else if (task.isCompleted)
            _moveToTrash(task);
          else
            _completeTask(task);
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
                      _permanentlyDelete(task);
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
            _restoreToActive(task);
          } else {
            _moveToTrash(task);
          }
        }
        return false;
      },
      child: content,
    );
  }

  Widget _buildSwipeBg(Color color, IconData icon, Alignment align) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: align,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Icon(icon, color: Colors.white),
    );
  }

  Widget _buildActiveTasksList() {
    final flatList = _buildHierarchicalList(
      (t) => !t.isDeleted && !t.isCompleted && t.parentId == null,
      (t) => !t.isDeleted,
    );

    return ReorderableListView.builder(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(0, 10, 0, 80),
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

  Widget _buildCompletedTasksList() {
    return _buildReadOnlyList(
      (t) => t.isCompleted && !t.isDeleted && t.parentId == null,
      (t) => t.parentId != null,
    );
  }

  Widget _buildDeletedTasksList() {
    return _buildReadOnlyList(
      (t) => t.isDeleted && t.parentId == null,
      (t) => t.parentId != null,
    );
  }

  Widget _buildReadOnlyList(
    bool Function(Task) rootFilter,
    bool Function(Task) childFilter,
  ) {
    final flatList = _buildHierarchicalList(rootFilter, childFilter);
    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 10),
      itemCount: flatList.length,
      itemBuilder: (context, index) {
        bool showCup = (_currentIndex == 2);
        if (_currentIndex == 0) showCup = false;
        if (flatList[index].isFolder) showCup = false;

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

  // ... (ДИАЛОГ и ХЕЛПЕРЫ без изменений) ...
  void _showTaskDialog(BuildContext context, {Task? task}) {
    final titleController = TextEditingController(text: task?.title ?? '');
    int urgency = task?.urgency ?? 1;
    int importance = task?.importance ?? 1;
    int positionMode = task == null ? 2 : 1;
    bool isFolder = task?.isFolder ?? false;
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

            void save() {
              if (titleController.text.trim().isNotEmpty) {
                attentionTimer?.cancel();
                if (task == null) {
                  _saveNewTask(
                    titleController.text,
                    urgency,
                    importance,
                    positionMode,
                    isFolder,
                  );
                } else {
                  task.title = titleController.text;
                  task.isFolder = isFolder;
                  _updateTaskAndMove(task, urgency, importance, positionMode);
                }
                Navigator.pop(ctx);
              }
            }

            return Dialog(
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.zero,
              ),
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
                            ),
                          ),
                        ),
                      ),
                      if (task == null || task.parentId == null)
                        Row(
                          children: [
                            Checkbox(
                              value: isFolder,
                              activeColor: Colors.black,
                              onChanged: (val) =>
                                  setDialogState(() => isFolder = val!),
                            ),
                            const Text("Это папка"),
                          ],
                        ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 170,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      _buildDialogStateButton(
                                        Icons.bolt,
                                        "Срочно",
                                        urgency == 2,
                                        Colors.red,
                                        () {
                                          setDialogState(() {
                                            urgency = (urgency == 1 ? 2 : 1);
                                            if (urgency == 2)
                                              triggerAttention();
                                          });
                                        },
                                      ),
                                      const SizedBox(width: 20),
                                      _buildDialogStateButton(
                                        Icons.priority_high,
                                        "Важно",
                                        importance == 2,
                                        Colors.orange,
                                        () {
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
                                  const SizedBox(height: 10),
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
                                            Clipboard.setData(
                                              ClipboardData(
                                                text: titleController.text,
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
                            SizedBox(
                              width: 50,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  _buildDialogPosButton(
                                    0,
                                    Icons.keyboard_arrow_up,
                                    positionMode,
                                    attentionTop,
                                    blinkStage,
                                    () => selectPosition(0),
                                  ),
                                  _buildDialogPosButton(
                                    1,
                                    Icons.stop,
                                    positionMode,
                                    attentionTop,
                                    blinkStage,
                                    () => selectPosition(1),
                                  ),
                                  _buildDialogPosButton(
                                    2,
                                    Icons.keyboard_arrow_down,
                                    positionMode,
                                    attentionTop,
                                    blinkStage,
                                    () => selectPosition(2),
                                  ),
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

  Widget _buildDialogStateButton(
    IconData icon,
    String label,
    bool isActive,
    Color activeColor,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 45,
            height: 45,
            decoration: BoxDecoration(
              color: Colors.transparent,
              shape: BoxShape.circle,
              border: Border.all(
                color: isActive ? activeColor : Colors.grey.withOpacity(0.3),
                width: 2,
              ),
            ),
            child: Icon(
              icon,
              color: isActive ? activeColor : Colors.grey.withOpacity(0.3),
              size: 26,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: isActive ? activeColor : Colors.grey,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDialogPosButton(
    int mode,
    IconData icon,
    int currentMode,
    bool attention,
    int blinkStage,
    VoidCallback onTap,
  ) {
    bool isSel = currentMode == mode;
    bool isBlinking = (mode == 0 && attention);
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
      onTap: onTap,
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

  // --- ЦВЕТА ЗАДАЧ (ЛОГИКА) ---
  BoxDecoration _getTaskDecoration(Task task, int tabIndex) {
    if (tabIndex == 0) {
      return BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(8),
        boxShadow: _shadow(),
      );
    }

    if (tabIndex == 1) {
      return BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: _shadow(),
      );
    }

    // Вкладка 2 (Триумфы): Золото для всех задач (включая детей)
    if (tabIndex == 2) {
      if (task.urgency == 2 && task.importance == 2)
        return _grad([
          const Color(0xFFBF953F),
          const Color(0xFFFCF6BA),
          const Color(0xFFAA771C),
        ]);
      if (task.importance == 2)
        return _grad([
          const Color(0xFFE0E0E0),
          const Color(0xFFFFFFFF),
          const Color(0xFFAAAAAA),
        ]);
      if (task.urgency == 2)
        return _grad([
          const Color(0xFFCD7F32),
          const Color(0xFFFFCC99),
          const Color(0xFFA0522D),
        ]);
      return BoxDecoration(
        color: const Color(0xFF8D6E63),
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

  BoxDecoration _grad(List<Color> colors) => BoxDecoration(
    gradient: LinearGradient(
      colors: colors,
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    borderRadius: BorderRadius.circular(8),
    boxShadow: _shadow(),
  );
  List<BoxShadow> _shadow() => const [
    BoxShadow(color: Colors.black12, blurRadius: 3, offset: Offset(0, 2)),
  ];

  // --- ИКОНКА ПАПКИ И ЧЕКБОКСЫ (СТРОГО ПО ТЗ) ---
  Widget _buildLeftIndicator(Task task, bool isSelected, int tabIndex) {
    if (isSelected) {
      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => _toggleSelection(task.id),
        child: Container(
          width: 50,
          color: Colors.transparent,
          alignment: Alignment.center,
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
        ),
      );
    }
    Widget iconWidget;

    // ПАПКА В АКТИВНОМ СПИСКЕ (Tab 1) - Специальная иконка
    if (task.isFolder && tabIndex == 1) {
      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => _toggleSelection(task.id),
        child: Container(
          width: 50,
          alignment: Alignment.center,
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
              ],
            ),
          ),
        ),
      );
    }
    // ПАПКА В ДРУГИХ СПИСКАХ ИЛИ ЗАДАЧА - Обычные чекбоксы
    else {
      IconData? icon;
      // В корзине (Tab 0) всегда крестик
      if (tabIndex == 0) {
        icon = Icons.close;
      }
      // В Триумфах (Tab 2) всегда галочка
      else if (tabIndex == 2) {
        icon = Icons.check;
      }
      // В активном списке (Tab 1) зависит от статуса
      else {
        if (task.isCompleted)
          icon = Icons.check;
        else
          icon = null;
      }

      if (icon != null) {
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
      } else {
        iconWidget = Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: Colors.transparent,
            border: Border.all(color: Colors.grey.withOpacity(0.5), width: 2),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }
    }
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => _toggleSelection(task.id),
      child: Container(
        width: 50,
        color: Colors.transparent,
        alignment: Alignment.center,
        child: iconWidget,
      ),
    );
  }
}

class TaskItemWidget extends StatefulWidget {
  final Task task;
  final int index;
  final bool isExpanded;
  final bool isSelected;
  final bool showCup;
  final bool shouldBlink;
  final bool isFolderOpen;
  final int tabIndex;
  final VoidCallback onBlinkFinished;
  final VoidCallback onToggleExpand;
  final VoidCallback onToggleSelection;
  final VoidCallback onDoubleTap;
  final VoidCallback onFolderTap;
  final BoxDecoration Function(Task) decorationBuilder;
  final Widget Function(Task, bool) indicatorBuilder;

  const TaskItemWidget({
    Key? key,
    required this.task,
    required this.index,
    required this.isExpanded,
    required this.isSelected,
    this.showCup = false,
    this.shouldBlink = false,
    this.isFolderOpen = false,
    required this.tabIndex,
    required this.onBlinkFinished,
    required this.onToggleExpand,
    required this.onToggleSelection,
    required this.onDoubleTap,
    required this.onFolderTap,
    required this.decorationBuilder,
    required this.indicatorBuilder,
  }) : super(key: key);

  @override
  State<TaskItemWidget> createState() => _TaskItemWidgetState();
}

class _TaskItemWidgetState extends State<TaskItemWidget> {
  bool _isHighlighed = false;
  Timer? _blinkTimer;
  bool _hasBlinked = false;

  @override
  void initState() {
    super.initState();
    // Мигание запускаем тут, если виджет создается и должен мигать
    if (widget.shouldBlink) {
      _startBlinking();
    }
  }

  @override
  void didUpdateWidget(TaskItemWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.shouldBlink && !oldWidget.shouldBlink) {
      _startBlinking();
    }
  }

  void _startBlinking() {
    if (_blinkTimer != null || _hasBlinked) return;
    _hasBlinked = true;
    int count = 0;
    _isHighlighed = true;
    _blinkTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _isHighlighed = !_isHighlighed;
      });
      count++;
      if (count >= 10) {
        timer.cancel();
        setState(() {
          _isHighlighed = false;
        });
        widget.onBlinkFinished();
      }
    });
  }

  @override
  void dispose() {
    _blinkTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Color textColor = Colors.black87;
    FontWeight fontWeight = FontWeight.normal;
    TextDecoration textDecoration = TextDecoration.none;

    // ЦВЕТ ТЕКСТА
    if (widget.tabIndex == 0) {
      textColor = Colors.grey;
      textDecoration = TextDecoration.lineThrough;
    } else if (widget.tabIndex == 2) {
      if (widget.task.urgency == 1 && widget.task.importance == 1)
        textColor = Colors.white;
      if (widget.task.importance == 2) fontWeight = FontWeight.bold;
    } else {
      if (widget.task.isCompleted) {
        textColor = Colors.grey;
      } else {
        if (widget.task.urgency == 2) textColor = const Color(0xFFD32F2F);
        if (widget.task.importance == 2) fontWeight = FontWeight.bold;
      }
    }

    BoxDecoration decoration = widget.decorationBuilder(widget.task);

    // Стиль стопки для папок
    if (widget.task.isFolder &&
        !widget.task.isDeleted &&
        !widget.task.isCompleted) {
      decoration = decoration.copyWith(
        boxShadow: [
          const BoxShadow(
            color: Colors.black12,
            offset: Offset(3, 3),
            blurRadius: 0,
          ),
          ...decoration.boxShadow ?? [],
        ],
      );
    }

    Color borderColor = Colors.transparent;
    if (_isHighlighed) {
      borderColor = Colors.red;
    }
    decoration = decoration.copyWith(
      border: Border.all(color: borderColor, width: 3),
    );

    EdgeInsets margin = const EdgeInsets.symmetric(vertical: 4, horizontal: 16);
    if (widget.task.parentId != null) {
      margin = const EdgeInsets.fromLTRB(48, 4, 16, 4);
    }

    VoidCallback onTap = widget.task.isFolder
        ? widget.onFolderTap
        : widget.onToggleExpand;

    return Container(
      margin: margin,
      decoration: decoration,
      child: InkWell(
        onTap: onTap,
        onDoubleTap: widget.onDoubleTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: widget.indicatorBuilder(widget.task, widget.isSelected),
              ),
              Expanded(
                child: Text(
                  widget.task.title,
                  maxLines: widget.isExpanded ? null : 2,
                  overflow: widget.isExpanded ? null : TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 18,
                    color: textColor,
                    height: 1.2,
                    fontWeight: fontWeight,
                    decoration: textDecoration,
                    decorationColor: Colors.grey,
                  ),
                ),
              ),
              if (widget.showCup) ...[
                const SizedBox(width: 8),
                const Icon(Icons.emoji_events, color: Colors.white, size: 28),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
