@echo off
:: Кодировка для Кириллицы
chcp 65001 > nul
setlocal EnableExtensions EnableDelayedExpansion
set SCRIPT_DIR=%~dp0

:: -------------------------------------------------------------------------------
:: Общие переменные
set RST=C:\Program Files\Autodesk\Revit 2024\RevitServerToolCommand\RevitServerTool.exe
set RBP=%LOCALAPPDATA%\RevitBatchProcessor\BatchRvt.exe
set BUT=C:\Program Files\Autodesk\Navisworks Manage 2020\FileToolsTaskRunner.exe

set SERVER=m-revit49
set PROJ=Likino
set BASE=G:\Мой диск\02_DEV\06_Projects\01_Облегченные модели\02_XML_RevitBatchProcessor\PROJECT

set LIST_RVT=%BASE%\Scripts\List_RVT-models.txt
set LOG=%BASE%\Scripts\Log.log
set RBP_RUN_LOG=%BASE%\Scripts\BatchRvt_run.log
set DETECT_SCRIPT=%SCRIPT_DIR%detect_revit_versions.py
set LIST_BY_VER_PREFIX=%BASE%\Scripts\List_RVT-models_
set LIST_UNKNOWN=%BASE%\Scripts\List_RVT-models_UNKNOWN.txt
set DETECT_LOG=%BASE%\Scripts\detect_revit_versions.log
set TASK_SCRIPT=%SCRIPT_DIR%RBP_Test_2_B1.py
set RBP_LOG_FOLDER=%BASE%\Scripts\BatchRvtLogs
set RBP_OUTPUT=%BASE%\CLEANED
set PYTHONUTF8=1
set PYTHONIOENCODING=utf-8
set ADDIN_VERSIONS=2020 2022 2024
set ADDIN_BUNDLE_DIRS=%ProgramData%\Autodesk\ApplicationPlugins %AppData%\Autodesk\ApplicationPlugins
set SKIP_BUNDLES=

call :DisableAddins

if not exist "%RBP%" (
  echo ERROR: BatchRvt.exe not found: "%RBP%"
  goto :fail
)
if not exist "%BASE%\Scripts" md "%BASE%\Scripts"
if not exist "%RBP_LOG_FOLDER%" md "%RBP_LOG_FOLDER%"

echo ================================
echo ВЫГРУЗКА МОДЕЛЕЙ С REVIT SERVER
echo ================================

:: Выгрузка моделей с сервера Revit
@REM "%RST%" L "%PROJ%\AR\UB\Likino_AR_GP_R24_B1.rvt" -s %SERVER% -d "%BASE%\CDE\B1\Likino_AR_GP_R24_B1.rvt" -o
@REM "%RST%" L "%PROJ%\AR\UB\Likino_AR_GP_R24_FSD_B1.rvt" -s %SERVER% -d "%BASE%\CDE\B1\Likino_AR_GP_R24_FSD_B1.rvt" -o
@REM "%RST%" L "%PROJ%\ST\Likino_KR_GP_R24_B1.rvt" -s %SERVER% -d "%BASE%\CDE\B1\Likino_KR_GP_R24_B1.rvt" -o
@REM "%RST%" L "%PROJ%\MEP\B1\Likino_EOM_GP_R24_B1.rvt" -s %SERVER% -d "%BASE%\CDE\B1\Likino_EOM_GP_R24_B1.rvt" -o
@REM "%RST%" L "%PROJ%\MEP\B1\Likino_KV_GP_R24_B1.rvt" -s %SERVER% -d "%BASE%\CDE\B1\Likino_KV_GP_R24_B1.rvt" -o
@REM "%RST%" L "%PROJ%\MEP\B1\Likino_OT_GP_R24_B1.rvt" -s %SERVER% -d "%BASE%\CDE\B1\Likino_OT_GP_R24_B1.rvt" -o
@REM "%RST%" L "%PROJ%\MEP\B1\Likino_PT_GP_R24_B1.rvt" -s %SERVER% -d "%BASE%\CDE\B1\Likino_PT_GP_R24_B1.rvt" -o
"%RST%" L "%PROJ%\MEP\B1\Likino_SS_GP_R24_B1.rvt" -s %SERVER% -d "%BASE%\CDE\B1\Likino_SS_GP_R24_B1.rvt" -o
@REM "%RST%" L "%PROJ%\MEP\B1\Likino_VENT_GP_R24_B1.rvt" -s %SERVER% -d "%BASE%\CDE\B1\Likino_VENT_GP_R24_B1.rvt" -o
@REM "%RST%" L "%PROJ%\MEP\B1\Likino_VKK_GP_R24_B1.rvt" -s %SERVER% -d "%BASE%\CDE\B1\Likino_VKK_GP_R24_B1.rvt" -o
@REM "%RST%" L "%PROJ%\MEP\B1\Likino_VKV_GP_R24_B1.rvt" -s %SERVER% -d "%BASE%\CDE\B1\Likino_VKV_GP_R24_B1.rvt" -o
@REM "%RST%" L "%PROJ%\MEP\B1\Likino_ITP_GP_R24_B1.rvt" -s %SERVER% -d "%BASE%\CDE\B1\Likino_ITP_GP_R24_B1.rvt" -o

echo ================================
echo СОЗДАНИЕ СПИСКА МОДЕЛЕЙ ДЛЯ ОЧИСТКИ
echo ================================

:: Получаем список выгруженных RVT (без ревизий и служебных файлов)
dir /b/s "%BASE%\CDE\B1\*.rvt" | findstr /i /v /r /c:"[.][0-9][0-9][0-9][0-9][.]" > "%LIST_RVT%"

for %%A in ("%LIST_RVT%") do if %%~zA==0 (
  echo ERROR: file list is empty: "%LIST_RVT%"
  goto :fail
)

