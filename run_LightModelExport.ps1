Param(
    [string]$ConfigPath = "$(Split-Path -Parent $MyInvocation.MyCommand.Path)\config.json",
    [string]$AddinVersionOut = ""
)

$ErrorActionPreference = "Stop"

function Normalize-SourceFolder([string]$Folder) {
    if ([string]::IsNullOrWhiteSpace($Folder)) { return "" }
    $s = $Folder.Trim()
    if ($s.StartsWith("RSN://", [System.StringComparison]::OrdinalIgnoreCase)) {
        return $s.TrimEnd("/")
    }
    if ($s -eq "|") { return "" }
    $s = $s -replace "[/\\]", "|"
    $s = $s.Trim("|")
    return $s
}

function Normalize-Model([string]$Model) {
    if ([string]::IsNullOrWhiteSpace($Model)) { return "" }
    $m = $Model.Trim()
    # Decode percent-encoded Cyrillic if present
    $m = Decode-Percent $m
    if ($m.StartsWith("RSN://", [System.StringComparison]::OrdinalIgnoreCase)) {
        return $m
    }
    return $m.TrimStart("|").TrimEnd("|")
}

function Get-ServerFromRsn([string]$RsnPath) {
    # RSN://server/...
    $uri = [Uri]$RsnPath
    return $uri.Host
}

function Get-RelFromRsn([string]$RsnPath) {
    $uri = [Uri]$RsnPath
    return $uri.AbsolutePath.TrimStart("/")
}

function Join-LocalPath([string]$Root, [string]$RelPath) {
    $parts = $RelPath -split "/"
    $p = $Root
    foreach ($part in $parts) {
        if ($part -ne "") { $p = Join-Path -Path $p -ChildPath $part }
    }
    return $p
}

function Decode-Percent([string]$Text) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return $Text }
    $prev = $Text
    for ($i = 0; $i -lt 2; $i++) {
        $dec = [System.Uri]::UnescapeDataString($prev)
        if ($dec -eq $prev) { break }
        $prev = $dec
    }
    return $prev
}

function Convert-ToRsPath([string]$RelPath) {
    if ([string]::IsNullOrWhiteSpace($RelPath)) { return "|" }
    $p = $RelPath -replace "[/\\]", "|"
    $p = $p.Trim("|")
    if ($p.Length -eq 0) { return "|" }
    return "|" + $p
}

function Get-RsnPathsFromServer([string]$Server, [int]$Version, [string]$StartPath, [string]$ListScriptPath) {
    if (-not (Test-Path $ListScriptPath)) { throw "List script not found: $ListScriptPath" }
    $tmp = Join-Path -Path $env:TEMP -ChildPath ("RevitServerModels_{0}.txt" -f ([guid]::NewGuid().ToString("N")))
    $sb = [ScriptBlock]::Create((Get-Content -Raw -Path $ListScriptPath))
    & $sb -Server $Server -Version $Version -OutFile $tmp -StartPath $StartPath
    if (-not (Test-Path $tmp)) { throw "List script did not produce output: $tmp" }
    $lines = Get-Content -Path $tmp -Encoding UTF8 | Where-Object { $_ -and $_.Trim() -ne "" }
    Remove-Item -Path $tmp -Force -ErrorAction SilentlyContinue

    $rsn = @()
    foreach ($line in $lines) {
        $decoded = Decode-Percent $line.Trim()
        $rel = $decoded.Trim().TrimStart("|")
        if ([string]::IsNullOrWhiteSpace($rel)) { continue }
        $rsn += ("RSN://{0}/{1}" -f $Server, $rel.Replace("|","/"))
    }
    return $rsn
}

if (-not (Test-Path $ConfigPath)) {
    throw "Config not found: $ConfigPath"
}

$cfg = Get-Content -Path $ConfigPath -Encoding UTF8 | ConvertFrom-Json
$rsHostDefault = $cfg.RS_HOST
$sourceFolder = Normalize-SourceFolder $cfg.source_folder
$downloadFolder = $cfg.download_folder
$outputFolder = $cfg.output_folder
$revitVersion = "$($cfg.revit_version)".Trim()
$models = @()
if ($cfg.models) { $models = @($cfg.models) }

if ([string]::IsNullOrWhiteSpace($revitVersion)) {
    throw "revit_version is required in config.json"
}
if ([string]::IsNullOrWhiteSpace($downloadFolder)) {
    throw "download_folder is required in config.json"
}

