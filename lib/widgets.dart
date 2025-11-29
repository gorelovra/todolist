import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:visibility_detector/visibility_detector.dart';

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

class TempTask {
  String title;
  int urgency;
  int importance;
  bool isFolder;
  List<TempTask> children;

  TempTask({
    required this.title,
    this.urgency = 1,
    this.importance = 1,
    this.isFolder = false,
  }) : children = [];
}

class TdlRomanApp extends StatelessWidget {
  final Widget home;
  const TdlRomanApp({super.key, required this.home});

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
      home: SplashScreen(nextScreen: home),
    );
  }
}

class SplashScreen extends StatefulWidget {
  final Widget nextScreen;
  const SplashScreen({super.key, required this.nextScreen});

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
        MaterialPageRoute(builder: (context) => widget.nextScreen),
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

class TaskItemWidget extends StatefulWidget {
  final Task task;
  final int index;
  final bool isExpanded;
  final bool isSelected;
  final bool showCup;
  final bool shouldBlink;
  final bool isFolderOpen;
  final bool isMenuOpen;
  final bool isDuplicate;
  final int tabIndex;
  final VoidCallback onBlinkFinished;
  final VoidCallback onToggleExpand;
  final VoidCallback onToggleSelection;
  final VoidCallback onMenuTap;
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
    this.isMenuOpen = false,
    this.isDuplicate = false,
    required this.tabIndex,
    required this.onBlinkFinished,
    required this.onToggleExpand,
    required this.onToggleSelection,
    required this.onMenuTap,
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
        if (widget.task.urgency == 2) textColor = const Color(0xFF1A237E);
        if (widget.task.importance == 2) fontWeight = FontWeight.bold;
      }
    }

    BoxDecoration decoration = widget.decorationBuilder(widget.task);

    if (widget.isMenuOpen) {
      Color menuHighlight;
      if (widget.tabIndex == 2) {
        menuHighlight = Colors.white24;
      } else {
        menuHighlight = Colors.grey.shade300;
      }

      if (decoration.gradient == null) {
        decoration = decoration.copyWith(color: menuHighlight);
      } else {
        decoration = decoration.copyWith(
          border: Border.all(color: Colors.white.withOpacity(0.5), width: 2),
        );
      }
    }

    Color borderColor = Colors.transparent;

    // Priority: Blinking (Highest) > Duplicate (Static)
    if (_isHighlighed) {
      borderColor = Colors.red;
    } else if (widget.isDuplicate) {
      borderColor = Colors.red;
    }

    // Always add 3px border to prevent Jitter
    bool hasCustomFolderBorder = widget.task.isFolder && widget.tabIndex != 2;

    if (_isHighlighed) {
      // Force red thick border if blinking
      decoration = decoration.copyWith(
        border: Border.all(color: Colors.red, width: 3),
      );
    } else if (!hasCustomFolderBorder) {
      decoration = decoration.copyWith(
        border: Border.all(color: borderColor, width: 3),
      );
    } else {
      // For light folders, override only if necessary (dup)
      if (borderColor != Colors.transparent) {
        decoration = decoration.copyWith(
          border: Border.all(color: borderColor, width: 3),
        );
      }
    }

    EdgeInsets margin = const EdgeInsets.symmetric(vertical: 4, horizontal: 16);
    if (widget.task.parentId != null) {
      margin = const EdgeInsets.fromLTRB(48, 4, 16, 4);
    }

    VoidCallback onTap = widget.task.isFolder
        ? widget.onFolderTap
        : widget.onToggleExpand;

    Widget content = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left click area (Indicator)
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: widget.onToggleSelection,
              child: Container(
                width: 50,
                padding: const EdgeInsets.only(left: 8),
                alignment: Alignment.centerLeft,
                color: Colors.transparent, // Hitbox
                child: widget.indicatorBuilder(widget.task, widget.isSelected),
              ),
            ),

            // Minimal spacer
            const SizedBox(width: 8),

            // Center Text
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 4, left: 0),
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
            ),

            // Right click area (Menu/Cup)
            Container(
              width: 50,
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (widget.showCup)
                    const Padding(
                      padding: EdgeInsets.only(right: 4),
                      child: Icon(
                        Icons.emoji_events,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),

                  GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: widget.onMenuTap,
                    child: Container(
                      width: 30, // Icon hitbox
                      height: 30,
                      color: Colors.transparent,
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.more_vert,
                        color: widget.tabIndex == 2
                            ? Colors.white54
                            : Colors.grey[400],
                        size: 24,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    Widget mainContainer = Container(
      margin: margin,
      decoration: decoration,
      child: content,
    );

    if (widget.task.isFolder) {
      BoxDecoration backLayerDeco;

      if (widget.tabIndex == 2) {
        backLayerDeco = decoration.copyWith(
          color: decoration.color?.withOpacity(0.6),
          boxShadow: [],
          gradient: null,
        );
        if (decoration.gradient != null) {
          backLayerDeco = backLayerDeco.copyWith(
            color: const Color(0xFFBF953F).withOpacity(0.5),
          );
        }
      } else {
        Color layerColor = (widget.tabIndex == 1)
            ? Colors.grey.shade300
            : Colors.grey.shade400;

        backLayerDeco = BoxDecoration(
          color: layerColor,
          borderRadius: BorderRadius.circular(8),
        );
      }

      BoxDecoration topLayerDeco = decoration;
      if (widget.tabIndex != 2) {
        // Only apply grey border if NOT highlighting (Red)
        if (borderColor == Colors.transparent) {
          topLayerDeco = topLayerDeco.copyWith(
            color: (widget.tabIndex == 1)
                ? const Color(0xFFF5F5F5)
                : Colors.grey[300],
            border: Border.all(
              color: (widget.tabIndex == 1)
                  ? Colors.grey.shade400
                  : Colors.grey.shade600,
              width: 1,
            ),
          );
        } else {
          // Highlight active (Red border already on mainContainer, just bg here)
          topLayerDeco = topLayerDeco.copyWith(
            color: (widget.tabIndex == 1)
                ? const Color(0xFFF5F5F5)
                : Colors.grey[300],
          );
        }

        mainContainer = Container(
          margin: margin,
          decoration: topLayerDeco,
          child: content,
        );
      }

      mainContainer = Container(
        margin: margin,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              top: 4,
              left: 0,
              right: 0,
              bottom: -4,
              child: Container(
                decoration: backLayerDeco.copyWith(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            Positioned(
              top: 2,
              left: 0,
              right: 0,
              bottom: -2,
              child: Container(
                decoration: backLayerDeco.copyWith(
                  color: (widget.tabIndex == 2)
                      ? backLayerDeco.color?.withOpacity(0.8)
                      : backLayerDeco.color,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            Container(decoration: topLayerDeco, child: content),
          ],
        ),
      );
    }

    return VisibilityDetector(
      key: widget.key ?? Key(widget.task.id),
      onVisibilityChanged: (info) {
        if (info.visibleFraction > 0.5 && widget.shouldBlink && !_hasBlinked) {
          _startBlinking();
        }
      },
      child: mainContainer,
    );
  }
}
