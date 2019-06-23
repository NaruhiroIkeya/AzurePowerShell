<################################################################################
## Copyright(c) 2019 BeeX Inc. All rights reserved.
## @auther#Naruhiro Ikeya
##
## @name:ReCreateAzureVM.ps1
## @summary:VHD���J�o����̉��z�}�V���̍č\�z�X�N���v�g
##
## @since:2019/02/03
## @version:1.0
## @see:
## @parameter
##  1:Azure VM��
##  2:Azure VM���\�[�X�O���[�v��
##  3:Recovery Services�R���e�i�[��
##  4:Boot�f�f�X�g���[�W�A�J�E���g��
##  5:Boot�f�f�X�g���[�W�A�J�E���g���\�[�X�O���[�v��
##
## @return:0:Success 9:�G���[�I��
################################################################################>

##########################
# �p�����[�^�ݒ�
##########################
param (
  [parameter(mandatory=$true)][string]$AzureVMName,
  [parameter(mandatory=$true)][string]$AzureVMResourceGroupName,
  [parameter(mandatory=$true)][string]$RecoveryServiceVaultName
)

##########################
# ���W���[���̃��[�h
##########################
. .\LogController.ps1
. .\AzureLogonFunction.ps1

##########################
# �Œ�l 
##########################

###############################
# LogController �I�u�W�F�N�g����
###############################
if($Stdout) {
  $Log = New-Object LogController
} else {
  $LogFilePath = Split-Path $MyInvocation.MyCommand.Path -Parent | Split-Path -Parent | Join-Path -ChildPath log -Resolve
  $LogFile = (Get-ChildItem $MyInvocation.MyCommand.Path).BaseName + ".log"
  $Log = New-Object LogController($($LogFilePath + "\" + $LogFile), $false)
}

##########################
# �p�����[�^�`�F�b�N
##########################

try {
  ##########################
  # Azure���O�I������
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
  #�Ώ�Recovery Services Vault�̑I��
  ###################################
  $Log.Info("ecovery Services�R���e�i�̑I��:�J�n")
  $RecoveryServiceVault = Get-AzRecoveryServicesVault -Name $RecoveryServiceVaultName
  if(-not $RecoveryServiceVault) { 
    $Log.Info("ecovery Service�R���e�i�[�����s���ł��B")
    exit 9
  }
  Set-AzRecoveryServicesVaultContext -Vault $RecoveryServiceVault
  $Log.Info("�I�����ꂽRecovery Services�R���e�i:" + $RecoveryServiceVault.Name)
  $Log.Info("ecovery Services�R���e�i�̑I��:����")

  #########################################
  ## �ŐV�̃��X�g�A�W���u���ʏڍׂ��擾
  #########################################
  $Log.Info("�ŐV�̃��J�o���W���u���ʏڍ׎擾:�J�n")
  $RecoveryVHDJob = Get-AzRecoveryServicesBackupJob | ? {$_.WorkloadName -eq $AzureVMName -and $_.Operation -eq "Restore" -and $_.Status -eq "Completed"} | sort @{Expression="Endtime";Descending=$true} | Select -First 1
  if(-not $RecoveryVHDJob) { 
    $Log.Info("���J�o���W���u�����݂��܂���B")
    exit 9
  }
  $JobDatails = Get-AzRecoveryServicesBackupJobDetails -Job $RecoveryVHDJob
  if(-not $JobDatails) { 
    $Log.Info("���J�o���W���u�ڍׂ��擾�ł��܂���ł����B")
    exit 9
  } elseif($JobDatails.Properties."Job Type" -ne "Recover disks") { 
    $Log.Info("�ŐV�̃��J�o���W���u���f�B�X�N�̃��J�o���W���u�ł͂���܂���B")
    exit 9
  }
  $Log.Info("�ŐV�̃��J�o���W���u����")
  Write-Output($JobDatails| format-list -DisplayError)
  $Log.Info("�ŐV�̃��J�o���W���u���ʏڍ׎擾:����")

  #########################################
  ## Config�t�@�C���̃_�E�����[�h�A�ǂݍ���
  #########################################
  $Log.Info("���J�o���W���uConfig�擾:�J�n")
  $ConfigFilePath = $(Convert-Path .) + "\" + $AzureVMName + "_config.json"
  $StorageAccountKey = (Get-AzStorageAccountKey -ResourceGroupName $JobDatails.Properties["Target resource group"] -Name $JobDatails.Properties["Target Storage Account Name"])[0].Value
  $StorageContext = New-AzStorageContext -StorageAccountName $JobDatails.Properties["Target Storage Account Name"] -StorageAccountKey $StorageAccountKey
  $DownloadConfiFile = Get-AzStorageBlobContent -Blob $JobDatails.Properties["Config Blob Name"] -Container $JobDatails.Properties["Config Blob Container Name"] -Destination $ConfigFilePath -Context $StorageContext -Force
  if(-not $DownloadConfiFile) { 
    $Log.Error("Config�t�@�C���̃_�E�����[�h�����s���܂����B")
    exit 9
  }
  $Log.Info("Config�t�@�C���i$ConfigFilePath�j�̃_�E�����[�h���������܂����B")
  $ConfigOBJ = ((Get-Content -Path $ConfigFilePath -Encoding Unicode)).TrimEnd([char]0x00) | ConvertFrom-Json
  $Log.Info("���J�o���W���uConfig�擾:����")

  ####################################################
  ## ���������f�B�X�N���S�đ����Ă��邩�m�F
  ####################################################
  $Log.Info("���J�o�������f�B�X�N�̐���m�F:�J�n")
  $CheckDisk = Get-AzDisk -ResourceGroupName $JobDatails.Properties["Target resource group"] -DiskName $ConfigOBJ.'properties.storageProfile'.osDisk.name
  if(-not $CheckDisk){
    $Log.Error("OS�f�B�X�N�����݂��܂���B:" + $ConfigOBJ.'properties.storageProfile'.osDisk.name)
    exit 9
  } elseif($CheckDisk.ProvisioningState -ne "Succeeded") {
    $Log.Error("OS�f�B�X�N�̕��������s���Ă��܂��B:" + $ConfigOBJ.'properties.storageProfile'.osDisk.name)
    exit 9
  }
  
  foreach($DataDiskInfo in $ConfigOBJ.'properties.storageProfile'.dataDisks){
    $CheckDisk = Get-AzDisk -ResourceGroupName $JobDatails.Properties["Target resource group"] -DiskName $DataDiskInfo.Name
    if(-not $CheckDisk){
      $Log.Error("Data�f�B�X�N�����݂��܂���B:" + $DataDiskInfo.Name)
      exit 9
    } elseif($CheckDisk.ProvisioningState -ne "Succeeded") {
      $Log.Error("Data�f�B�X�N�̕��������s���Ă��܂��B:" + $DataDiskInfo.Name)
      exit 9
    }
  }
  $Log.Info("���J�o�������f�B�X�N�̐���m�F:����")

  ####################################################
  ## ���s���z�}�V���̍\������ޔ�
  ####################################################
  $Log.Info("���z�}�V���̍\�����ޔ�:�J�n")
  $AzureVMInfo = Get-AzVM -Name $AzureVMName -ResourceGroupName $AzureVMResourceGroupName
  $Log.Info("���z�}�V���̍\�����ޔ�:����")

  ########################################
  ## ���z�}�V���̍폜
  ########################################
  $Log.Info("�������z�}�V���̍폜:�J�n")
  $StopResult = Stop-AzVM -Name $AzureVMInfo.Name -ResourceGroupName $AzureVMInfo.ResourceGroupName -Force
  if($StopResult.Status -eq "Succeeded") {
    $Log.Info("���z�}�V����~����:" + $AzureVMInfo.Name)
  } else { 
    Write-Output($RemoveResult | format-list -DisplayError)
    $Log.Info("���z�}�V�����~�ł��܂���ł����B:" + $AzureVMInfo.Name)
  }
  $RemoveResult = Remove-AzVM -Name $AzureVMInfo.Name -ResourceGroupName $AzureVMInfo.ResourceGroupName -Force
  if($RemoveResult.Status -eq "Succeeded") {
    $Log.Info("���z�}�V���폜����:" + $AzureVMInfo.Name)
  } else { 
    Write-Output($RemoveResult | format-list -DisplayError)
    $Log.Info("���z�}�V�����폜�ł��܂���ł����B:" + $AzureVMInfo.Name)
  }
  $Log.Info("�������z�}�V���̍폜:����")

  ########################################
  ## OS�f�B�X�N�̒u������
  ########################################
  $Log.Info("���z�}�V����OS�f�B�X�N�u������:�J�n")
  $RemoveResult = Remove-AzDisk -ResourceGroupName $AzureVMInfo.ResourceGroupName -DiskName $AzureVMInfo.StorageProfile.OsDisk.Name -Force
  if($RemoveResult.Status -eq "Succeeded") {
    $Log.Info("���sOS�f�B�X�N�폜����:" + $AzureVMInfo.StorageProfile.OsDisk.Name)
  } else { 
    Write-Output($RemoveResult | format-list -DisplayError)
    $Log.Info("���sOS�f�B�X�N���폜�o���܂���ł����B:" + $AzureVMInfo.StorageProfile.OsDisk.Name)
  }
  $CopyResult = Get-AzDisk -ResourceGroupName $JobDatails.Properties["Target resource group"] -DiskName $ConfigOBJ.'properties.storageProfile'.osDisk.name | Update-AzDisk -ResourceGroupName  $AzureVMInfo.ResourceGroupName -DiskName $AzureVMInfo.StorageProfile.OsDisk.Name
  if($CopyResult.ProvisioningState -eq "Succeeded") {
    $Log.Info("���J�o��OS�f�B�X�N�̕�������")
  } else {
    Write-Output($CopyResult | format-list -DisplayError)
    $Log.Error("���J�o��OS�f�B�X�N�̕����������ɃG���[���������܂����B")
    exit 9
  }
  $RemoveResult = Remove-AzDisk -ResourceGroupName $JobDatails.Properties["Target resource group"] -DiskName $ConfigOBJ.'properties.storageProfile'.osDisk.name -Force
  if($RemoveResult.Status -eq "Succeeded") {
    $Log.Info("������OS�f�B�X�N�폜����:" + $ConfigOBJ.'properties.storageProfile'.osDisk.name)
  } else { 
    Write-Output($RemoveResult | format-list -DisplayError)
    $Log.Info("������OS�f�B�X�N���폜�o���܂���ł����B:" + $ConfigOBJ.'properties.storageProfile'.osDisk.name)
  }
  $Log.Info("���z�}�V����OS�f�B�X�N�u������:����")

  ########################################
  ## Data�f�B�X�N�̒u������
  ########################################
  $Log.Info("���z�}�V����Data�f�B�X�N�u������:�J�n")
  foreach($RemoveDisk in $AzureVMInfo.StorageProfile.DataDisks) {
    $RemoveResult = Remove-AzDisk -ResourceGroupName $AzureVMInfo.ResourceGroupName -DiskName $RemoveDisk.Name -Force
    if($RemoveResult.Status -eq "Succeeded") {
      $Log.Info("���sData�f�B�X�N�폜����:" + $RemoveDisk.Name)
    } else { 
      Write-Output($RemoveResult | format-list -DisplayError)
      $Log.Info("���sData�f�B�X�N���폜�o���܂���ł����B:" + $RemoveDisk.Name)
    }
  } 
  $Log.Info("�������z�}�V����Data�f�B�X�N�폜:����")

  ########################################
  ## Data�f�B�X�N������ɖ߂��i�����j
  ########################################
  foreach($SourceDataDisk in $ConfigOBJ.'properties.storageProfile'.dataDisks) {
    $TargetDataDisk = $AzureVMInfo.StorageProfile.DataDisks | ? {$_.lun -eq $SourceDataDisk.lun }
    $CopyResult = Get-AzDisk -ResourceGroupName $JobDatails.Properties["Target resource group"] -DiskName $SourceDataDisk.name | Update-AzDisk -ResourceGroupName  $AzureVMInfo.ResourceGroupName -DiskName $TargetDataDisk.Name
    if($CopyResult.ProvisioningState -eq "Succeeded") {
      $Log.Info("���J�o��Data�f�B�X�N�̕�������:" + $CopyResult.Name)
    } else {
      Write-Output($CopyResult | format-list -DisplayError)
      $Log.Error("���J�o��Data�f�B�X�N�̕����������ɃG���[���������܂����B")    
      exit 9
    }
    $RemoveResult = Remove-AzDisk -ResourceGroupName $JobDatails.Properties["Target resource group"] -DiskName $SourceDataDisk.Name -Force
    if($RemoveResult.Status -eq "Succeeded") {
      $Log.Info("������Data�f�B�X�N�폜����:" + $SourceDataDisk.Name)
    } else { 
      Write-Output($RemoveResult | format-list -DisplayError)
      $Log.Info("������Data�f�B�X�N���폜�o���܂���ł����B:" + $SourceDataDisk.Name)
    }
  }
  $Log.Info("���z�}�V����Data�f�B�X�N�u������:����")

  ########################################
  ## ���z�}�V���̍č\�z
  ########################################
  $Log.Info("���z�}�V���̍č\�z����:�J�n")
  $Log.Info("���z�}�V���̐ݒ���J�n���܂��B")

  $AzureVMInfo.StorageProfile.OSDisk.CreateOption = "Attach"
  $AzureVMInfo.StorageProfile.DataDisks | ForEach-Object { $_.CreateOption = "Attach" }
  $AzureVMInfo.StorageProfile.ImageReference = $null
  $AzureVMInfo.OSProfile = $null
  $Log.Info("���z�}�V�����쐬���܂��B")
  $CreateVMJob = New-AzVM -ResourceGroupName $AzureVMInfo.ResourceGroupName -Location $AzureVMInfo.Location -VM $AzureVMInfo

  #################################################
  # �G���[�n���h�����O
  #################################################
  if($CreateVMJob.Status -eq "Failed") {
    $Log.Error("���z�}�V���̕����������ɂ��G���[�I�����܂����B")
    $log.Error($($CreateVMJob | Format-List -DisplayError))
    exit 9
  } else {
    $Log.Info("���z�}�V���̍č\�z����:����")
  }
} catch {
    $Log.Error("���z�}�V���̕����������ɃG���[���������܂����B")
    $Log.Error($_.Exception)
    exit 99
}
exit 0