import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_rustore_update/flutter_rustore_update.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'widgets.dart';
import 'dialogs.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

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

  await _initNotifications();

  runApp(const TdlRomanApp(home: RomanHomePage()));
}

Future<void> _initNotifications() async {
  tz.initializeTimeZones();

  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  final DarwinInitializationSettings initializationSettingsDarwin =
      DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

  final InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
    iOS: initializationSettingsDarwin,
  );

  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  final platform = flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();
  await platform?.requestNotificationsPermission();
  await platform?.requestExactAlarmsPermission();
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
  final ScrollController _scrollController = ScrollController();

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

    _fixOrphans();
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
      flutterLocalNotificationsPlugin.cancel(1);
    }
  }

  void _schedulePauseNotification() async {
    final activeTasks = _box.values
        .where((t) => !t.isDeleted && !t.isCompleted && t.parentId == null)
        .toList();

    if (activeTasks.isEmpty) return;

    activeTasks.sort((a, b) => a.sortIndex.compareTo(b.sortIndex));
    final topTask = activeTasks.first;

    final now = tz.TZDateTime.now(tz.local);
    final scheduledDate = now.add(const Duration(minutes: 5));

    await flutterLocalNotificationsPlugin.zonedSchedule(
      1,
      'Не забывай о главном',
      topTask.title,
      scheduledDate,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'pause_reminder',
          'Напоминание при выходе',
          channelDescription: 'Напоминает о задачах через 5 минут',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  void _scheduleDailyNotification() async {
    final activeTasks = _box.values
        .where((t) => !t.isDeleted && !t.isCompleted && t.parentId == null)
        .toList();

    if (activeTasks.isEmpty) {
      await flutterLocalNotificationsPlugin.cancel(0);
      return;
    }

    activeTasks.sort((a, b) => a.sortIndex.compareTo(b.sortIndex));
    final topTask = activeTasks.first;

    await flutterLocalNotificationsPlugin.cancel(0);

    final now = tz.TZDateTime.now(tz.local);
    var scheduledDate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      9,
      0,
    );

    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    await flutterLocalNotificationsPlugin.zonedSchedule(
      0,
      'Начни день с главного',
      topTask.title,
      scheduledDate,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'daily_top_task',
          'Главная задача',
          channelDescription: 'Утреннее уведомление о верхней задаче',
          importance: Importance.max,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  void _fixOrphans() {
    final allTasks = _box.values;
    final parentIds = allTasks
        .where((t) => t.parentId != null)
        .map((t) => t.parentId)
        .toSet();

    bool changed = false;
    for (var pid in parentIds) {
      final parent = _box.get(pid);
      if (parent != null && !parent.isFolder) {
        parent.isFolder = true;
        parent.save();
        changed = true;
      }
    }
    if (changed) {
      setState(() {});
    }
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

  Future<void> _performUpdate() async {
    // FIX: Wrapped in try-catch to prevent crashes during intent switching
    try {
      _showTopToast("Создание резервной копии...");
      // Await backup to ensure file is written, but don't crash if it fails
      await _backupData(silent: true);

      // Delay to let the Toast render and UI settle before heavy operation
      await Future.delayed(const Duration(seconds: 1));

      _showTopToast("Запуск RuStore...");

      // Try native download
      RustoreUpdateClient.download()
          .then((value) {
            // value != -1 logic from docs, but if it fails silently -> catchError
          })
          .catchError((e) {
            debugPrint("Native update error: $e");
            _launchStoreUrl();
          });
    } catch (e) {
      // Global fallback to ensure app doesn't just die
      debugPrint("Update flow error: $e");
      _launchStoreUrl();
    }
  }

  void _launchStoreUrl() {
    final uri = Uri.parse("https://apps.rustore.ru/app/ru.gorelovra.tdlroman");
    launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _showTopToast(String message) {
    _toastEntry?.remove();

    OverlayEntry? thisEntry;

    thisEntry = OverlayEntry(
      builder: (context) => _ToastWidget(
        message: message,
        onDismiss: () {
          thisEntry?.remove();
          if (_toastEntry == thisEntry) {
            _toastEntry = null;
          }
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

    if (text.contains("TDL ROMAN REPORT") ||
        text.contains("ТАРТАР") ||
        text.contains("ТРИУМФЫ") ||
        text.contains("СПИСОК ДЕЛ")) {
      _showTopToast("Нельзя вставить весь отчет. Скопируйте задачу.");
      return;
    }

    final lines = text.split(RegExp(r'\r?\n'));

    final rootRegex = RegExp(r'^(\d+)\.\s*(.*)');
    final childRegex = RegExp(r'^(\d+)\.(\d+)\.\s*(.*)');

    List<TempTask> roots = [];
    TempTask? currentRoot;
    TempTask? currentChild;

    for (var line in lines) {
      String trimmedLine = line.trim();
      if (trimmedLine.isEmpty) continue;

      final childMatch = childRegex.firstMatch(trimmedLine);
      if (childMatch != null) {
        if (currentRoot == null) continue;
        String rawTitle = childMatch.group(3) ?? "";
        TempTask child = _parseStyle(rawTitle);
        currentRoot.children.add(child);
        currentChild = child;
        continue;
      }

      final rootMatch = rootRegex.firstMatch(trimmedLine);
      if (rootMatch != null) {
        if (roots.isNotEmpty) {
          _showTopToast("Только одну структуру за раз.");
          return;
        }
        String rawTitle = rootMatch.group(2) ?? "";
        TempTask root = _parseStyle(rawTitle);
        root.isFolder = false;
        roots.add(root);
        currentRoot = root;
        currentChild = null;
        continue;
      }

      if (currentChild != null) {
        currentChild.title += "\n$trimmedLine";
        _reparseStyles(currentChild);
      } else if (currentRoot != null) {
        currentRoot.title += "\n$trimmedLine";
        _reparseStyles(currentRoot);
      }
    }

    if (roots.isEmpty) {
      TempTask root = _parseStyle(text.trim());
      roots.add(root);
    }

    if (roots.length > 1) {
      _showTopToast("Можно вставить только одну структуру.");
      return;
    }

    final candidate = roots.first;
    if (candidate.children.isNotEmpty) candidate.isFolder = true;

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

    showSandboxDialog(context, tempRoot: candidate, onImport: _importTask);
  }

  void _scrollToTask(Task target) {
    if (target.parentId != null) {
      if (!_openFolders.contains(target.parentId!)) {
        setState(() {
          _openFolders.add(target.parentId!);
        });
      }
    }

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

  TempTask _parseStyle(String raw) {
    var t = TempTask(title: raw, urgency: 1, importance: 1);
    _reparseStyles(t);
    return t;
  }

  void _reparseStyles(TempTask task) {
    String t = task.title.trim();
    int u = 1;
    int i = 1;

    if (t.startsWith("***") && t.endsWith("***") && t.length >= 6) {
      u = 2;
      i = 2;
      t = t.substring(3, t.length - 3);
    } else if (t.startsWith("**") && t.endsWith("**") && t.length >= 4) {
      i = 2;
      t = t.substring(2, t.length - 2);
    } else if (t.startsWith("*") && t.endsWith("*") && t.length >= 2) {
      u = 2;
      t = t.substring(1, t.length - 1);
    }

    task.title = t.trim();
    task.urgency = u;
    task.importance = i;
  }

  void _importTask(TempTask root) {
    int newIndex;
    if (root.urgency == 2) {
      newIndex = _getTargetIndexForUrgentBottom();
      _shiftIndicesDown(newIndex);
    } else {
      newIndex = _getBottomIndexForActive();
    }

    final rootId = const Uuid().v4();
    final rootTask = Task(
      id: rootId,
      title: root.title,
      createdAt: DateTime.now(),
      urgency: root.urgency,
      importance: root.importance,
      sortIndex: newIndex,
      isFolder: root.isFolder,
      parentId: null,
    );
    _box.put(rootId, rootTask);

    if (root.children.isNotEmpty) {
      int childIndex = _getChildBottomIndex(rootId);

      for (var child in root.children) {
        final childTask = Task(
          id: const Uuid().v4(),
          title: child.title,
          createdAt: DateTime.now(),
          urgency: child.urgency,
          importance: child.importance,
          sortIndex: childIndex++,
          isFolder: false,
          parentId: rootId,
        );
        _box.put(childTask.id, childTask);
      }
    }

    _highlightTaskId = rootId;
    _triggerBlink();
    setState(() {});
    _scheduleDailyNotification();
    _showTopToast("Импортировано!");
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
        if (parent != null && (parent.isDeleted || parent.isCompleted)) {
          continue;
        }
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
        if (parent != null && parent.isDeleted) {
          continue;
        }
      }

      if (task.isCompleted) {
        count++;
      } else {
        if (task.parentId != null) {
          final parent = _box.get(task.parentId);
          if (parent != null && parent.isCompleted && !parent.isDeleted) {
            count++;
          }
        }
      }
    }
    return count;
  }

  int _countDeletedRoots() {
    return _box.values.where((t) => t.isDeleted && t.parentId == null).length;
  }

  void _toggleExpand(String id) {
    HapticFeedback.selectionClick();
    final task = _box.get(id);

    setState(() {
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
        return;
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

  String _formatTaskTitle(Task t) {
    String text = t.title;
    if (t.urgency == 2 && t.importance == 2) {
      return "***$text***";
    } else if (t.importance == 2) {
      return "**$text**";
    } else if (t.urgency == 2) {
      return "*$text*";
    }
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
      if (rootCounter > 1) {
        buffer.writeln("");
      }

      final formattedTitle = _formatTaskTitle(task);
      buffer.writeln("$rootCounter. $formattedTitle");

      if (task.isFolder) {
        final children = _box.values
            .where((t) => t.parentId == task.id && childFilter(t))
            .toList();

        children.sort((a, b) {
          if (a.urgency != b.urgency) return b.urgency.compareTo(a.urgency);
          return a.sortIndex.compareTo(b.sortIndex);
        });

        int childCounter = 1;
        for (var child in children) {
          final childTitle = _formatTaskTitle(child);
          buffer.writeln("    $rootCounter.$childCounter. $childTitle");
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
      text = "🏛 **ТАРТАР (Удаленные)**\n\n";
      text += _generateMarkdownList(
        rootFilter: (t) => t.isDeleted && t.parentId == null,
        childFilter: (t) => t.isDeleted,
      );
    } else if (tabIndex == 1) {
      text = "🏛 **СПИСОК ДЕЛ**\n\n";
      text += _generateMarkdownList(
        rootFilter: (t) => !t.isDeleted && !t.isCompleted && t.parentId == null,
        childFilter: (t) => !t.isDeleted && !t.isCompleted,
      );
    } else {
      text = "🏛 **ТРИУМФЫ (Выполнено)**\n\n";
      text += _generateMarkdownList(
        rootFilter: (t) => t.isCompleted && !t.isDeleted && t.parentId == null,
        childFilter: (t) => t.isCompleted && !t.isDeleted,
      );
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
    final formattedTitle = _formatTaskTitle(rootTask);
    buffer.writeln("1. $formattedTitle");

    if (rootTask.isFolder) {
      bool Function(Task) childFilter;

      if (!rootTask.isDeleted && !rootTask.isCompleted) {
        childFilter = (t) => !t.isDeleted && !t.isCompleted;
      } else {
        childFilter = (t) => !t.isDeleted;
      }

      final children = _box.values
          .where((t) => t.parentId == rootTask.id && childFilter(t))
          .toList();

      children.sort((a, b) {
        if (a.urgency != b.urgency) return b.urgency.compareTo(a.urgency);
        return a.sortIndex.compareTo(b.sortIndex);
      });

      int childCounter = 1;
      for (var child in children) {
        final childTitle = _formatTaskTitle(child);
        buffer.writeln("    1.$childCounter. $childTitle");
        childCounter++;
      }
    }

    Clipboard.setData(ClipboardData(text: buffer.toString()));
    _showTopToast("Задача скопирована!");
  }

  Future<void> _backupData({bool silent = false}) async {
    try {
      final tasks = _box.values.map((e) => e.toJson()).toList();
      final jsonString = jsonEncode({'tasks': tasks});

      final directory = await getApplicationDocumentsDirectory();
      final backupDir = Directory('${directory.path}/backups');
      if (!backupDir.existsSync()) {
        backupDir.createSync();
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final file = File('${backupDir.path}/tdl_backup_$timestamp.json');
      await file.writeAsString(jsonString);

      final files = backupDir.listSync()
        ..sort(
          (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
        );

      if (files.length > 10) {
        for (var i = 10; i < files.length; i++) {
          files[i].deleteSync();
        }
      }

      if (!silent) {
        await Share.shareXFiles([XFile(file.path)], text: 'TDL-Roman Backup');
      }
    } catch (e) {
      if (!silent) _showTopToast("Ошибка бэкапа: $e");
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
                  if (tabIndex == 1)
                    _buildCopyActionButton("ВСТАВИТЬ", Icons.paste, () {
                      Navigator.pop(ctx);
                      _handlePasteFromClipboard();
                    }),
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

  void _showItemContextMenu(Task task) {
    setState(() {
      _menuOpenTaskId = task.id;
    });

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
      if (mounted) {
        setState(() {
          _menuOpenTaskId = null;
        });
      }
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

  void _saveNewTask(
    String title,
    int urgency,
    int importance,
    int positionMode,
    bool isFolder,
    String? parentId,
  ) {
    if (urgency == 2 && positionMode == 1) {
      positionMode = 2;
    }

    int newIndex;
    if (parentId != null) {
      String pid = parentId;
      if (urgency == 2) {
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
    }

    final newTask = Task(
      id: const Uuid().v4(),
      title: title,
      createdAt: DateTime.now(),
      urgency: urgency,
      importance: importance,
      sortIndex: newIndex,
      isFolder: isFolder,
      parentId: parentId,
    );
    _box.put(newTask.id, newTask);

    _highlightTaskId = newTask.id;
    _scheduleDailyNotification();

    setState(() {});
  }

  void _updateTaskAndMove(
    Task task,
    int urgency,
    int importance,
    int positionMode,
  ) {
    if (urgency == 2 && positionMode == 1) {
      positionMode = 2;
    }

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
    _scheduleDailyNotification();
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
    _scheduleDailyNotification();
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
    _scheduleDailyNotification();
    setState(() {});
  }

  void _moveToTrash(Task task) {
    task.isDeleted = true;
    task.isCompleted = false;
    task.parentId = null;
    task.sortIndex = _getTopIndexForState(deleted: true);

    _highlightTaskId = task.id;
    task.save();
    _scheduleDailyNotification();
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
    _scheduleDailyNotification();
    setState(() {});
  }

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
                    if (_openFolders.isNotEmpty) {
                      targetFolderId = _openFolders.first;
                    }
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
        if (_highlightTaskId == task.id) {
          _highlightTaskId = null;
        }
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

  void _showTaskDialogWrapped({Task? task, String? parentId}) {
    showTaskDialog(
      context,
      task: task,
      parentId: parentId,
      box: _box,
      onToast: _showTopToast,
      onSaveNew: _saveNewTask,
      onUpdate: _updateTaskAndMove,
    );
  }

  BoxDecoration _getTaskDecoration(Task task, int tabIndex) {
    BoxShadow? basicShadow = const BoxShadow(
      color: Colors.black12,
      blurRadius: 3,
      offset: Offset(0, 2),
    );

    if (tabIndex == 0) {
      // Deleted
      return BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(8),
        boxShadow: [basicShadow],
      );
    }

    if (tabIndex == 1) {
      // Active
      // FIX: If it is a folder in Tab 1, we want a stronger look but not stack
      if (task.isFolder) {
        return BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.black87, width: 2), // Visible Border
          boxShadow: [basicShadow],
        );
      }
      return BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [basicShadow],
      );
    }

    if (tabIndex == 2) {
      // Triumph
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
    if (isSelected) {
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
    }

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
      if (tabIndex == 0) {
        icon = Icons.close;
      } else if (tabIndex == 2) {
        icon = Icons.check;
      } else {
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
      if (mounted) {
        setState(() {
          _isVisible = false;
        });
      }
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
