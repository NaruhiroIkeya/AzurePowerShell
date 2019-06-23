<################################################################################
## Copyright(c) 2019 BeeX Inc. All rights reserved.
## @auther#Naruhiro Ikeya
##
## @name:RecoveryAzureVM.ps1
## @summary:VHD���J�o����̉��z�}�V���̍č\�z�X�N���v�g
##
## @since:2019/02/03
## @version:1.0
## @see:
## @parameter
##  1:Azure VM��
##  2:Azure VM���\�[�X�O���[�v��
##  3:Recovery Services�R���e�i�[��
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
$ErrorActionPreference = "Stop"

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
  $Log.Info("Recovery Services�R���e�i�̑I��:�J�n")
  $RecoveryServiceVault = Get-AzRecoveryServicesVault -Name $RecoveryServiceVaultName
  if(-not $RecoveryServiceVault) { 
    $Log.Error("Recovery Service�R���e�i�[�����s���ł�:" + $RecoveryServiceVaultName)
    exit 9
  }
  Set-AzRecoveryServicesVaultContext -Vault $RecoveryServiceVault
  $Log.Info("�I�����ꂽRecovery Services�R���e�i:" + $RecoveryServiceVault.Name)
  $Log.Info("Recovery Services�R���e�i�̑I��:����")

  #########################################
  ## �ŐV�̃��X�g�A�W���u���ʏڍׂ��擾
  #########################################
  $Log.Info("�ŐV�̃��J�o���W���u���ʏڍ׎擾:�J�n")
  $RecoveryVHDJob = Get-AzRecoveryServicesBackupJob | ? {$_.WorkloadName -eq $AzureVMName -and $_.Operation -eq "Restore" -and $_.Status -eq "Completed"} | sort @{Expression="Endtime";Descending=$true} | Select -First 1
  if(-not $RecoveryVHDJob) { 
    $Log.Error("���J�o���W���u�����݂��܂���")
    exit 9
  }
  $JobDatails = Get-AzRecoveryServicesBackupJobDetails -Job $RecoveryVHDJob
  if(-not $JobDatails) { 
    $Log.Error("���J�o���W���u�ڍׂ��擾�ł��܂���ł���")
    exit 9
  } elseif($JobDatails.Properties."Job Type" -ne "Recover disks") { 
    $Log.Error("�ŐV�̃��J�o���W���u���f�B�X�N�̃��J�o���W���u�ł͂���܂���")
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
    $Log.Error("Config�t�@�C���̃_�E�����[�h�����s���܂���")
    exit 9
  }
  $Log.Info("Config�t�@�C���i$ConfigFilePath�j�̃_�E�����[�h���������܂���")
  $ConfigOBJ = ((Get-Content -Path $ConfigFilePath -Encoding Unicode)).TrimEnd([char]0x00) | ConvertFrom-Json
  $Log.Info("���J�o���W���uConfig�擾:����")

  ####################################################
  ## ���������f�B�X�N���S�đ����Ă��邩�m�F
  ####################################################
  $Log.Info("���J�o�������f�B�X�N�̐���m�F:�J�n")
  $CheckDisk = Get-AzDisk -ResourceGroupName $JobDatails.Properties["Target resource group"] -DiskName $ConfigOBJ.'properties.storageProfile'.osDisk.name
  if(-not $CheckDisk){
    $Log.Error("OS�f�B�X�N�����݂��܂���:" + $ConfigOBJ.'properties.storageProfile'.osDisk.name)
    exit 9
  } elseif($CheckDisk.ProvisioningState -ne "Succeeded") {
    $Log.Error("OS�f�B�X�N�̕��������s���Ă��܂�:" + $ConfigOBJ.'properties.storageProfile'.osDisk.name)
    exit 9
  }
  
  foreach($DataDiskInfo in $ConfigOBJ.'properties.storageProfile'.dataDisks){
    $CheckDisk = Get-AzDisk -ResourceGroupName $JobDatails.Properties["Target resource group"] -DiskName $DataDiskInfo.Name
    if(-not $CheckDisk){
      $Log.Error("Data�f�B�X�N�����݂��܂���:" + $DataDiskInfo.Name)
      exit 9
    } elseif($CheckDisk.ProvisioningState -ne "Succeeded") {
      $Log.Error("Data�f�B�X�N�̕��������s���Ă��܂�:" + $DataDiskInfo.Name)
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
  ## ���z�}�V���̒�~
  ########################################
  $Log.Info("���J�o���Ώۉ��z�}�V���̒�~:�J�n")
  $Log.Info("���J�o���Ώۉ��z�}�V�����~���܂�:" + $AzureVMInfo.Name)
  $Result = Stop-AzVM -Name $AzureVMInfo.Name -ResourceGroupName $AzureVMInfo.ResourceGroupName -Force
  if($Result.Status -eq "Succeeded") {
    $Log.Info("���z�}�V���̒�~:����")
  } else { 
    Write-Output($StopResult | format-list -DisplayError)
    $Log.Error("���z�}�V���̒�~:���s" )
    exit 9
  }
  $Log.Info("���J�o���Ώۉ��z�}�V���̒�~:����")

  ########################################
  ## Data�f�B�X�N�̒u������
  ########################################
  $Log.Info("���z�}�V���̃f�[�^�f�B�X�N�u������:�J�n")
  foreach($RecoveryDisk in $ConfigOBJ.'properties.storageProfile'.dataDisks) {
    $SourceDataDisk = $AzureVMInfo.StorageProfile.DataDisks | ? { $_.Lun -eq $RecoveryDisk.Lun }
    if(-not $SourceDataDisk){
      $Log.Error("���z�}�V����LUN����v����f�B�X�N���ڑ�����Ă܂���B:" + $RecoveryDisk.Name)
      exit 9
    }
�@�@## ���z�}�V������f�[�^�f�B�X�N���f�^�b�`
    $Log.Info("���z�}�V������f�[�^�f�B�X�N���f�^�b�`���܂�:LUN:" + $SourceDataDisk.Lun + ",DISK:" + $SourceDataDisk.Name)
    $Result = Remove-AzVMDataDisk -VM $AzureVMInfo -Name $SourceDataDisk.Name
    if($Result.ProvisioningState -eq "Succeeded") {
      $Log.Info("�f�[�^�f�B�X�N�̃f�^�b�`:����")
    } else { 
      Write-Output($Result | format-list -DisplayError)
      $Log.Error("�f�[�^�f�B�X�N�̃f�^�b�`:���s")
      exit 9
    }
    $Result = Update-AzVM -ResourceGroupName $AzureVMInfo.ResourceGroupName -VM $AzureVMInfo  
    if($Result.IsSuccessStatusCode) {
      $Log.Info("���z�}�V���̍\���ύX:����")
    } else { 
      Write-Output($Result | format-list -DisplayError)
      $Log.Error("���z�}�V���̍\���ύX:���s")
      exit 9
    }

�@�@## �f�^�b�`�����f�B�X�N�̍폜
    $Log.Info("�f�^�b�`�����f�[�^�f�B�X�N���폜���܂�:" + $SourceDataDisk.Name)
    $Result = Remove-AzDisk -ResourceGroupName $AzureVMInfo.ResourceGroupName -DiskName $SourceDataDisk.Name -Force
    if($Result.Status -eq "Succeeded") {
      $Log.Info("�f�[�^�f�B�X�N�폜:����")
    } else { 
      Write-Output($Result | format-list -DisplayError)
      $Log.Error("�f�[�^�f�B�X�N�폜:���s")
      exit 9
    }

�@�@## ���J�o���f�B�X�N���̕ύX�i�����j
    $Log.Info("���J�o�������f�[�^�f�B�X�N�̖��̕ύX�i�����j���J�n���܂�:" + $RecoveryDisk.Name)
    $CopyResult = Get-AzDisk -ResourceGroupName $JobDatails.Properties["Target resource group"] -DiskName $RecoveryDisk.Name | Update-AzDisk -ResourceGroupName  $AzureVMInfo.ResourceGroupName -DiskName $SourceDataDisk.Name
    if($CopyResult.ProvisioningState -eq "Succeeded") {
      $Log.Info("�f�[�^�f�B�X�N�̖��̕ύX:����")
    } else {
      Write-Output($CopyResult | format-list -DisplayError)
      $Log.Error("�f�[�^�f�B�X�N�̖��̕ύX:���s")    
      exit 9
    }

�@�@## �����f�B�X�N�̃A�^�b�`
    $Log.Info("���z�}�V���Ƀf�[�^�f�B�X�N���A�^�b�`���܂�:" + $CopyResult.Name)
    $Result = Add-AzVMDataDisk -CreateOption Attach -Lun $SourceDataDisk.lun -VM $AzureVMInfo -ManagedDiskId $CopyResult.Id
    if($Result.ProvisioningState -eq "Succeeded") {
      $Log.Info("�f�[�^�f�B�X�N�̃A�^�b�`:����")
    } else { 
      Write-Output($Result | format-list -DisplayError)
      $Log.Error("�f�[�^�f�B�X�N�̃A�^�b�`:���s")
      exit 9
    }
    $Result = Update-AzVM -ResourceGroupName $AzureVMInfo.ResourceGroupName -VM $AzureVMInfo  
    if($Result.IsSuccessStatusCode) {
      $Log.Info("���z�}�V���̍\���ύX:����")
    } else { 
      Write-Output($Result | format-list -DisplayError)
      $Log.Error("���z�}�V���̍\���ύX:���s")
      exit 9
    }

�@�@## ���J�o�����f�B�X�N�폜
    $Log.Info("���J�o�������f�[�^�f�B�X�N���폜���܂�:" + $RecoveryDisk.Name)
    $Result = Remove-AzDisk -ResourceGroupName $JobDatails.Properties["Target resource group"] -DiskName $RecoveryDisk.Name -Force
    if($Result.Status -eq "Succeeded") {
      $Log.Info("�������f�[�^�f�B�X�N�폜:����:")
    } else { 
      Write-Output($Result | format-list -DisplayError)
      $Log.Error("�������f�[�^�f�B�X�N�폜:���s")
      exit 9
    }
  }
  $Log.Info("���z�}�V���̃f�[�^�f�B�X�N�u������:����")


  ########################################
  ## ���z�}�V���̍č\�z
  ########################################
  $Log.Info("���z�}�V���̍č\�z����:�J�n")
  $Log.Info("OS�f�B�X�N�̃��v���C�X�������J�n���܂�:" + $ConfigOBJ.'properties.storageProfile'.osDisk.name)
  $OsDiskName = $AzureVMInfo.StorageProfile.OsDisk.Name
  $OsDisk = Get-AzDisk -ResourceGroupName $JobDatails.Properties["Target resource group"] -Name $ConfigOBJ.'properties.storageProfile'.osDisk.name
  $Result = Set-AzVMOSDisk -VM $AzureVMInfo -ManagedDiskId $OsDisk.Id -Name $OsDisk.Name 
  if($Result.ProvisioningState -eq "Succeeded") {
    $Log.Info("OS�f�B�X�N�̃��v���C�X:����")
  } else {
    Write-Output($Result | format-list -DisplayError)
    $Log.Error("OS�f�B�X�N�̃��v���C�X:���s")    
    exit 9
  }
  $Result = Update-AzVM -ResourceGroupName $AzureVMInfo.ResourceGroupName -VM $AzureVMInfo
  if($Result.IsSuccessStatusCode) {
    $Log.Info("���z�}�V���̍\���ύX:����")
  } else { 
    Write-Output($Result | format-list -DisplayError)
    $Log.Error("���z�}�V���̍\���ύX:���s")
    exit 9
  }

  $Result = Remove-AzDisk -ResourceGroupName $JobDatails.Properties["Target resource group"] -DiskName $OsDiskName -Force
  if($Result.Status -eq "Succeeded") {
    $Log.Info("OS�f�B�X�N�폜:����:" + $SourceDataDisk.Name)
  } else { 
    Write-Output($Result | format-list -DisplayError)
    $Log.Error("OS�f�B�X�N�폜:���s" + $SourceDataDisk.Name)
    exit 9
  }

  $Log.Info("���z�}�V�����N�����܂�:" + $AzureVMInfo.Name)
  $Result = Start-AzVM -Name $AzureVMInfo.Name -ResourceGroupName $AzureVMResourceGroupName
  if($Result.Status -eq "Succeeded") {
    $Log.Info("���z�}�V���̋N��:����")
  } else { 
    Write-Output($Result | format-list -DisplayError)
    $Log.Error("���z�}�V���̋N��:���s" )
    exit 9
  }
  $Log.Info("���z�}�V���̍č\�z����:����")

  #################################################
  # �G���[�n���h�����O
  #################################################
} catch {
    $Log.Error("���z�}�V���̕����������ɃG���[���������܂����B")
    $Log.Error($_.Exception)
    exit 99
}
exit 0