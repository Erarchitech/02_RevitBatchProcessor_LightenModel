@echo off
chcp 65001 > nul
setlocal EnableExtensions EnableDelayedExpansion

:: ============================================================================
:: REVIT BATCH EXPORT & CLEAN - ШАБЛОН НАСТРОЕК
:: ============================================================================
:: Скопируйте этот файл и заполните настройки ниже
:: ============================================================================

:: ============================================================================
:: ПУТЬ К СЕРВЕРНЫМ СКРИПТАМ (не менять без необходимости)
:: ============================================================================
set "SCRIPTS_SERVER=\\srv-dfs\BIM\01_Ресурсы плагинов\10_Облегченные модели\Версия_BAT_3"

:: ============================================================================
:: НАСТРОЙКИ REVIT SERVER
:: ============================================================================
:: IP или имя Revit Server
set "RS_HOST=10.0.2.35"

:: Версия Revit (2020, 2021, 2022, 2023, 2024, 2025)
set "RVT_VERSION=2022"

:: Папка на Revit Server (можно использовать | или / или \)
:: Примеры: |Project|Folder| или Project/Folder или Project\Folder
set "RS_SOURCE_FOLDER=Grebnoy kanal 1/ST"

:: Список моделей (если пусто - берутся все из RS_SOURCE_FOLDER)
:: Формат: имена файлов через пробел или пустая строка для всех
set "MODELS="

:: ============================================================================
:: ПАПКИ ВЫВОДА (можно использовать / или \)
:: ============================================================================
:: Папка для локальных копий с RS
set "DOWNLOAD_FOLDER=C:\Users\e.ermolenko\Documents\ТЕСТИРОВАНИЕ\Grebnoy kanal1\CDE\rvt_ex"

:: Папка для очищенных файлов (используется если ENABLE_CLEAN=1)
set "OUTPUT_FOLDER=C:\Users\e.ermolenko\Documents\ТЕСТИРОВАНИЕ\Grebnoy kanal1\CDE\rvt_cl"

:: Папка для логов
set "LOG_FOLDER=C:\Users\e.ermolenko\Documents\ТЕСТИРОВАНИЕ\Grebnoy kanal1\Scripts\Logs"

:: Папка для NWC файлов (используется если ENABLE_NWC=1)
set "NWC_FOLDER=C:\Users\e.ermolenko\Documents\ТЕСТИРОВАНИЕ\Grebnoy kanal1\CDE\NWC"

:: Папка и имя NWD файла (используется если ENABLE_NWD=1)
set "NWD_FOLDER=C:\Users\e.ermolenko\Documents\ТЕСТИРОВАНИЕ\Grebnoy kanal1\CDE\NWD"
set "NWD_FILENAME=Combined_Model.nwd"

:: ============================================================================
:: ЭТАПЫ ОБРАБОТКИ (1 = включено, 0 = выключено)
:: ============================================================================
:: Скачивание моделей с RS (всегда выполняется первым)
set "ENABLE_DOWNLOAD=1"

:: Очистка моделей (удаление связей, листов, неиспользуемых элементов)
set "ENABLE_CLEAN=1"

:: Экспорт в NWC
set "ENABLE_NWC=1"

:: Сборка NWD из всех NWC
set "ENABLE_NWD=1"

:: ============================================================================
:: ПАРАМЕТРЫ NAVISWORKS (если ENABLE_NWC=1)
:: ============================================================================
:: Загружать связи Revit при экспорте NWC (1 = да, 0 = нет)
set "NWC_CONVERT_LINKS=0"

:: Разделять по уровням
set "NWC_DIVIDE_BY_LEVEL=1"

:: Экспортировать Element IDs (отключение ускоряет экспорт)
set "NWC_CONVERT_IDS=1"

:: Координаты: shared или internal
set "NWC_COORDINATES=shared"

:: Качество геометрии (0.1-10, где 1.0 = стандарт)
:: МЕНЬШЕ = БЫСТРЕЕ: 0.5 даёт ~2x ускорение с минимальной потерей качества
set "NWC_FACETING=1.0"

:: Конвертировать геометрию помещений (отключение ускоряет)
set "NWC_ROOMS=0"

:: Конвертировать источники света (отключение ускоряет)
set "NWC_LIGHTS=0"

:: ============================================================================
:: ПАРАМЕТРЫ УСКОРЕНИЯ ЭКСПОРТА
:: ============================================================================
:: Параллельный экспорт NWC (количество одновременных процессов)
:: Рекомендуется: 2-4 для обычных ПК, 4-8 для мощных серверов
set "NWC_PARALLEL=4"

:: Экспорт NWC через Revit API вместо Navisworks (быстрее, но требует BatchRvt)
:: 1 = экспорт в clean_model.py, 0 = через Navisworks BatchUtility
set "NWC_VIA_REVIT=1"

:: ============================================================================
:: ПАРАМЕТРЫ ОЧИСТКИ (если ENABLE_CLEAN=1)
:: ============================================================================
:: Удалять связи Revit
set "DELETE_LINKS=1"

:: Удалять импортированные CAD
set "DELETE_IMPORTS=1"

:: Удалять листы
set "DELETE_SHEETS=1"

