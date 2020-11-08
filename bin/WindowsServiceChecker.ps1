<################################################################################
## Copyright(c) 2020 BeeX Inc. All rights reserved.
## @auther#Naruhiro Ikeya
##
## @name:WindowsServiceChecker.ps1
## @summary:Windows Service Running Check
##
## @since:2020/11/08
## @version:1.0
## @see:
## @parameter
##  1:サービス名
##
## @return:0:Success 9:エラー終了
################################################################################>

##########################
# パラメータ設定
##########################
param (
  [string]$ServiceName=$null,
  [string]$HostName=$null,
  [switch]$Eventlog,
  [switch]$Stdout
)

##########################
# モジュールのロード
##########################
. .\LogController.ps1
. .\ServiceController.ps1

##########################
# 固定値 
##########################
$Stdout = $true
$Eventlog = $true

##########################
# 警告の表示抑止
##########################
# Set-Item Env:\SuppressAzurePowerShellBreakingChangeWarnings "true"


###############################
# LogController オブジェクト生成
###############################
if($Stdout -and $Eventlog) {
  $Log = New-Object LogController($true, (Get-ChildItem $MyInvocation.MyCommand.Path).Name)
} elseif($Stdout) {
  $Log = New-Object LogController
} else {
  $LogFilePath = Split-Path $MyInvocation.MyCommand.Path -Parent | Split-Path -Parent | Join-Path -ChildPath log -Resolve
  if($MyInvocation.ScriptName -eq "") {
    $LogBaseName = (Get-ChildItem $MyInvocation.MyCommand.Path).BaseName
  } else {
    $LogBaseName = (Get-ChildItem $MyInvocation.ScriptName).BaseName
  }
  $LogFileName = $LogBaseName + ".log"
  $Log = New-Object LogController($($LogFilePath + "\" + $LogFileName), $false, $true, $LogBaseName, $false)
  $Log.DeleteLog($SaveDays)
  $Log.Info("ログファイル名:$($Log.GetLogInfo())")
}
  
##########################
# パラメータチェック
##########################
if (-not $ServiceName) {
  $Log.Error("Syntax Error:実行時に -ServiceName を指定してください。")
  exit 9
}
  
try {
  ##########################
  # ServiceControllerオブジェクト生成
  ##########################
  [object]$Service = $null

  $Service = New-Object ServiceController($ServiceName)
  if($Service.Initialize($Log)) {    
    if($Service.GetStatus() -ne "Running") {
      $Log.Error($ServiceName + "サービスが起動していません。")
    }
  }
#################################################
# エラーハンドリング
#################################################
} catch {
    $Log.Error("処理中にエラーが発生しました。")
    $Log.Error($_.Exception)
    exit 9
}
exit 0