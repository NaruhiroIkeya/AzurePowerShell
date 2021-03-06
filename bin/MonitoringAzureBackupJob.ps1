<################################################################################
## Copyright(c) 2020 BeeX Inc. All rights reserved.
## @auther#Naruhiro Ikeya
##
## @name:MonitoringAzureBackupJob.ps1
## @summary:Azureバックアップ監視本体
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
  [parameter(mandatory=$true)][int64]$JobTimeout,
  [int]$AddDays=15,
  [int]$ReturnMode=1,
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
New-Variable -Name ReturnState -Value @("Take Snapshot","Transfer data to vault") -Option ReadOnly
[string]$CredentialFile = "AzureCredential.xml"

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
if($JobTimeout -le 0) {
  $Log.Info("ポーリング間隔（秒）は1以上を設定してください。")
  exit 1
}

try {
  ##########################
  # Azureログオン処理
  ##########################
  $CredentialFilePath = Split-Path $MyInvocation.MyCommand.Path -Parent | Split-Path -Parent | Join-Path -ChildPath etc -Resolve
  $CredentialFileFullPath = $CredentialFilePath + "\" + $CredentialFile 
  $Connect = New-Object AzureLogonFunction($CredentialFileFullPath)
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
  $Log.Info($AzureVMName + "のバックアップを監視します。")
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

  #################################################
  # 実行中バックアップジョブ取得
  #################################################
　$Job = Get-AzRecoveryServicesBackupJob | Where-Object {$_.Status -eq "InProgress" -and $_.Operation -eq "Backup" -and $_.WorkloadName -eq $AzureVMName}
  While(-not $Job) {
    $Log.Warn("実行中のバックアップジョブがありません。")
    exit 0
  }
  #################################################
  # ジョブ終了待機
  #################################################
  $JobResult = Wait-AzRecoveryServicesBackupJob -Job $Job -Timeout $JobTimeout
  While(($($JobResult.SubTasks | Where-Object {$_.Name -eq $ReturnState[$ReturnMode]} | ForEach-Object {$_.Status}) -ne "Completed") -and ($JobResult.Status -ne "Failed" -and $JobResult.Status -ne "Cancelled")) {
    $Log.Info($ReturnState[$ReturnMode] + "フェーズの完了を待機しています。")    
    $JobResult = Wait-AzRecoveryServicesBackupJob -Job $Job -Timeout $JobTimeout
  }
  if($JobResult.Status -eq "InProgress") {
    $SubTasks = $(Get-AzRecoveryServicesBackupJobDetails -JobId $JobResult.JobId).SubTasks
    $Log.Info("Azure Backupジョブ監視を中断します。Job ID=" +  $JobResult.JobId)
    Foreach($SubTask in $SubTasks) {
      $Log.Warn($SubTask.Name + " " +  $SubTask.Status)
    }
    exit 9
  }

  #################################################
  # エラーハンドリング
  #################################################
  if($JobResult.Status -eq "Failed") {
    $Log.Error("Azure Backupジョブ監視がエラー終了しました。")
    $Log.Error($($JobResult | Format-List -DisplayError))
    exit 9
  } else {
    $Log.Info("Azure Backupジョブ監視が完了しました。")
    exit 0
  }
} catch {
    $Log.Error("Backup監視中にエラーが発生しました。")
    $Log.Error($_.Exception)
    exit 99
}
exit 0