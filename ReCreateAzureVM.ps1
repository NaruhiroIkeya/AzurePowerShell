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
##  4:Boot診断ストレージアカウント名
##  5:Boot診断ストレージアカウントリソースグループ名
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
$TennantID = "2ab73ef2-d066-4ce0-923e-94235755e2a2"

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
  
  foreach($DataDiskInfo in $ConfigOBJ.'properties.storageProfile'.dataDisks){
    $CheckDisk = Get-AzDisk -ResourceGroupName $JobDatails.Properties["Target resource group"] -DiskName $DataDiskInfo.Name
    if(-not $CheckDisk){
      Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Dataディスクが存在しません。:" + $DataDiskInfo.Name)
      exit 9
    } elseif($CheckDisk.ProvisioningState -ne "Succeeded") {
      Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Dataディスクの復元が失敗しています。:" + $DataDiskInfo.Name)
      exit 9
    }
  }
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] リカバリしたディスクの正常確認:完了")

  ####################################################
  ## 現行仮想マシンの構成情報を退避
  ####################################################
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] 仮想マシンの構成情報退避:開始")
  $AzureVMInfo = Get-AzVM -Name $AzureVMName -ResourceGroupName $AzureVMResourceGroupName
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] 仮想マシンの構成情報退避:完了")

  ########################################
  ## 仮想マシンの削除
  ########################################
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] 既存仮想マシンの削除:開始")
  $StopResult = Stop-AzVM -Name $AzureVMInfo.Name -ResourceGroupName $AzureVMInfo.ResourceGroupName -Force
  if($StopResult.Status -eq "Succeeded") {
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] 仮想マシン停止完了:" + $AzureVMInfo.Name)
  } else { 
    Write-Output($RemoveResult | format-list -DisplayError)
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] 仮想マシンを停止できませんでした。:" + $AzureVMInfo.Name)
  }
  $RemoveResult = Remove-AzVM -Name $AzureVMInfo.Name -ResourceGroupName $AzureVMInfo.ResourceGroupName -Force
  if($RemoveResult.Status -eq "Succeeded") {
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] 仮想マシン削除完了:" + $AzureVMInfo.Name)
  } else { 
    Write-Output($RemoveResult | format-list -DisplayError)
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] 仮想マシンを削除できませんでした。:" + $AzureVMInfo.Name)
  }
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] 既存仮想マシンの削除:完了")

  ########################################
  ## OSディスクの置換処理
  ########################################
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] 仮想マシンのOSディスク置換処理:開始")
  $RemoveResult = Remove-AzDisk -ResourceGroupName $AzureVMInfo.ResourceGroupName -DiskName $AzureVMInfo.StorageProfile.OsDisk.Name -Force
  if($RemoveResult.Status -eq "Succeeded") {
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] 現行OSディスク削除完了:" + $AzureVMInfo.StorageProfile.OsDisk.Name)
  } else { 
    Write-Output($RemoveResult | format-list -DisplayError)
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] 現行OSディスクを削除出来ませんでした。:" + $AzureVMInfo.StorageProfile.OsDisk.Name)
  }
  $CopyResult = Get-AzDisk -ResourceGroupName $JobDatails.Properties["Target resource group"] -DiskName $ConfigOBJ.'properties.storageProfile'.osDisk.name | Update-AzDisk -ResourceGroupName  $AzureVMInfo.ResourceGroupName -DiskName $AzureVMInfo.StorageProfile.OsDisk.Name
  if($CopyResult.ProvisioningState -eq "Succeeded") {
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] リカバリOSディスクの複製完了")
  } else {
    Write-Output($CopyResult | format-list -DisplayError)
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] リカバリOSディスクの複製処理中にエラーが発生しました。")
    exit 9
  }
  $RemoveResult = Remove-AzDisk -ResourceGroupName $JobDatails.Properties["Target resource group"] -DiskName $ConfigOBJ.'properties.storageProfile'.osDisk.name -Force
  if($RemoveResult.Status -eq "Succeeded") {
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] 複製元OSディスク削除完了:" + $ConfigOBJ.'properties.storageProfile'.osDisk.name)
  } else { 
    Write-Output($RemoveResult | format-list -DisplayError)
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] 複製元OSディスクを削除出来ませんでした。:" + $ConfigOBJ.'properties.storageProfile'.osDisk.name)
  }
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] 仮想マシンのOSディスク置換処理:完了")

  ########################################
  ## Dataディスクの置換処理
  ########################################
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] 仮想マシンのDataディスク置換処理:開始")
  foreach($RemoveDisk in $AzureVMInfo.StorageProfile.DataDisks) {
    $RemoveResult = Remove-AzDisk -ResourceGroupName $AzureVMInfo.ResourceGroupName -DiskName $RemoveDisk.Name -Force
    if($RemoveResult.Status -eq "Succeeded") {
      Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] 現行Dataディスク削除完了:" + $RemoveDisk.Name)
    } else { 
      Write-Output($RemoveResult | format-list -DisplayError)
      Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] 現行Dataディスクを削除出来ませんでした。:" + $RemoveDisk.Name)
    }
  } 
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] 既存仮想マシンのDataディスク削除:完了")

  ########################################
  ## Dataディスク名を基に戻す（複製）
  ########################################
  foreach($SourceDataDisk in $ConfigOBJ.'properties.storageProfile'.dataDisks) {
    $TargetDataDisk = $AzureVMInfo.StorageProfile.DataDisks | ? {$_.lun -eq $SourceDataDisk.lun }
    $CopyResult = Get-AzDisk -ResourceGroupName $JobDatails.Properties["Target resource group"] -DiskName $SourceDataDisk.name | Update-AzDisk -ResourceGroupName  $AzureVMInfo.ResourceGroupName -DiskName $TargetDataDisk.Name
    if($CopyResult.ProvisioningState -eq "Succeeded") {
      Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] リカバリDataディスクの複製完了:" + $CopyResult.Name)
    } else {
      Write-Output($CopyResult | format-list -DisplayError)
      Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] リカバリDataディスクの複製処理中にエラーが発生しました。")    
      exit 9
    }
    $RemoveResult = Remove-AzDisk -ResourceGroupName $JobDatails.Properties["Target resource group"] -DiskName $SourceDataDisk.Name -Force
    if($RemoveResult.Status -eq "Succeeded") {
      Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] 複製元Dataディスク削除完了:" + $SourceDataDisk.Name)
    } else { 
      Write-Output($RemoveResult | format-list -DisplayError)
      Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] 複製元Dataディスクを削除出来ませんでした。:" + $SourceDataDisk.Name)
    }
  }
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] 仮想マシンのDataディスク置換処理:完了")

  ########################################
  ## 仮想マシンの再構築
  ########################################
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] 仮想マシンの再構築処理:開始")
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] 仮想マシンの設定を開始します。")

  $AzureVMInfo.StorageProfile.OSDisk.CreateOption = "Attach"
  $AzureVMInfo.StorageProfile.DataDisks | ForEach-Object { $_.CreateOption = "Attach" }
  $AzureVMInfo.StorageProfile.ImageReference = $null
  $AzureVMInfo.OSProfile = $null
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] 仮想マシンを作成します。")
  $CreateVMJob = New-AzVM -ResourceGroupName $AzureVMInfo.ResourceGroupName -Location $AzureVMInfo.Location -VM $AzureVMInfo

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
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $error[0] | Format-List --DisplayError)
    exit 99
}
exit 0