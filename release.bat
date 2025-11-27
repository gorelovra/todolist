@echo off
chcp 65001 >nul
cls

set "SOUND_SUCCESS=C:\Windows\Media\tada.wav"
set "SOUND_ERROR=C:\Windows\Media\Windows Critical Stop.wav"

echo ==========================================
echo      АВТОМАТИЧЕСКАЯ СБОРКА TDL-ROMAN
echo ==========================================
echo.

echo [PRE-CHECK] Копирование _vajno.md...
copy /Y "C:\_my\android\_vajno.md" ".\_vajno.md" >nul
if %errorlevel% neq 0 (
    echo [!] КРИТИЧЕСКАЯ ОШИБКА: Не удалось скопировать C:\_my\android\_vajno.md
    goto error
)
echo [OK] Файл _vajno.md скопирован.
echo.

echo [0/5] Поднятие версии (Patch + Build)...
(
echo $path = "pubspec.yaml"
echo $content = Get-Content $path -Raw
echo $pattern = "version: (\d+\.\d+)\.(\d+)\+(\d+)"
echo if ^($content -match $pattern^) {
echo     $majorMinor = $matches[1]
echo     $patch = [int]$matches[2] + 1
echo     $build = [int]$matches[3] + 1
echo     $newVersion = "version: $majorMinor.$patch+$build"
echo     $content = $content -replace $pattern, $newVersion
echo     Set-Content $path $content -NoNewline
echo     Write-Host "SUCCESS: New version is $majorMinor.$patch+$build" -ForegroundColor Green
echo } else {
echo     Write-Error "ERROR: Version string format X.Y.Z+B not found in pubspec.yaml"
echo     exit 1
echo }
) > update_version.ps1

powershell -ExecutionPolicy Bypass -File update_version.ps1
if %errorlevel% neq 0 (
    echo [!] Ошибка скрипта обновления версии.
    del update_version.ps1
    goto error
)
del update_version.ps1

echo.
echo [1/5] Принудительная остановка Java и очистка (flutter clean)...
taskkill /F /IM java.exe /T 2>nul
timeout /t 1 /nobreak >nul
call flutter clean
if %errorlevel% neq 0 goto error

echo.
echo [2/5] Загрузка библиотек (flutter pub get)...
call flutter pub get
if %errorlevel% neq 0 goto error

echo.
echo [3/5] Проверка логотипа...
set "CLOUD_ICON=C:\_YandexDisk\YandexDisk\_FTP\_sohrany\tdl_roman\512.png"
set "LOCAL_ICON=assets\icon.png"

if exist "%CLOUD_ICON%" (
    echo [!] Найден логотип в облаке. Копируем и генерируем иконки...
    copy /Y "%CLOUD_ICON%" "%LOCAL_ICON%" >nul
    call flutter pub run flutter_launcher_icons
) else (
    echo [i] Облачный логотип не найден, используем текущий.
)

echo.
echo [4/5] Сборка Release APK...
call flutter build apk --release
if %errorlevel% neq 0 goto error

echo.
echo [5/5] Запуск резервного копирования...

set "DEST=C:\_YandexDisk\YandexDisk\_FTP\_sohrany\tdl_roman"
set "KEY_PROP=android\key.properties"
set "KEY_STORE=android\app\upload-keystore.jks"
set "APK_FILE=build\app\outputs\flutter-apk\app-release.apk"

if not exist "%DEST%" (
    echo [+] Создаю папку в Яндекс.Диске...
    mkdir "%DEST%"
)

if exist "%KEY_PROP%" (
    copy /Y "%KEY_PROP%" "%DEST%\" >nul
    echo [OK] key.properties сохранен.
) else (
    echo [!] ОШИБКА: key.properties не найден!
)

if exist "%KEY_STORE%" (
    copy /Y "%KEY_STORE%" "%DEST%\" >nul
    echo [OK] upload-keystore.jks сохранен.
) else (
    echo [!] ОШИБКА: upload-keystore.jks не найден!
)

if exist "%APK_FILE%" (
    copy /Y "%APK_FILE%" "%DEST%\" >nul
    echo [OK] APK файл успешно скопирован.
) else (
    echo [!] ОШИБКА: APK файл не найден!
    goto error
)

echo.
echo ==========================================
echo      УСПЕХ! ВЕРСИЯ ПОДНЯТА, ИКОНКИ ПРОВЕРЕНЫ, СОБРАНО, СОХРАНЕНО
echo ==========================================

powershell -c "(New-Object Media.SoundPlayer '%SOUND_SUCCESS%').PlaySync();"
pause
exit /b 0

:error
echo.
echo !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
echo        ПРОИЗОШЛА ОШИБКА
echo !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
powershell -c "(New-Object Media.SoundPlayer '%SOUND_ERROR%').PlaySync();"

pause
exit /b 1