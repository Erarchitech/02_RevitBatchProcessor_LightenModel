@echo off

chcp 65001 > nul

setlocal EnableExtensions EnableDelayedExpansion

set SCRIPT_DIR=%~dp0



set RUN_PS=%SCRIPT_DIR%run_LightModelExport.ps1
set CONFIG_JSON=%SCRIPT_DIR%config.json
set "PS_EXE=powershell"
set ADDIN_VERSION=
set ADDIN_BUNDLE_DIRS=%ProgramData%\Autodesk\ApplicationPlugins %AppData%\Autodesk\ApplicationPlugins
set SKIP_BUNDLES=




echo ================================

echo ???????? ??????? ? REVIT SERVER

echo ================================



if not exist "%CONFIG_JSON%" (

  echo ERROR: config not found: "%CONFIG_JSON%"

  goto :fail

)

if not exist "%RUN_PS%" (

  echo ERROR: run script not found: "%RUN_PS%"

  goto :fail

)



for /f "usebackq delims=" %%V in (`%PS_EXE% -NoProfile -Command "$cfg = Get-Content -Raw -Encoding UTF8 ""%CONFIG_JSON%"" | ConvertFrom-Json; $cfg.revit_version"`) do set "ADDIN_VERSION=%%V"
if not defined ADDIN_VERSION (
  echo ERROR: revit_version not found in config.json
  goto :fail
)


call :DisableAddins


echo Running PowerShell pipeline...
"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%RUN_PS%" -ConfigPath "%CONFIG_JSON%"


goto :cleanup



:fail

echo ERROR: batch aborted.

goto :cleanup



:cleanup

call :RestoreAddins

echo ================================

echo ??????

echo ================================

pause

goto :eof



:DisableAddins

for %%V in (%ADDIN_VERSION%) do (
  call :DisableAddinsFor "%ProgramData%\Autodesk\Revit\Addins\%%V" "BatchRvtAddin%%V.addin"
  call :DisableAddinsFor "%AppData%\Autodesk\Revit\Addins\%%V" "BatchRvtAddin%%V.addin"
)
for %%D in (%ADDIN_BUNDLE_DIRS%) do (

  call :DisableBundlesIn "%%~D"

)

exit /b 0



:RestoreAddins

for %%V in (%ADDIN_VERSION%) do (
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

  echo WARN: ?????? ???????? ???? ?????????????????? "%ADDINS_DIR%". ?????????????????? bat ???? ????????????????????????????.

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

  echo WARN: ?????? ???????? ???? ???????????????????????????? ?? "%ADDINS_DIR%".

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

  echo WARN: ?????? ???????? ???? ?????????????????? "%BUNDLE_DIR%".

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

  echo WARN: ?????? ???????? ???? ???????????????????????????? ?? "%BUNDLE_DIR%".

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








