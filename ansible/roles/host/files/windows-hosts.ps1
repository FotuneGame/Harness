# Записывает в начало hosts Windows блок "127.0.0.1 <имена>" между маркерами
# "# BEGIN platform" и "# END platform". Права администратора запрашиваются
# через UAC только при изменении файла.
param(
    [Parameter(Mandatory = $true)]
    [string]$Names
)

$ErrorActionPreference = "Stop"
$path = Join-Path $env:WINDIR "System32\drivers\etc\hosts"
$begin = "# BEGIN platform"
$end = "# END platform"

$inside = $false
$kept = foreach ($line in Get-Content -LiteralPath $path) {
    if ($line -eq $begin) { $inside = $true; continue }
    if ($line -eq $end) { $inside = $false; continue }
    if (-not $inside) { $line }
}
$content = @($begin, "127.0.0.1 $($Names -replace ',', ' ')", $end) + @($kept)

if (((Get-Content -LiteralPath $path) -join "`n") -eq ($content -join "`n")) {
    Write-Output "unchanged"
    exit 0
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin = ([Security.Principal.WindowsPrincipal]$identity).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Names $Names"
    $process = Start-Process powershell.exe -Verb RunAs -Wait -PassThru -ArgumentList $arguments
    if ($process.ExitCode -ne 0) { throw "Failed to update Windows hosts (exit code $($process.ExitCode))" }
    Write-Output "updated"
    exit 0
}

Set-Content -LiteralPath $path -Value $content -Encoding ASCII
Write-Output "updated"
