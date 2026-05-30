# vcpkg_utilty.ps1
# vcpkg 相關的共用函數

# 內部使用 utilty.ps1 的函數
# 若外部需要直接使用 utilty.ps1 的函數（如 Write-YellowToConsole），請外部自己 import
Import-Module "$PSScriptRoot\utilty.ps1" -Force

function Initialize-VcVarsEnvironment {
    <#
    .SYNOPSIS
        正確呼叫 vcvars64.bat 並匯入環境變數到 PowerShell session
    .DESCRIPTION
        解決 PowerShell 無法直接執行 batch 檔案並保留環境變數的問題。
        同時設定 VCPKG_VISUAL_STUDIO_PATH 強制 vcpkg 使用指定的 Visual Studio。
        CMake 版本會從 PATH 選取，不能改用 Visual Studio 內建 CMake，避免 vcpkg binary cache ABI 變動。
    .PARAMETER VcVarsPath
        vcvars64.bat 的完整路徑
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$VcVarsPath
    )

    if (-not (Test-Path $VcVarsPath)) {
        Write-RedToConsole "vcvars64.bat not found: $VcVarsPath"
        throw "vcvars64.bat not found: $VcVarsPath"
    }

    Write-CyanToConsole "Setting up MSVC environment from: $VcVarsPath"
    $originalVcpkgRoot = $env:VCPKG_ROOT
    
    # 呼叫 vcvars64.bat 並擷取環境變數
    $vcvarsCmd = "`"$VcVarsPath`" && set"
    $envLines = cmd /c $vcvarsCmd 2>&1
    foreach ($line in $envLines) {
        if ($line -match "^([^=]+)=(.*)$") {
            [Environment]::SetEnvironmentVariable($matches[1], $matches[2], "Process")
        }
    }

    if ($originalVcpkgRoot) {
        $env:VCPKG_ROOT = $originalVcpkgRoot
        Write-CyanToConsole "Restored VCPKG_ROOT = $env:VCPKG_ROOT"
    } elseif ($env:VCPKG_ROOT) {
        Remove-Item Env:VCPKG_ROOT -ErrorAction SilentlyContinue
        Write-CyanToConsole "Unset VCPKG_ROOT from vcvars environment"
    }

    # 驗證 cl.exe 是否正確設定
    $clPath = (Get-Command cl.exe -ErrorAction SilentlyContinue).Source
    if ($clPath) {
        Write-GreenToConsole "Using compiler: $clPath"
    } else {
        Write-RedToConsole "cl.exe not found after setting up vcvars!"
        throw "cl.exe not found after setting up vcvars!"
    }

    # 強制 vcpkg 使用指定的 Visual Studio
    # 從 ".../VC/Auxiliary/Build/vcvars64.bat" 取得 ".../BuildTools" 或 ".../Community"
    $vsPath = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $VcVarsPath)))
    $env:VCPKG_VISUAL_STUDIO_PATH = $vsPath
    Write-CyanToConsole "Set VCPKG_VISUAL_STUDIO_PATH = $vsPath"

    Assert-CMakeVersion
}

function Get-RequiredCMakeVersion {
    if ($env:HOMER_EXPECTED_CMAKE_VERSION) {
        return $env:HOMER_EXPECTED_CMAKE_VERSION
    }

    return "4.3.3"
}

function Assert-CMakeVersion {
    param(
        [string]$ExpectedVersion = (Get-RequiredCMakeVersion)
    )

    $cmakeCommand = Get-Command cmake.exe -ErrorAction SilentlyContinue
    if (-not $cmakeCommand) {
        Write-RedToConsole "CMake not found. Install CMake $ExpectedVersion and add it to PATH."
        throw "CMake not found"
    }

    $versionOutput = & $cmakeCommand.Source --version 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-RedToConsole "Unable to run CMake at: $($cmakeCommand.Source)"
        throw "Unable to run CMake"
    }

    $versionLine = $versionOutput | Select-Object -First 1
    if ($versionLine -notmatch "cmake version\s+([^\s]+)") {
        Write-RedToConsole "Unable to parse CMake version from: $versionLine"
        throw "Unable to parse CMake version"
    }

    $actualVersion = $matches[1]
    Write-CyanToConsole "Using CMake: $($cmakeCommand.Source)"
    Write-CyanToConsole "CMake version: $actualVersion"

    if ($actualVersion -ne $ExpectedVersion) {
        Write-RedToConsole "CMake version mismatch. Expected $ExpectedVersion, got $actualVersion."
        Write-YellowToConsole "vcpkg binary cache ABI depends on CMake version; align local and CI before building."
        throw "CMake version mismatch"
    }
}

function Assert-CMakeSupportsGenerator {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Generator
    )

    $helpOutput = & cmake --help 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-RedToConsole "Unable to read CMake help output."
        throw "Unable to read CMake help"
    }

    if (-not ($helpOutput | Select-String -SimpleMatch $Generator -Quiet)) {
        Write-RedToConsole "CMake does not support generator: $Generator"
        throw "CMake generator not supported"
    }
}

function Get-CMakeVisualStudioGeneratorArgs {
    param(
        [string]$DefaultGenerator = "Visual Studio 18 2026",
        [string]$DefaultPlatform = "x64"
    )

    $generator = if ($env:CMAKE_GENERATOR) { $env:CMAKE_GENERATOR } else { $DefaultGenerator }
    $platform = if ($env:CMAKE_GENERATOR_PLATFORM) { $env:CMAKE_GENERATOR_PLATFORM } else { $DefaultPlatform }
    $toolset = $env:CMAKE_GENERATOR_TOOLSET

    $args = @("-G", $generator)
    if ($platform) {
        $args += @("-A", $platform)
    }
    if ($toolset) {
        $args += @("-T", $toolset)
    }

    Write-CyanToConsole "Using CMake generator: $generator"
    if ($platform) {
        Write-CyanToConsole "Using CMake platform: $platform"
    }
    if ($toolset) {
        Write-CyanToConsole "Using CMake toolset: $toolset"
    }

    Assert-CMakeSupportsGenerator -Generator $generator

    return $args
}
