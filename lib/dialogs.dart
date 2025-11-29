import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'widgets.dart';

void showTaskDialog(
  BuildContext context, {
  Task? task,
  String? parentId,
  required Box<Task> box,
  required Function(String msg) onToast,
  required Function(
    String title,
    int urgency,
    int importance,
    int positionMode,
    bool isFolder,
    String? parentId,
  )
  onSaveNew,
  required Function(Task task, int urgency, int importance, int positionMode)
  onUpdate,
  Function(String id)? onDuplicateFound,
  Function()? onDuplicateClear,
}) {
  final titleController = TextEditingController(text: task?.title ?? '');
  int urgency = task?.urgency ?? 1;
  int importance = task?.importance ?? 1;
  int positionMode = task == null ? 2 : 1;
  bool isFolder = task?.isFolder ?? false;
  bool attentionTop = false;
  int blinkStage = 0;
  Timer? attentionTimer;

  if (parentId != null) isFolder = false;

  bool hasChildren = false;
  if (task != null) {
    hasChildren = box.values.any((t) => t.parentId == task.id && !t.isDeleted);
  }

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      final double dialogHeight = MediaQuery.of(context).size.height * 0.72;
      return StatefulBuilder(
        builder: (context, setDialogState) {
          bool isDuplicateWarning = false;

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
            attentionTimer = Timer.periodic(const Duration(milliseconds: 200), (
              timer,
            ) {
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
            });
          }

          void checkAndSave({bool force = false}) {
            final text = titleController.text.trim();
            if (text.isEmpty) return;

            if (!force && task == null) {
              final duplicate = box.values.cast<Task?>().firstWhere(
                (t) =>
                    t != null &&
                    t.title.trim().toLowerCase() == text.toLowerCase() &&
                    !t.isDeleted &&
                    !t.isCompleted &&
                    t.parentId == parentId,
                orElse: () => null,
              );

              if (duplicate != null) {
                setDialogState(() {
                  isDuplicateWarning = true;
                });

                // Found *a* duplicate, but main.dart will find ALL and scroll
                // We return just to trigger the warning state in Dialog
                // Main logic handles the highlighting of all items via _duplicateIds
                return;
              }
            }

            attentionTimer?.cancel();
            if (task == null) {
              onSaveNew(
                titleController.text,
                urgency,
                importance,
                positionMode,
                isFolder,
                parentId,
              );
            } else {
              task.title = titleController.text;
              task.isFolder = isFolder;
              onUpdate(task, urgency, importance, positionMode);
            }
            onDuplicateClear?.call();
            Navigator.pop(ctx);
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
                            onChanged: (_) {
                              if (isDuplicateWarning) {
                                setDialogState(() {
                                  isDuplicateWarning = false;
                                });
                                onDuplicateClear?.call();
                              }
                            },
                          ),
                        ),
                      ),
                    ),

                    // 1.3 Fix: Message is now part of the Column flow, preventing overlap
                    if (isDuplicateWarning)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            border: Border.all(color: Colors.red.shade200),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.warning_amber_rounded,
                                color: Colors.red,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  "Дубликат! Создать копию?",
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.red,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: () {
                                  setDialogState(() {
                                    isDuplicateWarning = false;
                                  });
                                  onDuplicateClear?.call();
                                },
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  minimumSize: const Size(50, 30),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: const Text(
                                  "Отмена",
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              TextButton(
                                onPressed: () => checkAndSave(force: true),
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  minimumSize: const Size(50, 30),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: const Text(
                                  "Да",
                                  style: TextStyle(
                                    color: Colors.red,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
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
                                    if ((task == null ||
                                            task.parentId == null) &&
                                        parentId == null)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          right: 20,
                                        ),
                                        child: _buildDialogFolderButton(
                                          isFolder,
                                          hasChildren,
                                          () {
                                            if (hasChildren) {
                                              onToast("Сначала очистите папку");
                                              return;
                                            }
                                            setDialogState(
                                              () => isFolder = !isFolder,
                                            );
                                          },
                                        ),
                                      ),
                                    _buildDialogStateButton(
                                      Icons.bolt,
                                      "Срочно",
                                      urgency == 2,
                                      Colors.indigo[900]!,
                                      () {
                                        setDialogState(() {
                                          urgency = (urgency == 1 ? 2 : 1);
                                          if (urgency == 2) triggerAttention();
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
                                        onDuplicateClear?.call();
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
                                          onToast("Текст скопирован");
                                        }
                                      },
                                    ),
                                    _buildSquareButtonWithLabel(
                                      label: "OK",
                                      icon: Icons.check,
                                      color: Colors.black,
                                      size: 50,
                                      onTap: () => checkAndSave(),
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

void showSandboxDialog(
  BuildContext context, {
  required TempTask tempRoot,
  required Function(TempTask root) onImport,
}) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      return AlertDialog(
        backgroundColor: Colors.white,
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSandboxItem(tempRoot, isRoot: true),
                if (tempRoot.children.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 16.0, top: 8),
                    child: Column(
                      children: tempRoot.children
                          .map((c) => _buildSandboxItem(c, isRoot: false))
                          .toList(),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Отмена", style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              onImport(tempRoot);
            },
            child: const Text(
              "Импорт",
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      );
    },
  );
}

Widget _buildDialogFolderButton(
  bool isFolder,
  bool isLocked,
  VoidCallback onTap,
) {
  return GestureDetector(
    onTap: () {
      HapticFeedback.lightImpact();
      onTap();
    },
    child: Column(
      children: [
        Container(
          width: 45,
          height: 45,
          alignment: Alignment.center,
          child: SizedBox(
            width: 26,
            height: 26,
            child: Stack(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: isFolder ? Colors.black : Colors.transparent,
                    border: Border.all(
                      color: isFolder
                          ? Colors.black
                          : Colors.grey.withOpacity(0.5),
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: isFolder
                        ? [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              offset: const Offset(0, 4),
                              blurRadius: 0,
                              spreadRadius: -2,
                            ),
                          ]
                        : [],
                  ),
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  child: Container(
                    width: 11,
                    height: 7,
                    decoration: BoxDecoration(
                      color: isFolder
                          ? Colors.black
                          : Colors.grey.withOpacity(0.5),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(3),
                        bottomRight: Radius.circular(3),
                      ),
                    ),
                  ),
                ),
                if (isFolder)
                  const Center(
                    child: Icon(Icons.check, size: 18, color: Colors.white),
                  ),
                if (isLocked)
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.lock,
                        size: 14,
                        color: Colors.black,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          "Папка",
          style: TextStyle(
            fontSize: 10,
            color: isFolder ? Colors.black : Colors.grey,
            fontWeight: isFolder ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    ),
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
      borderColor = Colors.indigo[900]!;
      iconColor = Colors.indigo[900]!;
      bgColor = Colors.indigo.withOpacity(0.1);
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

Widget _buildSandboxItem(TempTask task, {required bool isRoot}) {
  Color color = Colors.black87;
  FontWeight fw = FontWeight.normal;

  if (task.urgency == 2) color = const Color(0xFF1A237E);
  if (task.importance == 2) fw = FontWeight.bold;

  return Container(
    margin: const EdgeInsets.symmetric(vertical: 4),
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      border: Border.all(color: Colors.grey.withOpacity(0.3)),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      children: [
        if (isRoot && task.isFolder)
          const Padding(
            padding: EdgeInsets.only(right: 8),
            child: Icon(Icons.folder_outlined, size: 20),
          ),
        Expanded(
          child: Text(
            task.title,
            style: TextStyle(color: color, fontWeight: fw, fontSize: 16),
          ),
        ),
        if (task.urgency == 2)
          const Padding(
            padding: EdgeInsets.only(left: 4),
            child: Icon(Icons.bolt, size: 16, color: Color(0xFF1A237E)),
          ),
        if (task.importance == 2)
          const Padding(
            padding: EdgeInsets.only(left: 4),
            child: Icon(Icons.priority_high, size: 16, color: Colors.orange),
          ),
      ],
    ),
  );
}
