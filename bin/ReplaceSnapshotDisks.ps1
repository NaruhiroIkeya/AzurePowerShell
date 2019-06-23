<################################################################################
## Copyright(c) 2019 BeeX Inc. All rights reserved.
## @auther#Naruhiro Ikeya
##
## @name:RecoveryDataDisk.ps1
## @summary:�Ǘ��f�B�X�N�̃X�i�b�v�V���b�g����f�[�^�f�B�X�N�̕���
##
## @since:2019/02/03
## @version:1.0
## @see:
## @parameter
##  1:Azure VM��
##  2:Azure VM���\�[�X�O���[�v��
##
## @return:0:Success 9:�G���[�I��
################################################################################>

##########################
$ErrorActionPreference = "Stop"
# �p�����[�^�ݒ�
##########################
param (
  [parameter(mandatory=$true)][string]$AzureVMName,
  [parameter(mandatory=$true)][string]$AzureVMResourceGroupName
)

##########################
# �F�؏��ݒ�
##########################
#####################
$TennantID = "2ab73ef2-d066-4ce0-923e-94235755e2a2"
$TennantID = "e2fb1fde-e67c-4a07-8478-5ab2b9a0577f"
$Key="AgndRfEIsRJ+8VjN0oQjy5T+vfnlcIQUUuYsXj780FM="
$ApplicationID="ea70cdb1-df24-4928-9bf4-4ff6b6963463"

##########################
# �x���̕\���}�~
##########################
Set-Item Env:\SuppressAzurePowerShellBreakingChangeWarnings "true"

