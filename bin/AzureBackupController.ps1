<################################################################################
## Copyright(c) 2020 BeeX Inc. All rights reserved.
## @auther#Naruhiro Ikeya
##
## @name:AzreBackupController.ps1
## @summary:Azure Backup Recovery Point Retention Controller
##
## @since:2019/06/04
## @version:1.0
## @see:
## @parameter
##  1:�o�b�N�A�b�v�|���V�[��
##  2:�L�����t���O
##  3:�������t���O
##
## @return:0:Success 9:�G���[�I�� / 99:Exception
################################################################################>

##########################
# �p�����[�^�ݒ�
##########################
param (
  [string]$RecoveryServicesVaultName=$null,
  [string]$AzureVMBackupPolicyName=$null,
  [switch]$EnableAzureBackup,
  [switch]$DisableAzureBackup,
  [switch]$Eventlog=$false,
  [switch]$Stdout=$false
)

##########################
# ���W���[���̃��[�h
##########################
. .\LogController.ps1
. .\AzureLogonFunction.ps1

##########################
# �Œ�l 
##########################
Set-Variable -Name "ConstantPolicyName" -Value "CooperationJobSchedulerDummyPolicy" -Option Constant
Set-Variable -Name "DisableHours" -Value 3 -Option Constant
[string]$CredenticialFile = "AzureCredential_Secure.xml"
[int]$SaveDays = 7

##########################
# �x���̕\���}�~
##########################
# Set-Item Env:\SuppressAzurePowerShellBreakingChangeWarnings "true"

###############################
# LogController �I�u�W�F�N�g����
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
  $Log.Info("���O�t�@�C����:$($Log.GetLogInfo())")
}

##########################
# �p�����[�^�`�F�b�N
##########################
if ($EnableAzureBackup -xor $DisableAzureBackup) {
  if ($EnableAzureBackup) {
    $Log.Info("Azure Backup��L�������܂��B")
    $StatusString="�L����"
  } else {
    $Log.Info("Azure Backup�𖳌������܂��B")
    $StatusString="������"
  }
} else {
  $Log.Error("Syntax Error:���s���� -EnableAzureBackup / -DisableAzureBackup ���w�肵�Ă��������B")
  exit 9
}

