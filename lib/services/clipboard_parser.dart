import '../widgets.dart';

class ClipboardParser {
  /// Разбирает текст из буфера обмена и возвращает список корневых задач (обычно одну).
  /// Если структура некорректна или пуста, возвращает пустой список.
  static List<TempTask> parse(String text) {
    if (text.trim().isEmpty) return [];

    final lines = text.split(RegExp(r'\r?\n'));
    final rootRegex = RegExp(r'^(\d+)\.\s*(.*)');
    final childRegex = RegExp(r'^(\d+)\.(\d+)\.\s*(.*)');

    List<TempTask> roots = [];
    TempTask? currentRoot;
    TempTask? currentChild;

    for (var line in lines) {
      String trimmedLine = line.trim();
      if (trimmedLine.isEmpty) continue;

      // 1. Проверяем, это подзадача?
      final childMatch = childRegex.firstMatch(trimmedLine);
      if (childMatch != null) {
        if (currentRoot == null) continue; // Подзадача без родителя - игнор
        String rawTitle = childMatch.group(3) ?? "";
        TempTask child = _parseStyle(rawTitle);
        currentRoot.children.add(child);
        currentChild = child;
        continue;
      }

      // 2. Проверяем, это корень?
      final rootMatch = rootRegex.firstMatch(trimmedLine);
      if (rootMatch != null) {
        // Если уже есть корни, это сигнал (в текущей логике мы разрешаем только 1 структуру,
        // но парсер может вернуть все, а UI решит что делать)
        String rawTitle = rootMatch.group(2) ?? "";
        TempTask root = _parseStyle(rawTitle);
        root.isFolder = false; // По дефолту false, станет true если будут дети
        roots.add(root);
        currentRoot = root;
        currentChild = null;
        continue;
      }

      // 3. Это продолжение текста (multiline)
      if (currentChild != null) {
        currentChild.title += "\n$trimmedLine";
        _reparseStyles(currentChild);
      } else if (currentRoot != null) {
        currentRoot.title += "\n$trimmedLine";
        _reparseStyles(currentRoot);
      }
    }

    // Фоллбэк: если регулярки не сработали, считаем весь текст одной задачей
    if (roots.isEmpty && text.trim().isNotEmpty) {
      TempTask root = _parseStyle(text.trim());
      roots.add(root);
    }

    // Пост-обработка: если у корня появились дети, он становится папкой
    for (var root in roots) {
      if (root.children.isNotEmpty) root.isFolder = true;
    }

    return roots;
  }

  static TempTask _parseStyle(String raw) {
    var t = TempTask(title: raw, urgency: 1, importance: 1);
    _reparseStyles(t);
    return t;
  }

  static void _reparseStyles(TempTask task) {
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
}
