import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_rustore_update/flutter_rustore_update.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../widgets.dart';

class UpdateService {
  /// Проверяет наличие обновлений. Возвращает true, если обновление доступно (availability == 2).
  Future<bool> checkUpdateAvailable() async {
    try {
      final info = await RustoreUpdateClient.info();
      return info.updateAvailability == 2;
    } catch (e) {
      debugPrint("Ошибка проверки обновлений: $e");
      return false;
    }
  }

  /// Запускает процесс обновления (бэкап -> скачивание -> установка).
  /// Возвращает Stream или Future, но для простоты здесь выполняет действия.
  /// [onBackupStarted] и [onDownloadStarted] - колбэки для уведомления UI.
  Future<void> performUpdate(
    Box<Task> box, {
    required Function(String msg) onStatusChange,
  }) async {
    try {
      onStatusChange("Создание резервной копии...");
      // Делаем тихий бэкап перед обновлением
      await createBackup(box, silent: true);

      // Небольшая задержка для UI
      await Future.delayed(const Duration(seconds: 1));

      onStatusChange("Запуск RuStore...");

      // Пытаемся скачать нативно
      await RustoreUpdateClient.download()
          .then((value) {
            // Logic for success/fail codes if needed
          })
          .catchError((e) {
            debugPrint("Native update error: $e");
            _launchStoreUrl();
          });
    } catch (e) {
      debugPrint("Update flow error: $e");
      _launchStoreUrl();
    }
  }

  void _launchStoreUrl() {
    final uri = Uri.parse("https://apps.rustore.ru/app/ru.gorelovra.tdlroman");
    launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// Создает JSON бэкап и (опционально) открывает диалог шаринга.
  Future<void> createBackup(Box<Task> box, {bool silent = false}) async {
    try {
      final tasks = box.values.map((e) => e.toJson()).toList();
      final jsonString = jsonEncode({'tasks': tasks});

      final directory = await getApplicationDocumentsDirectory();
      final backupDir = Directory('${directory.path}/backups');
      if (!backupDir.existsSync()) {
        backupDir.createSync();
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final file = File('${backupDir.path}/tdl_backup_$timestamp.json');
      await file.writeAsString(jsonString);

      // Очистка старых бэкапов (оставляем последние 10)
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
      if (!silent) rethrow;
    }
  }
}
