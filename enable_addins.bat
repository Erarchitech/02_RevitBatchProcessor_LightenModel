@echo off
setlocal EnableExtensions EnableDelayedExpansion

:: ============================================================================
:: ENABLE REVIT ADDINS
:: ============================================================================

set "VER=%~1"
if not defined VER set "VER=%RVT_VERSION%"

if not defined VER (
    echo ERROR: Revit version not specified
    exit /b 1
)

echo.
echo Restoring Revit %VER% addins...

set "ADDIN_USER=%AppData%\Autodesk\Revit\Addins\%VER%"
set "ADDIN_MACHINE=%ProgramData%\Autodesk\Revit\Addins\%VER%"
set "COUNT=0"

:: User addins
if exist "%ADDIN_USER%" (
    for /f "delims=" %%F in ('dir /b /a-d "%ADDIN_USER%\*.addin.disabled" 2^>nul') do (
        set "ORIG=%%~nF"
        attrib -R "%ADDIN_USER%\%%F" >nul 2>nul
        if exist "%ADDIN_USER%\!ORIG!" (
            del "%ADDIN_USER%\%%F" >nul 2>nul
        ) else (
            ren "%ADDIN_USER%\%%F" "!ORIG!" >nul 2>nul
        )
        if exist "%ADDIN_USER%\!ORIG!" (
            echo   [USER] !ORIG!
            set /a COUNT+=1
        )
    )
)

:: Machine addins
if exist "%ADDIN_MACHINE%" (
    for /f "delims=" %%F in ('dir /b /a-d "%ADDIN_MACHINE%\*.addin.disabled" 2^>nul') do (
        set "ORIG=%%~nF"
        attrib -R "%ADDIN_MACHINE%\%%F" >nul 2>nul
        if exist "%ADDIN_MACHINE%\!ORIG!" (
            del "%ADDIN_MACHINE%\%%F" >nul 2>nul
        ) else (
            ren "%ADDIN_MACHINE%\%%F" "!ORIG!" >nul 2>nul
        )
        if exist "%ADDIN_MACHINE%\!ORIG!" (
            echo   [MACHINE] !ORIG!
            set /a COUNT+=1
        )
    )
)

echo Restored: !COUNT! addins
endlocal
exit /b 0