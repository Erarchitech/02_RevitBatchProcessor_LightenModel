@echo off
:: Кодировка для Кириллицы
chcp 65001 > nul
setlocal
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
set TASK_SCRIPT=%SCRIPT_DIR%RBP_Test_2_B1.py
set RBP_LOG_FOLDER=%BASE%\Scripts\BatchRvtLogs
set RBP_OUTPUT=%BASE%\CLEANED

if not exist "%RBP%" (
  echo ERROR: BatchRvt.exe not found: "%RBP%"
  exit /b 1
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
  exit /b 1
)

echo ================================
echo ОЧИСТКА МОДЕЛЕЙ (PURGE/AUDIT)
echo ================================

if not exist "%TASK_SCRIPT%" (
  echo ERROR: task script not found: "%TASK_SCRIPT%"
  exit /b 1
)
if not exist "%LIST_RVT%" (
  echo ERROR: file list not found: "%LIST_RVT%"
  exit /b 1
)

echo Запуск BatchRvt: --task_script "%TASK_SCRIPT%" --file_list "%LIST_RVT%" --revit_version 2024 --audit
"%RBP%" --task_script "%TASK_SCRIPT%" --file_list "%LIST_RVT%" --revit_version 2024 --audit --log_folder "%RBP_LOG_FOLDER%" > "%RBP_RUN_LOG%" 2>&1
type "%RBP_RUN_LOG%"

echo ================================
echo ГОТОВО
echo ================================
pause
goto :eof