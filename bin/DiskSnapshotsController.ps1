<################################################################################
## Copyright(c) 2020 BeeX Inc. All rights reserved.
## @auther#Naruhiro Ikeya
##
## @name:VMDiskSnapshots.ps1
## @summary:Azure VM Disk Snapshots Controller
##
## @since:2020/05/02
## @version:1.0
## @see:
## @parameter
##  1:Snapshot作成モード
##  2:Snapshot削除モード
##  3:Azure VMリソースグループ名
##  4:Azure VM名
##  5:LUN
##  6:Snapshot保存期間
##  7:標準出力
##  8:Snapshot実行フラグ
##
## @return:0:Success 9:エラー終了
################################################################################>

##########################
# パラメータ設定
##########################
param (
  [parameter(mandatory=$false)][switch]$CreateSnapshot,
  [parameter(mandatory=$false)][switch]$RemoveSnapshot,
  [parameter(mandatory=$false)][string]$ResourceGroupName,
  [parameter(mandatory=$false)][string]$AzureVMName,
  [parameter(mandatory=$false)][string]$Luns="ALL",
  [parameter(mandatory=$false)][int]$ExpireDays,
  [parameter(mandatory=$false)][switch]$DataDiskOnly,
  [parameter(mandatory=$false)][switch]$Reboot,
  [parameter(mandatory=$false)][switch]$Eventlog=$false,
  [parameter(mandatory=$false)][switch]$Stdout,
  [parameter(mandatory=$false)][switch]$Force
)

##########################
# モジュールのロード
##########################
. .\LogController.ps1
. .\AzureLogonFunction.ps1

##########################
# 固定値 
##########################
[string]$CredenticialFile = "AzureCredential_Secure.xml"
[int]$SaveDays = 7
[string]$SnapshotSuffix = "_Snapshot_" + (Get-Date).ToString("yyyyMMddHHmm")

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
if (-not ($CreateSnapshot -xor $RemoveSnapshot)) {
  $Log.Error("Syntax Error:実行時に -CreateSnapshot / -RemoveSnapshot を指定してください。")
  $Log.Info("スナップショット作成時に必須のオプション：")
  $Log.Info("　-ResourceGroupName:リソースグループ名")
  $Log.Info("　-AzureVMName:VM名")
  $Log.Info("　-ExpireDays:保持日数（1以上を設定）")
  $Log.Info("Option:　-Luns:LUNs カンマ区切り（Default:ALL）")
  $Log.Info("スナップショット削除時に必須のオプション：（Optionの指定が無い場合は、全ての期限切れSnapshotが削除対象）")
  $Log.Info("Option:　-ResourceGroupName:リソースグループ名（リソースグループでSnapshot削除対象指定）")
  $Log.Info("Option:　-AzureVMName:VM名（VMでSnapshot削除対象指定）")
  exit 9
}

