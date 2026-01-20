# vcpkg_build_windows.ps1

param(
    [string]$vcvarsPath = "C:/Program Files/Microsoft Visual Studio/2022/BuildTools/VC/Auxiliary/Build/vcvars64.bat",
    [string]$installPath = "C:/Source/kvs_supergiftpack/",
    [string]$vcpkgTriplet = "x64-windows",
    [string]$toolchainFile = "C:/vcpkg/scripts/buildsystems/vcpkg.cmake"
)

$installPrefixDebug = Join-Path $installPath "Debug/webrtc"
$installPrefixRelease = Join-Path $installPath "Release/webrtc"
$kvspcDirDebug = Join-Path $installPath "Debug/producer"
$kvspcDirRelease = Join-Path $installPath "Release/producer"
$buildDir = "build"

$env:VCPKG_DEFAULT_TRIPLET = $vcpkgTriplet

# === 正確呼叫 vcvars64.bat 並匯入環境變數到 PowerShell ===
Write-Host "Setting up MSVC environment from: $vcvarsPath" -ForegroundColor Cyan
$vcvarsCmd = "`"$vcvarsPath`" && set"
$envLines = cmd /c $vcvarsCmd 2>&1
foreach ($line in $envLines) {
    if ($line -match "^([^=]+)=(.*)$") {
        [Environment]::SetEnvironmentVariable($matches[1], $matches[2], "Process")
    }
}

# 驗證 cl.exe 是否正確設定
$clPath = (Get-Command cl.exe -ErrorAction SilentlyContinue).Source
if ($clPath) {
    Write-Host "Using compiler: $clPath" -ForegroundColor Green
} else {
    Write-Error "cl.exe not found after setting up vcvars!"
    exit 1
}

# 強制 vcpkg 使用指定的 Visual Studio
$vsPath = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $vcvarsPath)))
# 這會從 ".../VC/Auxiliary/Build/vcvars64.bat" 取得 ".../BuildTools" 或 ".../Community"
$env:VCPKG_VISUAL_STUDIO_PATH = $vsPath
Write-Host "Set VCPKG_VISUAL_STUDIO_PATH = $vsPath" -ForegroundColor Cyan

if (-not (Test-Path $buildDir)) {
    New-Item -ItemType Directory -Path $buildDir | Out-Null
}
Push-Location $buildDir

Write-Host "Generating Debug configuration..." -ForegroundColor Cyan
cmake -G "Visual Studio 17 2022" `
    -DBUILD_TEST=FALSE `
    -DENABLE_AWS_SDK_IN_TESTS=OFF `
    -DCMAKE_TOOLCHAIN_FILE="$toolchainFile" `
    -DCMAKE_INSTALL_PREFIX="$installPrefixDebug" `
    -DKVSPC_DIR="$kvspcDirDebug" `
    -DVCPKG_INSTALL_OPTIONS="--clean-after-build" `
    ..

Write-Host "Building Debug configuration..." -ForegroundColor Cyan
cmake --build . --config Debug --target install

Write-Host "Generating Release configuration..." -ForegroundColor Green
cmake -G "Visual Studio 17 2022" `
    -DBUILD_TEST=FALSE `
    -DENABLE_AWS_SDK_IN_TESTS=OFF `
    -DCMAKE_TOOLCHAIN_FILE="$toolchainFile" `
    -DCMAKE_INSTALL_PREFIX="$installPrefixRelease" `
    -DKVSPC_DIR="$kvspcDirRelease" `
    -DVCPKG_INSTALL_OPTIONS="--clean-after-build" `
    ..

Write-Host "Building Release configuration..." -ForegroundColor Green
cmake --build . --config Release --target install

Write-Host "Build and installation completed." -ForegroundColor Yellow

Pop-Location