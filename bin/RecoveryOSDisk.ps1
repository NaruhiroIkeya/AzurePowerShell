<################################################################################
## Copyright(c) 2019 BeeX Inc. All rights reserved.
## @auther#Naruhiro Ikeya
##
## @name:ReCreateAzureVM.ps1
## @summary:VHDリカバリ後の仮想マシンの再構築スクリプト
##
## @since:2019/02/03
## @version:1.0
## @see:
## @parameter
##  1:Azure VM名
##  2:Azure VMリソースグループ名
##  3:Recovery Servicesコンテナー名
##
## @return:0:Success 9:エラー終了
################################################################################>

##########################
# パラメータ設定
##########################
param (
  [parameter(mandatory=$true)][string]$AzureVMName,
  [parameter(mandatory=$true)][string]$AzureVMResourceGroupName,
  [parameter(mandatory=$true)][string]$RecoveryServiceVaultName
)

##########################
# 認証情報設定
##########################
$TennantID = "e2fb1fde-e67c-4a07-8478-5ab2b9a0577f"

##########################
# 警告の表示抑止
##########################
Set-Item Env:\SuppressAzurePowerShellBreakingChangeWarnings "true"

try {
  Import-Module Az

  ##########################
  # Azureへのログイン
  ##########################
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Azureへログイン:開始")
  $LoginInfo = Login-AzAccount -Tenant $TennantID -WarningAction Ignore
  if(-not $LoginInfo) { 
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Azureへログインできませんでした。")
    exit 9
  }
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Azureへログイン:完了")

  ###################################
  #対象Recovery Services Vaultの選択
  ###################################
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Recovery Servicesコンテナの選択:開始")
  $RecoveryServiceVault = Get-AzRecoveryServicesVault -Name $RecoveryServiceVaultName
  if(-not $RecoveryServiceVault) { 
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Recovery Serviceコンテナー名が不正です。")
    exit 9
  }
  Set-AzRecoveryServicesVaultContext -Vault $RecoveryServiceVault
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] 選択されたRecovery Servicesコンテナ:" + $RecoveryServiceVault.Name)
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Recovery Servicesコンテナの選択:完了")

  #########################################
  ## 最新のリストアジョブ結果詳細を取得
  #########################################
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] 最新のリカバリジョブ結果詳細取得:開始")
  $RecoveryVHDJob = Get-AzRecoveryServicesBackupJob | ? {$_.WorkloadName -eq $AzureVMName -and $_.Operation -eq "Restore" -and $_.Status -eq "Completed"} | sort @{Expression="Endtime";Descending=$true} | Select -First 1
  if(-not $RecoveryVHDJob) { 
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] リカバリジョブが存在しません。")
    exit 9
  }
  $JobDatails = Get-AzRecoveryServicesBackupJobDetails -Job $RecoveryVHDJob
  if(-not $JobDatails) { 
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] リカバリジョブ詳細が取得できませんでした。")
    exit 9
  } elseif($JobDatails.Properties."Job Type" -ne "Recover disks") { 
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] 最新のリカバリジョブがディスクのリカバリジョブではありません。")
    exit 9
  }
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] 最新のリカバリジョブ結果")
  Write-Output($JobDatails| format-list -DisplayError)
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] 最新のリカバリジョブ結果詳細取得:完了")

  #########################################
  ## Configファイルのダウンロード、読み込み
  #########################################
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] リカバリジョブConfig取得:開始")
  $ConfigFilePath = $(Convert-Path .) + "\" + $AzureVMName + "_config.json"
  $StorageAccountKey = (Get-AzStorageAccountKey -ResourceGroupName $JobDatails.Properties["Target resource group"] -Name $JobDatails.Properties["Target Storage Account Name"])[0].Value
  $StorageContext = New-AzStorageContext -StorageAccountName $JobDatails.Properties["Target Storage Account Name"] -StorageAccountKey $StorageAccountKey
  $DownloadConfiFile = Get-AzStorageBlobContent -Blob $JobDatails.Properties["Config Blob Name"] -Container $JobDatails.Properties["Config Blob Container Name"] -Destination $ConfigFilePath -Context $StorageContext -Force
  if(-not $DownloadConfiFile) { 
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Configファイルのダウンロードが失敗しました。")
    exit 9
  }
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Configファイル（$ConfigFilePath）のダウンロードが完了しました。")
  $ConfigOBJ = ((Get-Content -Path $ConfigFilePath -Encoding Unicode)).TrimEnd([char]0x00) | ConvertFrom-Json
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] リカバリジョブConfig取得:完了")

  ####################################################
  ## 復元したディスクが全て揃っているか確認
  ####################################################
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] リカバリしたディスクの正常確認:開始")
  $CheckDisk = Get-AzDisk -ResourceGroupName $JobDatails.Properties["Target resource group"] -DiskName $ConfigOBJ.'properties.storageProfile'.osDisk.name
  if(-not $CheckDisk){
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] OSディスクが存在しません。:" + $ConfigOBJ.'properties.storageProfile'.osDisk.name)
    exit 9
  } elseif($CheckDisk.ProvisioningState -ne "Succeeded") {
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] OSディスクの復元が失敗しています。:" + $ConfigOBJ.'properties.storageProfile'.osDisk.name)
    exit 9
  }
  
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] リカバリしたディスクの正常確認:完了")

  ####################################################
  ## 現行仮想マシンの構成情報を退避
  ####################################################
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] 仮想マシンの構成情報退避:開始")
  $AzureVMInfo = Get-AzVM -Name $AzureVMName -ResourceGroupName $AzureVMResourceGroupName
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] 仮想マシンの構成情報退避:完了")

  ########################################
  ## 仮想マシンの停止
  ########################################
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] 既存仮想マシンの停止:開始")
  $StopResult = Stop-AzVM -Name $AzureVMInfo.Name -ResourceGroupName $AzureVMInfo.ResourceGroupName -Force
  if($StopResult.Status -eq "Succeeded") {
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] 仮想マシン停止完了:" + $AzureVMInfo.Name)
  } else { 
    Write-Output($RemoveResult | format-list -DisplayError)
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] 仮想マシンを停止できませんでした。:" + $AzureVMInfo.Name)
  }
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] 既存仮想マシンの停止:完了")

  ########################################
  ## 不要Dataディスクの削除処理
  ########################################
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] 不要Dataディスク削除処理:開始")
  foreach($RemoveDisk in $ConfigOBJ.'properties.storageProfile'.DataDisks) {
    $RemoveResult = Remove-AzDisk -ResourceGroupName $AzureVMInfo.ResourceGroupName -DiskName $RemoveDisk.Name -Force
    if($RemoveResult.Status -eq "Succeeded") {
      Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] 不要Dataディスク削除完了:" + $RemoveDisk.Name)
    } else { 
      Write-Output($RemoveResult | format-list -DisplayError)
      Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] 不要Dataディスクを削除出来ませんでした。:" + $RemoveDisk.Name)
    }
  } 
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] 不要Dataディスク削除:完了")

  ########################################
  ## 仮想マシンの再構築
  ########################################
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] 仮想マシンの再構築処理:開始")
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] 仮想マシンの設定を開始します。")

  $OsDisk = Get-AzDisk -ResourceGroupName $JobDatails.Properties["Target resource group"] -Name  $ConfigOBJ.'properties.storageProfile'.osDisk.name
  Set-AzVMOSDisk -VM $AzureVMInfo -ManagedDiskId $OsDisk.Id -Name $OsDisk.Name 
  Update-AzVM -ResourceGroupName $AzureVMInfo.ResourceGroupName -VM $AzureVMInfo
  Start-AzVM -Name $vm.Name -ResourceGroupName $AzureVMResourceGroupName
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] 仮想マシンの再構築処理:完了")

  #################################################
  # エラーハンドリング
  #################################################
  if($CreateVMJob.Status -eq "Failed") {
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] 仮想マシンの復元処理中にがエラー終了しました。")
    $CreateVMJob | Format-List -DisplayError
    exit 9
  } else {
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] 仮想マシンの再構築処理:完了")
  }
} catch {
    Write-Output("`r`n`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] 仮想マシンの復元処理中にエラーが発生しました。")
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $error[0] | Format-List -DisplayError)
    exit 99
}
exit 0