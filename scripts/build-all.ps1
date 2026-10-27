# build-all.ps1
# Master build script for Vicharak Shrike-Fi FPGA-Primary PID Line Follower.

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " Building Shrike-Fi PID Line Follower (FPGA + MCU)" -ForegroundColor Cyan
Write-Host " Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

$projDir = (Resolve-Path "$PSScriptRoot\..").Path
$rootDir = (Resolve-Path "$projDir\..\..").Path
$srcDir  = "$projDir\ffpga\src"

# Step 1: RTL Lint & Timing Check
Write-Host "[1/3] Running Verilator Static Timing & Lint Checks..." -ForegroundColor Yellow
$env:VERILATOR_ROOT = "C:\PROGRA~1\RENESA~1\GOCONF~1\external\verilator"
& "$env:VERILATOR_ROOT\bin\verilator_bin.exe" `
    -Wno-INITIALDLY -Wno-fatal `
    -I"$srcDir" `
    --lint-only --timing `
    "$srcDir\pid_top.v"
if ($LASTEXITCODE -ne 0) {
    Write-Host "Verilator check failed!" -ForegroundColor Red
    exit 1
}
Write-Host "  -> Verilator checks PASSED." -ForegroundColor Green

# Step 2: Yosys Synthesis & Netlist Check
Write-Host "[2/3] Running Yosys Elaboration & Netlist Verification..." -ForegroundColor Yellow
$srcs = @(
    "$srcDir/spi_target.v",
    "$srcDir/line_position_encoder.v",
    "$srcDir/pid_controller.v",
    "$srcDir/motor_mixer.v",
    "$srcDir/pid_top.v"
) -replace '\\', '/' -join " "
$yosysCmd = "read_verilog $srcs; hierarchy -check -top pid_top; proc; opt; check; stat"
& "C:\PROGRA~1\RENESA~1\GOCONF~1\external\yosys\v59\yosys.exe" -p $yosysCmd
if ($LASTEXITCODE -ne 0) {
    Write-Host "Yosys synthesis check failed!" -ForegroundColor Red
    exit 1
}
Write-Host "  -> Yosys netlist checks PASSED." -ForegroundColor Green

# Step 3: Arduino CLI MCU Firmware Compilation
Write-Host "[3/3] Compiling ESP32-S3 Firmware via Arduino CLI..." -ForegroundColor Yellow
$cli = if (Test-Path "$rootDir\tools\arduino-cli\arduino-cli.exe") {
    "$rootDir\tools\arduino-cli\arduino-cli.exe"
} else {
    "arduino-cli"
}
$sketch = "$projDir\firmware\shrike_line_follower\shrike_line_follower.ino"
& $cli compile --fqbn esp32:esp32:esp32s3 $sketch
if ($LASTEXITCODE -ne 0) {
    Write-Host "Arduino CLI compilation failed!" -ForegroundColor Red
    exit 1
}
Write-Host "  -> MCU Firmware compiled successfully." -ForegroundColor Green

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " BUILD SUCCESS: All FPGA RTL and MCU Firmware components built!" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Cyan
exit 0
