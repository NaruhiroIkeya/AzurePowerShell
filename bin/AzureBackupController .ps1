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
  [switch]$EnableAzureBakup,
  [switch]$DisableAzureBakup,
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
  $LogFile = (Get-ChildItem $MyInvocation.MyCommand.Path).BaseName + ".log"
  $Log = New-Object LogController($($LogFilePath + "\" + $LogFile), $false, $true, (Get-ChildItem $MyInvocation.MyCommand.Path).Name, $false)
  $Log.DeleteLog($SaveDays)
}

##########################
# �p�����[�^�`�F�b�N
##########################
if ($EnableAzureBakup -xor $DisableAzureBakup) {
  if ($EnableAzureBakup) {
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
      if((-not $AzureVMProtectionPolicies) -and $DisableAzureBakup) {
        $Log.Info("�w�肳�ꂽBackup Policy��������܂���B:$AzureVMBackupPolicyName")
        exit 9
      } 
    }

    $RegisterdVMsContainer = Get-AzRecoveryServicesBackupContainer -VaultId $Vault.ID -ContainerType "AzureVM" -Status "Registered"
    $Log.Info("Azure Backup" + $StatusString + "����:�J�n")
    foreach($AzureVMProtectionPolicy in $AzureVMProtectionPolicies) {
      ############################
      # �����X�P�W���[���W���u
      ############################
      if($AzureVMProtectionPolicy.RetentionPolicy.IsDailyScheduleEnabled) {
        $RetaintionTime = $AzureVMProtectionPolicy.RetentionPolicy.DailySchedule.RetentionTimes[0].toString("HH:mm")

        $UTCDate = (Get-Date).AddHours($DisableHours).ToUniversalTime().ToString("yyyy/MM/dd")
        $RetentionTime = Get-Date -Date $($UTCDate + " " + $RetaintionTime)
        $DisableTime = $RetentionTime.AddHours(-1 * $DisableHours)
        $Now = (Get-Date).ToUniversalTime()
      ############################
      # �T���X�P�W���[���W���u
      ############################
      } elseif($AzureVMProtectionPolicy.RetentionPolicy.IsWeeklyScheduleEnabled) {
        $RetaintionTime = $AzureVMProtectionPolicy.RetentionPolicy.WeeklySchedule.RetentionTimes[0].toString("HH:mm")

        $Today = Get-Date
        if($Today.DayOfWeek -eq $AzureVMProtectionPolicy.RetentionPolicy.WeeklySchedule.DaysOfTheWeek) {
          $UTCDate = $Today.AddHours($DisableHours).ToUniversalTime().ToString("yyyy/MM/dd")
        } else {
          $UTCDate = ($Today.AddDays((6 - $Today.DayOfWeek + [DayOfWeek]::$($AzureVMProtectionPolicy.RetentionPolicy.WeeklySchedule.DaysOfTheWeek)) % 7 + 1)).AddHours($DisableHours).ToUniversalTime().ToString("yyyy/MM/dd")
        }
        $RetentionTime = Get-Date -Date $($UTCDate + " " + $RetaintionTime)
        $DisableTime = $RetentionTime.AddHours(-1 * $DisableHours)
        $Now = (Get-Date).ToUniversalTime()
      ############################
      # �����X�P�W���[���W���u
      ############################
      } elseif($AzureVMProtectionPolicy.RetentionPolicy.IsMonthlyScheduleEnabled) {
        $RetaintionTime = $AzureVMProtectionPolicy.RetentionPolicy.MonthlySchedule.RetentionTimes[0].toString("HH:mm")
      ############################
      # �N���X�P�W���[���W���u
      ############################
      } elseif($AzureVMProtectionPolicy.RetentionPolicy.IsYearlyScheduleEnabled) {
        $RetaintionTime = $AzureVMProtectionPolicy.RetentionPolicy.YearlySchedule.RetentionTimes[0].toString("HH:mm")
      }

      if($EnableAzureBakup -and ($Now -gt $RetentionTime) -or ($Now -le $DisableTime)) {
        $Log.Info($AzureVMProtectionPolicy.Name + "�̗L�������ԑт� �`" + $DisableTime.ToLocalTime().ToString("yyyy/MM/dd HH:mm") + "�܂łł��B" + $RetentionTime.ToLocalTime().ToString("yyyy/MM/dd HH:mm") + "�ڍs�ɍėL�����\�ł��B")
        $Log.Info($AzureVMProtectionPolicy.Name + "�̗L�����������J�n���܂��B")
      } elseif($DisableAzureBakup -and ($DisableTime -le $Now) -and ($Now -lt $RetentionTime)) {
        $Log.Info($AzureVMProtectionPolicy.Name + "�̖��������ԑт� " + $DisableTime.ToLocalTime().ToString("yyyy/MM/dd HH:mm") + "�`" + $RetentionTime.ToLocalTime().ToString("yyyy/MM/dd HH:mm") + "�ł��B")
        $Log.Info("Azure Backup����������:�J�n")
      } else {
        $Log.Info($AzureVMProtectionPolicy.Name + "��" + $StatusString + "�����̑ΏۊO�ł��B")
        break
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
          if($EnableAzureBakup -and $BackupItem.ProtectionPolicyName) {
            $Log.Info($Container.FriendlyName + "��" + $StatusString + "�ςł��B")
            break
          } elseif($DisableAzureBakup -and $null -eq $BackupItem.ProtectionPolicyName) {
            $Log.Info($Container.FriendlyName + "��" + $StatusString + "�ςł��B")
            break
          } elseif(($AzureVMProtectionPolicy.Name -eq $BackupItem.ProtectionPolicyName) -and ($Container.FriendlyName -eq $AzureVM.Name)) {
            ############################
            # �L�����o�b�N�O���E���h���s
            ############################
            if($EnableAzureBakup) {
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
            ############################
            # �������o�b�N�O���E���h���s
            ############################
            } elseif($DisableAzureBakup) {
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
            }
            Start-Job $BackgroundJob -ArgumentList $Vault.Name, $Container.FriendlyName, $AzureVMProtectionPolicy.Name
            $Log.Info($Container.FriendlyName + "��Azure Backup�W���u��" + $StatusString + "���܂����B")
            break
          } else {
            Continue
          }
        }
      }
    }
    Get-Job | Wait-Job
    $Log.Info($(Get-Job | Receive-Job))
    Get-Job | Remove-Job
    $Log.Info("Azure Backup" + $StatusString + "����:����")
  }
} catch {
    $Log.Error("�������ɃG���[���������܂����B")
    $Log.Error($_.Exception)
    exit 99
}
exit 0