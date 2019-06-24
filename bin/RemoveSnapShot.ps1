<################################################################################
## Copyright(c) 2019 BeeX Inc. All rights reserved.
## @auther#Naruhiro Ikeya
##
## @name:RemoveSnapshot.ps1
## @summary:期限切れスナップショットの削除
##
## @since:2019/03/16
## @version:1.0
## @see:
## @parameter
##  1:Azure VMリソースグループ名
##
## @return:0:Success 9:エラー終了
################################################################################>

##########################
# パラメータ設定
##########################
param (
  [string]$AzureVMResourceGroupName,
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
  # パラメータチェック
  ###################################
  $RemoveSnapshots = $null
  if(-not $AzureVMResourceGroupName) {
    $RemoveSnapshots = Get-AzSnapshot | Where-Object { $_.Tags.ExpireDate -ne $null -and [DateTime]::Parse($_.Tags.ExpireDate) -lt (Get-Date) }
  } else {
    $ResourceGroups = Get-AzResourceGroup -Name $AzureVMResourceGroupName
    if(-not $ResourceGroups) {
      $Log.Info("指定されたリソースグループがありません:$AzureVMResourceGroupName")
      exit 9
    }
    $RemoveSnapshots = Get-AzSnapshot -ResourceGroupName $ResourceGroups.ResourceGroupName | Where-Object { $_.Tags.ExpireDate -ne $null -and [DateTime]::Parse($_.Tags.ExpireDate) -lt (Get-Date) }
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
    Remove-AzSnapshot -ResourceGroupName $Snapshot.ResourceGroupName -SnapshotName $Snapshot.Name -Force | % { $Log.Info("期限切れSnapshot削除:" + $Snapshot.Name + " : " + $_.Status) }
  }
  $Log.Info("期限切れSnapShot削除:完了")
} catch {
    $Log.Error("管理ディスクのスナップショット削除中にエラーが発生しました。")
    $Log.Error($_.Exception)
    exit 99
}
exit 0