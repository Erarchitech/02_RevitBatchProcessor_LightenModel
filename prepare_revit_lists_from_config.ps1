Param(
    [Parameter(Mandatory = $true)][string]$Config,
    [Parameter(Mandatory = $true)][string]$DownloadFolder,
    [Parameter(Mandatory = $true)][string]$List,
    [Parameter(Mandatory = $true)][string]$DownloadList,
    [Parameter(Mandatory = $true)][string]$Env
)

$ErrorActionPreference = "Stop"

function Normalize-SourceFolder([string]$Folder) {
    if ([string]::IsNullOrWhiteSpace($Folder)) { return "" }
    $s = $Folder.Trim()
    if ($s -eq "|") { return "" }
    $s = $s -replace "[/\\]", "|"
    $s = $s.Trim("|")
    return $s
}

function Normalize-ModelPath([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return "" }
    $s = $Path.Trim()
    $s = $s -replace "[/\\]", "|"
    $s = $s.Trim("|")
    return $s
}

function Join-SourceAndModel([string]$SourceFolder, [string]$Model) {
    $m = Normalize-ModelPath $Model
    if ([string]::IsNullOrWhiteSpace($m)) { return "" }
    if ($m.Contains("|")) { return $m }
    if ([string]::IsNullOrWhiteSpace($SourceFolder)) { return $m }
    return "$SourceFolder|$m"
}

function Get-RSContent([string]$BaseUrl, [string]$FolderToken) {
    $url = "$BaseUrl$FolderToken/contents"
    $headers = @{
        "User-Name" = $env:USERNAME
        "User-Machine-Name" = $env:COMPUTERNAME
        "Operation-GUID" = [guid]::NewGuid().ToString()
    }
    return Invoke-RestMethod -Uri $url -Headers $headers -Method Get
}

function Get-RSModels([string]$Host, [string]$Version, [string]$SourceFolder) {
    $base = "http://$Host/RevitServerAdminRESTService$Version/AdminRESTService.svc/"
    $root = if ([string]::IsNullOrWhiteSpace($SourceFolder)) { "|" } else { "|" + $SourceFolder }
    $results = New-Object System.Collections.Generic.List[string]

    function Walk([string]$FolderToken) {
        $data = Get-RSContent -BaseUrl $base -FolderToken $FolderToken
        foreach ($model in $data.Models) {
            $name = $model.Name
            if ([string]::IsNullOrWhiteSpace($name)) { continue }
            $rel = if ($FolderToken -eq "|") { $name } else { ($FolderToken.Trim("|") + "|" + $name) }
            $results.Add($rel)
        }
        foreach ($folder in $data.Folders) {
            $fname = $folder.Name
            if ([string]::IsNullOrWhiteSpace($fname)) { continue }
            $next = if ($FolderToken -eq "|") { "|" + $fname } else { $FolderToken + "|" + $fname }
            Walk $next
        }
    }

    Walk $root
    return $results
}

function Write-Lines([string]$Path, [string[]]$Lines) {
    $dir = Split-Path -Parent $Path
    if ($dir) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Set-Content -Path $Path -Value $Lines -Encoding UTF8
}

function Write-Env([string]$Path, [hashtable]$Values) {
    $dir = Split-Path -Parent $Path
    if ($dir) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $lines = @()
    foreach ($k in $Values.Keys) {
        $v = $Values[$k]
        if ($null -ne $v -and "$v" -ne "") {
            $lines += "set $k=$v"
        }
    }
    Set-Content -Path $Path -Value $lines -Encoding ASCII
}

$cfg = Get-Content -Path $Config -Encoding UTF8 | ConvertFrom-Json
$rsHost = $cfg.RS_HOST
$revitVersion = "$($cfg.revit_version)".Trim()
$sourceFolder = Normalize-SourceFolder $cfg.source_folder
$outputFolder = $cfg.output_folder
$downloadFolder = if ($cfg.download_folder) { $cfg.download_folder } else { $DownloadFolder }

$models = @()
if ($cfg.models) { $models = @($cfg.models) }

$relModels = @()
if ($models.Count -gt 0) {
    foreach ($m in $models) {
        $rel = Join-SourceAndModel -SourceFolder $sourceFolder -Model $m
        if ($rel) { $relModels += $rel }
    }
} elseif ($rsHost -and $revitVersion) {
    try {
        $relModels = Get-RSModels -Host $rsHost -Version $revitVersion -SourceFolder $sourceFolder
    } catch {
        Write-Output ("ERROR: Revit Server listing failed: {0}" -f $_.Exception.Message)
        $relModels = @()
    }
}

if ($relModels.Count -eq 0) {
    Write-Output "ERROR: no models resolved from config"
    Write-Lines -Path $List -Lines @()
    Write-Lines -Path $DownloadList -Lines @()
    Write-Env -Path $Env -Values @{
        RS_HOST = $rsHost
        RVT_VERSION = $revitVersion
        RS_SOURCE_FOLDER = $sourceFolder
        DOWNLOAD_FOLDER = $downloadFolder
        RBP_OUTPUT = $outputFolder
    }
    exit 2
}

$localList = @()
$downloadList = @()
foreach ($rel in $relModels) {
    $serverPath = ($rel -replace "\|", "\")
    $parts = $rel.Split("|")
    $localPath = $downloadFolder
    foreach ($p in $parts) {
        if ($p -ne "") {
            $localPath = Join-Path -Path $localPath -ChildPath $p
        }
    }
    $localList += $localPath
    $downloadList += ("{0}|{1}" -f $serverPath, $localPath)
}

Write-Lines -Path $List -Lines $localList
Write-Lines -Path $DownloadList -Lines $downloadList
Write-Env -Path $Env -Values @{
    RS_HOST = $rsHost
    RVT_VERSION = $revitVersion
    RS_SOURCE_FOLDER = $sourceFolder
    DOWNLOAD_FOLDER = $downloadFolder
    RBP_OUTPUT = $outputFolder
}

Write-Output ("Models resolved: {0}" -f $localList.Count)
