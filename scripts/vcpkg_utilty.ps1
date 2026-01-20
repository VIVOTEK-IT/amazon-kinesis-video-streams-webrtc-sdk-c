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
    
    # 呼叫 vcvars64.bat 並擷取環境變數
    $vcvarsCmd = "`"$VcVarsPath`" && set"
    $envLines = cmd /c $vcvarsCmd 2>&1
    foreach ($line in $envLines) {
        if ($line -match "^([^=]+)=(.*)$") {
            [Environment]::SetEnvironmentVariable($matches[1], $matches[2], "Process")
        }
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
}
