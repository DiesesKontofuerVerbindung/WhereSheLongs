param(
    [switch]$InstallInnoSetup
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$GameExe = Join-Path $RepoRoot "releases\windows\Where She Longs.exe"
$InstallerScript = Join-Path $PSScriptRoot "WhereSheLongs.iss"

function Assert-RealGameExe {
    if (-not (Test-Path -LiteralPath $GameExe)) {
        throw "Game EXE not found: $GameExe"
    }

    $item = Get-Item -LiteralPath $GameExe
    if ($item.Length -lt 100MB) {
        $head = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($GameExe)[0..([Math]::Min(255, [int]$item.Length - 1))])
        if ($head -match "git-lfs.github.com/spec/v1") {
            throw "Where She Longs.exe is only a Git LFS pointer. Run 'git lfs pull' before building the installer."
        }
        throw "Where She Longs.exe is unexpectedly small ($($item.Length) bytes). Refusing to package it."
    }

    Write-Host ("OK: real game EXE found ({0:N2} GiB)" -f ($item.Length / 1GB)) -ForegroundColor Green
}

function Find-Iscc {
    $command = Get-Command ISCC.exe -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }

    $candidates = @(
        "$env:ProgramFiles\Inno Setup 7\ISCC.exe",
        "${env:ProgramFiles(x86)}\Inno Setup 7\ISCC.exe",
        "$env:LOCALAPPDATA\Programs\Inno Setup 7\ISCC.exe",
        "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
        "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }

    return $candidates | Select-Object -First 1
}

Assert-RealGameExe

$iscc = Find-Iscc
if (-not $iscc -and $InstallInnoSetup) {
    if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
        throw "winget is unavailable. Install Inno Setup 7 manually, then rerun this script."
    }
    Write-Host "Installing Inno Setup 7.1+ with winget..." -ForegroundColor Cyan
    & winget install --id JRSoftware.InnoSetup.7 -e -s winget --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) { throw "winget failed with exit code $LASTEXITCODE" }
    $iscc = Find-Iscc
}

if (-not $iscc) {
    throw "Inno Setup compiler (ISCC.exe) not found. Install Inno Setup 7, or rerun with -InstallInnoSetup."
}

Write-Host "Compiler: $iscc" -ForegroundColor Cyan
Write-Host "Building offline installer..." -ForegroundColor Cyan
& $iscc $InstallerScript
if ($LASTEXITCODE -ne 0) {
    throw "Inno Setup compilation failed with exit code $LASTEXITCODE"
}

$output = Join-Path $RepoRoot "dist\windows\WhereSheLongs-Setup-1.3.17.exe"
if (-not (Test-Path -LiteralPath $output)) {
    throw "Compiler returned success but installer was not found at: $output"
}

$item = Get-Item -LiteralPath $output
Write-Host ("DONE: {0} ({1:N2} GiB)" -f $output, ($item.Length / 1GB)) -ForegroundColor Green
Write-Host "This Setup EXE is self-contained and does not download game files during installation." -ForegroundColor Green
