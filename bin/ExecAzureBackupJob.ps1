<################################################################################
## Copyright(c) 2019 BeeX Inc. All rights reserved.
## @auther#Naruhiro Ikeya
##
## @name:ExecAzureBackupJob.ps1
## @summary:Azureバックアップ実行本体
##
## @since:2019/01/28
## @version:1.0
## @see:
## @parameter
##  1:AzureVM名
##  2:Recovery Serviceコンテナー名
##  3:Azure Backupジョブポーリング間隔（秒）
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
  [int]$ReturnMode=0
)

##########################
# 認証情報設定
##########################
$TennantID="e2fb1fde-e67c-4a07-8478-5ab2b9a0577f"
$Key="I9UCoQXrv/G/EqC93RC7as8eyWARVd77UUC/fxRdGTw="
$ApplicationID="1cb16aa7-59a6-4d8e-89ef-3b896d9f1718"

##########################
# パラメータチェック
##########################
if($JobTimeout -le 0) {
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] ポーリング間隔（秒）は1以上を設定してください。")
  exit 1
}
if($AddDays -le 0) {
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] バックアップ保持日数は1以上を設定してください。")
  exit 1
}

try {
  Import-Module AzureRM

  New-Variable -Name ReturnState -Value @("Take Snapshot","Transfer data to vault") -Option ReadOnly

  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $AzureVMName + "のバックアップを開始します。")
  ##########################
  # Azureへのログイン
  ##########################
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] サービスプリンシパルを利用しAzureへログインします。")
  $SecPasswd = ConvertTo-SecureString $Key -AsPlainText -Force
  $MyCreds = New-Object System.Management.Automation.PSCredential ($ApplicationID, $SecPasswd)
  $LoginInfo = Login-AzureRmAccount  -ServicePrincipal -Tenant $TennantID -Credential $MyCreds
  if(-not $LoginInfo) { 
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Azureへログインできませんでした。")
    exit 9
  }

  #################################################
  # Recovery Service コンテナーのコンテキストの設定
  #################################################
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Recovery Services コンテナーから情報を取得します。")
  $RecoveryServiceVault = Get-AzureRmRecoveryServicesVault -Name $RecoveryServiceVaultName
  if(-not $RecoveryServiceVault) { 
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Recovery Serviceコンテナー名が不正です。")
    exit 1
  }
  Set-AzureRmRecoveryServicesVaultContext -Vault $RecoveryServiceVault

  #################################################
  # Azure Backup(IaaS) 設定済みサーバ 情報取得
  #################################################
  $BackupContainer = Get-AzureRmRecoveryServicesBackupContainer -ContainerType "AzureVM" -Status "Registered" -FriendlyName $AzureVMName
  if(-not $BackupContainer) { 
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Recovery Services コンテナーにバックアップ対象（" + $AzureVMName + "）が存在しません。")
    exit 1
  }
  $BackupItem = Get-AzureRmRecoveryServicesBackupItem -Container $BackupContainer -WorkloadType "AzureVM"
  ##########################################################################################################################
  # -ExpiryDateTimeUTCには、バックアップ保管期間を指定（「UTC」かつジョブ実行タイミングから「1日後」～「99年後」で指定）
  ##########################################################################################################################
  $ExpiryDateUTC = [DateTime](Get-Date).ToUniversalTime().AddDays($AddDays).ToString("yyyy/MM/dd")
  #################################################
  # Azure Backup(IaaS) 実行
  #################################################
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Azure Backupジョブを実行します。")
  $Job = Backup-AzureRmRecoveryServicesBackupItem -Item $BackupItem -ExpiryDateTimeUTC $ExpiryDateUTC
  if($Job.Status -eq "Failed") {
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Azure Backupジョブがエラー終了しました。")
　　$Job | Format-List -DisplayError
    exit 9
  }

  #################################################
  # ジョブ終了待機(Snapshot取得待ち)
  #################################################
  $JobResult = Wait-AzureRmRecoveryServicesBackupJob -Job $Job -Timeout $JobTimeout
  While(($($JobResult.SubTasks | ? {$_.Name -eq $ReturnState[$ReturnMode]} | % {$_.Status}) -ne "Completed") -and ($JobResult.Status -ne "Failed" -and $JobResult.Status -ne "Cancelled")) {
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $ReturnState[$ReturnMode] + "フェーズの完了を待機しています。")    
    $JobResult = Wait-AzureRmRecoveryServicesBackupJob -Job $Job -Timeout $JobTimeout
  }
  if($JobResult.Status -eq "InProgress") {
    $SubTasks = $(Get-AzureRmRecoveryServicesBackupJobDetails -JobId $JobResult.JobId).SubTasks
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Azure Backupジョブ監視を中断します。Job ID=" +  $JobResult.JobId)
    Foreach($SubTask in $SubTasks) {
      Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $SubTask.Name + " " +  $SubTask.Status)
    }
    exit 2
  } elseif($JobResult.Status -eq "Cancelled") {
    $SubTasks = $(Get-AzureRmRecoveryServicesBackupJobDetails -JobId $JobResult.JobId).SubTasks
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Azure Backupジョブがキャンセルされました。Job ID=" +  $JobResult.JobId)
    Foreach($SubTask in $SubTasks) {
      Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $SubTask.Name + " " +  $SubTask.Status)
    }
    exit 0
  }

  #################################################
  # エラーハンドリング
  #################################################
  if($JobResult.Status -eq "Failed") {
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Azure Backupジョブがエラー終了しました。")
　　$JobResult | Format-List -DisplayError
    exit 9
  } else {
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Azure Backupジョブが完了しました。")
  }
} catch {
    Write-Output("`r`n`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Azure Backup実行中にエラーが発生しました。")
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $error[0] | Format-List --DisplayError)
    exit 99
}
exit 0