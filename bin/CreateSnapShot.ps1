<################################################################################
## Copyright(c) 2019 BeeX Inc. All rights reserved.
## @auther#Naruhiro Ikeya
##
## @name:CreateSnapshot.ps1
## @summary:Azure VMデータディスクのSnapshot
##
## @since:2019/03/16
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
  [parameter(mandatory=$true)][int]$ExpireDays
)

##########################
# パラメータチェック
##########################
if($ExpireDays -lt 1) {
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] 保持日数は1以上を設定してください。")
  exit 1
}

##########################
# 警告の表示抑止
##########################
Set-Item Env:\SuppressAzurePowerShellBreakingChangeWarnings "true"

try {
  Import-Module Az

  ##########################
  # Azureへのログイン
  ##########################
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] サービスプリンシパルを利用しAzureへログインします。")
  $SecPasswd = ConvertTo-SecureString $Key -AsPlainText -Force
  $MyCreds = New-Object System.Management.Automation.PSCredential ($ApplicationID, $SecPasswd)
  $LoginInfo = Login-AzAccount -ServicePrincipal -Tenant $TennantID -Credential $MyCreds -WarningAction Ignore
  if(-not $LoginInfo) { 
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Azureへログインできませんでした。")
    exit 9
  }

  ###################################
  # AzureVM 確認
  ###################################
  $SnapshotSuffix = "_Snapshot_" + (Get-Date).ToString("yyyyMMddHHmm")
  $AzureVMInfo = Get-AzVM -ResourceGroupName $AzureVMResourceGroupName -Name $AzureVMName
  if(-not $AzureVMInfo) {
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Azure VMが見つかりません。")
    exit 9
  }

  ###################################
  # AzureVM Snapshot作成
  ###################################
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] $AzureVMName SnapShot作成:開始")
  $CreateDate=(Get-Date).ToString("yyyy/MM/dd HH:mm")
  if($Luns -eq "ALL") {
    $AzureVMInfo.StorageProfile.DataDisks | ForEach-Object { New-AzSnapshotConfig -SourceUri $_.ManagedDisk.Id -Location $AzureVMInfo.Location -Tag @{ SourceVMName=$AzureVMInfo.Name; SourceDiskName=$_.Name; SourceLun=[string]$_.Lun; CreateDate=$CreateDate; ExpireDate=(Get-Date).AddDays($ExpireDays).ToString("yyyy/MM/dd") } -CreateOption copy } | % { New-AzSnapshot -Snapshot $_ -SnapshotName ($_.Tags.SourceDiskName + $SnapshotSuffix) -ResourceGroupName $AzureVMInfo.ResourceGroupName } | % { Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $_.Name + " : " + $_.ProvisioningState) }
  } else {
    foreach($Lun in $($Luns -split ",")) {
      $AzureVMInfo.StorageProfile.DataDisks | ? { $_.Lun -eq $Lun } | ForEach-Object { New-AzSnapshotConfig -SourceUri $_.ManagedDisk.Id -Location $AzureVMInfo.Location -Tag @{ SourceVMName=$AzureVMInfo.Name; SourceDiskName=$_.Name; SourceLun=[string]$_.Lun; CreateDate=$CreateDate; ExpireDate=(Get-Date).AddDays($ExpireDays).ToString("yyyy/MM/dd") } -CreateOption copy } | % { New-AzSnapshot -Snapshot $_ -SnapshotName ($_.Tags.SourceDiskName + $SnapshotSuffix) -ResourceGroupName $AzureVMInfo.ResourceGroupName } | % { Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $_.Name + " : " + $_.ProvisioningState) }
    }
  }
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] $AzureVMName SnapShot作成:完了")

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
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] 管理ディスクのスナップショット作成中にエラーが発生しました。")
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $error[0] | Format-List --DisplayError)
    exit 99
}
exit 0