try {
  ##########################
  # Azure���O�I������
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

  if($RecoveryServicesVaultName) {
    $RecoveryServicesVaults = Get-AzRecoveryServicesVault -Name $RecoveryServicesVaultName
    if(-not $RecoveryServicesVaults) {
      $Log.Error("�w�肳�ꂽRecovery Service �R���e�i�[($RecoveryServicesVaultName)�����݂��܂���B")
      exit 9
    }
  } else {
    $RecoveryServicesVaults = Get-AzRecoveryServicesVault
    if(-not $RecoveryServicesVaults) {
      $Log.Error("Recovery Service �R���e�i�[�����݂��܂���B")
      exit 9
    }
  }

  foreach($Vault in $RecoveryServicesVaults) {
    $Log.Info("Recovery Service �R���e�i�[:" + $Vault.Name)
    if(-not $AzureVMBackupPolicyName) {
      $AzureVMProtectionPolicies = Get-AzRecoveryServicesBackupProtectionPolicy -VaultId $Vault.ID -WorkloadType "AzureVM" 
    } else {
      $AzureVMProtectionPolicies = Get-AzRecoveryServicesBackupProtectionPolicy -VaultId $Vault.ID | Where-Object { $_.Name -eq $AzureVMBackupPolicyName }
      if((-not $AzureVMProtectionPolicies) -and $DisableAzureBackup) {
        $Log.Error("�w�肳�ꂽBackup Policy��������܂���B:$AzureVMBackupPolicyName")
        exit 9
      } 
    }

    $RegisterdVMsContainer = Get-AzRecoveryServicesBackupContainer -VaultId $Vault.ID -ContainerType "AzureVM" -Status "Registered"
    $Log.Info("Azure Backup" + $StatusString + "����:�J�n")
    foreach($AzureVMProtectionPolicy in $AzureVMProtectionPolicies) {
      ############################
      # �����X�P�W���[���W���u
      ############################
      if($AzureVMProtectionPolicy.SchedulePolicy.ScheduleRunFrequency -eq "Daily") {
        $UTCNow = (Get-Date).ToUniversalTime()
        ########################################################
        # �o�b�N�A�b�v���Ԃ��߂��Ă��玟��̃o�b�N�A�b�v�͗���
        ########################################################
        if ($AzureVMProtectionPolicy.SchedulePolicy.ScheduleRunTimes[0].TimeOfDay -gt $UTCNow.TimeOfDay) {
          $RunDate = $UTCNow.ToString("yyyy/MM/dd")
        } else {
          $RunDate = $UTCNow.AddDays(1).tostring("yyyy/MM/dd")
        }
        $BackupTime = Get-Date -Date $($RunDate + " " + $AzureVMProtectionPolicy.SchedulePolicy.ScheduleRunTimes[0].toString("HH:mm"))

      ############################
      # �T���X�P�W���[���W���u
      ############################
      } elseif($AzureVMProtectionPolicy.SchedulePolicy.ScheduleRunFrequency -eq "Weekly") {
        $UTCNow = (Get-Date).ToUniversalTime()
        ########################################################
        # �j�����قȂ��Ă����玟��̃o�b�N�A�b�v�����Z�o
        # �o�b�N�A�b�v���Ԃ��߂��Ă��玟��̃o�b�N�A�b�v�͗��T
        ########################################################
        $RunDayOfWeek = $AzureVMProtectionPolicy.SchedulePolicy.ScheduleRunDays[0]
        $RunTimeOfDay = $AzureVMProtectionPolicy.SchedulePolicy.ScheduleRunTimes[0].TimeOfDay 
        if(($UTCNow.DayOfWeek -eq $RunDayOfWeek) -and ($UTCNow.TimeOfDay -lt $RunTimeOfDay)) {
          $RunDate = $UTCNow.ToString("yyyy/MM/dd")
        } else {
          $AddDaysVaule = (6 - $UTCNow.DayOfWeek + [DayOfWeek]::$($AzureVMProtectionPolicy.SchedulePolicy.ScheduleRunDays[0])) % 7 + 1
          $RunDate = ($UTCNow.AddDays($AddDaysVaule)).ToString("yyyy/MM/dd")
        }
        $RunTime = $AzureVMProtectionPolicy.SchedulePolicy.ScheduleRunTimes[0].toString("HH:mm")
        $BackupTime = (Get-Date -Date $("$RunDate $Runtime +00:00")).ToUniversalTime()
      }
      $DisableTime = $BackupTime.AddHours(-1 * $DisableHours)

      if($EnableAzureBackup -and (($UTCNow -gt $BackupTime) -or ($UTCNow -le $DisableTime))) {
        $Log.Info($AzureVMProtectionPolicy.Name + "�̗L�����������J�n���܂��B")
      } elseif($DisableAzureBackup -and (($DisableTime -le $UTCNow) -and ($UTCNow -lt $BackupTime))) {
        $Log.Info($AzureVMProtectionPolicy.Name + "�̖������������J�n���܂��B")
      } else {
        if($EnableAzureBackup) { $Log.Info($AzureVMProtectionPolicy.Name + "�̗L�����\���ԑт� �`" + $DisableTime.ToLocalTime().ToString("yyyy/MM/dd HH:mm") + "�܂łł��B" + $BackupTime.ToLocalTime().ToString("yyyy/MM/dd HH:mm") + "�ȍ~�ɍėL�����\�ł��B") }
        if($DisableAzureBackup) { $Log.Info($AzureVMProtectionPolicy.Name + "�̖������\���ԑт� " + $DisableTime.ToLocalTime().ToString("yyyy/MM/dd HH:mm") + "�`" + $BackupTime.ToLocalTime().ToString("yyyy/MM/dd HH:mm") + "�ł��B") }
        continue
      }

      $SettingFilePath = Split-Path $MyInvocation.MyCommand.Path -Parent | Split-Path -Parent | Join-Path -ChildPath etc -Resolve
      $SettingFile = $Vault.Name + "_" + $AzureVMProtectionPolicy.Name + ".xml"
      $Log.Info("Backup Policy�t�@�C�����F" + $SettingFile)
      if(-not (Test-Path(Join-Path $SettingFilePath -ChildPath $SettingFile))) {
        $Log.Warn("Backup Policy�t�@�C�������݂��܂���B")
        break
      }
      $BackupPolicyConfig = [xml](Get-Content (Join-Path $SettingFilePath -ChildPath $SettingFile -Resolve))
      if(-not $BackupPolicyConfig) { 
        $Log.Error("����̃t�@�C������ݒ��񂪓ǂݍ��߂܂���ł����B")
        exit 9
      } 
      foreach($Container in $RegisterdVMsContainer) {
        $BackupItem = Get-AzRecoveryServicesBackupItem -VaultId $Vault.ID -Container $Container -WorkloadType AzureVM 
        foreach($AzureVM in $BackupPolicyConfig.BackupPolicy.VM) {
          if($EnableAzureBackup -and $BackupItem.ProtectionPolicyName) {
            $Log.Info($Container.FriendlyName + "��" + $StatusString + "�ςł��B")
            break
          } elseif($DisableAzureBackup -and ($null -eq $BackupItem.ProtectionPolicyName)) {
            $Log.Info($Container.FriendlyName + "��" + $StatusString + "�ςł��B")
            break
          } elseif($EnableAzureBackup -and ($Container.FriendlyName -eq $AzureVM.Name)) {
            ############################
            # �L�����o�b�N�O���E���h���s
            ############################
            $BackgroundJob = {
              param([string]$VaultName, [string]$VMName, [string]$PolicyName)
              try {
                $Vault = Get-AzRecoveryServicesVault -Name $VaultName
                $Container = Get-AzRecoveryServicesBackupContainer -VaultId $Vault.ID -ContainerType "AzureVM" -Status "Registered" -FriendlyName $VMName
                $Item = Get-AzRecoveryServicesBackupItem -VaultId $Vault.ID -Container $Container -WorkloadType AzureVM 
                $AzureVMProtectionPolicy = Get-AzRecoveryServicesBackupProtectionPolicy -VaultId $Vault.ID -Name $PolicyName
                $EnabledItem = Enable-AzRecoveryServicesBackupProtection -VaultId $Vault.ID -Item $Item -Policy $AzureVMProtectionPolicy
                Write-Host("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $EnabledItem.WorkloadName + "��Azure Backup��L�������܂����B")
              } catch {
                Write-Host("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $VMName + "��Azure Backu�L�����Ɏ��s���܂����B")
                throw
              } 
            }
            $JobResult = Start-Job $BackgroundJob -ArgumentList $Vault.Name, $Container.FriendlyName, $AzureVMProtectionPolicy.Name
            $Log.Info($Container.FriendlyName + "��Azure Backup" + $StatusString + "�W���u�����s���܂����BJobID = " + $JobResult.Id)
            break
          } elseif($DisableAzureBackup -and ($AzureVMProtectionPolicy.Name -eq $BackupItem.ProtectionPolicyName) -and ($Container.FriendlyName -eq $AzureVM.Name)) {
            ############################
            # �������o�b�N�O���E���h���s
            ############################
            $BackgroundJob = {
              param([string]$VaultName, [string]$VMName)
              try {
                $Vault = Get-AzRecoveryServicesVault -Name $VaultName
                $Container = Get-AzRecoveryServicesBackupContainer -VaultId $Vault.ID -ContainerType "AzureVM" -Status "Registered" -FriendlyName $VMName
                $Item = Get-AzRecoveryServicesBackupItem -VaultId $Vault.ID -Container $Container -WorkloadType AzureVM
                $DisabledItem = Disable-AzRecoveryServicesBackupProtection -VaultId $Vault.ID -Item $Item -Force
                Write-Host("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $DisabledItem.WorkloadName + "��Azure Backup�𖳌������܂����B")
              } catch {
                Write-Host("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $VMName + "��Azure Backup�������Ɏ��s���܂����B")
                throw
              } 
            }
            $JobResult = Start-Job $BackgroundJob -ArgumentList $Vault.Name, $Container.FriendlyName, $AzureVMProtectionPolicy.Name
            $Log.Info($Container.FriendlyName + "��Azure Backup" + $StatusString + "�W���u�����s���܂����BJobID = " + $JobResult.Id)
            $Log.Info($BackupTime.ToLocalTime().ToString("yyyy/MM/dd HH:mm") + " �̃o�b�N�A�b�v�W���u���X�L�b�v���܂��B")
            break
          }
        }
      }
    }
    ######################################
    # �o�b�N�O���E���h�W���u�̊����҂�
    ######################################
    $Log.Info("�o�b�N�O���E���h�W���u�����҂�")
    $JobResults=Get-Job | Wait-Job -Timeout 600
    foreach($JobResult in $JobResults) { 
      $Log.Info("Id:$($JobResult.Id) State:$($JobResult.JobStateInfo.State)")
    } 
    ######################################
    # �o�b�N�O���E���h�W���u�̍폜
    ######################################
    Get-Job | Remove-Job
    $Log.Info("Azure Backup" + $StatusString + "����:����")
  }
#################################################
# �G���[�n���h�����O
#################################################
} catch {
    $Log.Error("�������ɃG���[���������܂����B")
    $Log.Error($_.Exception)
    exit 9
}
exit 0