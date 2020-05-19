<################################################################################
## Copyright(c) 2019 BeeX Inc. All rights reserved.
## @auther#Naruhiro Ikeya
##
## @name:RecoveryDataDisk.ps1
## @summary:管理ディスクのスナップショットからデータディスクの復元
##
## @since:2019/02/03
## @version:1.0
## @see:
## @parameter
##  1:Azure VM名
##  2:Azure VMリソースグループ名
##
## @return:0:Success 9:エラー終了
################################################################################>

##########################
# パラメータ設定
##########################
param (
  [parameter(mandatory=$true)][string]$AzureVMName,
  [parameter(mandatory=$true)][string]$AzureVMResourceGroupName,
  [parameter(mandatory=$true)][switch]$Eventlog=$false,
  [parameter(mandatory=$true)][switch]$Stdout
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
  $AzureVMInfo = Get-AzVM -ResourceGroupName $AzureVMResourceGroupName -Name $AzureVMName
  if(-not $AzureVMInfo) {
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $AzureVMResourceGroupName + "に" + $AzureVMName + "が存在しません。")
    exit 9
  }

  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] リカバリポイントの選択:開始")
  ##############################
  # リストボックスフォーム作成
  ##############################
  Add-Type -AssemblyName System.Windows.Forms
  Add-Type -AssemblyName System.Drawing

  $form = New-Object System.Windows.Forms.Form
  $form.Text = 'リカバリ対象を選択してください。'
  $form.Size = New-Object System.Drawing.Size(350,200)
  $form.StartPosition = 'CenterScreen'

  $OKButton = New-Object System.Windows.Forms.Button
  $OKButton.Location = New-Object System.Drawing.Point(75,120)
  $OKButton.Size = New-Object System.Drawing.Size(75,23)
  $OKButton.Text = 'OK'
  $OKButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
  $form.AcceptButton = $OKButton
  $form.Controls.Add($OKButton)

  $CancelButton = New-Object System.Windows.Forms.Button
  $CancelButton.Location = New-Object System.Drawing.Point(150,120)
  $CancelButton.Size = New-Object System.Drawing.Size(75,23)
  $CancelButton.Text = 'Cancel'
  $CancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
  $form.CancelButton = $CancelButton
  $form.Controls.Add($CancelButton)

  $label = New-Object System.Windows.Forms.Label
  $label.Location = New-Object System.Drawing.Point(10,20)
  $label.Size = New-Object System.Drawing.Size(320,20)
  $label.Text = 'リカバリ対象を選択してください：'
  $form.Controls.Add($label)

  $listBox = New-Object System.Windows.Forms.ListBox
  $listBox.Location = New-Object System.Drawing.Point(10,40)
  $listBox.Size = New-Object System.Drawing.Size(310,20)
  $listBox.Height = 80

  ##############################
  # Snapshot作成時間の一覧化
  ##############################
  Get-AzSnapshot -ResourceGroupName $AzureVMResourceGroupName | Where-Object { $_.Tags.SourceVMName -ne $null -and $_.Tags.SourceVMName -eq $AzureVMName } | Sort-Object {$_.tags.CreateDate} -unique | ForEach-Object { [void] $listBox.Items.Add($_.tags.CreateDate) } 
  $form.Controls.Add($listBox)
  
  ##############################
  # リストボックスの表示
  ##############################
  $form.Topmost = $true
  $result = $form.ShowDialog()

  if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
    $RecoveryPoint = $listBox.SelectedItem
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $RecoveryPoint + "にデータディスクを復元します")
  } elseif ($result -eq [System.Windows.Forms.DialogResult]::Cancel) {
    exit 0
  } else {
    exit 0
  }

  ##############################
  # リカバリ対象ディスクの一覧
  ##############################
  $listBox.Items.Clear();  
  $listBox.SelectionMode = 'MultiExtended'
  Get-AzSnapshot -ResourceGroupName $AzureVMResourceGroupName | Where-Object { $_.tags.CreateDate -ne $null -and $_.tags.CreateDate -eq $RecoveryPoint } | ForEach-Object { [void] $listBox.Items.Add($_.Name) } 
  $form.Controls.Add($listBox)
  
  ##############################
  # リストボックスの表示
  ##############################
  $form.Topmost = $true
  $result = $form.ShowDialog()

  if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
    $SelectedSnapshots = $listBox.SelectedItems
    $SelectedSnapshots | ForEach-Object { Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $_ + "を復元します") }
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] リカバリポイントの選択:完了")
  } elseif ($result -eq [System.Windows.Forms.DialogResult]::Cancel) {
    exit 0
  } else {
    exit 0
  }

  $RecoverySnapshots = $SelectedSnapshots | ForEach-Object { Get-AzSnapshot  -ResourceGroupName $AzureVMResourceGroupName -SnapshotName $_ }
  foreach($Snapshot in $RecoverySnapshots) {
    if($null -eq $Snapshot.Tags.SourceDiskName -or $Snapshot.Tags.SourceDiskName -eq "") {
      Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] ディスクのSnapshotにディスクの復元情報（Tag）が無い為リカバリできません。")
      exit 9
    }
  }

  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] 仮想マシン(" + $AzureVMInfo.Name + ")の復元:開始")
  ########################################
  ## 仮想マシンの停止
  ########################################
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] 仮想マシンの停止:開始")
  $Result = Stop-AzVM -Name $AzureVMInfo.Name -ResourceGroupName $AzureVMInfo.ResourceGroupName -Force
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] 仮想マシンの停止:" + $Result.Status)
  if($Result.Status -ne "Succeeded") {
    Write-Output($Result | format-list -DisplayError)
    exit 9
  }

  ########################################
  ## データディスクのデタッチ
  ########################################
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] データディスクのデタッチ:開始")
  $Results = $RecoverySnapshots | ForEach-Object { Remove-AzVMDataDisk -VM $AzureVMInfo -Name $_.Tags.SourceDiskName }
  foreach($Result in $Results) {
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] データディスクのデタッチ:" + $Result.ProvisioningState)
  }
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] データディスクのデタッチ:完了")
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] 仮想マシンの更新:開始")
  $Result = Update-AzVM -ResourceGroupName $AzureVMInfo.ResourceGroupName -VM $AzureVMInfo
  if(-not $Result -or $Result.IsSuccessStatusCode -ne "True") {
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] 仮想マシンの更新:失敗")
    exit 9
  }
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] 仮想マシンの更新:完了")
　
  ########################################
  ## データディスクの削除
  ########################################
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] データディスク削除処理:開始")
  $Results = $RecoverySnapshots | ForEach-Object { Remove-AzDisk -ResourceGroupName $AzureVMInfo.ResourceGroupName -DiskName $_.Tags.SourceDiskName -Force }
  foreach($Result in $Results) {
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] データディスクの削除:" + $Result.Status)
  }
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] データディスク削除処理:完了")

  #######################################################
  ## 選択されたリカバリポイントのスナップショットを復元
  #######################################################
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] データディスクの復元処理:開始")
  $RecoveredDisks = $RecoverySnapshots | ForEach-Object { New-AzDiskConfig -Location $_.Location -SourceResourceId $_.Id -CreateOption Copy -Tag $_.Tags } | ForEach-Object { New-AzDisk -Disk $_ -ResourceGroupName $AzureVMResourceGroupName -DiskName $_.Tags.SourceDiskName } | ForEach-Object { Add-AzVMDataDisk -VM $AzureVMInfo -Name $_.Name -ManagedDiskId $_.Id -Lun $_.Tags.SourceLun -Caching ReadOnly -CreateOption Attach }
  foreach($Result in $RecoveredDisks) {
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] データディスクの復元:" + $Result.ProvisioningState)
  }
  $Result = Update-AzVM -ResourceGroupName $AzureVMInfo.ResourceGroupName -VM $AzureVMInfo
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] データディスクの復元処理:完了")
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] 仮想マシンの構成更新:開始")
  if(-not $Result -or $Result.IsSuccessStatusCode -ne "True") {
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] 仮想マシンの構成更新:失敗")
    exit 9
  }
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] 仮想マシンの構成更新:完了")
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] 仮想マシン(" + $AzureVMInfo.Name + ")の復元:完了")

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
    $Log.Error($_.Exception)
    exit 99
}
exit 0
