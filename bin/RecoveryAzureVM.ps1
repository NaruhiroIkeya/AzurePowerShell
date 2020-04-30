<################################################################################
## Copyright(c) 2020 BeeX Inc. All rights reserved.
## @auther#Naruhiro Ikeya
##
## @name:RecoveryAzureVM.ps1
## @summary:VHDリカバリ後の仮想マシンの再構築スクリプト
##
## @since:2020/05/07
## @version:1.1
## @see:
## @parameter
##  1:Azure VM名
##  2:Azure VMリソースグループ名
##  3:Recovery Servicesコンテナー名
##  4:OSのみの復元フラグ
##  5:VM再構築フラグ
##
## @return:0:Success 9:エラー終了
################################################################################>

##########################
# パラメータ設定
##########################
param (
  [parameter(mandatory=$true)][string]$AzureVMName,
  [parameter(mandatory=$true)][string]$AzureVMResourceGroupName,
  [parameter(mandatory=$true)][string]$RecoveryServiceVaultName,
  [switch]$DataDiskOnly=$false,
  [switch]$RebuildVM=$false,
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
#$ErrorActionPreference = "Stop"
[string]$CredentialFile = "AzureCredential_Secure.xml"

##########################
# 警告の表示抑止
##########################
#Set-Item Env:\SuppressAzurePowerShellBreakingChangeWarnings "true"

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

  ############################
  # ResourceGroup名のチェック
  ############################
  $ResourceGroup = Get-AzResourceGroup | Where-Object{$_.ResourceGroupName -eq $AzureVMResourceGroupName}
  if(-not $ResourceGroup) { 
    $Log.Error("ResourceGroup名が不正です。" + $AzureVMResourceGroupName)
    exit 9
  }

  ############################
  # AzureVM名のチェック
  ############################
  $AzureVM = Get-AzVM -ResourceGroupName $AzureVMResourceGroupName | Where-Object{$_.Name -eq $AzureVMName}
  if(-not $AzureVM) { 
    $Log.Error("AzureVM名が不正です。" + $AzureVMName)
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
  $Log.Info("選択されたRecovery Servicesコンテナ:" + $RecoveryServiceVault.Name)
  $Log.Info("Recovery Servicesコンテナの選択:完了")

  #########################################
  ## 最新のリストアジョブ結果詳細を取得
  #########################################
  $Log.Info("最新のリカバリジョブ結果詳細取得:開始")
  $RecoveryVHDJob = Get-AzRecoveryServicesBackupJob -VaultId $RecoveryServiceVault.ID | Where-Object {$_.WorkloadName -eq $AzureVMName -and $_.Operation -eq "Restore" -and $_.Status -eq "Completed"} | Sort-Object @{Expression="Endtime";Descending=$true} | Select-Object -First 1
  if(-not $RecoveryVHDJob) {
    $Log.Error("リカバリジョブが存在しません")
    exit 9
  }
  $JobDatails = Get-AzRecoveryServicesBackupJobDetails -VaultId $RecoveryServiceVault.ID -Job $RecoveryVHDJob
  if(-not $JobDatails) {
    $Log.Error("リカバリジョブ詳細が取得できませんでした。")
    exit 9
  } elseif($JobDatails.Properties."Job Type" -ne "Recover disks") { 
    $Log.Error("最新のリカバリジョブがディスクのリカバリジョブではありません。")
    exit 9
  }
  $Log.Info("最新のリカバリジョブ結果")
  $Log.Info($($JobDatails | Format-List | Out-String -Stream))
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
    $Log.Error("Configファイルのダウンロードが失敗しました。")
    exit 9
  }
  $Log.Info("Configファイル（$ConfigFilePath）のダウンロードが完了しました。")
  $ConfigOBJ = ((Get-Content -Path $ConfigFilePath -Encoding Unicode)).TrimEnd([char]0x00) | ConvertFrom-Json
  $Log.Info("リカバリジョブConfig取得:完了")

  ####################################################
  ## 復元したディスクが全て揃っているか確認
  ####################################################
  $Log.Info("リカバリしたディスクの正常確認:開始")
  if(-not $DataDisksOnly) {
    $CheckDisk = Get-AzDisk -ResourceGroupName $JobDatails.Properties["Target resource group"] -DiskName $ConfigOBJ.'properties.storageProfile'.osDisk.Name
    if(-not $CheckDisk){
      $Log.Error("OSディスクが存在しません:" + $ConfigOBJ.'properties.storageProfile'.osDisk.Name)
      exit 9
    } elseif($CheckDisk.ProvisioningState -ne "Succeeded") {
      $Log.Error("OSディスクの復元が失敗しています:" + $ConfigOBJ.'properties.storageProfile'.osDisk.Name)
      exit 9
    } else {
      $Log.Info("OSディスクの復元確認が完了しました:" + $ConfigOBJ.'properties.storageProfile'.osDisk.Name)
    }
  }
  foreach($DataDiskInfo in $ConfigOBJ.'properties.storageProfile'.dataDisks){
    $CheckDisk = Get-AzDisk -ResourceGroupName $JobDatails.Properties["Target resource group"] -DiskName $DataDiskInfo.Name
    if(-not $CheckDisk){
      $Log.Error("Dataディスクが存在しません:" + $DataDiskInfo.Name)
      exit 9
    } elseif($CheckDisk.ProvisioningState -ne "Succeeded") {
      $Log.Error("Dataディスクの復元が失敗しています:" + $DataDiskInfo.Name)
      exit 9
    } else {
      $Log.Info("Dataディスクの復元確認が完了しました:" + $DataDiskInfo.Name)  	
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
  $Log.Info("リカバリ対象仮想マシン($($AzureVMInfo.Name))を停止します")
  $Result = Stop-AzVM -Name $AzureVMInfo.Name -ResourceGroupName $AzureVMInfo.ResourceGroupName -Force
  if($Result.Status -eq "Succeeded") {
    $Log.Info("リカバリ対象仮想マシンの停止:$($Result.Status)")
  } else { 
    $Log.Error($($Result | Format-List | Out-String -Stream))
    $Log.Error("リカバリ対象仮想マシンの停止:$($Result.Status)")
    exit 9
  }

  ########################################
  ## 仮想マシンを再構築する場合
  ########################################
  if($RebuildVM) {
    ########################################
    ## 仮想マシンの削除
    ########################################
    $Log.Info("仮想マシン(" + $AzureVMInfo.Name + ")の削除:開始")
    $RemoveResult = Remove-AzVM -Name $AzureVMInfo.Name -ResourceGroupName $AzureVMInfo.ResourceGroupName -Force
    if($RemoveResult.Status -eq "Succeeded") {
      $Log.Info("仮想マシンの削除:$($RemoveResult.Status)")
    } else {
      $Log.Error($($RemoveResult | Format-List | Out-String -Stream))
      $Log.Error("仮想マシンの削除:$($RemoveResult.Status)")
      exit 9
    }
    $Log.Info("仮想マシンの削除:完了")
  }

  if(-not $DataDiskOnly) {
    ########################################
    ## OSディスクの置換処理
    ########################################
    $Log.Info("仮想マシンのOSディスク置換処理:開始")
    $TargetOsDisk = Get-AzDisk -ResourceGroupName $AzureVMInfo.ResourceGroupName -DiskName $AzureVMInfo.StorageProfile.OsDisk.Name
    $SourceOsDisk = Get-AzDisk -ResourceGroupName $JobDatails.Properties["Target resource group"] -Name $ConfigOBJ.'properties.storageProfile'.osDisk.name
    ########################################
    ## 現行OSディスクの退避処理(日付を付与して退避)
    ########################################
    $Log.Info("現行OSディスク($($AzureVMInfo.StorageProfile.OsDisk.Name))の退避:開始")
    $TmpDiskConfig = New-AzDiskConfig -SourceResourceId $TargetOsDisk.Id -Location $TargetOsDisk.Location -CreateOption Copy -DiskSizeGB $TargetOsDisk.DiskSizeGB -SkuName $TargetOsDisk.Sku.Name
    $CopyResult = New-AzDisk -Disk $TmpDiskConfig -ResourceGroupName $AzureVMInfo.ResourceGroupName -DiskName $($AzureVMInfo.StorageProfile.OsDisk.Name + "_" + $(Get-Date -Format "yyyyMMddHHmm")) 
    if($CopyResult.ProvisioningState -eq "Succeeded") {
      $Log.Info("現行OSディスクの退避($($CopyResult.Name)):$($CopyResult.ProvisioningState)")
    } else {
      $Log.Error($($CopyResult | Format-List | Out-String -Stream))
      $Log.Error("現行OSディスクの退避($($CopyResult.Name)):$($CopyResult.ProvisioningState)")
      exit 9
    }

    if(-not $RebuildVM) {
      ########################################
      ## VMのOSディスクの置換処理(暫定)
      ########################################
      $Log.Info("OSディスク($($AzureVMInfo.StorageProfile.OsDisk.Name))のリプレイス処理:開始")
      $Result = Set-AzVMOSDisk -VM $AzureVMInfo -ManagedDiskId $SourceOsDisk.Id -Name $SourceOsDisk.Name 
      if($Result.ProvisioningState -eq "Succeeded") {
        $Log.Info("OSディスクのリプレイス処理($($Result.StorageProfile.OsDisk.Name)):$($Result.ProvisioningState)")
      } else {
        $Log.Error($($Result | Format-List | Out-String -Stream))
        $Log.Error("OSディスクのリプレイス処理($($Result.StorageProfile.OsDisk.Name)):$($Result.ProvisioningState)")
        exit 9
      }
      ########################################
      ## 仮想マシンの構成アップデート
      ########################################
      $Log.Info("仮想マシンの構成変更:開始")
      $Result = Update-AzVM -ResourceGroupName $AzureVMInfo.ResourceGroupName -VM $AzureVMInfo  
      if($Result.IsSuccessStatusCode) {
        $Log.Info("仮想マシンの構成変更:$($Result.StatusCode)")
      } else { 
        $Log.Error($($Result | Format-List | Out-String -Stream))
        $Log.Error("仮想マシンの構成変更:$($Result.StatusCode)")
        exit 9
      }
    }

    ########################################
    ## 現行OSディスクの削除
    ########################################
    $Log.Info("現行OSディスク($($TargetOsDisk.Name))の削除:開始" )
    $RemoveResult = Remove-AzDisk -ResourceGroupName $TargetOsDisk.ResourceGroupName -DiskName $TargetOsDisk.Name -Force
    if($RemoveResult.Status -eq "Succeeded") {
      $Log.Info("現行OSディスクの削除:$($RemoveResult.Status)")
    } else { 
      $Log.Error($($RemoveResult | Format-List | Out-String -Stream))
      $Log.Error("現行OSディスクの削除:$($RemoveResult.Status)")
      exit 9
    }

    ########################################
    ## 新ディスクの作成
    ########################################
    $Log.Info("新OSディスク$($TargetOsDisk.Name)の作成:開始")
    $TmpDiskConfig = New-AzDiskConfig -SourceResourceId $SourceOsDisk.Id -Location $SourceOsDisk.Location -CreateOption Copy -DiskSizeGB $SourceOsDisk.DiskSizeGB -SkuName $SourceOsDisk.Sku.Name
    $CopyResult = New-AzDisk -Disk $TmpDiskConfig -ResourceGroupName $AzureVMInfo.ResourceGroupName -DiskName $TargetOsDisk.Name
    if($CopyResult.ProvisioningState -eq "Succeeded") {
      $Log.Info("新OSディスクの作成:$($CopyResult.ProvisioningState)")
    } else {
      $Log.Error($($CopyResult | Format-List | Out-String -Stream))
      $Log.Error("新OSディスクの作成:$($CopyResult.ProvisioningState)")
      exit 9
    }

    if(-not $RebuildVM) {
      ########################################
      ## VMのOSディスクの置換処理
      ########################################
      $TargetOsDisk = Get-AzDisk -ResourceGroupName $AzureVMInfo.ResourceGroupName -DiskName $TargetOsDisk.Name
      $Log.Info("OSディスク($($AzureVMInfo.StorageProfile.OsDisk.Name))のリプレイス処理:開始")
      $Result = Set-AzVMOSDisk -VM $AzureVMInfo -ManagedDiskId $TargetOsDisk.Id -Name $TargetOsDisk.Name 
      if($Result.ProvisioningState -eq "Succeeded") {
        $Log.Info("OSディスクのリプレイス処理($($Result.StorageProfile.OsDisk.Name)):$($Result.ProvisioningState)")
      } else {
        $Log.Error($($Result | Format-List | Out-String -Stream))
        $Log.Error("OSディスクのリプレイス処理($($Result.StorageProfile.OsDisk.Name)):$($Result.ProvisioningState)")
        exit 9
      }
      ########################################
      ## 仮想マシンの構成アップデート
      ########################################
      $Log.Info("仮想マシンの構成変更:開始")
      $Result = Update-AzVM -ResourceGroupName $AzureVMInfo.ResourceGroupName -VM $AzureVMInfo  
      if($Result.IsSuccessStatusCode) {
        $Log.Info("仮想マシンの構成変更:$($Result.StatusCode)")
      } else { 
        $Log.Error($($Result | Format-List | Out-String -Stream))
        $Log.Error("仮想マシンの構成変更:$($Result.StatusCode)")
        exit 9
      }
    }
    $Log.Info("仮想マシンのOSディスク置換処理:完了")
  }

  ########################################
  ## Dataディスクの置換処理
  ########################################
  $Log.Info("仮想マシンのデータディスク置換処理:開始")
  foreach($RecoveryDisk in $ConfigOBJ.'properties.storageProfile'.dataDisks) {
    if(-not $OSDiskOnly) {
      $SourceDataDisk = $AzureVMInfo.StorageProfile.DataDisks | Where-Object { $_.Lun -eq $RecoveryDisk.Lun }
      if(-not $SourceDataDisk){
        $Log.Error("仮想マシンにLUNが一致するディスクが接続されてません。:" + $RecoveryDisk.Name)
        exit 9
      }

      if(-not $RebuildVM) {
        ########################################
        ## 仮想マシンからデータディスクをデタッチ
        ########################################
        $Log.Info("データディスク(LUN:$($SourceDataDisk.Lun),DISK:$($SourceDataDisk.Name))のデタッチ処理:開始")
        $Result = Remove-AzVMDataDisk -VM $AzureVMInfo -Name $SourceDataDisk.Name
        if($Result.ProvisioningState -eq "Succeeded") {
          $Log.Info("データディスクのデタッチ処理:$($Result.ProvisioningState)")
        } else { 
          $Log.Error($($Result | Format-List | Out-String -Stream))
          $Log.Error("データディスクのデタッチ処理:$($Result.ProvisioningState)")
          exit 9
        }
        ########################################
        ## 仮想マシンの構成アップデート
        ########################################
        $Log.Info("仮想マシンの構成変更:開始")
        $Result = Update-AzVM -ResourceGroupName $AzureVMInfo.ResourceGroupName -VM $AzureVMInfo  
        if($Result.IsSuccessStatusCode) {
          $Log.Info("仮想マシンの構成変更:$($Result.StatusCode)")
        } else { 
          $Log.Error($($Result | Format-List | Out-String -Stream))
          $Log.Error("仮想マシンの構成変更:$($Result.StatusCode)")
          exit 9
        }
      }

      ########################################
      ## デタッチしたディスクの削除
      ########################################
      $Log.Info("データディスク($($SourceDataDisk.Name))の削除処理:開始")
      $Result = Remove-AzDisk -ResourceGroupName $AzureVMInfo.ResourceGroupName -DiskName $SourceDataDisk.Name -Force
      if($Result.Status -eq "Succeeded") {
        $Log.Info("データディスクの削除:$($Result.Status)")
      } else { 
        $Log.Error($($Result | Format-List | Out-String -Stream))
        $Log.Error("データディスクの削除:$($Result.Status)")
        exit 9
      }

      ########################################
      ## リカバリディスク名称変更（複製）
      ########################################
      $Log.Info("データディスク($($RecoveryDisk.Name))の複製処理:開始")
      $CopyResult = Get-AzDisk -ResourceGroupName $JobDatails.Properties["Target resource group"] -DiskName $RecoveryDisk.Name | Update-AzDisk -ResourceGroupName $AzureVMInfo.ResourceGroupName -DiskName $SourceDataDisk.Name
      if($CopyResult.ProvisioningState -eq "Succeeded") {
        $Log.Info("データディスク($($CopyResult.Name))の複製処理:$($CopyResult.ProvisioningState)")
      } else {
        $Log.Error($($CopyResult | Format-List | Out-String -Stream))
        $Log.Error("データディスク($($CopyResult.Name))の複製処理:$($CopyResult.ProvisioningState)")
        exit 9
      }

      if(-not $RebuildVM) {
        ########################################
        ## 複製ディスクのアタッチ
        ########################################
        $Log.Info("データディスク($($CopyResult.Name))のアタッチ:開始")
        $Result = Add-AzVMDataDisk -CreateOption Attach -Lun $SourceDataDisk.lun -Caching $SourceDataDisk.Caching -VM $AzureVMInfo -ManagedDiskId $CopyResult.Id
        if($Result.ProvisioningState -eq "Succeeded") {
          $Log.Info("データディスクのアタッチ処理:$($Result.ProvisioningState)")
        } else { 
          $Log.Error($($Result | Format-List | Out-String -Stream))
          $Log.Error("データディスクのアタッチ処理:$($Result.ProvisioningState)")
          exit 9
        }
        ########################################
        ## 仮想マシンの構成アップデート
        ########################################
        $Log.Info("仮想マシンの構成変更:開始")
        $Result = Update-AzVM -ResourceGroupName $AzureVMInfo.ResourceGroupName -VM $AzureVMInfo  
        if($Result.IsSuccessStatusCode) {
          $Log.Info("仮想マシンの構成変更:$($Result.StatusCode)")
        } else { 
          $Log.Error($($Result | Format-List | Out-String -Stream))
          $Log.Error("仮想マシンの構成変更:$($Result.StatusCode)")
          exit 9
        }
      }        
    }
  }
  $Log.Info("仮想マシンのデータディスク置換処理:完了")

  ########################################
  ## 仮想マシンの再構築
  ########################################
  $Log.Info("仮想マシンの再構築処理:開始")
  if($RebuildVM) {
    $AzureVMInfo.StorageProfile.OSDisk.CreateOption = "Attach"
    $AzureVMInfo.StorageProfile.DataDisks | ForEach-Object { $_.CreateOption = "Attach" }
    $AzureVMInfo.StorageProfile.ImageReference = $null
    $AzureVMInfo.OSProfile = $null
    $Log.Info("仮想マシンを作成します。")
    $CreateVMJob = New-AzVM -ResourceGroupName $AzureVMInfo.ResourceGroupName -Location $AzureVMInfo.Location -VM $AzureVMInfo -DisableBginfoExtension
    if($CreateVMJob){
        $Log.Info("仮想マシンの作成:$($Result.StatusCode)")
    } else { 
      $Log.Error($($CreateVMJob | Format-List | Out-String -Stream))
      $Log.Error("仮想マシンの作成:$($Result.StatusCode)")
      exit 9
    }
  } elseif (-not $RebuildVM) {
    $Log.Info("仮想マシンを起動します:" + $AzureVMInfo.Name)
    $Result = Start-AzVM -Name $AzureVMInfo.Name -ResourceGroupName $AzureVMResourceGroupName
    if($Result.Status -eq "Succeeded") {
      $Log.Info("仮想マシンの起動:完了")
    } else { 
      $Log.Error($($Result | Format-List | Out-String -Stream))
      $Log.Error("仮想マシンの起動:失敗" )
      exit 9
    }
    $Log.Info("仮想マシンの再構築処理:完了")
  }

  ########################################
  ## リカバリ元ディスク削除
  ########################################
  $Log.Info("リカバリしたディスクの削除処理:開始")
  $Result = Remove-AzDisk -ResourceGroupName $JobDatails.Properties["Target resource group"] -DiskName $ConfigOBJ.'properties.storageProfile'.osDisk.Name -Force
  if($Result.Status -eq "Succeeded") {
    $Log.Info("OSディスク($($ConfigOBJ.'properties.storageProfile'.osDisk.Name))の削除:$($Result.Status)")
  } else { 
    $Log.Error($($Result | Format-List | Out-String -Stream))
    $Log.Error("OSディスク($($ConfigOBJ.'properties.storageProfile'.osDisk.Name))の削除:$($Result.Status)")
    exit 9
  }
  foreach($DataDiskInfo in $ConfigOBJ.'properties.storageProfile'.dataDisks){
    $Result = Remove-AzDisk -ResourceGroupName $JobDatails.Properties["Target resource group"] -DiskName $DataDiskInfo.Name -Force
    if($Result.Status -eq "Succeeded") {
      $Log.Info("データディスク($($DataDiskInfo.Name))の削除:$($Result.Status)")
    } else { 
      $Log.Error($($Result | Format-List | Out-String -Stream))
      $Log.Error("データディスク($($DataDiskInfo.Name))の削除:$($Result.Status)")
      exit 9
    }
  }
  $Log.Info("リカバリしたディスクの削除処理:完了")

<#
    $Log.Info("リカバリしたデータディスクを削除します:" + $RecoveryDisk.Name)
    $Result = Remove-AzDisk -ResourceGroupName $JobDatails.Properties["Target resource group"] -DiskName $RecoveryDisk.Name -Force
    if($Result.Status -eq "Succeeded") {
      $Log.Info("複製元データディスク削除:完了:")
    } else { 
      Write-Output($($Result | Format-List | Out-String -Stream))
      $Log.Error("複製元データディスク削除:失敗")
      exit 9
    }
#>

  #################################################
  # エラーハンドリング
  #################################################
} catch {
    $Log.Error("仮想マシンの復元処理中にエラーが発生しました。")
    $Log.Error($_.Exception)
    exit 99
}
exit 0