REM .\backup.bat
@echo off
chcp 65001 >nul
echo.
echo --- ЗАПУСК РЕЗЕРВНОГО КОПИРОВАНИЯ ---

:: 1. Настройка путей
set "DEST=C:\_YandexDisk\YandexDisk\_FTP\_sohrany\tdl_roman"
set "KEY_PROP=android\key.properties"
set "KEY_STORE=android\app\upload-keystore.jks"
set "APK_FILE=build\app\outputs\flutter-apk\app-release.apk"

:: 2. Создание папки в облаке, если её нет
if not exist "%DEST%" (
    echo [+] Создаю папку в Яндекс.Диске...
    mkdir "%DEST%"
)

:: 3. Копирование key.properties
if exist "%KEY_PROP%" (
    copy /Y "%KEY_PROP%" "%DEST%\" >nul
    echo [OK] Файл key.properties сохранен.
) else (
    echo [!] ОШИБКА: Файл key.properties не найден!
)

:: 4. Копирование ключа .jks
if exist "%KEY_STORE%" (
    copy /Y "%KEY_STORE%" "%DEST%\" >nul
    echo [OK] Файл upload-keystore.jks сохранен.
) else (
    echo [!] ОШИБКА: Ключ upload-keystore.jks не найден!
)

:: 5. (Бонус) Копирование готового APK (если он есть)
if exist "%APK_FILE%" (
    copy /Y "%APK_FILE%" "%DEST%\" >nul
    echo [OK] Последний APK-файл сохранен.
) else (
    echo [-] APK файл не найден (возможно, еще не было сборки).
)

echo.
echo --- КОПИРОВАНИЕ ЗАВЕРШЕНО ---
echo Файлы лежат тут: %DEST%