<################################################################################
## Copyright(c) 2019 BeeX Inc. All rights reserved.
## @auther#Naruhiro Ikeya
##
## @name:AzureBackup.ps1
## @summary:ExecAzureBackupJob.ps1 Wrapper
##
## @since:2019/01/17
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
  [parameter(mandatory=$true)][int64]$JobTimeout
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
if($JobTimeout -lt 0) {
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] タイムアウト値は0以上を設定してください。`r`n")
  exit 1
}

try {

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
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Recovery Serviceコンテナーから情報を取得します。")
  $RecoveryServiceVault = Get-AzRecoveryServicesVault -Name $RecoveryServiceVaultName
  if(-not $RecoveryServiceVault) { 
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Recovery Serviceコンテナー名が不正です。")
    exit 1
  }
  Set-AzRecoveryServicesVaultContext -Vault $RecoveryServiceVault

  #################################################
  # Azure Backup(IaaS) 設定済みサーバ 情報取得
  #################################################
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Azure Backupを実行します。")
  $BackupContainer = Get-AzRecoveryServicesBackupContainer -ContainerType "AzureVM" -Status "Registered" -FriendlyName $AzureVMName
  if(-not $BackupContainer) { 
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Recovery Serviceコンテナーにバックアップ対象が存在しません。")
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
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Azure Backupジョブがエラー終了しました。")
　　$JobResult | Format-List -force 
    exit 2
  } else {
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Azure Backupジョブが完了しました。")
  }
} catch {
    Write-Output("`r`n`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Azure Backup実行中にエラーが発生しました。")
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $error[0] | Format-List -force  )
    exit 9
}
exit 0