try {
  Import-Module Az

  ##########################
  # Azure�ւ̃��O�C��
  ##########################
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Azure�փ��O�C��:�J�n")
  $LoginInfo = Login-AzAccount -Tenant $TennantID -WarningAction Ignore
  if(-not $LoginInfo) { 
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Azure�փ��O�C���ł��܂���ł����B")
    exit 9
  }
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Azure�փ��O�C��:����")

  ###################################
  # AzureVM �m�F
  ###################################
  $AzureVMInfo = Get-AzVM -ResourceGroupName $AzureVMResourceGroupName -Name $AzureVMName
  if(-not $AzureVMInfo) {
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $AzureVMResourceGroupName + "��" + $AzureVMName + "�����݂��܂���B")
    exit 9
  }

  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] ���J�o���|�C���g�̑I��:�J�n")
  ##############################
  # ���X�g�{�b�N�X�t�H�[���쐬
  ##############################
  Add-Type -AssemblyName System.Windows.Forms
  Add-Type -AssemblyName System.Drawing

  $form = New-Object System.Windows.Forms.Form
  $form.Text = '���J�o���Ώۂ�I�����Ă��������B'
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
  $label.Text = '���J�o���Ώۂ�I�����Ă��������F'
  $form.Controls.Add($label)

  $listBox = New-Object System.Windows.Forms.ListBox
  $listBox.Location = New-Object System.Drawing.Point(10,40)
  $listBox.Size = New-Object System.Drawing.Size(310,20)
  $listBox.Height = 80

  ##############################
  # Snapshot�쐬���Ԃ̈ꗗ��
  ##############################
  Get-AzSnapshot -ResourceGroupName $AzureVMResourceGroupName | ? { $_.Tags.SourceVMName -ne $null -and $_.Tags.SourceVMName -eq $AzureVMName } | sort {$_.tags.CreateDate} -unique | % { [void] $listBox.Items.Add($_.tags.CreateDate) } 
  $form.Controls.Add($listBox)
  
  ##############################
  # ���X�g�{�b�N�X�̕\��
  ##############################
  $form.Topmost = $true
  $result = $form.ShowDialog()

  if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
    $RecoveryPoint = $listBox.SelectedItem
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $RecoveryPoint + "�Ƀf�[�^�f�B�X�N�𕜌����܂�")
  } elseif ($result -eq [System.Windows.Forms.DialogResult]::Cancel) {
    exit 0
  } else {
    exit 0
  }

  ##############################
  # ���J�o���Ώۃf�B�X�N�̈ꗗ
  ##############################
  $listBox.Items.Clear();  
  $listBox.SelectionMode = 'MultiExtended'
  Get-AzSnapshot -ResourceGroupName $AzureVMResourceGroupName | ? { $_.tags.CreateDate -ne $null -and $_.tags.CreateDate -eq $RecoveryPoint } | % { [void] $listBox.Items.Add($_.Name) } 
  $form.Controls.Add($listBox)
  
  ##############################
  # ���X�g�{�b�N�X�̕\��
  ##############################
  $form.Topmost = $true
  $result = $form.ShowDialog()

  if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
    $SelectedSnapshots = $listBox.SelectedItems
    $SelectedSnapshots | % { Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $_ + "�𕜌����܂�") }
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] ���J�o���|�C���g�̑I��:����")
  } elseif ($result -eq [System.Windows.Forms.DialogResult]::Cancel) {
    exit 0
  } else {
    exit 0
  }

  $RecoverySnapshots = $SelectedSnapshots | % { Get-AzSnapshot  -ResourceGroupName $AzureVMResourceGroupName -SnapshotName $_ }
  foreach($Snapshot in $RecoverySnapshots) {
    if($Snapshot.Tags.SourceDiskName -eq $null -or $Snapshot.Tags.SourceDiskName -eq "") {
      Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] �f�B�X�N��Snapshot�Ƀf�B�X�N�̕������iTag�j�������׃��J�o���ł��܂���B")
      exit 9
    }
  }

  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] ���z�}�V��(" + $AzureVMInfo.Name + ")�̕���:�J�n")
  ########################################
  ## ���z�}�V���̒�~
  ########################################
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] ���z�}�V���̒�~:�J�n")
  $Result = Stop-AzVM -Name $AzureVMInfo.Name -ResourceGroupName $AzureVMInfo.ResourceGroupName -Force
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] ���z�}�V���̒�~:" + $Result.Status)
  if($Result.Status -ne "Succeeded") {
    Write-Output($Result | format-list -DisplayError)
    exit 9
  }


  ########################################
  ## �f�[�^�f�B�X�N�̃f�^�b�`
  ########################################
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] �f�[�^�f�B�X�N�̃f�^�b�`:�J�n")
  $Results = $RecoverySnapshots | % { Remove-AzVMDataDisk -VM $AzureVMInfo -Name $_.Tags.SourceDiskName }
  foreach($Result in $Results) {
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] �f�[�^�f�B�X�N�̃f�^�b�`:" + $Result.ProvisioningState)
  }
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] �f�[�^�f�B�X�N�̃f�^�b�`:����")
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] ���z�}�V���̍X�V:�J�n")
  $Result = Update-AzVM -ResourceGroupName $AzureVMInfo.ResourceGroupName -VM $AzureVMInfo
  if(-not $Result -or $Result.IsSuccessStatusCode -ne "True") {
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] ���z�}�V���̍X�V:���s")
    exit 9
  }
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] ���z�}�V���̍X�V:����")
�@
  ########################################
  ## �f�[�^�f�B�X�N�̍폜
  ########################################
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] �f�[�^�f�B�X�N�폜����:�J�n")
  $Results = $RecoverySnapshots | % { Remove-AzDisk -ResourceGroupName $AzureVMInfo.ResourceGroupName -DiskName $_.Tags.SourceDiskName -Force }
  foreach($Result in $Results) {
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] �f�[�^�f�B�X�N�̍폜:" + $Result.Status)
  }
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] �f�[�^�f�B�X�N�폜����:����")

  #######################################################
  ## �I�����ꂽ���J�o���|�C���g�̃X�i�b�v�V���b�g�𕜌�
  #######################################################
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] �f�[�^�f�B�X�N�̕�������:�J�n")
  $RecoveredDisks = $RecoverySnapshots | % { New-AzDiskConfig -Location $_.Location -SourceResourceId $_.Id -CreateOption Copy -Tag $_.Tags } | % { New-AzDisk -Disk $_ -ResourceGroupName $AzureVMResourceGroupName -DiskName $_.Tags.SourceDiskName } | % { Add-AzVMDataDisk -VM $AzureVMInfo -Name $_.Name -ManagedDiskId $_.Id -Lun $_.Tags.SourceLun -Caching ReadOnly -CreateOption Attach }
  foreach($Result in $RecoveredDisks) {
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] �f�[�^�f�B�X�N�̕���:" + $Result.ProvisioningState)
  }
  $Result = Update-AzVM -ResourceGroupName $AzureVMInfo.ResourceGroupName -VM $AzureVMInfo
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] �f�[�^�f�B�X�N�̕�������:����")
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] ���z�}�V���̍\���X�V:�J�n")
  if(-not $Result -or $Result.IsSuccessStatusCode -ne "True") {
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] ���z�}�V���̍\���X�V:���s")
    exit 9
  }
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] ���z�}�V���̍\���X�V:����")
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] ���z�}�V��(" + $AzureVMInfo.Name + ")�̕���:����")

  #################################################
  # �G���[�n���h�����O
  #################################################
  if($CreateVMJob.Status -eq "Failed") {
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] ���z�}�V���̕����������ɂ��G���[�I�����܂����B")
    $CreateVMJob | Format-List -DisplayError
    exit 9
  } else {
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] ���z�}�V���̍č\�z����:����")
  }
} catch {
    Write-Output("`r`n`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] ���z�}�V���̕����������ɃG���[���������܂����B")
    $Log.Error($_.Exception)
    exit 99
}
exit 0
