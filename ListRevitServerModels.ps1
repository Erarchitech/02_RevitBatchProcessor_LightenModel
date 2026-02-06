#Requires -Version 5.1
<#
.SYNOPSIS
    Получение списка моделей с Revit Server
#>

param(
    [Parameter(Mandatory)][string]$Server,
    [Parameter(Mandatory)][int]$Version,
    [Parameter(Mandatory)][string]$OutFile,
    [string]$StartPath = "|",
    [switch]$Https,
    [int]$Timeout = 30
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$scheme = if ($Https) { "https" } else { "http" }
$baseUrl = "${scheme}://${Server}/RevitServerAdminRESTService${Version}/AdminRESTService.svc"

$headers = @{
    "User-Name"         = $env:USERNAME
    "User-Machine-Name" = $env:COMPUTERNAME
    "Operation-GUID"    = ([guid]::NewGuid().ToString())
    "Accept"            = "application/json"
}

$script:Models = @()
$script:Errors = 0

function Normalize-RsPath([string]$p) {
    if ([string]::IsNullOrWhiteSpace($p)) { return "|" }
    $p = $p.Trim()
    if ($p -notlike "|*") { $p = "|" + $p }
    $p = $p.TrimEnd("|")
    if ($p.Length -eq 0) { $p = "|" }
    return $p
}

function Get-Contents([string]$rsPath) {
    $uri = "$baseUrl/$rsPath/Contents"
    try {
        return Invoke-RestMethod -Method Get -Uri $uri -Headers $headers -TimeoutSec $Timeout
    } catch {
        throw "API Error: $($_.Exception.Message)"
    }
}

function Walk([string]$rsPath) {
    $rsPath = Normalize-RsPath $rsPath
    
    try {
        $contents = Get-Contents $rsPath
    } catch {
        Write-Warning "Failed: $rsPath - $($_.Exception.Message)"
        $script:Errors++
        return
    }
    
    # Модели
    if ($contents.Models) {
        foreach ($m in $contents.Models) {
            $name = if ($m -is [string]) { $m } else { $m.Name }
            if ($name -and $name.ToLower().EndsWith(".rvt")) {
                $fullPath = "$(Normalize-RsPath $rsPath)|$name"
                $script:Models += $fullPath
            }
        }
    }
    
    # Подпапки
    if ($contents.Folders) {
        foreach ($f in $contents.Folders) {
            $fname = if ($f -is [string]) { $f } else { $f.Name }
            if ($fname) {
                $subPath = if ($rsPath -eq "|") { "|$fname" } else { "$rsPath|$fname" }
                Walk $subPath
            }
        }
    }
}

# Проверка подключения
Write-Host "Connecting to $Server..."
try {
    $null = Get-Contents (Normalize-RsPath $StartPath)
} catch {
    Write-Error "Cannot connect: $($_.Exception.Message)"
    exit 1
}

# Обход
Write-Host "Scanning..."
Walk (Normalize-RsPath $StartPath)

# Сохранение
$outDir = Split-Path -Parent $OutFile
if ($outDir -and -not (Test-Path $outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}

if (Test-Path $OutFile) { Remove-Item $OutFile -Force }

if ($script:Models.Count -gt 0) {
    Set-Content -Path $OutFile -Value $script:Models -Encoding UTF8
}

Write-Host "Found: $($script:Models.Count) models"
if ($script:Errors -gt 0) {
    Write-Warning "Errors: $script:Errors"
}