:: Удалять виды (кроме указанных в VIEWS_TO_KEEP)
set "DELETE_VIEWS=1"

:: Виды которые сохранить (через запятую, без пробелов)
set "VIEWS_TO_KEEP=Navisworks"

:: Очищать неиспользуемые элементы
set "PURGE_UNUSED=1"

:: Сжимать при сохранении
set "COMPACT_ON_SAVE=1"

:: Тестовый режим (без сохранения изменений)
set "DRY_RUN=0"

:: Автоматически закрывать все диалоги и предупреждения
set "SUPPRESS_DIALOGS=1"

:: ============================================================================
:: ПАРАМЕТРЫ ОБРАБОТКИ
:: ============================================================================
:: Количество попыток скачивания
set "RETRY_COUNT=3"

:: Таймаут в минутах
set "TIMEOUT_MINUTES=10"

:: Время ожидания после завершения (в секундах, 300 = 5 минут)
set "AUTO_CLOSE_TIMEOUT=300"

:: ============================================================================
:: ЗАПУСК (не менять)
:: ============================================================================
powershell -NoProfile -Command ^
    "$sig = '[DllImport(\"kernel32.dll\", SetLastError = true)] public static extern IntPtr GetStdHandle(int nStdHandle);' + ^
    '[DllImport(\"kernel32.dll\", SetLastError = true)] public static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);' + ^
    '[DllImport(\"kernel32.dll\", SetLastError = true)] public static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);'; ^
    $t = Add-Type -MemberDefinition $sig -Name WinAPI -Namespace Console -PassThru; ^
    $h = $t::GetStdHandle(-10); ^
    $m = 0; ^
    $null = $t::GetConsoleMode($h, [ref]$m); ^
    $null = $t::SetConsoleMode($h, $m -band (-bnot 0x0040))" >nul 2>&1

echo.
echo ================================================================
echo   REVIT BATCH EXPORT ^& CLEAN
echo ================================================================
echo.

:: Проверка доступности серверных скриптов
if not exist "%SCRIPTS_SERVER%" (
    echo ОШИБКА: Серверные скрипты недоступны!
    echo Путь: %SCRIPTS_SERVER%
    echo.
    pause
    exit /b 1
)

:: Запуск основного скрипта
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPTS_SERVER%\Main_Export.ps1" ^
    -RS_HOST "%RS_HOST%" ^
    -RVT_VERSION "%RVT_VERSION%" ^
    -RS_SOURCE_FOLDER "%RS_SOURCE_FOLDER%" ^
    -MODELS "%MODELS%" ^
    -DOWNLOAD_FOLDER "%DOWNLOAD_FOLDER%" ^
    -OUTPUT_FOLDER "%OUTPUT_FOLDER%" ^
    -LOG_FOLDER "%LOG_FOLDER%" ^
    -NWC_FOLDER "%NWC_FOLDER%" ^
    -NWD_FOLDER "%NWD_FOLDER%" ^
    -NWD_FILENAME "%NWD_FILENAME%" ^
    -ENABLE_DOWNLOAD %ENABLE_DOWNLOAD% ^
    -ENABLE_CLEAN %ENABLE_CLEAN% ^
    -ENABLE_NWC %ENABLE_NWC% ^
    -ENABLE_NWD %ENABLE_NWD% ^
    -DELETE_LINKS %DELETE_LINKS% ^
    -DELETE_IMPORTS %DELETE_IMPORTS% ^
    -DELETE_SHEETS %DELETE_SHEETS% ^
    -DELETE_VIEWS %DELETE_VIEWS% ^
    -VIEWS_TO_KEEP "%VIEWS_TO_KEEP%" ^
    -PURGE_UNUSED %PURGE_UNUSED% ^
    -COMPACT_ON_SAVE %COMPACT_ON_SAVE% ^
    -DRY_RUN %DRY_RUN% ^
    -SUPPRESS_DIALOGS %SUPPRESS_DIALOGS% ^
    -RETRY_COUNT %RETRY_COUNT% ^
    -TIMEOUT_MINUTES %TIMEOUT_MINUTES% ^
    -SCRIPTS_SERVER "%SCRIPTS_SERVER%" ^
    -NWC_CONVERT_LINKS %NWC_CONVERT_LINKS% ^
    -NWC_DIVIDE_BY_LEVEL %NWC_DIVIDE_BY_LEVEL% ^
    -NWC_CONVERT_IDS %NWC_CONVERT_IDS% ^
    -NWC_COORDINATES "%NWC_COORDINATES%" ^
    -NWC_FACETING %NWC_FACETING% ^
    -NWC_ROOMS %NWC_ROOMS% ^
    -NWC_LIGHTS %NWC_LIGHTS% ^
    -NWC_PARALLEL %NWC_PARALLEL% ^
    -NWC_VIA_REVIT %NWC_VIA_REVIT%

set "EXIT_CODE=%ERRORLEVEL%"

echo.
if %EXIT_CODE% equ 0 (
    echo ================================================================
    echo   ЗАВЕРШЕНО УСПЕШНО
    echo ================================================================
) else (
    echo ================================================================
    echo   ЗАВЕРШЕНО С ОШИБКАМИ (код: %EXIT_CODE%)
    echo ================================================================
)
echo.
pause
exit /b %EXIT_CODE%