<################################################################################
## Copyright(c) 2019 BeeX Inc. All rights reserved.
## @auther#Naruhiro Ikeya
##
## @name:CreateSnapshot.ps1
## @summary:Azure VMデータディスクのSnapshot
##
## @since:2019/06/24
## @version:1.0
## @see:
## @parameter
##  1:Azure VM名
##  2:Azure VMリソースグループ名
##  3:保存日数
##
## @return:0:Success 9:エラー終了
################################################################################>

##########################
# パラメータ設定
##########################
param (
  [parameter(mandatory=$true)][string]$AzureVMName,
  [parameter(mandatory=$true)][string]$AzureVMResourceGroupName,
  [parameter(mandatory=$false)][string]$Luns="ALL",
  [parameter(mandatory=$true)][int]$ExpireDays,
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

##########################
# 警告の表示抑止
##########################
Set-Item Env:\SuppressAzurePowerShellBreakingChangeWarnings "true"

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
if($ExpireDays -lt 1) {
  $Log.Info("保持日数は1以上を設定してください。")
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
  
  ###################################
  # AzureVM 確認
  ###################################
  $SnapshotSuffix = "_Snapshot_" + (Get-Date).ToString("yyyyMMddHHmm")
  $AzureVMInfo = Get-AzVM -ResourceGroupName $AzureVMResourceGroupName -Name $AzureVMName
  if(-not $AzureVMInfo) {
    $Log.Info("Azure VMが見つかりません。")
    exit 9
  }

  ###################################
  # AzureVM Snapshot作成
  ###################################
  $Log.Info("$AzureVMName SnapShot作成:開始")
  $CreateDate=(Get-Date).ToString("yyyy/MM/dd HH:mm")
  if($Luns -eq "ALL") {
    $AzureVMInfo.StorageProfile.DataDisks | ForEach-Object { New-AzSnapshotConfig -SourceUri $_.ManagedDisk.Id -Location $AzureVMInfo.Location -Tag @{ SourceVMName=$AzureVMInfo.Name; SourceDiskName=$_.Name; SourceLun=[string]$_.Lun; CreateDate=$CreateDate; ExpireDate=(Get-Date).AddDays($ExpireDays).ToString("yyyy/MM/dd") } -CreateOption copy } | % { New-AzSnapshot -Snapshot $_ -SnapshotName ($_.Tags.SourceDiskName + $SnapshotSuffix) -ResourceGroupName $AzureVMInfo.ResourceGroupName } | % { $Log.Info("" + $_.Name + " : " + $_.ProvisioningState) }
  } else {
    foreach($Lun in $($Luns -split ",")) {
      $AzureVMInfo.StorageProfile.DataDisks | ? { $_.Lun -eq $Lun } | ForEach-Object { New-AzSnapshotConfig -SourceUri $_.ManagedDisk.Id -Location $AzureVMInfo.Location -Tag @{ SourceVMName=$AzureVMInfo.Name; SourceDiskName=$_.Name; SourceLun=[string]$_.Lun; CreateDate=$CreateDate; ExpireDate=(Get-Date).AddDays($ExpireDays).ToString("yyyy/MM/dd") } -CreateOption copy } | % { New-AzSnapshot -Snapshot $_ -SnapshotName ($_.Tags.SourceDiskName + $SnapshotSuffix) -ResourceGroupName $AzureVMInfo.ResourceGroupName } | % { $Log.Info("" + $_.Name + " : " + $_.ProvisioningState) }
    }
  }
  $Log.Info("$AzureVMName SnapShot作成:完了")

  ########################################
  # AzureVM に付与されているタグを追加
  ########################################
  if($null -ne $AzureVMInfo.Tags) {
    $DiskSnapshots = Get-AzResource -ResourceGroupName $AzureVMInfo.ResourceGroupName -ResourceType Microsoft.Compute/snapshots | ? { $_.Tags.SourceVMName -eq $AzureVMInfo.Name }
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
    }
  }
} catch {
    $Log.Error("管理ディスクのスナップショット作成中にエラーが発生しました。")
    $Log.Error($_.Exception)
    exit 99
}
exit 0