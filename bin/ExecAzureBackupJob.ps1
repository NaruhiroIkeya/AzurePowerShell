<################################################################################
## Copyright(c) 2020 BeeX Inc. All rights reserved.
## @auther#Naruhiro Ikeya
##
## @name:ExecAzureBackupJob.ps1
## @summary:Azureバックアップ実行本体
##
## @since:2019/06/24
## @version:1.0
## @see:
## @parameter
##  1:AzureVM名
##  2:Recovery Serviceコンテナー名
##  3:バックアップ保管日数
##  4:Azure Backupジョブポーリング間隔（秒）
##  5:リターンステータス（スナップショット待ち、完了待ち）
##
## @return:0:Success 
##         1:入力パラメータエラー
##         2:Azure Backupジョブ監視中断（Take Snapshot完了）
##         9:Azure Backup実行エラー
##         99:Exception
################################################################################>

##########################
# パラメータ設定
##########################
param (
  [parameter(mandatory=$true)][string]$AzureVMName,
  [parameter(mandatory=$true)][string]$RecoveryServiceVaultName,
  [parameter(mandatory=$true)][int]$AddDays,
  [parameter(mandatory=$true)][int64]$JobTimeout,
  [switch]$Complete=$false,
  [switch]$Eventlog=$false,
  [switch]$Stdout=$false
)

##########################
# モジュールのロード
##########################
. .\LogController.ps1
. .\AzureLogonFunction.ps1

##########################
# 固定値 
##########################
New-Variable -Name ReturnState -Value @("Take Snapshot","Transfer data to vault") -Option ReadOnly
# $ErrorActionPreference="Stop"

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
  $LogFile = (Get-ChildItem $MyInvocation.MyCommand.Path).BaseName + ".log"
  $Log = New-Object LogController($($LogFilePath + "\" + $LogFile), $false, $true, (Get-ChildItem $MyInvocation.MyCommand.Path).Name, $false)
  $Log.DeleteLog($SaveDays)
}

##########################
# パラメータチェック
##########################
if($JobTimeout -le 0) {
  $Log.Info("ポーリング間隔（秒）は1以上を設定してください。")
  exit 1
}
if($AddDays -le 0) {
  $Log.Info("バックアップ保持日数は1以上を設定してください。")
  exit 1
}

try {
  ##########################
  # Azureログオン処理
  ##########################
  $CredenticialFilePath = Split-Path $MyInvocation.MyCommand.Path -Parent | Split-Path -Parent | Join-Path -ChildPath etc -Resolve
  $CredenticialFileFullPath = $CredenticialFilePath + "\" + $CredenticialFile 
  $Connect = New-Object AzureLogonFunction($CredenticialFileFullPath)
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
  $Log.Info($AzureVMName + "のバックアップを開始します。")
  $Log.Info("Recovery Services コンテナーから情報を取得します。")
  $RecoveryServiceVault = Get-AzRecoveryServicesVault -Name $RecoveryServiceVaultName
  if(-not $RecoveryServiceVault) { 
    $Log.Error("Recovery Serviceコンテナー名が不正です。")
    exit 9
  }

  #################################################
  # Azure Backup(IaaS) 設定済みサーバ 情報取得
  #################################################
  $BackupContainer = Get-AzRecoveryServicesBackupContainer -VaultId $RecoveryServiceVault.ID -ContainerType "AzureVM" -Status "Registered" -FriendlyName $AzureVMName
  if(-not $BackupContainer) { 
    $Log.Error("Recovery Services コンテナーにバックアップ対象（" + $AzureVMName + "）が存在しません。")
    exit 9
  }
  $BackupItem = Get-AzRecoveryServicesBackupItem -VaultId $RecoveryServiceVault.ID -Container $BackupContainer -WorkloadType "AzureVM"
  ##########################################################################################################################
  # -ExpiryDateTimeUTCには、バックアップ保管期間を指定（「UTC」かつジョブ実行タイミングから「1日後」～「99年後」で指定）
  ##########################################################################################################################
  $ExpiryDateUTC = [DateTime](Get-Date).ToUniversalTime().AddDays($AddDays).ToString("yyyy/MM/dd")
  #################################################
  # Azure Backup(IaaS) 実行
  #################################################
  $Log.Info("Azure Backupジョブを実行します。")
  $Job = Backup-AzRecoveryServicesBackupItem -VaultId $RecoveryServiceVault.ID -Item $BackupItem -ExpiryDateTimeUTC $ExpiryDateUTC
  if($Job.Status -eq "Failed") {
    $Log.Error("Azure Backupジョブがエラー終了しました。")
    $Log.Error($($Job | Format-List | Out-String -Stream))
    exit 9
  }

  #################################################
  # ジョブ終了待機(Snapshot取得待ち)
  #################################################
  $JobResult = Wait-AzRecoveryServicesBackupJob -VaultId $RecoveryServiceVault.ID -Job $Job -Timeout $JobTimeout
  $CompStatus = if($Complete) { Write-Output "1" } else { Write-Output "0" }
    While(($($JobResult.SubTasks | ? {$_.Name -eq $ReturnState[$CompStatus]} | % {$_.Status}) -ne "Completed") -and ($JobResult.Status -ne "Failed" -and $JobResult.Status -ne "Cancelled")) {
    $Log.Info($ReturnState[$CompStatus] + "フェーズの完了を待機しています。")    
    $JobResult = Wait-AzRecoveryServicesBackupJob -VaultId $RecoveryServiceVault.ID -Job $Job -Timeout $JobTimeout
  }
  if($JobResult.Status -eq "InProgress") {
    $SubTasks = $(Get-AzRecoveryServicesBackupJobDetails -VaultId $RecoveryServiceVault.ID -JobId $JobResult.JobId).SubTasks
    $Log.Info("Azure Backupジョブ監視を中断します。Job ID=" +  $JobResult.JobId)
    Foreach($SubTask in $SubTasks) {
      $Log.Info($SubTask.Name + " " +  $SubTask.Status)
    }
    exit 2
  } elseif($JobResult.Status -eq "Cancelled") {
    $SubTasks = $(Get-AzRecoveryServicesBackupJobDetails -VaultId $RecoveryServiceVault.ID -JobId $JobResult.JobId).SubTasks
    $Log.Warn("Azure Backupジョブがキャンセルされました。Job ID=" +  $JobResult.JobId)
    Foreach($SubTask in $SubTasks) {
      $Log.Warn($SubTask.Name + " " +  $SubTask.Status)
    }
    exit 0
  }

  #################################################
  # エラーハンドリング
  #################################################
  if($JobResult.Status -eq "Failed") {
    $Log.Error("Azure Backupジョブがエラー終了しました。")
    $Log.Error($($JobResult | Format-List | Out-String -Stream))
    exit 9
  } else {
    $Log.Info("Azure Backupジョブが完了しました。")
    exit 0
  }
} catch {
    $Log.Error("Azure Backup実行中にエラーが発生しました。")
    $Log.Error($_.Exception)
    exit 99
}
exit 0