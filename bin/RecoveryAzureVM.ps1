<################################################################################
## Copyright(c) 2020 BeeX Inc. All rights reserved.
## @auther#Naruhiro Ikeya
##
## @name:RecoveryAzureVM.ps1
## @summary:VHD���J�o����̉��z�}�V���̍č\�z�X�N���v�g
##
## @since:2020/05/07
## @version:1.1
## @see:
## @parameter
##  1:Azure VM��
##  2:Azure VM���\�[�X�O���[�v��
##  3:Recovery Services�R���e�i�[��
##  4:OS�݂̂̕����t���O
##  5:VM�č\�z�t���O
##
## @return:0:Success 9:�G���[�I��
################################################################################>

##########################
# �p�����[�^�ݒ�
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
# ���W���[���̃��[�h
##########################
. .\LogController.ps1
. .\AzureLogonFunction.ps1

##########################
# �Œ�l 
##########################
#$ErrorActionPreference = "Stop"
[string]$CredentialFile = "AzureCredential_Secure.xml"

##########################
# �x���̕\���}�~
##########################
#Set-Item Env:\SuppressAzurePowerShellBreakingChangeWarnings "true"

###############################
# LogController �I�u�W�F�N�g����
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
# �p�����[�^�`�F�b�N
##########################

try {
  ##########################
  # Azure���O�I������
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
  # ResourceGroup���̃`�F�b�N
  ############################
  $ResourceGroup = Get-AzResourceGroup | Where-Object{$_.ResourceGroupName -eq $AzureVMResourceGroupName}
  if(-not $ResourceGroup) { 
    $Log.Error("ResourceGroup�����s���ł��B" + $AzureVMResourceGroupName)
    exit 9
  }

  ############################
  # AzureVM���̃`�F�b�N
  ############################
  $AzureVM = Get-AzVM -ResourceGroupName $AzureVMResourceGroupName | Where-Object{$_.Name -eq $AzureVMName}
  if(-not $AzureVM) { 
    $Log.Error("AzureVM�����s���ł��B" + $AzureVMName)
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
  $Log.Info("�I�����ꂽRecovery Services�R���e�i:" + $RecoveryServiceVault.Name)
  $Log.Info("Recovery Services�R���e�i�̑I��:����")

  #########################################
  ## �ŐV�̃��X�g�A�W���u���ʏڍׂ��擾
  #########################################
  $Log.Info("�ŐV�̃��J�o���W���u���ʏڍ׎擾:�J�n")
  $RecoveryVHDJob = Get-AzRecoveryServicesBackupJob -VaultId $RecoveryServiceVault.ID | Where-Object {$_.WorkloadName -eq $AzureVMName -and $_.Operation -eq "Restore" -and $_.Status -eq "Completed"} | Sort-Object @{Expression="Endtime";Descending=$true} | Select-Object -First 1
  if(-not $RecoveryVHDJob) {
    $Log.Error("���J�o���W���u�����݂��܂���")
    exit 9
  }
  $JobDatails = Get-AzRecoveryServicesBackupJobDetails -VaultId $RecoveryServiceVault.ID -Job $RecoveryVHDJob
  if(-not $JobDatails) {
    $Log.Error("���J�o���W���u�ڍׂ��擾�ł��܂���ł����B")
    exit 9
  } elseif($JobDatails.Properties."Job Type" -ne "Recover disks") { 
    $Log.Error("�ŐV�̃��J�o���W���u���f�B�X�N�̃��J�o���W���u�ł͂���܂���B")
    exit 9
  }
  $Log.Info("�ŐV�̃��J�o���W���u����")
  $Log.Info($($JobDatails | Format-List | Out-String -Stream))
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
  if(-not $DataDisksOnly) {
    $CheckDisk = Get-AzDisk -ResourceGroupName $JobDatails.Properties["Target resource group"] -DiskName $ConfigOBJ.'properties.storageProfile'.osDisk.Name
    if(-not $CheckDisk){
      $Log.Error("OS�f�B�X�N�����݂��܂���:" + $ConfigOBJ.'properties.storageProfile'.osDisk.Name)
      exit 9
    } elseif($CheckDisk.ProvisioningState -ne "Succeeded") {
      $Log.Error("OS�f�B�X�N�̕��������s���Ă��܂�:" + $ConfigOBJ.'properties.storageProfile'.osDisk.Name)
      exit 9
    } else {
      $Log.Info("OS�f�B�X�N�̕����m�F���������܂���:" + $ConfigOBJ.'properties.storageProfile'.osDisk.Name)
    }
  }
  foreach($DataDiskInfo in $ConfigOBJ.'properties.storageProfile'.dataDisks){
    $CheckDisk = Get-AzDisk -ResourceGroupName $JobDatails.Properties["Target resource group"] -DiskName $DataDiskInfo.Name
    if(-not $CheckDisk){
      $Log.Error("Data�f�B�X�N�����݂��܂���:" + $DataDiskInfo.Name)
      exit 9
    } elseif($CheckDisk.ProvisioningState -ne "Succeeded") {
      $Log.Error("Data�f�B�X�N�̕��������s���Ă��܂�:" + $DataDiskInfo.Name)
      exit 9
    } else {
      $Log.Info("Data�f�B�X�N�̕����m�F���������܂���:" + $DataDiskInfo.Name)  	
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
  $Log.Info("���J�o���Ώۉ��z�}�V��($($AzureVMInfo.Name))���~���܂�")
  $Result = Stop-AzVM -Name $AzureVMInfo.Name -ResourceGroupName $AzureVMInfo.ResourceGroupName -Force
  if($Result.Status -eq "Succeeded") {
    $Log.Info("���J�o���Ώۉ��z�}�V���̒�~:$($Result.Status)")
  } else { 
    $Log.Error($($Result | Format-List | Out-String -Stream))
    $Log.Error("���J�o���Ώۉ��z�}�V���̒�~:$($Result.Status)")
    exit 9
  }

  ########################################
  ## ���z�}�V�����č\�z����ꍇ
  ########################################
  if($RebuildVM) {
    ########################################
    ## ���z�}�V���̍폜
    ########################################
    $Log.Info("���z�}�V��(" + $AzureVMInfo.Name + ")�̍폜:�J�n")
    $RemoveResult = Remove-AzVM -Name $AzureVMInfo.Name -ResourceGroupName $AzureVMInfo.ResourceGroupName -Force
    if($RemoveResult.Status -eq "Succeeded") {
      $Log.Info("���z�}�V���̍폜:$($RemoveResult.Status)")
    } else {
      $Log.Error($($RemoveResult | Format-List | Out-String -Stream))
      $Log.Error("���z�}�V���̍폜:$($RemoveResult.Status)")
      exit 9
    }
    $Log.Info("���z�}�V���̍폜:����")
  }

  if(-not $DataDiskOnly) {
    ########################################
    ## OS�f�B�X�N�̒u������
    ########################################
    $Log.Info("���z�}�V����OS�f�B�X�N�u������:�J�n")
    $TargetOsDisk = Get-AzDisk -ResourceGroupName $AzureVMInfo.ResourceGroupName -DiskName $AzureVMInfo.StorageProfile.OsDisk.Name
    $SourceOsDisk = Get-AzDisk -ResourceGroupName $JobDatails.Properties["Target resource group"] -Name $ConfigOBJ.'properties.storageProfile'.osDisk.name
    ########################################
    ## ���sOS�f�B�X�N�̑ޔ�����(���t��t�^���đޔ�)
    ########################################
    $Log.Info("���sOS�f�B�X�N($($AzureVMInfo.StorageProfile.OsDisk.Name))�̑ޔ�:�J�n")
    $TmpDiskConfig = New-AzDiskConfig -SourceResourceId $TargetOsDisk.Id -Location $TargetOsDisk.Location -CreateOption Copy -DiskSizeGB $TargetOsDisk.DiskSizeGB -SkuName $TargetOsDisk.Sku.Name
    $CopyResult = New-AzDisk -Disk $TmpDiskConfig -ResourceGroupName $AzureVMInfo.ResourceGroupName -DiskName $($AzureVMInfo.StorageProfile.OsDisk.Name + "_" + $(Get-Date -Format "yyyyMMddHHmm")) 
    if($CopyResult.ProvisioningState -eq "Succeeded") {
      $Log.Info("���sOS�f�B�X�N�̑ޔ�($($CopyResult.Name)):$($CopyResult.ProvisioningState)")
    } else {
      $Log.Error($($CopyResult | Format-List | Out-String -Stream))
      $Log.Error("���sOS�f�B�X�N�̑ޔ�($($CopyResult.Name)):$($CopyResult.ProvisioningState)")
      exit 9
    }

    if(-not $RebuildVM) {
      ########################################
      ## VM��OS�f�B�X�N�̒u������(�b��)
      ########################################
      $Log.Info("OS�f�B�X�N($($AzureVMInfo.StorageProfile.OsDisk.Name))�̃��v���C�X����:�J�n")
      $Result = Set-AzVMOSDisk -VM $AzureVMInfo -ManagedDiskId $SourceOsDisk.Id -Name $SourceOsDisk.Name 
      if($Result.ProvisioningState -eq "Succeeded") {
        $Log.Info("OS�f�B�X�N�̃��v���C�X����($($Result.StorageProfile.OsDisk.Name)):$($Result.ProvisioningState)")
      } else {
        $Log.Error($($Result | Format-List | Out-String -Stream))
        $Log.Error("OS�f�B�X�N�̃��v���C�X����($($Result.StorageProfile.OsDisk.Name)):$($Result.ProvisioningState)")
        exit 9
      }
      ########################################
      ## ���z�}�V���̍\���A�b�v�f�[�g
      ########################################
      $Log.Info("���z�}�V���̍\���ύX:�J�n")
      $Result = Update-AzVM -ResourceGroupName $AzureVMInfo.ResourceGroupName -VM $AzureVMInfo  
      if($Result.IsSuccessStatusCode) {
        $Log.Info("���z�}�V���̍\���ύX:$($Result.StatusCode)")
      } else { 
        $Log.Error($($Result | Format-List | Out-String -Stream))
        $Log.Error("���z�}�V���̍\���ύX:$($Result.StatusCode)")
        exit 9
      }
    }

    ########################################
    ## ���sOS�f�B�X�N�̍폜
    ########################################
    $Log.Info("���sOS�f�B�X�N($($TargetOsDisk.Name))�̍폜:�J�n" )
    $RemoveResult = Remove-AzDisk -ResourceGroupName $TargetOsDisk.ResourceGroupName -DiskName $TargetOsDisk.Name -Force
    if($RemoveResult.Status -eq "Succeeded") {
      $Log.Info("���sOS�f�B�X�N�̍폜:$($RemoveResult.Status)")
    } else { 
      $Log.Error($($RemoveResult | Format-List | Out-String -Stream))
      $Log.Error("���sOS�f�B�X�N�̍폜:$($RemoveResult.Status)")
      exit 9
    }

    ########################################
    ## �V�f�B�X�N�̍쐬
    ########################################
    $Log.Info("�VOS�f�B�X�N$($TargetOsDisk.Name)�̍쐬:�J�n")
    $TmpDiskConfig = New-AzDiskConfig -SourceResourceId $SourceOsDisk.Id -Location $SourceOsDisk.Location -CreateOption Copy -DiskSizeGB $SourceOsDisk.DiskSizeGB -SkuName $SourceOsDisk.Sku.Name
    $CopyResult = New-AzDisk -Disk $TmpDiskConfig -ResourceGroupName $AzureVMInfo.ResourceGroupName -DiskName $TargetOsDisk.Name
    if($CopyResult.ProvisioningState -eq "Succeeded") {
      $Log.Info("�VOS�f�B�X�N�̍쐬:$($CopyResult.ProvisioningState)")
    } else {
      $Log.Error($($CopyResult | Format-List | Out-String -Stream))
      $Log.Error("�VOS�f�B�X�N�̍쐬:$($CopyResult.ProvisioningState)")
      exit 9
    }

    if(-not $RebuildVM) {
      ########################################
      ## VM��OS�f�B�X�N�̒u������
      ########################################
      $TargetOsDisk = Get-AzDisk -ResourceGroupName $AzureVMInfo.ResourceGroupName -DiskName $TargetOsDisk.Name
      $Log.Info("OS�f�B�X�N($($AzureVMInfo.StorageProfile.OsDisk.Name))�̃��v���C�X����:�J�n")
      $Result = Set-AzVMOSDisk -VM $AzureVMInfo -ManagedDiskId $TargetOsDisk.Id -Name $TargetOsDisk.Name 
      if($Result.ProvisioningState -eq "Succeeded") {
        $Log.Info("OS�f�B�X�N�̃��v���C�X����($($Result.StorageProfile.OsDisk.Name)):$($Result.ProvisioningState)")
      } else {
        $Log.Error($($Result | Format-List | Out-String -Stream))
        $Log.Error("OS�f�B�X�N�̃��v���C�X����($($Result.StorageProfile.OsDisk.Name)):$($Result.ProvisioningState)")
        exit 9
      }
      ########################################
      ## ���z�}�V���̍\���A�b�v�f�[�g
      ########################################
      $Log.Info("���z�}�V���̍\���ύX:�J�n")
      $Result = Update-AzVM -ResourceGroupName $AzureVMInfo.ResourceGroupName -VM $AzureVMInfo  
      if($Result.IsSuccessStatusCode) {
        $Log.Info("���z�}�V���̍\���ύX:$($Result.StatusCode)")
      } else { 
        $Log.Error($($Result | Format-List | Out-String -Stream))
        $Log.Error("���z�}�V���̍\���ύX:$($Result.StatusCode)")
        exit 9
      }
    }
    $Log.Info("���z�}�V����OS�f�B�X�N�u������:����")
  }

  ########################################
  ## Data�f�B�X�N�̒u������
  ########################################
  $Log.Info("���z�}�V���̃f�[�^�f�B�X�N�u������:�J�n")
  foreach($RecoveryDisk in $ConfigOBJ.'properties.storageProfile'.dataDisks) {
    if(-not $OSDiskOnly) {
      $SourceDataDisk = $AzureVMInfo.StorageProfile.DataDisks | Where-Object { $_.Lun -eq $RecoveryDisk.Lun }
      if(-not $SourceDataDisk){
        $Log.Error("���z�}�V����LUN����v����f�B�X�N���ڑ�����Ă܂���B:" + $RecoveryDisk.Name)
        exit 9
      }

      if(-not $RebuildVM) {
        ########################################
        ## ���z�}�V������f�[�^�f�B�X�N���f�^�b�`
        ########################################
        $Log.Info("�f�[�^�f�B�X�N(LUN:$($SourceDataDisk.Lun),DISK:$($SourceDataDisk.Name))�̃f�^�b�`����:�J�n")
        $Result = Remove-AzVMDataDisk -VM $AzureVMInfo -Name $SourceDataDisk.Name
        if($Result.ProvisioningState -eq "Succeeded") {
          $Log.Info("�f�[�^�f�B�X�N�̃f�^�b�`����:$($Result.ProvisioningState)")
        } else { 
          $Log.Error($($Result | Format-List | Out-String -Stream))
          $Log.Error("�f�[�^�f�B�X�N�̃f�^�b�`����:$($Result.ProvisioningState)")
          exit 9
        }
        ########################################
        ## ���z�}�V���̍\���A�b�v�f�[�g
        ########################################
        $Log.Info("���z�}�V���̍\���ύX:�J�n")
        $Result = Update-AzVM -ResourceGroupName $AzureVMInfo.ResourceGroupName -VM $AzureVMInfo  
        if($Result.IsSuccessStatusCode) {
          $Log.Info("���z�}�V���̍\���ύX:$($Result.StatusCode)")
        } else { 
          $Log.Error($($Result | Format-List | Out-String -Stream))
          $Log.Error("���z�}�V���̍\���ύX:$($Result.StatusCode)")
          exit 9
        }
      }

      ########################################
      ## �f�^�b�`�����f�B�X�N�̍폜
      ########################################
      $Log.Info("�f�[�^�f�B�X�N($($SourceDataDisk.Name))�̍폜����:�J�n")
      $Result = Remove-AzDisk -ResourceGroupName $AzureVMInfo.ResourceGroupName -DiskName $SourceDataDisk.Name -Force
      if($Result.Status -eq "Succeeded") {
        $Log.Info("�f�[�^�f�B�X�N�̍폜:$($Result.Status)")
      } else { 
        $Log.Error($($Result | Format-List | Out-String -Stream))
        $Log.Error("�f�[�^�f�B�X�N�̍폜:$($Result.Status)")
        exit 9
      }

      ########################################
      ## ���J�o���f�B�X�N���̕ύX�i�����j
      ########################################
      $Log.Info("�f�[�^�f�B�X�N($($RecoveryDisk.Name))�̕�������:�J�n")
      $CopyResult = Get-AzDisk -ResourceGroupName $JobDatails.Properties["Target resource group"] -DiskName $RecoveryDisk.Name | Update-AzDisk -ResourceGroupName $AzureVMInfo.ResourceGroupName -DiskName $SourceDataDisk.Name
      if($CopyResult.ProvisioningState -eq "Succeeded") {
        $Log.Info("�f�[�^�f�B�X�N($($CopyResult.Name))�̕�������:$($CopyResult.ProvisioningState)")
      } else {
        $Log.Error($($CopyResult | Format-List | Out-String -Stream))
        $Log.Error("�f�[�^�f�B�X�N($($CopyResult.Name))�̕�������:$($CopyResult.ProvisioningState)")
        exit 9
      }

      if(-not $RebuildVM) {
        ########################################
        ## �����f�B�X�N�̃A�^�b�`
        ########################################
        $Log.Info("�f�[�^�f�B�X�N($($CopyResult.Name))�̃A�^�b�`:�J�n")
        $Result = Add-AzVMDataDisk -CreateOption Attach -Lun $SourceDataDisk.lun -Caching $SourceDataDisk.Caching -VM $AzureVMInfo -ManagedDiskId $CopyResult.Id
        if($Result.ProvisioningState -eq "Succeeded") {
          $Log.Info("�f�[�^�f�B�X�N�̃A�^�b�`����:$($Result.ProvisioningState)")
        } else { 
          $Log.Error($($Result | Format-List | Out-String -Stream))
          $Log.Error("�f�[�^�f�B�X�N�̃A�^�b�`����:$($Result.ProvisioningState)")
          exit 9
        }
        ########################################
        ## ���z�}�V���̍\���A�b�v�f�[�g
        ########################################
        $Log.Info("���z�}�V���̍\���ύX:�J�n")
        $Result = Update-AzVM -ResourceGroupName $AzureVMInfo.ResourceGroupName -VM $AzureVMInfo  
        if($Result.IsSuccessStatusCode) {
          $Log.Info("���z�}�V���̍\���ύX:$($Result.StatusCode)")
        } else { 
          $Log.Error($($Result | Format-List | Out-String -Stream))
          $Log.Error("���z�}�V���̍\���ύX:$($Result.StatusCode)")
          exit 9
        }
      }        
    }
  }
  $Log.Info("���z�}�V���̃f�[�^�f�B�X�N�u������:����")

  ########################################
  ## ���z�}�V���̍č\�z
  ########################################
  $Log.Info("���z�}�V���̍č\�z����:�J�n")
  if($RebuildVM) {
    $AzureVMInfo.StorageProfile.OSDisk.CreateOption = "Attach"
    $AzureVMInfo.StorageProfile.DataDisks | ForEach-Object { $_.CreateOption = "Attach" }
    $AzureVMInfo.StorageProfile.ImageReference = $null
    $AzureVMInfo.OSProfile = $null
    $Log.Info("���z�}�V�����쐬���܂��B")
    $CreateVMJob = New-AzVM -ResourceGroupName $AzureVMInfo.ResourceGroupName -Location $AzureVMInfo.Location -VM $AzureVMInfo -DisableBginfoExtension
    if($CreateVMJob){
        $Log.Info("���z�}�V���̍쐬:$($Result.StatusCode)")
    } else { 
      $Log.Error($($CreateVMJob | Format-List | Out-String -Stream))
      $Log.Error("���z�}�V���̍쐬:$($Result.StatusCode)")
      exit 9
    }
  } elseif (-not $RebuildVM) {
    $Log.Info("���z�}�V�����N�����܂�:" + $AzureVMInfo.Name)
    $Result = Start-AzVM -Name $AzureVMInfo.Name -ResourceGroupName $AzureVMResourceGroupName
    if($Result.Status -eq "Succeeded") {
      $Log.Info("���z�}�V���̋N��:����")
    } else { 
      $Log.Error($($Result | Format-List | Out-String -Stream))
      $Log.Error("���z�}�V���̋N��:���s" )
      exit 9
    }
    $Log.Info("���z�}�V���̍č\�z����:����")
  }

  ########################################
  ## ���J�o�����f�B�X�N�폜
  ########################################
  $Log.Info("���J�o�������f�B�X�N�̍폜����:�J�n")
  $Result = Remove-AzDisk -ResourceGroupName $JobDatails.Properties["Target resource group"] -DiskName $ConfigOBJ.'properties.storageProfile'.osDisk.Name -Force
  if($Result.Status -eq "Succeeded") {
    $Log.Info("OS�f�B�X�N($($ConfigOBJ.'properties.storageProfile'.osDisk.Name))�̍폜:$($Result.Status)")
  } else { 
    $Log.Error($($Result | Format-List | Out-String -Stream))
    $Log.Error("OS�f�B�X�N($($ConfigOBJ.'properties.storageProfile'.osDisk.Name))�̍폜:$($Result.Status)")
    exit 9
  }
  foreach($DataDiskInfo in $ConfigOBJ.'properties.storageProfile'.dataDisks){
    $Result = Remove-AzDisk -ResourceGroupName $JobDatails.Properties["Target resource group"] -DiskName $DataDiskInfo.Name -Force
    if($Result.Status -eq "Succeeded") {
      $Log.Info("�f�[�^�f�B�X�N($($DataDiskInfo.Name))�̍폜:$($Result.Status)")
    } else { 
      $Log.Error($($Result | Format-List | Out-String -Stream))
      $Log.Error("�f�[�^�f�B�X�N($($DataDiskInfo.Name))�̍폜:$($Result.Status)")
      exit 9
    }
  }
  $Log.Info("���J�o�������f�B�X�N�̍폜����:����")

<#
    $Log.Info("���J�o�������f�[�^�f�B�X�N���폜���܂�:" + $RecoveryDisk.Name)
    $Result = Remove-AzDisk -ResourceGroupName $JobDatails.Properties["Target resource group"] -DiskName $RecoveryDisk.Name -Force
    if($Result.Status -eq "Succeeded") {
      $Log.Info("�������f�[�^�f�B�X�N�폜:����:")
    } else { 
      Write-Output($($Result | Format-List | Out-String -Stream))
      $Log.Error("�������f�[�^�f�B�X�N�폜:���s")
      exit 9
    }
#>

  #################################################
  # �G���[�n���h�����O
  #################################################
} catch {
    $Log.Error("���z�}�V���̕����������ɃG���[���������܂����B")
    $Log.Error($_.Exception)
    exit 99
}
exit 0