<################################################################################
## Copyright(c) 2019 BeeX Inc. All rights reserved.
## @auther#Naruhiro Ikeya
##
## @name:AzureBackup.ps1
## @summary:ExecAzureBackupJob.ps1 Wrapper
##
## @since:2019/06/24
## @version:1.0
## @see:
## @parameter
##  1:AzureVM名
##  2:Recovery Serviceコンテナー名
##  3:Azure Backupジョブ実行待ちタイムアウト値
##
## @return:0:Success 1:パラメータエラー 2:Azure Backup実行エラー 9:Exception
################################################################################>

##########################
# パラメータ設定
##########################
param (
  [parameter(mandatory=$true)][string]$AzureVMName,
  [parameter(mandatory=$true)][string]$RecoveryServiceVaultName,
  [parameter(mandatory=$true)][int64]$JobTimeout,
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
$ErrorActionPreference = "Stop"

###############################
# LogController オブジェクト生成
###############################
if($Stdout) {
  $Log = New-Object LogController
} else {
  $LogFilePath = Split-Path $MyInvocation.MyCommand.Path -Parent | Split-Path -Parent | Join-Path -ChildPath log -Resolve
  $LogFile = (Get-ChildItem $MyInvocation.MyCommand.Path).BaseName + ".log"
  $Log = New-Object LogController($($LogFilePath + "\" + $LogFile), $false)
}

##########################
# パラメータチェック
##########################
if($JobTimeout -lt 0) {
  $Log.Info("タイムアウト値は0以上を設定してください。`r`n")
  exit 1
}

try {
  ##########################
  # Azureログオン処理
  ##########################
  $SettingFilePath = Split-Path $MyInvocation.MyCommand.Path -Parent | Split-Path -Parent | Join-Path -ChildPath etc -Resolve
  $SettingFile = "AzureCredential.xml"
  $SettingFileFull = $SettingFilePath + "\" + $SettingFile 
  $Connect = New-Object AzureLogonFunction($SettingFileFull)
  if($Connect.Initialize($Log)) {
    if(-not $Connect.Logon()) {
      exit 9
    }
  } else {
    exit 9
  }

  #################################################
  # Recovery Service コンテナーのコンテキストの設定
  #################################################
  $Log.Info("Recovery Serviceコンテナーから情報を取得します。")
  $RecoveryServiceVault = Get-AzRecoveryServicesVault -Name $RecoveryServiceVaultName
  if(-not $RecoveryServiceVault) { 
    $Log.Info("Recovery Serviceコンテナー名が不正です。")
    exit 1
  }
  Set-AzRecoveryServicesVaultContext -Vault $RecoveryServiceVault

  #################################################
  # Azure Backup(IaaS) 設定済みサーバ 情報取得
  #################################################
  $Log.Info("Azure Backupを実行します。")
  $BackupContainer = Get-AzRecoveryServicesBackupContainer -ContainerType "AzureVM" -Status "Registered" -FriendlyName $AzureVMName
  if(-not $BackupContainer) { 
    $Log.Info("Recovery Serviceコンテナーにバックアップ対象が存在しません。")
    exit 1
  }
  $BackupItem = Get-AzRecoveryServicesBackupItem -Container $BackupContainer -WorkloadType "AzureVM"
  $Job = Backup-AzRecoveryServicesBackupItem -Item $BackupItem

  #################################################
  # Azure Backup(IaaS) 実行
  #################################################
  $JobResult = Wait-AzRecoveryServicesBackupJob -Job $Job -Timeout $JobTimeout

  #################################################
  # エラーハンドリング
  #################################################
  if($JobResult.Status -eq "Failed") {
    $Log.Error("Azure Backupジョブがエラー終了しました。")
    $Log.Error($($JobResult | Format-List -DisplayError))
    exit 9
  } elseif($JobResult.Status -eq "InProgress") {
    $Log.Warn("Azure Backup待ちがタイムアウトしました。")
    $Log.Warn($($JobResult | Format-List -DisplayError))
  } elseif($JobResult.Status -eq "Completed") {
    $Log.Info("Azure Backupが完了しました。")
    exit 0
  } else {
    $Log.Warn("Azure Backupが実行中です。")
    $Log.Warn($($JobResult | Format-List -DisplayError))
  } 
} catch {
    $log.Error("Azure Backup実行中にエラーが発生しました。")
    $Log.Error($_.Exception)
    exit 99
}
exit 0