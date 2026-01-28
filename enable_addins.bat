@echo off
setlocal EnableExtensions EnableDelayedExpansion

:: Usage: enable_addins.bat [RevitVersion]
:: Example: enable_addins.bat 2024

set "VER=%~1"
if not defined VER set "VER=%RVT_VERSION%"

if not defined VER (
  echo ERROR: version not set. Pass argument or set RVT_VERSION.
  exit /b 1
)

set "ADDIN_DIR=%AppData%\Autodesk\Revit\Addins\%VER%"
set "ADDIN_DIR_PD=%ProgramData%\Autodesk\Revit\Addins\%VER%"
set "SKIP_ADDIN=BatchRvtAddin%VER%.addin"

if exist "%ADDIN_DIR%" (
  echo Restoring *.addin in "%ADDIN_DIR%"
  for /f "delims=" %%F in ('dir /b /a-d "%ADDIN_DIR%\*.addin.disabled" 2^>nul') do (
    echo RESTORE: "%ADDIN_DIR%\%%F"
    set "TARGET=%ADDIN_DIR%\%%F"
    set "DONE=0"
    for /l %%R in (1,1,5) do (
      if /I not "%%~nF.addin"=="%SKIP_ADDIN%" (
        ren "!TARGET!" "%%~nF" >nul 2>nul
      ) else (
        set "DONE=1"
      )
      if not exist "!TARGET!" set "DONE=1"
      if exist "!TARGET!" timeout /t 1 /nobreak >nul
    )
    if "!DONE!"=="0" echo WARN: failed to restore "!TARGET!"
  )
) else (
  echo WARN: folder not found: "%ADDIN_DIR%"
)

if exist "%ADDIN_DIR_PD%" (
  echo Restoring *.addin in "%ADDIN_DIR_PD%"
  for /f "delims=" %%F in ('dir /b /a-d "%ADDIN_DIR_PD%\*.addin.disabled" 2^>nul') do (
    echo RESTORE: "%ADDIN_DIR_PD%\%%F"
    set "TARGET=%ADDIN_DIR_PD%\%%F"
    set "DONE=0"
    for /l %%R in (1,1,5) do (
      if /I not "%%~nF.addin"=="%SKIP_ADDIN%" (
        ren "!TARGET!" "%%~nF" >nul 2>nul
      ) else (
        set "DONE=1"
      )
      if not exist "!TARGET!" set "DONE=1"
      if exist "!TARGET!" timeout /t 1 /nobreak >nul
    )
    if "!DONE!"=="0" echo WARN: failed to restore "!TARGET!"
  )
) else (
  echo WARN: folder not found: "%ADDIN_DIR_PD%"
)

echo DONE.
endlocal
