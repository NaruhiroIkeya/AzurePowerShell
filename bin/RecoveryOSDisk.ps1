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
# �F�؏��ݒ�
##########################
$TennantID = "e2fb1fde-e67c-4a07-8478-5ab2b9a0577f"

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
  #�Ώ�Recovery Services Vault�̑I��
  ###################################
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Recovery Services�R���e�i�̑I��:�J�n")
  $RecoveryServiceVault = Get-AzRecoveryServicesVault -Name $RecoveryServiceVaultName
  if(-not $RecoveryServiceVault) { 
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Recovery Service�R���e�i�[�����s���ł��B")
    exit 9
  }
  Set-AzRecoveryServicesVaultContext -Vault $RecoveryServiceVault
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] �I�����ꂽRecovery Services�R���e�i:" + $RecoveryServiceVault.Name)
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Recovery Services�R���e�i�̑I��:����")

  #########################################
  ## �ŐV�̃��X�g�A�W���u���ʏڍׂ��擾
  #########################################
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] �ŐV�̃��J�o���W���u���ʏڍ׎擾:�J�n")
  $RecoveryVHDJob = Get-AzRecoveryServicesBackupJob | ? {$_.WorkloadName -eq $AzureVMName -and $_.Operation -eq "Restore" -and $_.Status -eq "Completed"} | sort @{Expression="Endtime";Descending=$true} | Select -First 1
  if(-not $RecoveryVHDJob) { 
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] ���J�o���W���u�����݂��܂���B")
    exit 9
  }
  $JobDatails = Get-AzRecoveryServicesBackupJobDetails -Job $RecoveryVHDJob
  if(-not $JobDatails) { 
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] ���J�o���W���u�ڍׂ��擾�ł��܂���ł����B")
    exit 9
  } elseif($JobDatails.Properties."Job Type" -ne "Recover disks") { 
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] �ŐV�̃��J�o���W���u���f�B�X�N�̃��J�o���W���u�ł͂���܂���B")
    exit 9
  }
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] �ŐV�̃��J�o���W���u����")
  Write-Output($JobDatails| format-list -DisplayError)
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] �ŐV�̃��J�o���W���u���ʏڍ׎擾:����")

  #########################################
  ## Config�t�@�C���̃_�E�����[�h�A�ǂݍ���
  #########################################
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] ���J�o���W���uConfig�擾:�J�n")
  $ConfigFilePath = $(Convert-Path .) + "\" + $AzureVMName + "_config.json"
  $StorageAccountKey = (Get-AzStorageAccountKey -ResourceGroupName $JobDatails.Properties["Target resource group"] -Name $JobDatails.Properties["Target Storage Account Name"])[0].Value
  $StorageContext = New-AzStorageContext -StorageAccountName $JobDatails.Properties["Target Storage Account Name"] -StorageAccountKey $StorageAccountKey
  $DownloadConfiFile = Get-AzStorageBlobContent -Blob $JobDatails.Properties["Config Blob Name"] -Container $JobDatails.Properties["Config Blob Container Name"] -Destination $ConfigFilePath -Context $StorageContext -Force
  if(-not $DownloadConfiFile) { 
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Config�t�@�C���̃_�E�����[�h�����s���܂����B")
    exit 9
  }
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Config�t�@�C���i$ConfigFilePath�j�̃_�E�����[�h���������܂����B")
  $ConfigOBJ = ((Get-Content -Path $ConfigFilePath -Encoding Unicode)).TrimEnd([char]0x00) | ConvertFrom-Json
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] ���J�o���W���uConfig�擾:����")

  ####################################################
  ## ���������f�B�X�N���S�đ����Ă��邩�m�F
  ####################################################
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] ���J�o�������f�B�X�N�̐���m�F:�J�n")
  $CheckDisk = Get-AzDisk -ResourceGroupName $JobDatails.Properties["Target resource group"] -DiskName $ConfigOBJ.'properties.storageProfile'.osDisk.name
  if(-not $CheckDisk){
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] OS�f�B�X�N�����݂��܂���B:" + $ConfigOBJ.'properties.storageProfile'.osDisk.name)
    exit 9
  } elseif($CheckDisk.ProvisioningState -ne "Succeeded") {
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] OS�f�B�X�N�̕��������s���Ă��܂��B:" + $ConfigOBJ.'properties.storageProfile'.osDisk.name)
    exit 9
  }
  
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] ���J�o�������f�B�X�N�̐���m�F:����")

  ####################################################
  ## ���s���z�}�V���̍\������ޔ�
  ####################################################
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] ���z�}�V���̍\�����ޔ�:�J�n")
  $AzureVMInfo = Get-AzVM -Name $AzureVMName -ResourceGroupName $AzureVMResourceGroupName
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] ���z�}�V���̍\�����ޔ�:����")

  ########################################
  ## ���z�}�V���̒�~
  ########################################
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] �������z�}�V���̒�~:�J�n")
  $StopResult = Stop-AzVM -Name $AzureVMInfo.Name -ResourceGroupName $AzureVMInfo.ResourceGroupName -Force
  if($StopResult.Status -eq "Succeeded") {
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] ���z�}�V����~����:" + $AzureVMInfo.Name)
  } else { 
    Write-Output($RemoveResult | format-list -DisplayError)
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] ���z�}�V�����~�ł��܂���ł����B:" + $AzureVMInfo.Name)
  }
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] �������z�}�V���̒�~:����")

  ########################################
  ## �s�vData�f�B�X�N�̍폜����
  ########################################
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] �s�vData�f�B�X�N�폜����:�J�n")
  foreach($RemoveDisk in $ConfigOBJ.'properties.storageProfile'.DataDisks) {
    $RemoveResult = Remove-AzDisk -ResourceGroupName $AzureVMInfo.ResourceGroupName -DiskName $RemoveDisk.Name -Force
    if($RemoveResult.Status -eq "Succeeded") {
      Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] �s�vData�f�B�X�N�폜����:" + $RemoveDisk.Name)
    } else { 
      Write-Output($RemoveResult | format-list -DisplayError)
      Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] �s�vData�f�B�X�N���폜�o���܂���ł����B:" + $RemoveDisk.Name)
    }
  } 
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] �s�vData�f�B�X�N�폜:����")

  ########################################
  ## ���z�}�V���̍č\�z
  ########################################
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] ���z�}�V���̍č\�z����:�J�n")
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] ���z�}�V���̐ݒ���J�n���܂��B")

  $OsDisk = Get-AzDisk -ResourceGroupName $JobDatails.Properties["Target resource group"] -Name  $ConfigOBJ.'properties.storageProfile'.osDisk.name
  Set-AzVMOSDisk -VM $AzureVMInfo -ManagedDiskId $OsDisk.Id -Name $OsDisk.Name 
  Update-AzVM -ResourceGroupName $AzureVMInfo.ResourceGroupName -VM $AzureVMInfo
  Start-AzVM -Name $vm.Name -ResourceGroupName $AzureVMResourceGroupName
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] ���z�}�V���̍č\�z����:����")

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
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $error[0] | Format-List -DisplayError)
    exit 99
}
exit 0