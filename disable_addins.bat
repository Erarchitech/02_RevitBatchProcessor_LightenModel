@echo off
setlocal EnableExtensions EnableDelayedExpansion

:: Usage: disable_addins.bat [RevitVersion]
:: Example: disable_addins.bat 2024

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
  echo Disabling *.addin in "%ADDIN_DIR%"
  for /f "delims=" %%F in ('dir /b /a-d "%ADDIN_DIR%\*.addin" 2^>nul') do (
    if /I not "%%F"=="%SKIP_ADDIN%" (
      echo DISABLE: "%ADDIN_DIR%\%%F"
      ren "%ADDIN_DIR%\%%F" "%%F.disabled" >nul 2>nul
    ) else (
      echo SKIP: "%ADDIN_DIR%\%%F"
    )
  )
) else (
  echo WARN: folder not found: "%ADDIN_DIR%"
)

if exist "%ADDIN_DIR_PD%" (
  echo Disabling *.addin in "%ADDIN_DIR_PD%"
  for /f "delims=" %%F in ('dir /b /a-d "%ADDIN_DIR_PD%\*.addin" 2^>nul') do (
    if /I not "%%F"=="%SKIP_ADDIN%" (
      echo DISABLE: "%ADDIN_DIR_PD%\%%F"
      ren "%ADDIN_DIR_PD%\%%F" "%%F.disabled" >nul 2>nul
    ) else (
      echo SKIP: "%ADDIN_DIR_PD%\%%F"
    )
  )
) else (
  echo WARN: folder not found: "%ADDIN_DIR_PD%"
)

echo DONE.
endlocal
