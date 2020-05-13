<################################################################################
## Copyright(c) 2020 BeeX Inc. All rights reserved.
## @auther#Naruhiro Ikeya
##
## @name:ConvertSecretKey2SecureString.ps1
## @summary:Convert Service Principal Secret Key to SecureString
##
## @since:2020/05/01
## @version:1.0
## @see:
## @parameter
##  1:標準出力
##
## @return:0:Success 1:パラメータエラー 2:Az command実行エラー 9:Exception
################################################################################>

##########################
# パラメータ設定
##########################
param (
  [switch]$Eventlog=$false,
  [switch]$Stdout
)

##########################
# モジュールのロード
##########################
. .\LogController.ps1
. .\AzureLogonFunction.ps1

##########################
# 固定値 
##########################
[string]$CredenticialFile = "AzureCredential.xml"
[string]$SecureCredenticialFile = "AzureCredential_Secure.xml"
[int]$SaveDays = 7

##########################
# 警告の表示抑止
##########################
# Set-Item Env:\SuppressAzurePowerShellBreakingChangeWarnings "true"

###############################
# LogController オブジェクト生成
###############################
if($Stdout) {
  $Log = New-Object LogController($true, (Get-ChildItem $MyInvocation.MyCommand.Path).Name)
} else {
  $LogFilePath = Split-Path $MyInvocation.MyCommand.Path -Parent | Split-Path -Parent | Join-Path -ChildPath log -Resolve
  $LogFile = (Get-ChildItem $MyInvocation.MyCommand.Path).BaseName + ".log"
  $Log = New-Object LogController($($LogFilePath + "\" + $LogFile), $false, $true, (Get-ChildItem $MyInvocation.MyCommand.Path).Name, $false)
  $Log.DeleteLog($SaveDays)
}

try {
  ##########################
  # Azureログオン処理
  ##########################
  $Connect = New-Object AzureLogonFunction($(Split-Path $MyInvocation.MyCommand.Path -Parent | Split-Path -Parent | Join-Path -ChildPath etc -Resolve), $CredenticialFile)
  $Connect.ConvertSecretKeytoSecureString($SecureCredenticialFile) 
  
  $Log.Info("ログオンテストを実施します。")
  $Connect = New-Object AzureLogonFunction($(Split-Path $MyInvocation.MyCommand.Path -Parent | Split-Path -Parent | Join-Path -ChildPath etc -Resolve), $SecureCredenticialFile)
  if($Connect.Initialize($Log)) {
    if(-not $Connect.Logon()) {
      exit 9
    }
  } else {
    exit 9
  }
} catch {
    $Log.Error("ログオンテスト中にエラーが発生しました。")
    $Log.Error($_.Exception)
    return $false
}
exit 0