echo ================================
echo ОЧИСТКА МОДЕЛЕЙ (PURGE/AUDIT)
echo ================================

if not exist "%TASK_SCRIPT%" (
  echo ERROR: task script not found: "%TASK_SCRIPT%"
  goto :fail
)
if not exist "%LIST_RVT%" (
  echo ERROR: file list not found: "%LIST_RVT%"
  goto :fail
)

if not exist "%DETECT_SCRIPT%" (
  echo ERROR: detect script not found: "%DETECT_SCRIPT%"
  goto :fail
)

echo Detecting Revit versions...
python "%DETECT_SCRIPT%" --list "%LIST_RVT%" --out_prefix "%LIST_BY_VER_PREFIX%" --years %ADDIN_VERSIONS% --unknown "%LIST_UNKNOWN%" > "%DETECT_LOG%" 2>&1
type "%DETECT_LOG%"

set "ANY=0"
for %%V in (%ADDIN_VERSIONS%) do (
  set "LIST_VER=%LIST_BY_VER_PREFIX%%%V.txt"
  if exist "!LIST_VER!" (
    for %%A in ("!LIST_VER!") do if %%~zA gtr 0 (
      set "ANY=1"
      set "RBP_RUN_LOG=%BASE%\Scripts\BatchRvt_run_%%V.log"
      echo Running BatchRvt for Revit %%V: --task_script "%TASK_SCRIPT%" --file_list "!LIST_VER!" --revit_version %%V --audit
      "%RBP%" --task_script "%TASK_SCRIPT%" --file_list "!LIST_VER!" --revit_version %%V --audit --log_folder "%RBP_LOG_FOLDER%" > "!RBP_RUN_LOG!" 2>&1
      type "!RBP_RUN_LOG!"
    )
  )
)

if "!ANY!"=="0" (
  echo ERROR: No files matched supported Revit versions: %ADDIN_VERSIONS%
)
if exist "%LIST_UNKNOWN%" (
  for %%U in ("%LIST_UNKNOWN%") do if %%~zU gtr 0 (
    echo WARN: Some files had unknown/unsupported Revit versions. See: "%LIST_UNKNOWN%"
  )
)

goto :cleanup

:fail
echo ERROR: batch aborted.
goto :cleanup

:cleanup
call :RestoreAddins
echo ================================
echo ГОТОВО
echo ================================
pause
goto :eof

:DisableAddins
for %%V in (%ADDIN_VERSIONS%) do (
  call :DisableAddinsFor "%ProgramData%\Autodesk\Revit\Addins\%%V" "BatchRvtAddin%%V.addin"
  call :DisableAddinsFor "%AppData%\Autodesk\Revit\Addins\%%V" "BatchRvtAddin%%V.addin"
)
for %%D in (%ADDIN_BUNDLE_DIRS%) do (
  call :DisableBundlesIn "%%~D"
)
exit /b 0

:RestoreAddins
for %%V in (%ADDIN_VERSIONS%) do (
  call :RestoreAddinsFor "%ProgramData%\Autodesk\Revit\Addins\%%V"
  call :RestoreAddinsFor "%AppData%\Autodesk\Revit\Addins\%%V"
)
for %%D in (%ADDIN_BUNDLE_DIRS%) do (
  call :RestoreBundlesIn "%%~D"
)
exit /b 0

:DisableAddinsFor
set "ADDINS_DIR=%~1"
set "SKIP_ADDIN=%~2"
call :CanWriteDir "%ADDINS_DIR%"
if errorlevel 1 (
  echo WARN: нет прав на изменение "%ADDINS_DIR%". Запустите bat от администратора.
  exit /b 0
)
if exist "%ADDINS_DIR%\\*.addin" (
  for %%F in ("%ADDINS_DIR%\\*.addin") do (
    if /I not "%%~nxF"=="%SKIP_ADDIN%" ren "%%F" "%%~nxF.disabled" >nul 2>nul
  )
)
exit /b 0

:RestoreAddinsFor
set "ADDINS_DIR=%~1"
call :CanWriteDir "%ADDINS_DIR%"
if errorlevel 1 (
  echo WARN: нет прав на восстановление в "%ADDINS_DIR%".
  exit /b 0
)
if exist "%ADDINS_DIR%\\*.addin.disabled" (
  for %%F in ("%ADDINS_DIR%\\*.addin.disabled") do ren "%%F" "%%~nF" >nul 2>nul
)
exit /b 0

:DisableBundlesIn
set "BUNDLE_DIR=%~1"
call :CanWriteDir "%BUNDLE_DIR%"
if errorlevel 1 (
  echo WARN: нет прав на изменение "%BUNDLE_DIR%".
  exit /b 0
)
for /d %%B in ("%BUNDLE_DIR%\*.bundle") do (
  set "SKIP=0"
  for %%S in (!SKIP_BUNDLES!) do if /I "%%~nxB"=="%%S" set "SKIP=1"
  if "!SKIP!"=="0" ren "%%B" "%%~nxB.disabled" >nul 2>nul
)
exit /b 0

:RestoreBundlesIn
set "BUNDLE_DIR=%~1"
call :CanWriteDir "%BUNDLE_DIR%"
if errorlevel 1 (
  echo WARN: нет прав на восстановление в "%BUNDLE_DIR%".
  exit /b 0
)
for /d %%B in ("%BUNDLE_DIR%\*.bundle.disabled") do ren "%%B" "%%~nB" >nul 2>nul
exit /b 0

:CanWriteDir
set "TEST_FILE=%~1\\_rbp_write_test.tmp"
> "%TEST_FILE%" echo. 2>nul
if exist "%TEST_FILE%" (
  del "%TEST_FILE%" >nul 2>nul
  exit /b 0
)
exit /b 1