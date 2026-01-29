param(
  [Parameter(Mandatory = $true)][string]$Server,     # IP Revit Server
  [Parameter(Mandatory = $true)][int]$Version,       # 2024
  [Parameter(Mandatory = $true)][string]$OutFile,    # C:\Temp\RevitServerModels.txt
  [string]$StartPath = "|",                          # "|" или "|Project|Subfolder"
  [switch]$Https
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$scheme = $(if ($Https) { "https" } else { "http" })
$base = "${scheme}://$Server/RevitServerAdminRESTService$Version/AdminRESTService.svc"

$headers = @{
  "User-Name"         = $env:USERNAME
  "User-Machine-Name" = $env:COMPUTERNAME
  "Operation-GUID"    = ([guid]::NewGuid().ToString())
  "Accept"            = "application/json"
}

function ConvertTo-RsPath([string]$p) {
  if ([string]::IsNullOrWhiteSpace($p)) { return "|" }
  $p = $p.Trim()
  if ($p -notlike "|*") { $p = "|" + $p }
  $p = $p.TrimEnd("|")
  if ($p.Length -eq 0) { $p = "|" }
  return $p
}

function Get-ContentsJson([string]$rsPath) {
  $rsPath = ConvertTo-RsPath $rsPath
  $uri = "$base/$rsPath/Contents"

  try {
    return Invoke-RestMethod -Method Get -Uri $uri -Headers $headers
  }
  catch {
    $resp = $_.Exception.Response
    if ($null -eq $resp) { throw }

    $stream = $resp.GetResponseStream()
    if ($null -eq $stream) { throw }

    $reader = New-Object System.IO.StreamReader($stream)
    $body = $reader.ReadToEnd()

    if ([string]::IsNullOrWhiteSpace($body)) { throw }
    return ($body | ConvertFrom-Json)
  }
}

function Add-ModelLine([string]$rsFolderPath, $modelObj) {
  $name = $null
  if ($modelObj -is [string]) { $name = $modelObj }
  elseif ($null -ne $modelObj.Name) { $name = [string]$modelObj.Name }

  if ([string]::IsNullOrWhiteSpace($name)) { return }
  if ($name.ToLower().EndsWith(".rvt") -eq $false) { return }

  $full = "$(ConvertTo-RsPath $rsFolderPath)|$name"
  Add-Content -Path $OutFile -Value $full -Encoding UTF8
}

function Walk([string]$rsPath) {
  $rsPath = ConvertTo-RsPath $rsPath
  $j = Get-ContentsJson $rsPath

  if ($null -ne $j.Models) {
    foreach ($m in $j.Models) { Add-ModelLine $rsPath $m }
  }

  if ($null -ne $j.Folders) {
    foreach ($f in $j.Folders) {
      $fname = $null
      if ($f -is [string]) { $fname = $f }
      elseif ($null -ne $f.Name) { $fname = [string]$f.Name }
      if ([string]::IsNullOrWhiteSpace($fname)) { continue }

      Walk "$rsPath|$fname"
    }
  }
}

# --- START ---
$StartPath = ConvertTo-RsPath $StartPath
Remove-Item $OutFile -ErrorAction SilentlyContinue

Walk $StartPath
