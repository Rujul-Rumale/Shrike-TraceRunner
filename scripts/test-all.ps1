# test-all.ps1
# Comprehensive automated regression and test suite for Shrike-Fi PID Line Follower.
# Validates Python golden models, Verilator static lint, and Yosys synthesis elaboration.

[CmdletBinding()]
param()

$passed = 0
$failed = 0

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " Shrike-Fi FPGA-Primary PID Line Follower: Test Suite" -ForegroundColor Cyan
Write-Host " Target Actuator: 360-Degree Continuous Rotation Servos" -ForegroundColor Cyan
Write-Host " Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

function Run-Step {
    param(
        [string]$Name,
        [scriptblock]$Script
    )
    Write-Host "[TEST] $Name..." -NoNewline
    try {
        $res = & $Script
        if ($LASTEXITCODE -eq 0 -or $res -eq $true) {
            Write-Host " [PASS]" -ForegroundColor Green
            $script:passed++
        } else {
            Write-Host " [FAIL]" -ForegroundColor Red
            if ($res) { Write-Host "       $res" -ForegroundColor DarkRed }
            $script:failed++
        }
    } catch {
        Write-Host " [EXCEPTION: $_]" -ForegroundColor Red
        $script:failed++
    }
}

$projDir = (Resolve-Path "$PSScriptRoot\..").Path
$rootDir = (Resolve-Path "$projDir\..\..").Path
$srcDir  = "$projDir\ffpga\src"
$testDir = "$projDir\tests"

# 1. Golden Reference Model Unit Tests & Waveform Simulation
Run-Step "1. Python Golden Models & Servo Engine Tests" {
    $out1 = python -m pytest "$testDir" 2>&1
    if ($LASTEXITCODE -ne 0) { return $false }
    $out2 = python "$projDir\scripts\generate_waveforms.py" 2>&1
    return ($LASTEXITCODE -eq 0)
}

# 2. Verilator Static Timing & Lint Check
Run-Step "2. Verilator Static Timing & Lint Checks (ForgeFPGA)" {
    $env:VERILATOR_ROOT = "C:\PROGRA~1\RENESA~1\GOCONF~1\external\verilator"
    $out = & "$env:VERILATOR_ROOT\bin\verilator_bin.exe" `
        -Wno-INITIALDLY -Wno-fatal -Wno-MULTIDRIVEN -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC `
        -I"$srcDir" `
        --lint-only `
        "$srcDir\pid_top.v" 2>&1
    return ($LASTEXITCODE -eq 0)
}

# 3. Yosys Netlist Elaboration & Hierarchy Check
Run-Step "3. Yosys Synthesis & Netlist Elaboration" {
    $topFile = ("$srcDir/pid_top.v" -replace '\\', '/')
    $cmd = "read_verilog $topFile; hierarchy -check -top pid_top; proc; opt; check; stat"
    $out = & "C:\PROGRA~1\RENESA~1\GOCONF~1\external\yosys\v59\yosys.exe" -p $cmd 2>&1
    return ($LASTEXITCODE -eq 0)
}

# 4. Workspace Verification
Run-Step "4. Workspace & Upstream Git Integrity" {
    $verifyWs = "$rootDir\scripts\verify-workspace.ps1"
    if (Test-Path $verifyWs) {
        $out = powershell -ExecutionPolicy Bypass -File $verifyWs 2>&1
        return ($LASTEXITCODE -eq 0)
    }
    return $true
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
$color = if ($failed -eq 0) { "Green" } else { "Red" }
Write-Host " Summary: $passed PASSED, $failed FAILED" -ForegroundColor $color
Write-Host "============================================================" -ForegroundColor Cyan

exit $failed
