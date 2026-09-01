param(
    [int]$TimeoutSeconds = 90
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$ProjectDir = Join-Path $RepoRoot "Qimiaoye_DarkForest_TextOnly_V0.1"
$GodotZip = Join-Path $RepoRoot "tools\godot\windows\Godot_v4.7.2-stable_win64.zip"
$GodotDir = Join-Path $RepoRoot ".qa-tools\godot-4.7.2"
$ResultDir = Join-Path $RepoRoot "qa-results"

if (-not (Test-Path -LiteralPath (Join-Path $ProjectDir "project.godot"))) {
    throw "Godot project not found: $ProjectDir"
}
if (-not (Test-Path -LiteralPath $GodotZip)) {
    throw "Bundled Godot 4.7.2 zip not found: $GodotZip"
}

New-Item -ItemType Directory -Force -Path $GodotDir | Out-Null
New-Item -ItemType Directory -Force -Path $ResultDir | Out-Null

$GodotExe = Get-ChildItem -LiteralPath $GodotDir -Filter "Godot*.exe" -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $GodotExe) {
    Write-Host "Extracting bundled Godot 4.7.2..." -ForegroundColor Cyan
    Expand-Archive -LiteralPath $GodotZip -DestinationPath $GodotDir -Force
    $GodotExe = Get-ChildItem -LiteralPath $GodotDir -Filter "Godot*.exe" -File -Recurse | Select-Object -First 1
}
if (-not $GodotExe) { throw "Godot executable not found after extraction." }

$checks = @(
    @{ Name = "opening";  Scene = "res://scenes/opening/opening.tscn"; Args = @("--verify") },
    @{ Name = "wedding";  Scene = "res://scenes/wedding/wedding_prologue.tscn"; Args = @("--verify") },
    @{ Name = "mystic";   Scene = "res://scenes/mystic_night/mystic_night.tscn"; Args = @("--verify") },
    @{ Name = "forest";   Scene = "res://main.tscn"; Args = @("--verify") },
    @{ Name = "chapter3-A"; Scene = "res://scenes/chapter3/chapter3.tscn"; Args = @("--verify", "--choice=A") },
    @{ Name = "chapter3-B"; Scene = "res://scenes/chapter3/chapter3.tscn"; Args = @("--verify", "--choice=B") },
    @{ Name = "chapter3-C"; Scene = "res://scenes/chapter3/chapter3.tscn"; Args = @("--verify", "--choice=C") }
)

$results = @()
foreach ($check in $checks) {
    $stdout = Join-Path $ResultDir ($check.Name + ".stdout.log")
    $stderr = Join-Path $ResultDir ($check.Name + ".stderr.log")
    Remove-Item $stdout, $stderr -Force -ErrorAction SilentlyContinue

    $argList = @(
        "--headless",
        "--path", ('"' + $ProjectDir + '"'),
        "--scene", $check.Scene,
        "--"
    ) + $check.Args

    Write-Host ("QA {0} ..." -f $check.Name) -ForegroundColor Cyan
    $process = Start-Process -FilePath $GodotExe.FullName -ArgumentList $argList -PassThru -NoNewWindow `
        -RedirectStandardOutput $stdout -RedirectStandardError $stderr

    $finished = $process.WaitForExit($TimeoutSeconds * 1000)
    if (-not $finished) {
        try { $process.Kill() } catch {}
        $status = "TIMEOUT"
        $exitCode = $null
    } else {
        $exitCode = $process.ExitCode
        $status = if ($exitCode -eq 0) { "PASS" } else { "FAIL" }
    }

    $results += [pscustomobject]@{
        Check = $check.Name
        Status = $status
        ExitCode = $exitCode
        Stdout = $stdout
        Stderr = $stderr
    }
}

$results | Format-Table -AutoSize
$csv = Join-Path $ResultDir "summary.csv"
$results | Export-Csv -Path $csv -NoTypeInformation -Encoding UTF8

$failed = @($results | Where-Object { $_.Status -ne "PASS" })
if ($failed.Count -gt 0) {
    Write-Host "QA FAILED. Inspect qa-results/*.log. A TIMEOUT is treated as a blocking bug." -ForegroundColor Red
    exit 1
}

Write-Host "QA PASS: all chapter verification entry points returned exit code 0." -ForegroundColor Green
Write-Host "Note: Forest --verify validates story/module contracts and simulates module completion; it does not replace a manual physics/gameplay playthrough." -ForegroundColor Yellow
exit 0