if($CreateSnapshot) {
  if(-not $ResourceGroupName) {
    $Log.Error("リソースグループ名を指定してください。")
    exit 9
  }
  if(-not $AzureVMName) {
    $Log.Error("VM名を指定してください。")
    exit 9
  }
  if($ExpireDays -lt 1) {
    $Log.Info("保持日数は1以上を設定してください。")
    exit 1
  }
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
  
  if($CreateSnapshot) {
    ###################################
    # AzureVM 確認
    ###################################
    $ResourceGroups = Get-AzResourceGroup -Name $ResourceGroupName
    if(-not $ResourceGroups) {
      $Log.Info("指定されたリソースグループがありません:$ResourceGroupName")
      exit 9
    }
    $AzureVMInfo = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $AzureVMName
    if(-not $AzureVMInfo) {
      $Log.Info("指定されたAzure VMが見つかりません:$AzureVMName")
      exit 9
    }

    ###################################
    # 再起動実施判断
    ###################################
    $Log.Info("$AzureVMName のステータスを取得します。")
    $AzureVMStatus = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $AzureVMName -Status | Select-Object @{n="Status"; e={$_.Statuses[1].Code}}
    if(-not $AzureVMStatus) { 
      $Log.Info("AzureVMのステータスが取得できませんでした。")
      $Log.Info("AzureVMの再起動は実施しません。")
      $Reboot = $false
    } else {
      $Log.Info("現在のステータスは [" + $AzureVMStatus.Status + "] です。")
      $EnableBoot = if(($AzureVMStatus.Status -eq "PowerState/deallocated") -or ($AzureVMStatus.Status -eq "PowerState/stopped")) { Write-Output 0 } else { Write-Output 1 }
    }

    ###################################
    # 再起動モードの時はVM停止
    ###################################
    if($Reboot -and $EnableBoot) {
      $Log.Info("AzureVMを停止します。")
      $JobResult = Get-AzVM -ResourceGroupName $ResourceGroupName  -Name $AzureVMName | ForEach-Object { Stop-AzVM -ResourceGroupName $_.ResourceGroupName -Name $_.Name -Force }
      if($JobResult.Status -eq "Failed") {
        $Log.Error("AzureVM停止ジョブがエラー終了しました。")
        $Log.Error($($JobResult | Format-List | Out-String -Stream))
        exit 9
      } else {
        $Log.Info("AzureVM停止ジョブが完了しました。")
        exit 0
      }
    }

    ###################################
    # AzureVM Snapshot作成
    ###################################
    $Log.Info("$AzureVMName SnapShot作成:開始")
    $CreateDate=(Get-Date).ToString("yyyy/MM/dd HH:mm")
    if(-not $DataDiskOnly) {
      $AzureVMInfo.StorageProfile.OsDisk | ForEach-Object { New-AzSnapshotConfig -SourceUri $_.ManagedDisk.Id -Location $AzureVMInfo.Location -Tag @{ SourceVMName=$AzureVMInfo.Name; SourceDiskName=$_.Name; SourceLun="OS"; CreateDate=$CreateDate; ExpireDate=(Get-Date).AddDays($ExpireDays).ToString("yyyy/MM/dd") } -CreateOption copy } | ForEach-Object { New-AzSnapshot -Snapshot $_ -SnapshotName ($_.Tags.SourceDiskName + $SnapshotSuffix) -ResourceGroupName $AzureVMInfo.ResourceGroupName } | ForEach-Object { $Log.Info("" + $_.Name + " : " + $_.ProvisioningState) }
      $Log.Info("$AzureVMName OS Disk SnapShot 作成:完了")
    }
    if($Luns -eq "ALL") {
      $AzureVMInfo.StorageProfile.DataDisks | ForEach-Object { New-AzSnapshotConfig -SourceUri $_.ManagedDisk.Id -Location $AzureVMInfo.Location -Tag @{ SourceVMName=$AzureVMInfo.Name; SourceDiskName=$_.Name; SourceLun=[string]$_.Lun; CreateDate=$CreateDate; ExpireDate=(Get-Date).AddDays($ExpireDays).ToString("yyyy/MM/dd") } -CreateOption copy } | ForEach-Object { New-AzSnapshot -Snapshot $_ -SnapshotName ($_.Tags.SourceDiskName + $SnapshotSuffix) -ResourceGroupName $AzureVMInfo.ResourceGroupName } | ForEach-Object { $Log.Info("" + $_.Name + " : " + $_.ProvisioningState) }
    } else {
      foreach($Lun in $($Luns -split ",")) {
        $AzureVMInfo.StorageProfile.DataDisks | Where-Object { $_.Lun -eq $Lun } | ForEach-Object { New-AzSnapshotConfig -SourceUri $_.ManagedDisk.Id -Location $AzureVMInfo.Location -Tag @{ SourceVMName=$AzureVMInfo.Name; SourceDiskName=$_.Name; SourceLun=[string]$_.Lun; CreateDate=$CreateDate; ExpireDate=(Get-Date).AddDays($ExpireDays).ToString("yyyy/MM/dd") } -CreateOption copy } | ForEach-Object { New-AzSnapshot -Snapshot $_ -SnapshotName ($_.Tags.SourceDiskName + $SnapshotSuffix) -ResourceGroupName $AzureVMInfo.ResourceGroupName } | ForEach-Object { $Log.Info("" + $_.Name + " : " + $_.ProvisioningState) }
      }
    }
    $Log.Info("$AzureVMName Data Disk SnapShots 作成:完了")

    ########################################
    # AzureVM に付与されているタグを追加
    ########################################
    if($null -ne $AzureVMInfo.Tags) {
      $DiskSnapshots = Get-AzResource -ResourceGroupName $AzureVMInfo.ResourceGroupName -ResourceType Microsoft.Compute/snapshots | Where-Object { $_.Tags.SourceVMName -eq $AzureVMInfo.Name }
      foreach($Snapshot in $DiskSnapshots) {
        $ResourceTags = (Get-AzResource -ResourceId $Snapshot.Id).Tags
        if($ResourceTags) {
          foreach($Key in $AzureVMInfo.Tags.Keys) {
            if (-not($ResourceTags.ContainsKey($key))) {
              $ResourceTags.Add($Key, $AzureVMInfo.Tags[$Key])
            }
          }
          $Result = Set-AzResource -Tag $ResourceTags -ResourceId $Snapshot.ResourceId -Force
        } else {
          $Result = Set-AzResource -Tag $AzureVMInfo.Tags -ResourceId $Snapshot.ResourceId -Force
        }
        if($Result) {}
      }
    }

    ###################################
    # 再起動モードの時はVM起動
    ###################################
    if($Reboot -and $EnableBoot) {
      $Log.Info("AzureVMを起動します。")
      $JobResult = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $AzureVMName | ForEach-Object { Start-AzVM -ResourceGroupName $_.ResourceGroupName -Name $_.Name }
      if($JobResult.Status -eq "Failed") {
        $Log.Error("AzureVM起動ジョブがエラー終了しました。")
        $Log.Error($($JobResult | Format-List | Out-String -Stream))
        exit 9
      } else {
        $Log.Info("AzureVM起動ジョブが完了しました。")
        exit 0
      }
    }
  } elseif($RemoveSnapshot) {
    $RemoveSnapshots = $null
    if(-not $ResourceGroupName) {
      if($Force) {
        $RemoveSnapshots = Get-AzSnapshot
      } else {
        $RemoveSnapshots = Get-AzSnapshot | Where-Object { $_.Tags.ExpireDate -ne $null -and [DateTime]::Parse($_.Tags.ExpireDate) -lt (Get-Date) }
      }
    } elseif($ResourceGroupName) {
      $ResourceGroups = Get-AzResourceGroup -Name $ResourceGroupName
      if(-not $ResourceGroups) {
        $Log.Info("指定されたリソースグループがありません:$ResourceGroupName")
        exit 9
      }
      if($Force) {
        $RemoveSnapshots = Get-AzSnapshot -ResourceGroupName $ResourceGroups.ResourceGroupName
      } else {
        $RemoveSnapshots = Get-AzSnapshot -ResourceGroupName $ResourceGroups.ResourceGroupName | Where-Object { $_.Tags.ExpireDate -ne $null -and [DateTime]::Parse($_.Tags.ExpireDate) -lt (Get-Date) }
      }
    } else {
      $ResourceGroups = Get-AzResourceGroup -Name $ResourceGroupName
      if(-not $ResourceGroups) {
        $Log.Info("指定されたリソースグループがありません:$ResourceGroupName")
        exit 9
      }
      if($Force) {
        $RemoveSnapshots = Get-AzSnapshot -ResourceGroupName $ResourceGroups.ResourceGroupName -SnapshotName $($AzureVMName + "*") | Where-Object { $_.Tags.SourceVMName -eq $AzureVMName }
      } else {
        $RemoveSnapshots = Get-AzSnapshot -ResourceGroupName $ResourceGroups.ResourceGroupName -SnapshotName $($AzureVMName + "*") | Where-Object { $_.Tags.ExpireDate -ne $null -and [DateTime]::Parse($_.Tags.ExpireDate) -lt (Get-Date) -and $_.Tags.SourceVMName -eq $AzureVMName }
      }
    }
    if(-not $RemoveSnapshots){
      $Log.Info("削除対象のSnapshotがありません。")
      exit 0
    }

    ###################################
    # AzureVM Snapshot世代管理
    ###################################
    $Log.Info("期限切れSnapShot削除:開始")
    foreach ($Snapshot in $RemoveSnapshots) {
      Remove-AzSnapshot -ResourceGroupName $Snapshot.ResourceGroupName -SnapshotName $Snapshot.Name -Force | ForEach-Object { $Log.Info("期限切れSnapshot削除:" + $Snapshot.Name + " : " + $_.Status) }
    }
    $Log.Info("期限切れSnapShot削除:完了")
  } else {
    $Log.Error("Logic Error!!")
    exit 99
  }
} catch {
    $Log.Error("管理ディスクのスナップショット作成中にエラーが発生しました。")
    $Log.Error($_.Exception)
    exit 99
}
exit 0