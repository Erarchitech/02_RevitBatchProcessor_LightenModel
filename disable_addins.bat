@echo off
setlocal EnableExtensions EnableDelayedExpansion

:: ============================================================================
:: DISABLE REVIT ADDINS
:: ============================================================================

set "VER=%~1"
if not defined VER set "VER=%RVT_VERSION%"

if not defined VER (
    echo ERROR: Revit version not specified
    exit /b 1
)

echo.
echo Disabling Revit %VER% addins...

set "ADDIN_USER=%AppData%\Autodesk\Revit\Addins\%VER%"
set "ADDIN_MACHINE=%ProgramData%\Autodesk\Revit\Addins\%VER%"
set "SKIP=BatchRvtAddin%VER%.addin"
set "COUNT=0"

:: User addins
if exist "%ADDIN_USER%" (
    for /f "delims=" %%F in ('dir /b /a-d "%ADDIN_USER%\*.addin" 2^>nul') do (
        if /I not "%%F"=="%SKIP%" (
            attrib -R "%ADDIN_USER%\%%F" >nul 2>nul
            if exist "%ADDIN_USER%\%%F.disabled" del "%ADDIN_USER%\%%F.disabled" >nul 2>nul
            ren "%ADDIN_USER%\%%F" "%%F.disabled" >nul 2>nul
            if exist "%ADDIN_USER%\%%F.disabled" (
                echo   [USER] %%F
                set /a COUNT+=1
            )
        )
    )
)

:: Machine addins
if exist "%ADDIN_MACHINE%" (
    for /f "delims=" %%F in ('dir /b /a-d "%ADDIN_MACHINE%\*.addin" 2^>nul') do (
        if /I not "%%F"=="%SKIP%" (
            attrib -R "%ADDIN_MACHINE%\%%F" >nul 2>nul
            if exist "%ADDIN_MACHINE%\%%F.disabled" del "%ADDIN_MACHINE%\%%F.disabled" >nul 2>nul
            ren "%ADDIN_MACHINE%\%%F" "%%F.disabled" >nul 2>nul
            if exist "%ADDIN_MACHINE%\%%F.disabled" (
                echo   [MACHINE] %%F
                set /a COUNT+=1
            )
        )
    )
)

echo Disabled: !COUNT! addins
endlocal
exit /b 0