$rsnPaths = @()
if ($models.Count -eq 0) {
    $listScript = Join-Path -Path (Split-Path -Parent $MyInvocation.MyCommand.Path) -ChildPath "ListRevitServerModels.ps1"
    $verInt = [int]$revitVersion
    if ($sourceFolder.StartsWith("RSN://", [System.StringComparison]::OrdinalIgnoreCase)) {
        $rsHost = Get-ServerFromRsn $sourceFolder
        $rel = Get-RelFromRsn $sourceFolder
        $startPath = Convert-ToRsPath $rel
    } else {
        if (-not $rsHostDefault) { throw "RS_HOST is required when source_folder is not RSN://..." }
        $rsHost = $rsHostDefault
        $startPath = Convert-ToRsPath $sourceFolder
    }
    $rsnPaths = Get-RsnPathsFromServer -Server $rsHost -Version $verInt -StartPath $startPath -ListScriptPath $listScript
    if ($rsnPaths.Count -eq 0) {
        throw "No models found on Revit Server for source_folder: $($cfg.source_folder)"
    }
}

foreach ($m in $models) {
    $nm = Normalize-Model $m
    if ([string]::IsNullOrWhiteSpace($nm)) { continue }
    if ($nm.StartsWith("RSN://", [System.StringComparison]::OrdinalIgnoreCase)) {
        $rsnPaths += $nm
    } else {
        if ($sourceFolder.StartsWith("RSN://", [System.StringComparison]::OrdinalIgnoreCase)) {
            $rsnPaths += ($sourceFolder.TrimEnd("/") + "/" + $nm.TrimStart("/"))
        } elseif ([string]::IsNullOrWhiteSpace($sourceFolder)) {
            # treat model as relative path like Project/Folder/Model.rvt
            if (-not $rsHostDefault) { throw "RS_HOST is required when source_folder is not RSN://..." }
            $rsnPaths += ("RSN://{0}/{1}" -f $rsHostDefault, $nm.Replace("|","/"))
        } else {
            if (-not $rsHostDefault) { throw "RS_HOST is required when source_folder is not RSN://..." }
            $rel = ($sourceFolder + "|" + $nm).Replace("|","/")
            $rsnPaths += ("RSN://{0}/{1}" -f $rsHostDefault, $rel)
        }
    }
}

if ($rsnPaths.Count -eq 0) {
    throw "No RSN paths resolved from config.json"
}

$rst = "C:\Program Files\Autodesk\Revit $revitVersion\RevitServerToolCommand\RevitServerTool.exe"
$rbp = "$env:LOCALAPPDATA\RevitBatchProcessor\BatchRvt.exe"
$taskScript = Join-Path -Path (Split-Path -Parent $MyInvocation.MyCommand.Path) -ChildPath "clean_model.py"
$logFolder = Join-Path -Path (Split-Path -Parent $MyInvocation.MyCommand.Path) -ChildPath "PROJECT\Scripts\BatchRvtLogs"
$rbpRunLog = Join-Path -Path (Split-Path -Parent $MyInvocation.MyCommand.Path) -ChildPath ("PROJECT\Scripts\BatchRvt_run_{0}.log" -f $revitVersion)

if ($AddinVersionOut) {
    Set-Content -Path $AddinVersionOut -Value $revitVersion -Encoding ASCII
}

if (-not (Test-Path $rst)) { throw "RevitServerTool.exe not found: $rst" }
if (-not (Test-Path $rbp)) { throw "BatchRvt.exe not found: $rbp" }
if (-not (Test-Path $taskScript)) { throw "Task script not found: $taskScript" }
New-Item -ItemType Directory -Path $logFolder -Force | Out-Null

$localFiles = @()
foreach ($rsn in $rsnPaths) {
    $rsHost = Get-ServerFromRsn $rsn
    $rel = Get-RelFromRsn $rsn
    $rel = Decode-Percent $rel
    $fileName = Split-Path -Leaf $rel
    $localPath = Join-Path -Path $downloadFolder -ChildPath $fileName
    if (-not (Test-Path $downloadFolder)) { New-Item -ItemType Directory -Path $downloadFolder -Force | Out-Null }
    & $rst L $rel -s $rsHost -d $localPath -o | Out-Null
    $localFiles += $localPath
}

$tmpList = Join-Path -Path $env:TEMP -ChildPath ("BatchRvt_list_{0}.txt" -f ([guid]::NewGuid().ToString("N")))
Set-Content -Path $tmpList -Value $localFiles -Encoding UTF8

$env:CLEAN_CONFIG = $ConfigPath
if ($outputFolder) { $env:RBP_OUTPUT = $outputFolder }

& $rbp --task_script $taskScript --file_list $tmpList --revit_version $revitVersion --audit --log_folder $logFolder *> $rbpRunLog
Get-Content -Path $rbpRunLog

Remove-Item -Path $tmpList -Force -ErrorAction SilentlyContinue

