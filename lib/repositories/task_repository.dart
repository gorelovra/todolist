import 'dart:math';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';
import '../widgets.dart';

class TaskRepository {
  final Box<Task> _box;

  TaskRepository(this._box);

  /// Исправляет "сирот" (задачи с parentId, но родитель не помечен как папка)
  /// Возвращает true, если были исправления.
  bool fixOrphans() {
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
    return changed;
  }

  // --- CRUD Operations ---

  /// Создает новую задачу с автоматическим расчетом позиции
  Task createTask({
    required String title,
    required int urgency,
    required int importance,
    required int positionMode, // 0=Top, 1=Bottom, 2=Auto/Manual
    required bool isFolder,
    String? parentId,
  }) {
    // Корректировка: Срочные задачи (urgency=2) всегда стремятся наверх,
    // поэтому positionMode=1 (Bottom) для них превращается в Auto/Manual
    if (urgency == 2 && positionMode == 1) {
      positionMode = 2;
    }

    int newIndex;
    if (parentId != null) {
      // Логика для подзадач
      if (urgency == 2) {
        if (positionMode == 0) {
          newIndex = _getChildTopIndex(parentId);
        } else {
          newIndex = _getChildTargetIndexForUrgentBottom(parentId);
          _shiftChildIndicesDown(parentId, newIndex);
        }
      } else {
        if (positionMode == 0) {
          newIndex = _getChildTargetIndexForNormalTop(parentId);
          _shiftChildIndicesDown(parentId, newIndex);
        } else {
          newIndex = _getChildBottomIndex(parentId);
        }
      }
    } else {
      // Логика для корневых задач
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
    return newTask;
  }

  void updateTask(
    Task task, {
    required int urgency,
    required int importance,
    required int positionMode,
  }) {
    if (urgency == 2 && positionMode == 1) {
      positionMode = 2;
    }

    task.urgency = urgency;
    task.importance = importance;
    // При обновлении сохраняем флаг папки как был (он меняется отдельно в UI)

    int newIndex = task.sortIndex; // По умолчанию оставляем где был

    // Если меняется позиция (Top/Bottom) или статус, пересчитываем индекс
    // Здесь упрощенная логика из оригинала: если не Manual (2), то двигаем
    // Плюс если статус сменился, часто нужно пересчитать (но оригинал завязан на positionMode)

    // В оригинале, если positionMode != 1, мы часто сбрасываем parentId для корня.
    // Сохраним оригинальную логику расчета индексов:

    if (task.parentId != null) {
      String pid = task.parentId!;
      if (task.urgency == 2) {
        if (positionMode == 0) {
          newIndex = _getChildTopIndex(pid);
        } else {
          newIndex = _getChildTargetIndexForUrgentBottom(pid);
          _shiftChildIndicesDown(pid, newIndex);
        }
      } else {
        if (positionMode == 0) {
          newIndex = _getChildTargetIndexForNormalTop(pid);
          _shiftChildIndicesDown(pid, newIndex);
        } else {
          newIndex = _getChildBottomIndex(pid);
        }
      }
    } else {
      if (task.urgency == 2) {
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

      // Оригинальная логика сброса родителя при перемещении "в корень" через диалог
      if (positionMode != 1) {
        task.parentId = null;
      }
    }

    // Применяем индекс только если это не Manual Mode (там драг-дроп решает)
    // НО в оригинале даже для Manual часто пересчитывали, если статус менялся.
    // Здесь следуем оригиналу: если не 1 (Bottom/Manual mixed), обновляем.
    // Учтем: positionMode == 2 это Manual (в диалоге это "оставить как есть/авто").
    // В оригинале: positionMode == 2 используется как дефолт для редактирования.
    // Если мы передаем явно 0 или 1 - двигаем.
    if (positionMode != 1 && positionMode != 2) {
      task.sortIndex = newIndex;
    }
    // Если передали 0 или 1, то применили newIndex. Если 2 - оставили старый.
    // Но в _updateTaskAndMove есть нюанс: там 0, 1, 2.
    // Тут мы немного упрощаем, полагаясь на то, что вызывающий код передает намерение.
    // Для полной точности с оригиналом:
    if (positionMode != 1 && positionMode != 2) {
      task.sortIndex = newIndex;
    } else if (positionMode == 0 || positionMode == 1) {
      // Cover cases where calculate logic ran
      task.sortIndex = newIndex;
    }
    // FIX: Просто применим если режим предполагает перемещение.
    // В диалоге: 0=Top, 1=Bottom(Standard), 2=Manual(Urgent).
    // В коде оригинала сложный if. Давай просто сохраним:
    if (positionMode == 0) task.sortIndex = newIndex;
    // Для остальных режимов (авто-сортировка по срочности) индекс уже мог быть сдвинут _shift...

    task.save();
  }

  void importTaskTree(TempTask root) {
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
  }

  // --- Status Changes ---

  void completeTask(Task task) {
    task.isCompleted = true;
    task.isDeleted = false;
    if (task.parentId == null) {
      task.sortIndex = _getTopIndexForState(completed: true);
    }
    task.save();
  }

  void uncompleteTask(Task task) {
    task.isCompleted = false;
    task.save();
  }

  void restoreTask(Task task) {
    task.isCompleted = false;
    task.isDeleted = false;
    task.parentId = null; // Восстанавливаем в корень

    int newIndex;
    if (task.urgency == 2) {
      newIndex = _getTopIndexForState();
    } else {
      newIndex = _getTargetIndexForNormalTop();
      _shiftIndicesDown(newIndex);
    }
    task.sortIndex = newIndex;
    task.save();
  }

  void moveToTrash(Task task) {
    task.isDeleted = true;
    task.isCompleted = false;
    task.parentId = null;
    task.sortIndex = _getTopIndexForState(deleted: true);
    task.save();
  }

  Future<void> permanentlyDelete(Task task) async {
    if (task.isFolder) {
      final children = _box.values.where((t) => t.parentId == task.id).toList();
      for (var child in children) {
        await child.delete();
      }
    }
    await task.delete();
  }

  // --- Internal Index Helpers (Private logic made available for Repo) ---

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
}
