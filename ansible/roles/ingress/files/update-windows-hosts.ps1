param(
    [Parameter(Mandatory = $true)]
    [string]$Names
)

$ErrorActionPreference = "Stop"
$hostnames = @($Names -split ",")
$hostsPath = Join-Path $env:WINDIR "System32\drivers\etc\hosts"
$addresses = @{}

foreach ($line in Get-Content -LiteralPath $hostsPath) {
    $content = ($line -split "#", 2)[0].Trim()
    if (-not $content) {
        continue
    }

    $parts = $content -split "\s+"
    if ($parts.Count -lt 2) {
        continue
    }

    $address = $parts[0]
    foreach ($alias in $parts | Select-Object -Skip 1) {
        $key = $alias.ToLowerInvariant()
        if (-not $addresses.ContainsKey($key)) {
            $addresses[$key] = @()
        }
        $addresses[$key] += $address
    }
}

$conflicts = @(
    foreach ($name in $hostnames) {
        $key = $name.ToLowerInvariant()
        if ($addresses.ContainsKey($key) -and
            @($addresses[$key] | Where-Object { $_ -ne "127.0.0.1" }).Count -gt 0) {
            $name
        }
    }
)
if ($conflicts.Count -gt 0) {
    throw "В Windows hosts уже есть другие адреса для: $($conflicts -join ', '). Исправьте записи вручную."
}

$missing = @(
    foreach ($name in $hostnames) {
        $key = $name.ToLowerInvariant()
        if (-not $addresses.ContainsKey($key) -or
            "127.0.0.1" -notin $addresses[$key]) {
            $name
        }
    }
)
if ($missing.Count -eq 0) {
    Write-Output "Все имена *.local уже сопоставлены с 127.0.0.1 в Windows hosts."
    exit 0
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
$isAdministrator = $principal.IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)

if (-not $isAdministrator) {
    $arguments = @(
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        "`"$PSCommandPath`"",
        "-Names",
        ($hostnames -join ",")
    )
    $process = Start-Process -FilePath "powershell.exe" `
        -Verb RunAs -Wait -PassThru -ArgumentList $arguments
    if ($process.ExitCode -ne 0) {
        throw "Не удалось обновить Windows hosts (код $($process.ExitCode))."
    }
    exit 0
}

$prefix = ""
$existing = [System.IO.File]::ReadAllText($hostsPath)
if ($existing.Length -gt 0 -and -not $existing.EndsWith("`n")) {
    $prefix = [Environment]::NewLine
}
$entry = "127.0.0.1 " + ($missing -join " ") + [Environment]::NewLine
[System.IO.File]::AppendAllText(
    $hostsPath,
    $prefix + $entry,
    [System.Text.Encoding]::ASCII
)
Write-Output "Добавлены имена в Windows hosts: $($missing -join ', ')"
