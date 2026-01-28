@echo off

chcp 65001 > nul

setlocal EnableExtensions EnableDelayedExpansion

set SCRIPT_DIR=%~dp0



set RUN_PS=%SCRIPT_DIR%run_LightModelExport.ps1
set CONFIG_JSON=%SCRIPT_DIR%config.json
set DISABLE_ADDINS=%SCRIPT_DIR%disable_addins.bat
set ENABLE_ADDINS=%SCRIPT_DIR%enable_addins.bat
set "PS_EXE=powershell"
set ADDIN_VERSION=2024




echo ================================
echo ВЫГРУЗКА МОДЕЛЕЙ С REVIT SERVER
echo ================================



if not exist "%CONFIG_JSON%" (

  echo ERROR: config not found: "%CONFIG_JSON%"

  goto :fail

)

if not exist "%RUN_PS%" (

  echo ERROR: run script not found: "%RUN_PS%"

  goto :fail

)



set "RVT_VER_FILE=%TEMP%\\revit_version.txt"
if exist "%RVT_VER_FILE%" del "%RVT_VER_FILE%" >nul 2>nul
%PS_EXE% -NoProfile -Command "(Get-Content -Raw -LiteralPath '%CONFIG_JSON%' | ConvertFrom-Json).revit_version" > "%RVT_VER_FILE%"
set /p ADDIN_VERSION=<"%RVT_VER_FILE%"
del "%RVT_VER_FILE%" >nul 2>nul
if not defined ADDIN_VERSION (
  echo ERROR: revit_version not found in config.json
  goto :fail
)
for /f "delims=" %%A in ("%ADDIN_VERSION%") do set "ADDIN_VERSION=%%~A"
set "ADDIN_VERSION=%ADDIN_VERSION: =%"
if "%ADDIN_VERSION%"=="" (
  echo ERROR: revit_version is empty in config.json
  goto :fail
)
set "RVT_VERSION=%ADDIN_VERSION%"

if not exist "%DISABLE_ADDINS%" (
  echo ERROR: disable_addins.bat not found: "%DISABLE_ADDINS%"
  goto :fail
)
if not exist "%ENABLE_ADDINS%" (
  echo ERROR: enable_addins.bat not found: "%ENABLE_ADDINS%"
  goto :fail
)

call "%DISABLE_ADDINS%" "%ADDIN_VERSION%"
if errorlevel 1 (
  echo ERROR: disable_addins.bat failed.
  goto :fail
)

echo ОЧИСТКА МОДЕЛЕЙ
echo ================================

"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%RUN_PS%" -ConfigPath "%CONFIG_JSON%"


goto :cleanup



:fail

echo ERROR: batch aborted.

goto :cleanup



:cleanup

timeout /t 3 /nobreak >nul
call "%ENABLE_ADDINS%" "%ADDIN_VERSION%"

echo ================================
echo ЗАВЕРШЕНО
echo ================================

pause

goto :eof





