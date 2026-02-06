#Requires -Version 5.1
<#
.SYNOPSIS
    Основной скрипт экспорта и очистки моделей Revit
.DESCRIPTION
    Скачивает модели с Revit Server, очищает их, экспортирует в NWC/NWD
.VERSION
    2.0 - Финальные правки
#>

param(
    [string]$RS_HOST,
    [string]$RVT_VERSION,
    [string]$RS_SOURCE_FOLDER,
    [string]$MODELS = "",
    [string]$DOWNLOAD_FOLDER,
    [string]$OUTPUT_FOLDER,
    [string]$LOG_FOLDER,
    [string]$NWC_FOLDER,
    [string]$NWD_FOLDER,
    [string]$NWD_FILENAME = "Combined.nwd",
    [int]$ENABLE_DOWNLOAD = 1,
    [int]$ENABLE_CLEAN = 1,
    [int]$ENABLE_NWC = 1,
    [int]$ENABLE_NWD = 1,
    [int]$DELETE_LINKS = 1,
    [int]$DELETE_IMPORTS = 1,
    [int]$DELETE_SHEETS = 1,
    [int]$DELETE_VIEWS = 0,
    [string]$VIEWS_TO_KEEP = "{3D},3D,Level",
    [int]$PURGE_UNUSED = 1,
    [int]$COMPACT_ON_SAVE = 1,
    [int]$DRY_RUN = 0,
    [int]$SUPPRESS_DIALOGS = 1,
    [int]$RETRY_COUNT = 3,
    [int]$TIMEOUT_MINUTES = 60,
    [string]$SCRIPTS_SERVER,
    [int]$NWC_CONVERT_LINKS = 0,
    [int]$NWC_DIVIDE_BY_LEVEL = 1,
    [int]$NWC_CONVERT_IDS = 1,
    [string]$NWC_COORDINATES = "shared",
    [double]$NWC_FACETING = 1.0,
    [int]$NWC_ROOMS = 0,
    [int]$NWC_LIGHTS = 0,
    [int]$NWC_PARALLEL = 4,
    [int]$NWC_VIA_REVIT = 0
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# ============================================================================
# ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
# ============================================================================

function Normalize-Path([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return "" }
    $p = $Path.Trim()
    $p = $p -replace "[/\\|]+", "\"
    $p = $p.Trim("\")
    return $p
}

function Normalize-RsPath([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return "|" }
    $p = $Path.Trim()
    $p = $p -replace "[/\\]+", "|"
    $p = $p.Trim("|")
    if ($p.Length -eq 0) { return "|" }
    return "|" + $p
}

function Ensure-Directory([string]$Path) {
    $normalized = Normalize-Path $Path
    if (-not [string]::IsNullOrWhiteSpace($normalized)) {
        if (-not (Test-Path $normalized)) {
            New-Item -ItemType Directory -Path $normalized -Force | Out-Null
        }
    }
    return $normalized
}

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logLine = "[$timestamp] [$Level] $Message"
    switch ($Level) {
        "ERROR"   { Write-Host $logLine -ForegroundColor Red }
        "WARN"    { Write-Host $logLine -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $logLine -ForegroundColor Green }
        "STEP"    { Write-Host $logLine -ForegroundColor Cyan }
        default   { Write-Host $logLine }
    }
    if ($script:LogFile) {
        Add-Content -Path $script:LogFile -Value $logLine -Encoding UTF8
    }
}

function Test-RevitProcessesRunning {
    $revitProcs = Get-Process -Name "Revit" -ErrorAction SilentlyContinue
    $batchRvtProcs = Get-Process -Name "BatchRvt*" -ErrorAction SilentlyContinue
    $otherProcesses = @()
    if ($revitProcs) { $otherProcesses += $revitProcs }
    if ($batchRvtProcs) { $otherProcesses += $batchRvtProcs }
    return $otherProcesses.Count -gt 0
}

function Test-OtherBatchExportRunning {
    param([string]$Version)
    $lockFile = Join-Path $env:TEMP "RevitBatchExport_$Version.lock"
    if (Test-Path $lockFile) {
        try {
            $lockContent = Get-Content $lockFile -ErrorAction SilentlyContinue
            if ($lockContent) {
                $lockPID = [int]$lockContent
                $proc = Get-Process -Id $lockPID -ErrorAction SilentlyContinue
                if ($proc) { return $true }
            }
        } catch {}
    }
    Set-Content -Path $lockFile -Value $PID -Force
    return $false
}

function Remove-LockFile {
    param([string]$Version)
    $lockFile = Join-Path $env:TEMP "RevitBatchExport_$Version.lock"
    if (Test-Path $lockFile) {
        Remove-Item $lockFile -Force -ErrorAction SilentlyContinue
    }
}

function Get-NavisworksInfo {
    $versions = @("2025", "2024", "2023", "2022", "2021", "2020")
    foreach ($v in $versions) {
        $path = "C:\Program Files\Autodesk\Navisworks Manage $v\FileToolsTaskRunner.exe"
        if (Test-Path $path) {
            return @{ Version = $v; Path = $path }
        }
    }
    return $null
}

function Set-NavisworksRevitOptions {
    param([string]$Version, [hashtable]$Options)
    $regPath = "HKCU:\Software\Autodesk\Navisworks Manage $Version\File Readers\nwcrvt"
    if (-not (Test-Path $regPath)) {
        New-Item -Path $regPath -Force | Out-Null
    }
    $backup = @{}
    try {
        $current = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
        if ($current) {
            foreach ($prop in $current.PSObject.Properties) {
                if ($prop.Name -notlike "PS*") {
                    $backup[$prop.Name] = $prop.Value
                }
            }
        }
    } catch {}
    foreach ($key in $Options.Keys) {
        try {
            Set-ItemProperty -Path $regPath -Name $key -Value $Options[$key] -Type DWord -ErrorAction SilentlyContinue
        } catch {}
    }
    return $backup
}

function Restore-NavisworksRevitOptions {
    param([string]$Version, [hashtable]$Backup)
    if (-not $Backup -or $Backup.Count -eq 0) { return }
    $regPath = "HKCU:\Software\Autodesk\Navisworks Manage $Version\File Readers\nwcrvt"
    foreach ($key in $Backup.Keys) {
        try {
            Set-ItemProperty -Path $regPath -Name $key -Value $Backup[$key] -ErrorAction SilentlyContinue
        } catch {}
    }
}

# ============================================================================
# ИНИЦИАЛИЗАЦИЯ
# ============================================================================

$script:StartTime = Get-Date
$script:AddinsDisabled = $false
$script:Stats = @{
    Downloaded = 0
    DownloadFailed = 0
    Cleaned = 0
    CleanFailed = 0
    NwcExported = 0
    NwcFailed = 0
    Errors = [System.Collections.ArrayList]::new()
}

# ВАЖНО: Список успешно очищенных файлов (для NWC экспорта)
$script:CleanedFiles = @()

# Нормализация путей
$DOWNLOAD_FOLDER = Ensure-Directory $DOWNLOAD_FOLDER
$OUTPUT_FOLDER = Ensure-Directory $OUTPUT_FOLDER
$LOG_FOLDER = Ensure-Directory $LOG_FOLDER
$NWC_FOLDER = Ensure-Directory $NWC_FOLDER
$NWD_FOLDER = Ensure-Directory $NWD_FOLDER

# Инициализация лога
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$script:LogFile = Join-Path $LOG_FOLDER "export_$timestamp.log"

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  REVIT BATCH EXPORT & CLEAN v2.0" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

Write-Log "=" * 60 -Level STEP
Write-Log "REVIT BATCH EXPORT & CLEAN v2.0" -Level STEP
Write-Log "=" * 60 -Level STEP
Write-Log ""
Write-Log "Настройки:"
Write-Log "  RS Host:         $RS_HOST"
Write-Log "  Revit Version:   $RVT_VERSION"
Write-Log "  Source Folder:   $RS_SOURCE_FOLDER"
Write-Log "  Download:        $DOWNLOAD_FOLDER"
Write-Log "  Output:          $OUTPUT_FOLDER"
Write-Log "  NWC:             $NWC_FOLDER"
Write-Log "  NWD:             $NWD_FOLDER\$NWD_FILENAME"
Write-Log ""
Write-Log "Этапы:"
Write-Log "  Скачивание:      $(if($ENABLE_DOWNLOAD){'ДА'}else{'НЕТ'})"
Write-Log "  Очистка:         $(if($ENABLE_CLEAN){'ДА'}else{'НЕТ'})"
Write-Log "  Экспорт NWC:     $(if($ENABLE_NWC){'ДА'}else{'НЕТ'})"
Write-Log "  Сборка NWD:      $(if($ENABLE_NWD){'ДА'}else{'НЕТ'})"
Write-Log ""

# ============================================================================
# ПРОВЕРКА ЗАВИСИМОСТЕЙ
# ============================================================================

Write-Log "Проверка зависимостей..." -Level STEP

if (Test-OtherBatchExportRunning -Version $RVT_VERSION) {
    Write-Log "Обнаружен другой процесс экспорта для Revit $RVT_VERSION" -Level WARN
}

$RST = "C:\Program Files\Autodesk\Revit $RVT_VERSION\RevitServerToolCommand\RevitServerTool.exe"
$BatchRvt = "$env:LOCALAPPDATA\RevitBatchProcessor\BatchRvt.exe"
$NavisInfo = Get-NavisworksInfo

if (-not (Test-Path $RST)) {
    Write-Log "RevitServerTool не найден: $RST" -Level ERROR
    exit 1
}
Write-Log "  RevitServerTool: OK"

if ($ENABLE_CLEAN -and -not (Test-Path $BatchRvt)) {
    Write-Log "BatchRvt не найден: $BatchRvt" -Level ERROR
    exit 1
}
if ($ENABLE_CLEAN) { Write-Log "  BatchRvt: OK" }

if ($ENABLE_NWC -and -not $NavisInfo) {
    Write-Log "Navisworks не найден!" -Level ERROR
    exit 1
}
if ($NavisInfo) { Write-Log "  Navisworks: $($NavisInfo.Version)" }

$DisableAddins = Join-Path $SCRIPTS_SERVER "disable_addins.bat"
$EnableAddins = Join-Path $SCRIPTS_SERVER "enable_addins.bat"
$CleanScript = Join-Path $SCRIPTS_SERVER "clean_model.py"
$ListScript = Join-Path $SCRIPTS_SERVER "ListRevitServerModels.ps1"

foreach ($f in @($DisableAddins, $EnableAddins, $CleanScript, $ListScript)) {
    if (-not (Test-Path $f)) {
        Write-Log "Серверный скрипт не найден: $f" -Level ERROR
        exit 1
    }
}
Write-Log "  Серверные скрипты: OK"

Write-Log ""

# ============================================================================
# ЭТАП 1: СКАЧИВАНИЕ МОДЕЛЕЙ
# ============================================================================

$LocalFiles = @()

if ($ENABLE_DOWNLOAD) {
    Write-Log "=" * 60 -Level STEP
    Write-Log "ЭТАП 1: СКАЧИВАНИЕ МОДЕЛЕЙ" -Level STEP
    Write-Log "=" * 60 -Level STEP
    
    $rsSourceNormalized = $RS_SOURCE_FOLDER -replace "[/\\]", "|"
    $rsSourceNormalized = $rsSourceNormalized.Trim("|")
    $rsPath = Normalize-RsPath $RS_SOURCE_FOLDER
    $modelList = @()
    
    if ([string]::IsNullOrWhiteSpace($MODELS)) {
        Write-Log "Получение списка моделей с сервера..."
        Write-Log "  Сервер: $RS_HOST"
        Write-Log "  Путь: $rsPath"
        Write-Log "  Версия API: $RVT_VERSION"
        
        $tmpList = Join-Path $env:TEMP "rs_models_$([guid]::NewGuid().ToString('N')).txt"
        try {
            $listError = $null
            & $ListScript -Server $RS_HOST -Version ([int]$RVT_VERSION) -OutFile $tmpList -StartPath $rsPath -ErrorAction SilentlyContinue -ErrorVariable listError
            
            if ($listError) {
                Write-Log "Ошибка при получении списка: $listError" -Level ERROR
            }
            
            if (Test-Path $tmpList) {
                $modelList = Get-Content $tmpList -Encoding UTF8 | Where-Object { $_ -and $_.Trim() }
            }
        } catch {
            Write-Log "Исключение: $($_.Exception.Message)" -Level ERROR
        } finally {
            if (Test-Path $tmpList) { Remove-Item $tmpList -Force -ErrorAction SilentlyContinue }
        }
    } else {
        Write-Log "Используется список моделей из настроек..."
        $modelNames = $MODELS -split "\s+" | Where-Object { $_ }
        foreach ($modelName in $modelNames) {
            $modelName = $modelName.Trim()
            if ([string]::IsNullOrWhiteSpace($modelName)) { continue }
            if ($modelName -match "[|/\\]") {
                $fullPath = $modelName -replace "[/\\]", "|"
                $fullPath = $fullPath.Trim("|")
                $modelList += "|$fullPath"
            } else {
                if ([string]::IsNullOrWhiteSpace($rsSourceNormalized)) {
                    $modelList += "|$modelName"
                } else {
                    $modelList += "|$rsSourceNormalized|$modelName"
                }
            }
        }
    }
    
    if ($modelList.Count -eq 0) {
        Write-Log "Модели не найдены!" -Level ERROR
        Remove-LockFile -Version $RVT_VERSION
        exit 1
    }
    
    Write-Log "Найдено моделей: $($modelList.Count)" -Level SUCCESS
    foreach ($m in $modelList) { Write-Log "  - $m" }
    
    $total = $modelList.Count
    $current = 0
    
    foreach ($model in $modelList) {
        $current++
        $modelPath = $model.Trim().TrimStart("|")
        $relPath = $modelPath -replace "\|", "\"
        $fileName = Split-Path -Leaf $relPath
        $localPath = Join-Path $DOWNLOAD_FOLDER $fileName
        
        Write-Log ""
        Write-Log "[$current/$total] $fileName"
        Write-Log "  RS путь: $relPath"
        
        $success = $false
        for ($attempt = 1; $attempt -le $RETRY_COUNT; $attempt++) {
            Write-Log "  Попытка $attempt/$RETRY_COUNT..."
            try {
                if (Test-Path $localPath) { Remove-Item $localPath -Force }
                $output = & $RST L $relPath -s $RS_HOST -d $localPath -o 2>&1
                if ((Test-Path $localPath) -and (Get-Item $localPath).Length -gt 0) {
                    $size = [math]::Round((Get-Item $localPath).Length / 1MB, 2)
                    Write-Log "  Скачано: $size MB" -Level SUCCESS
                    $LocalFiles += $localPath
                    $script:Stats.Downloaded++
                    $success = $true
                    break
                } else {
                    Write-Log "  Файл не создан" -Level WARN
                    if ($output) { Write-Log "  RST: $($output | Out-String)" -Level WARN }
                }
            } catch {
                Write-Log "  Ошибка: $($_.Exception.Message)" -Level WARN
            }
            if ($attempt -lt $RETRY_COUNT) { Start-Sleep -Seconds ($attempt * 5) }
        }
        
        if (-not $success) {
            Write-Log "  ПРОПУЩЕН" -Level ERROR
            $script:Stats.DownloadFailed++
            [void]$script:Stats.Errors.Add("Не удалось скачать: $fileName")
        }
    }
    
    Write-Log ""
    Write-Log "Скачано: $($script:Stats.Downloaded), Ошибок: $($script:Stats.DownloadFailed)"
}

# ============================================================================
# ЭТАП 2: ОЧИСТКА МОДЕЛЕЙ
# ============================================================================

if ($ENABLE_CLEAN -and $LocalFiles.Count -gt 0) {
    Write-Log ""
    Write-Log "=" * 60 -Level STEP
    Write-Log "ЭТАП 2: ОЧИСТКА МОДЕЛЕЙ" -Level STEP
    Write-Log "=" * 60 -Level STEP
    
    # Отключаем аддины (без проверки других процессов)
    Write-Log "Отключение аддинов Revit..."
    & cmd /c "`"$DisableAddins`" $RVT_VERSION"
    $script:AddinsDisabled = $true
    
    $configPath = ""
    $fileListPath = ""
    
    try {
        $configJson = @{
            output_folder = $OUTPUT_FOLDER
            cleaning_options = @{
                purge_unused = [bool]$PURGE_UNUSED
                delete_sheets = [bool]$DELETE_SHEETS
                delete_imports = [bool]$DELETE_IMPORTS
                delete_links = [bool]$DELETE_LINKS
                delete_views = [bool]$DELETE_VIEWS
                delete_views_except = $VIEWS_TO_KEEP -split ","
                compact_on_save = [bool]$COMPACT_ON_SAVE
                dry_run = [bool]$DRY_RUN
                suppress_dialogs = [bool]$SUPPRESS_DIALOGS
                export_nwc = [bool]$NWC_VIA_REVIT
                nwc_folder = $NWC_FOLDER
                nwc_coordinates = $NWC_COORDINATES
                nwc_divide_by_level = [bool]$NWC_DIVIDE_BY_LEVEL
                nwc_convert_ids = [bool]$NWC_CONVERT_IDS
                nwc_convert_links = [bool]$NWC_CONVERT_LINKS
            }
        } | ConvertTo-Json -Depth 5
        
        $configPath = Join-Path $env:TEMP "clean_config_$([guid]::NewGuid().ToString('N')).json"
        Set-Content -Path $configPath -Value $configJson -Encoding UTF8
        
        $fileListPath = Join-Path $env:TEMP "batchrvt_list_$([guid]::NewGuid().ToString('N')).txt"
        Set-Content -Path $fileListPath -Value $LocalFiles -Encoding UTF8
        
        $env:CLEAN_CONFIG = $configPath
        $env:RBP_OUTPUT = $OUTPUT_FOLDER
        
        $batchRvtLog = Join-Path $LOG_FOLDER "BatchRvt_$timestamp.log"
        Write-Log "Запуск BatchRvt..."
        
        & $BatchRvt --task_script $CleanScript --file_list $fileListPath --revit_version $RVT_VERSION --audit --log_folder $LOG_FOLDER *> $batchRvtLog
        
        # ВАЖНО: Собираем ТОЛЬКО файлы, которые были очищены в этом сеансе
        # Проверяем по именам исходных файлов
        $script:CleanedFiles = @()
        foreach ($srcFile in $LocalFiles) {
            $fileName = Split-Path -Leaf $srcFile
            $cleanedPath = Join-Path $OUTPUT_FOLDER $fileName
            if (Test-Path $cleanedPath) {
                $script:CleanedFiles += $cleanedPath
                Write-Log "  Очищен: $fileName" -Level SUCCESS
            } else {
                Write-Log "  Не очищен: $fileName" -Level WARN
                [void]$script:Stats.Errors.Add("Не удалось очистить: $fileName")
            }
        }
        
        $script:Stats.Cleaned = $script:CleanedFiles.Count
        $script:Stats.CleanFailed = $LocalFiles.Count - $script:CleanedFiles.Count
        
        Write-Log ""
        Write-Log "Очищено: $($script:Stats.Cleaned), Ошибок: $($script:Stats.CleanFailed)" -Level SUCCESS
        
    } finally {
        if ($configPath -and (Test-Path $configPath)) { Remove-Item $configPath -Force -ErrorAction SilentlyContinue }
        if ($fileListPath -and (Test-Path $fileListPath)) { Remove-Item $fileListPath -Force -ErrorAction SilentlyContinue }
    }
} else {
    # Если очистка отключена - используем скачанные файлы
    $script:CleanedFiles = $LocalFiles
}

# ============================================================================
# ЭТАП 3: ЭКСПОРТ NWC
# ============================================================================

$NwcFiles = @()

# Если NWC экспортируется через Revit API - пропускаем Navisworks BatchUtility
if ($ENABLE_NWC -and $NWC_VIA_REVIT) {
    Write-Log ""
    Write-Log "=" * 60 -Level STEP
    Write-Log "ЭТАП 3: ЭКСПОРТ NWC (через Revit API)" -Level STEP
    Write-Log "=" * 60 -Level STEP
    Write-Log "NWC экспортируется во время очистки модели (этап 2)" -Level SUCCESS
    
    # Собираем NWC файлы ТОЛЬКО для очищенных моделей
    foreach ($cleanedFile in $script:CleanedFiles) {
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($cleanedFile)
        $nwcPath = Join-Path $NWC_FOLDER "$baseName.nwc"
        if (Test-Path $nwcPath) {
            $NwcFiles += $nwcPath
        }
    }
    $script:Stats.NwcExported = $NwcFiles.Count
    Write-Log "NWC файлов: $($NwcFiles.Count)"
}
elseif ($ENABLE_NWC -and $script:CleanedFiles.Count -gt 0 -and $NavisInfo) {
    Write-Log ""
    Write-Log "=" * 60 -Level STEP
    Write-Log "ЭТАП 3: ЭКСПОРТ NWC" -Level STEP
    Write-Log "=" * 60 -Level STEP
    
    Write-Log "Navisworks версия: $($NavisInfo.Version)"
    Write-Log "Параллельных процессов: $NWC_PARALLEL"
    Write-Log "Файлов для экспорта: $($script:CleanedFiles.Count)"
    
    $coordValue = if ($NWC_COORDINATES -eq "shared") { 1 } else { 0 }
    $nwcOptions = @{
        ConvertLinkedFiles = $NWC_CONVERT_LINKS
        DivideByLevel = $NWC_DIVIDE_BY_LEVEL
        ConvertElementIds = $NWC_CONVERT_IDS
        Coordinates = $coordValue
        ConvertRoomGeometry = $NWC_ROOMS
        ConvertLights = $NWC_LIGHTS
        FacetingFactor = [int]($NWC_FACETING * 100)
    }
    
    Write-Log "Настройки NWC:"
    Write-Log "  Связи: $(if($NWC_CONVERT_LINKS){'ДА'}else{'НЕТ'})"
    Write-Log "  По уровням: $(if($NWC_DIVIDE_BY_LEVEL){'ДА'}else{'НЕТ'})"
    Write-Log "  Element IDs: $(if($NWC_CONVERT_IDS){'ДА'}else{'НЕТ'})"
    Write-Log "  Качество: $NWC_FACETING"
    Write-Log "  Координаты: $NWC_COORDINATES"
    
    $backupOptions = Set-NavisworksRevitOptions -Version $NavisInfo.Version -Options $nwcOptions
    
    try {
        # ВАЖНО: Используем только очищенные файлы из текущего сеанса
        $rvtFilesForNwc = $script:CleanedFiles
        
        Write-Log "Файлов для экспорта: $($rvtFilesForNwc.Count)"
        
        $startNwcTime = Get-Date
        
        if ($NWC_PARALLEL -gt 1 -and $rvtFilesForNwc.Count -gt 1) {
            # ========== ПАРАЛЛЕЛЬНЫЙ ЭКСПОРТ ==========
            Write-Log "Режим: ПАРАЛЛЕЛЬНЫЙ ($NWC_PARALLEL потоков)"
            
            $fileGroups = @{}
            $groupIndex = 0
            foreach ($file in $rvtFilesForNwc) {
                $groupKey = $groupIndex % $NWC_PARALLEL
                if (-not $fileGroups.ContainsKey($groupKey)) {
                    $fileGroups[$groupKey] = @()
                }
                $fileGroups[$groupKey] += $file
                $groupIndex++
            }
            
            $jobs = @()
            
            foreach ($groupKey in $fileGroups.Keys) {
                $groupFiles = $fileGroups[$groupKey]
                $groupListPath = Join-Path $env:TEMP "nwc_group_${groupKey}_$([guid]::NewGuid().ToString('N')).txt"
                $groupNwdPath = Join-Path $env:TEMP "temp_nwd_${groupKey}_$([guid]::NewGuid().ToString('N')).nwd"
                $groupLogPath = Join-Path $LOG_FOLDER "Navisworks_group_${groupKey}_$timestamp.log"
                
                Set-Content -Path $groupListPath -Value $groupFiles -Encoding UTF8
                
                Write-Log "  Группа $($groupKey + 1): $($groupFiles.Count) файлов"
                
                $job = Start-Process -FilePath $NavisInfo.Path `
                    -ArgumentList "/i `"$groupListPath`" /of `"$groupNwdPath`" /log `"$groupLogPath`"" `
                    -PassThru -WindowStyle Hidden
                
                $jobs += @{
                    Process = $job
                    ListPath = $groupListPath
                    NwdPath = $groupNwdPath
                }
            }
            
            Write-Log "Ожидание завершения экспорта..."
            $completedCount = 0
            foreach ($job in $jobs) {
                $job.Process | Wait-Process
                $completedCount++
                Write-Log "  Завершено: $completedCount/$($jobs.Count)"
                
                if (Test-Path $job.ListPath) { Remove-Item $job.ListPath -Force -ErrorAction SilentlyContinue }
                if (Test-Path $job.NwdPath) { Remove-Item $job.NwdPath -Force -ErrorAction SilentlyContinue }
            }
            
        } else {
            # ========== ПОСЛЕДОВАТЕЛЬНЫЙ ЭКСПОРТ ==========
            Write-Log "Режим: ПОСЛЕДОВАТЕЛЬНЫЙ"
            
            $nwcListPath = Join-Path $env:TEMP "nwc_list_$([guid]::NewGuid().ToString('N')).txt"
            $rvtFilesForNwc | Set-Content -Path $nwcListPath -Encoding UTF8
            
            $nwcLogPath = Join-Path $LOG_FOLDER "Navisworks_$timestamp.log"
            $tempNwd = Join-Path $env:TEMP "temp_$([guid]::NewGuid().ToString('N')).nwd"
            
            Write-Log "Запуск Navisworks BatchUtility..."
            Start-Process -FilePath $NavisInfo.Path -ArgumentList "/i `"$nwcListPath`" /of `"$tempNwd`" /log `"$nwcLogPath`"" -Wait -NoNewWindow
            
            if (Test-Path $tempNwd) {
                Remove-Item $tempNwd -Force -ErrorAction SilentlyContinue
            }
            if (Test-Path $nwcListPath) { Remove-Item $nwcListPath -Force -ErrorAction SilentlyContinue }
        }
        
        $nwcElapsed = (Get-Date) - $startNwcTime
        Write-Log "Время экспорта NWC: $([math]::Round($nwcElapsed.TotalMinutes, 1)) мин"
        
        # Перемещение NWC файлов - только для очищенных моделей
        Write-Log "Перемещение NWC файлов..."
        $sourceForNwc = if ($ENABLE_CLEAN) { $OUTPUT_FOLDER } else { $DOWNLOAD_FOLDER }
        $movedCount = 0
        
        foreach ($cleanedFile in $script:CleanedFiles) {
            $baseName = [System.IO.Path]::GetFileNameWithoutExtension($cleanedFile)
            $nwcSourcePattern = Join-Path $sourceForNwc "$baseName*.nwc"
            
            Get-ChildItem -Path $nwcSourcePattern -ErrorAction SilentlyContinue | ForEach-Object {
                $destPath = Join-Path $NWC_FOLDER $_.Name
                try {
                    Move-Item -Path $_.FullName -Destination $destPath -Force
                    $NwcFiles += $destPath
                    $movedCount++
                } catch {}
            }
        }
        
        $script:Stats.NwcExported = $movedCount
        Write-Log "NWC экспортировано: $movedCount" -Level SUCCESS
        
    } finally {
        Restore-NavisworksRevitOptions -Version $NavisInfo.Version -Backup $backupOptions
    }
}

# ============================================================================
# ЭТАП 4: СБОРКА NWD
# ============================================================================

if ($ENABLE_NWD -and $NwcFiles.Count -gt 0 -and $NavisInfo) {
    Write-Log ""
    Write-Log "=" * 60 -Level STEP
    Write-Log "ЭТАП 4: СБОРКА NWD" -Level STEP
    Write-Log "=" * 60 -Level STEP
    
    $nwdPath = Join-Path $NWD_FOLDER $NWD_FILENAME
    
    # ВАЖНО: Удаляем старый NWD файл перед созданием нового
    if (Test-Path $nwdPath) {
        Write-Log "Удаление старого NWD: $nwdPath"
        Remove-Item $nwdPath -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
    }
    
    $nwdListPath = Join-Path $env:TEMP "nwd_list_$([guid]::NewGuid().ToString('N')).txt"
    $NwcFiles | Set-Content -Path $nwdListPath -Encoding UTF8
    $nwdLogPath = Join-Path $LOG_FOLDER "Navisworks_NWD_$timestamp.log"
    
    Write-Log "Сборка NWD из $($NwcFiles.Count) файлов..."
    Write-Log "  Выходной файл: $nwdPath"
    
    # Запускаем сборку NWD
    $nwdProcess = Start-Process -FilePath $NavisInfo.Path `
        -ArgumentList "/i `"$nwdListPath`" /of `"$nwdPath`" /log `"$nwdLogPath`"" `
        -Wait -NoNewWindow -PassThru
    
    # Проверка результата
    $nwdRetry = 0
    $nwdMaxRetry = 3
    
    while (-not (Test-Path $nwdPath) -and $nwdRetry -lt $nwdMaxRetry) {
        $nwdRetry++
        Write-Log "NWD не создан, повторная попытка $nwdRetry/$nwdMaxRetry..." -Level WARN
        Start-Sleep -Seconds 5
        
        # Повторный запуск
        Start-Process -FilePath $NavisInfo.Path `
            -ArgumentList "/i `"$nwdListPath`" /of `"$nwdPath`" /log `"$nwdLogPath`"" `
            -Wait -NoNewWindow
    }
    
    if (Test-Path $nwdPath) {
        $nwdSize = [math]::Round((Get-Item $nwdPath).Length / 1MB, 2)
        Write-Log "NWD создан: $nwdPath ($nwdSize MB)" -Level SUCCESS
    } else {
        Write-Log "ОШИБКА: NWD не создан после $nwdMaxRetry попыток!" -Level ERROR
        [void]$script:Stats.Errors.Add("Не удалось создать NWD: $nwdPath")
    }
    
    if (Test-Path $nwdListPath) { Remove-Item $nwdListPath -Force -ErrorAction SilentlyContinue }
}

# ============================================================================
# ФИНАЛИЗАЦИЯ: ВСЕГДА ВКЛЮЧАЕМ АДДИНЫ
# ============================================================================

Write-Log ""
Write-Log "=" * 60 -Level STEP
Write-Log "ФИНАЛИЗАЦИЯ" -Level STEP
Write-Log "=" * 60 -Level STEP

# ВАЖНО: Всегда включаем аддины, независимо от наличия других процессов Revit
if ($script:AddinsDisabled) {
    Write-Log "Восстановление аддинов Revit..."
    Start-Sleep -Seconds 2
    & cmd /c "`"$EnableAddins`" $RVT_VERSION"
    Write-Log "Аддины восстановлены" -Level SUCCESS
}

# ============================================================================
# ИТОГОВЫЙ ОТЧЕТ
# ============================================================================

$elapsed = (Get-Date) - $script:StartTime

Write-Log ""
Write-Log "=" * 60 -Level STEP
Write-Log "ИТОГОВЫЙ ОТЧЕТ" -Level STEP
Write-Log "=" * 60 -Level STEP
Write-Log ""
Write-Log "Скачано моделей:     $($script:Stats.Downloaded)"
Write-Log "Ошибок скачивания:   $($script:Stats.DownloadFailed)"
Write-Log "Очищено моделей:     $($script:Stats.Cleaned)"
Write-Log "Ошибок очистки:      $($script:Stats.CleanFailed)"
Write-Log "Экспортировано NWC:  $($script:Stats.NwcExported)"
Write-Log ""
Write-Log "Время выполнения:    $([math]::Round($elapsed.TotalMinutes, 1)) мин"
Write-Log "Лог-файл:            $($script:LogFile)"
Write-Log ""

if ($script:Stats.Errors.Count -gt 0) {
    Write-Log "ОШИБКИ:" -Level ERROR
    foreach ($err in $script:Stats.Errors) {
        Write-Log "  - $err" -Level ERROR
    }
}

$report = @{
    timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    duration_minutes = [math]::Round($elapsed.TotalMinutes, 2)
    settings = @{ rs_host = $RS_HOST; revit_version = $RVT_VERSION; source_folder = $RS_SOURCE_FOLDER }
    statistics = @{
        downloaded = $script:Stats.Downloaded
        download_failed = $script:Stats.DownloadFailed
        cleaned = $script:Stats.Cleaned
        clean_failed = $script:Stats.CleanFailed
        nwc_exported = $script:Stats.NwcExported
    }
    cleaned_files = $script:CleanedFiles
    errors = $script:Stats.Errors
} | ConvertTo-Json -Depth 5

$reportPath = Join-Path $LOG_FOLDER "report_$timestamp.json"
Set-Content -Path $reportPath -Value $report -Encoding UTF8

Remove-LockFile -Version $RVT_VERSION

$exitCode = 0
if ($script:Stats.DownloadFailed -gt 0 -or $script:Stats.CleanFailed -gt 0) { $exitCode = 1 }
exit $exitCode