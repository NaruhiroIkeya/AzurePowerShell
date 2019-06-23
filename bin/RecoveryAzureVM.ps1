<################################################################################
## Copyright(c) 2019 BeeX Inc. All rights reserved.
## @auther#Naruhiro Ikeya
##
## @name:RecoveryAzureVM.ps1
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

  ###################################
  #対象Recovery Services Vaultの選択
  ###################################
  $Log.Info("Recovery Servicesコンテナの選択:開始")
  $RecoveryServiceVault = Get-AzRecoveryServicesVault -Name $RecoveryServiceVaultName
  if(-not $RecoveryServiceVault) { 
    $Log.Error("Recovery Serviceコンテナー名が不正です:" + $RecoveryServiceVaultName)
    exit 9
  }
  Set-AzRecoveryServicesVaultContext -Vault $RecoveryServiceVault
  $Log.Info("選択されたRecovery Servicesコンテナ:" + $RecoveryServiceVault.Name)
  $Log.Info("Recovery Servicesコンテナの選択:完了")

  #########################################
  ## 最新のリストアジョブ結果詳細を取得
  #########################################
  $Log.Info("最新のリカバリジョブ結果詳細取得:開始")
  $RecoveryVHDJob = Get-AzRecoveryServicesBackupJob | ? {$_.WorkloadName -eq $AzureVMName -and $_.Operation -eq "Restore" -and $_.Status -eq "Completed"} | sort @{Expression="Endtime";Descending=$true} | Select -First 1
  if(-not $RecoveryVHDJob) { 
    $Log.Error("リカバリジョブが存在しません")
    exit 9
  }
  $JobDatails = Get-AzRecoveryServicesBackupJobDetails -Job $RecoveryVHDJob
  if(-not $JobDatails) { 
    $Log.Error("リカバリジョブ詳細が取得できませんでした")
    exit 9
  } elseif($JobDatails.Properties."Job Type" -ne "Recover disks") { 
    $Log.Error("最新のリカバリジョブがディスクのリカバリジョブではありません")
    exit 9
  }
  $Log.Info("最新のリカバリジョブ結果")
  Write-Output($JobDatails| format-list -DisplayError)
  $Log.Info("最新のリカバリジョブ結果詳細取得:完了")

  #########################################
  ## Configファイルのダウンロード、読み込み
  #########################################
  $Log.Info("リカバリジョブConfig取得:開始")
  $ConfigFilePath = $(Convert-Path .) + "\" + $AzureVMName + "_config.json"
  $StorageAccountKey = (Get-AzStorageAccountKey -ResourceGroupName $JobDatails.Properties["Target resource group"] -Name $JobDatails.Properties["Target Storage Account Name"])[0].Value
  $StorageContext = New-AzStorageContext -StorageAccountName $JobDatails.Properties["Target Storage Account Name"] -StorageAccountKey $StorageAccountKey
  $DownloadConfiFile = Get-AzStorageBlobContent -Blob $JobDatails.Properties["Config Blob Name"] -Container $JobDatails.Properties["Config Blob Container Name"] -Destination $ConfigFilePath -Context $StorageContext -Force
  if(-not $DownloadConfiFile) { 
    $Log.Error("Configファイルのダウンロードが失敗しました")
    exit 9
  }
  $Log.Info("Configファイル（$ConfigFilePath）のダウンロードが完了しました")
  $ConfigOBJ = ((Get-Content -Path $ConfigFilePath -Encoding Unicode)).TrimEnd([char]0x00) | ConvertFrom-Json
  $Log.Info("リカバリジョブConfig取得:完了")

  ####################################################
  ## 復元したディスクが全て揃っているか確認
  ####################################################
  $Log.Info("リカバリしたディスクの正常確認:開始")
  $CheckDisk = Get-AzDisk -ResourceGroupName $JobDatails.Properties["Target resource group"] -DiskName $ConfigOBJ.'properties.storageProfile'.osDisk.name
  if(-not $CheckDisk){
    $Log.Error("OSディスクが存在しません:" + $ConfigOBJ.'properties.storageProfile'.osDisk.name)
    exit 9
  } elseif($CheckDisk.ProvisioningState -ne "Succeeded") {
    $Log.Error("OSディスクの復元が失敗しています:" + $ConfigOBJ.'properties.storageProfile'.osDisk.name)
    exit 9
  }
  
  foreach($DataDiskInfo in $ConfigOBJ.'properties.storageProfile'.dataDisks){
    $CheckDisk = Get-AzDisk -ResourceGroupName $JobDatails.Properties["Target resource group"] -DiskName $DataDiskInfo.Name
    if(-not $CheckDisk){
      $Log.Error("Dataディスクが存在しません:" + $DataDiskInfo.Name)
      exit 9
    } elseif($CheckDisk.ProvisioningState -ne "Succeeded") {
      $Log.Error("Dataディスクの復元が失敗しています:" + $DataDiskInfo.Name)
      exit 9
    }
  }
  $Log.Info("リカバリしたディスクの正常確認:完了")

  ####################################################
  ## 現行仮想マシンの構成情報を退避
  ####################################################
  $Log.Info("仮想マシンの構成情報退避:開始")
  $AzureVMInfo = Get-AzVM -Name $AzureVMName -ResourceGroupName $AzureVMResourceGroupName  
  $Log.Info("仮想マシンの構成情報退避:完了")

  ########################################
  ## 仮想マシンの停止
  ########################################
  $Log.Info("リカバリ対象仮想マシンの停止:開始")
  $Log.Info("リカバリ対象仮想マシンを停止します:" + $AzureVMInfo.Name)
  $Result = Stop-AzVM -Name $AzureVMInfo.Name -ResourceGroupName $AzureVMInfo.ResourceGroupName -Force
  if($Result.Status -eq "Succeeded") {
    $Log.Info("仮想マシンの停止:完了")
  } else { 
    Write-Output($StopResult | format-list -DisplayError)
    $Log.Error("仮想マシンの停止:失敗" )
    exit 9
  }
  $Log.Info("リカバリ対象仮想マシンの停止:完了")

  ########################################
  ## Dataディスクの置換処理
  ########################################
  $Log.Info("仮想マシンのデータディスク置換処理:開始")
  foreach($RecoveryDisk in $ConfigOBJ.'properties.storageProfile'.dataDisks) {
    $SourceDataDisk = $AzureVMInfo.StorageProfile.DataDisks | ? { $_.Lun -eq $RecoveryDisk.Lun }
    if(-not $SourceDataDisk){
      $Log.Error("仮想マシンにLUNが一致するディスクが接続されてません。:" + $RecoveryDisk.Name)
      exit 9
    }
　　## 仮想マシンからデータディスクをデタッチ
    $Log.Info("仮想マシンからデータディスクをデタッチします:LUN:" + $SourceDataDisk.Lun + ",DISK:" + $SourceDataDisk.Name)
    $Result = Remove-AzVMDataDisk -VM $AzureVMInfo -Name $SourceDataDisk.Name
    if($Result.ProvisioningState -eq "Succeeded") {
      $Log.Info("データディスクのデタッチ:完了")
    } else { 
      Write-Output($Result | format-list -DisplayError)
      $Log.Error("データディスクのデタッチ:失敗")
      exit 9
    }
    $Result = Update-AzVM -ResourceGroupName $AzureVMInfo.ResourceGroupName -VM $AzureVMInfo  
    if($Result.IsSuccessStatusCode) {
      $Log.Info("仮想マシンの構成変更:完了")
    } else { 
      Write-Output($Result | format-list -DisplayError)
      $Log.Error("仮想マシンの構成変更:失敗")
      exit 9
    }

　　## デタッチしたディスクの削除
    $Log.Info("デタッチしたデータディスクを削除します:" + $SourceDataDisk.Name)
    $Result = Remove-AzDisk -ResourceGroupName $AzureVMInfo.ResourceGroupName -DiskName $SourceDataDisk.Name -Force
    if($Result.Status -eq "Succeeded") {
      $Log.Info("データディスク削除:完了")
    } else { 
      Write-Output($Result | format-list -DisplayError)
      $Log.Error("データディスク削除:失敗")
      exit 9
    }

　　## リカバリディスク名称変更（複製）
    $Log.Info("リカバリしたデータディスクの名称変更（複製）を開始します:" + $RecoveryDisk.Name)
    $CopyResult = Get-AzDisk -ResourceGroupName $JobDatails.Properties["Target resource group"] -DiskName $RecoveryDisk.Name | Update-AzDisk -ResourceGroupName  $AzureVMInfo.ResourceGroupName -DiskName $SourceDataDisk.Name
    if($CopyResult.ProvisioningState -eq "Succeeded") {
      $Log.Info("データディスクの名称変更:完了")
    } else {
      Write-Output($CopyResult | format-list -DisplayError)
      $Log.Error("データディスクの名称変更:失敗")    
      exit 9
    }

　　## 複製ディスクのアタッチ
    $Log.Info("仮想マシンにデータディスクをアタッチします:" + $CopyResult.Name)
    $Result = Add-AzVMDataDisk -CreateOption Attach -Lun $SourceDataDisk.lun -VM $AzureVMInfo -ManagedDiskId $CopyResult.Id
    if($Result.ProvisioningState -eq "Succeeded") {
      $Log.Info("データディスクのアタッチ:完了")
    } else { 
      Write-Output($Result | format-list -DisplayError)
      $Log.Error("データディスクのアタッチ:失敗")
      exit 9
    }
    $Result = Update-AzVM -ResourceGroupName $AzureVMInfo.ResourceGroupName -VM $AzureVMInfo  
    if($Result.IsSuccessStatusCode) {
      $Log.Info("仮想マシンの構成変更:完了")
    } else { 
      Write-Output($Result | format-list -DisplayError)
      $Log.Error("仮想マシンの構成変更:失敗")
      exit 9
    }

　　## リカバリ元ディスク削除
    $Log.Info("リカバリしたデータディスクを削除します:" + $RecoveryDisk.Name)
    $Result = Remove-AzDisk -ResourceGroupName $JobDatails.Properties["Target resource group"] -DiskName $RecoveryDisk.Name -Force
    if($Result.Status -eq "Succeeded") {
      $Log.Info("複製元データディスク削除:完了:")
    } else { 
      Write-Output($Result | format-list -DisplayError)
      $Log.Error("複製元データディスク削除:失敗")
      exit 9
    }
  }
  $Log.Info("仮想マシンのデータディスク置換処理:完了")


  ########################################
  ## 仮想マシンの再構築
  ########################################
  $Log.Info("仮想マシンの再構築処理:開始")
  $Log.Info("OSディスクのリプレイス処理を開始します:" + $ConfigOBJ.'properties.storageProfile'.osDisk.name)
  $OsDiskName = $AzureVMInfo.StorageProfile.OsDisk.Name
  $OsDisk = Get-AzDisk -ResourceGroupName $JobDatails.Properties["Target resource group"] -Name $ConfigOBJ.'properties.storageProfile'.osDisk.name
  $Result = Set-AzVMOSDisk -VM $AzureVMInfo -ManagedDiskId $OsDisk.Id -Name $OsDisk.Name 
  if($Result.ProvisioningState -eq "Succeeded") {
    $Log.Info("OSディスクのリプレイス:完了")
  } else {
    Write-Output($Result | format-list -DisplayError)
    $Log.Error("OSディスクのリプレイス:失敗")    
    exit 9
  }
  $Result = Update-AzVM -ResourceGroupName $AzureVMInfo.ResourceGroupName -VM $AzureVMInfo
  if($Result.IsSuccessStatusCode) {
    $Log.Info("仮想マシンの構成変更:完了")
  } else { 
    Write-Output($Result | format-list -DisplayError)
    $Log.Error("仮想マシンの構成変更:失敗")
    exit 9
  }

  $Result = Remove-AzDisk -ResourceGroupName $JobDatails.Properties["Target resource group"] -DiskName $OsDiskName -Force
  if($Result.Status -eq "Succeeded") {
    $Log.Info("OSディスク削除:完了:" + $SourceDataDisk.Name)
  } else { 
    Write-Output($Result | format-list -DisplayError)
    $Log.Error("OSディスク削除:失敗" + $SourceDataDisk.Name)
    exit 9
  }

  $Log.Info("仮想マシンを起動します:" + $AzureVMInfo.Name)
  $Result = Start-AzVM -Name $AzureVMInfo.Name -ResourceGroupName $AzureVMResourceGroupName
  if($Result.Status -eq "Succeeded") {
    $Log.Info("仮想マシンの起動:完了")
  } else { 
    Write-Output($Result | format-list -DisplayError)
    $Log.Error("仮想マシンの起動:失敗" )
    exit 9
  }
  $Log.Info("仮想マシンの再構築処理:完了")

  #################################################
  # エラーハンドリング
  #################################################
} catch {
    $Log.Error("仮想マシンの復元処理中にエラーが発生しました。")
    $Log.Error($_.Exception)
    exit 99
}
exit 0