<################################################################################
## Copyright(c) 2019 BeeX Inc. All rights reserved.
## @auther#Naruhiro Ikeya
##
## @name:AzreBackupController.ps1
## @summary:Azure Backup Recovery Point Retention Controller
##
## @since:2019/06/04
## @version:1.0
## @see:
## @parameter
##  1:Azure VM��
##  2:Azure VM���\�[�X�O���[�v��
##  3:�ۑ�����
##
## @return:0:Success 9:�G���[�I�� / 99:Exception
################################################################################>

##########################
# �p�����[�^�ݒ�
##########################
param (
  [String]$AzureVMBackupPolicyName,
  [Switch]$EnableAzureBakup,
  [Switch]$DisableAzureBakup
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
Set-Variable -Name "DisableHours" -Value 1 -Option Constant

###############################
# LogController �I�u�W�F�N�g����
###############################
$LogFilePath = Split-Path $MyInvocation.MyCommand.Path -Parent | Split-Path -Parent | Join-Path -ChildPath log -Resolve
$LogFile = (Get-ChildItem $MyInvocation.MyCommand.Path).BaseName + ".log"
$Log = New-Object LogController($($LogFilePath + "\" + $LogFile), $true)
$Log.RotateLog(7)

##########################
# �p�����[�^�`�F�b�N
##########################
if ($EnableAzureBakup -xor $DisableAzureBakup) {
  if ($EnableAzureBakup) {
    $Log.Info("Azure Backup��L�������܂��B")
  } else {
    $Log.Info("Azure Backup�𖳌������܂��B")
  }
} else {
  $Log.Error("Syntax Error:���s���� -EnableAzureBackup / -DisableAzureBackup ���w�肵�Ă��������B")
  exit 9
}

##########################
# �x���̕\���}�~
##########################
Set-Item Env:\SuppressAzurePowerShellBreakingChangeWarnings "true"

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
  
  $RecoveryServicesVaults = Get-AzRecoveryServicesVault
  foreach($Vault in $RecoveryServicesVaults) {
    Set-AzRecoveryServicesVaultContext -Vault $Vault
    if(-not $AzureVMBackupPolicyName) {
      $AzureVMProtectionPolicies = Get-AzRecoveryServicesBackupProtectionPolicy -WorkloadType "AzureVM" 
    } else {
      $AzureVMProtectionPolicies = Get-AzRecoveryServicesBackupProtectionPolicy | ? { $_.Name -eq $AzureVMBackupPolicyName }
      if((-not $AzureVMProtectionPolicies) -and $DisableAzureBakup) {
        $Log.Info("�w�肳�ꂽBackup Policy��������܂���B:$AzureVMBackupPolicyName")
        exit 9
      } elseif((-not $AzureVMProtectionPolicies) -and $EnableAzureBakup) {
        $Log.Info("�w�肳�ꂽ�|���V�[��V�K�쐬���܂��B:$AzureVMBackupPolicyName")
      }
    }

    $RegisterdVMsContainer = Get-AzRecoveryServicesBackupContainer -ContainerType "AzureVM" -Status "Registered"
    if($EnableAzureBakup) {
      $Log.Info("Azure Backup�L��������:�J�n")
      if(-not $AzureVMProtectionPolicies) {
        ##########################
        # Backup Policy�̐V�K�쐬
        ##########################
        $SchedulePolicyObject = Get-AzRecoveryServicesBackupSchedulePolicyObject -WorkloadType "AzureVM"
        if(-not $SchedulePolicyObject) { 
          $Log.Info("SchedulePolicyObject�̐����Ɏ��s���܂����B")
          exit 9
        }
        $UtcTime = Get-Date -Date ((Get-Date).ToString("yyyy/MM/dd") + " 12:00:00")
        $UtcTime = $UtcTime.ToUniversalTime()
        $SchedulePolicyObject.ScheduleRunTimes[0] = $UtcTime
        
        $RetentionPolicyObject = Get-AzRecoveryServicesBackupRetentionPolicyObject -WorkloadType "AzureVM"
        if(-not $RetentionPolicyObject) { 
          $Log.Info("RetentionPolicyObject�̐����Ɏ��s���܂����B")
          exit 9
        }
        $RetentionPolicyObject.IsWeeklyScheduleEnabled = $false
        $RetentionPolicyObject.IsMonthlyScheduleEnabled = $false
        $RetentionPolicyObject.IsYearlyScheduleEnabled = $false
        $RetentionPolicyObject.DailySchedule.DurationCountInDays = 7
        $UtcTime = Get-Date -Date ((Get-Date).ToString("yyyy/MM/dd") + " 15:00:00")
        $UtcTime = $UtcTime.ToUniversalTime()
        $RetentionPolicyObject.DailySchedule.RetentionTimes[0] = $UtcTime

        $AzureVMProtectionPolicy = New-AzRecoveryServicesBackupProtectionPolicy -Name $AzureVMBackupPolicyName -WorkloadType "AzureVM" -RetentionPolicy $RetentionPolicyObject -SchedulePolicy $SchedulePolicyObject
        if(-not $AzureVMProtectionPolicy) { 
          $Log.Error("�o�b�N�A�b�v�|���V�[�̍쐬�Ɏ��s���܂����B")
          exit 9
        }
      } 
      ############################
      # Azure Backup(IaaS)�̗L����
      ############################
      foreach($AzureVMProtectionPolicy in $AzureVMProtectionPolicies) {
        $UTCDate = (Get-Date).AddHours($DisableHours).ToUniversalTime().ToString("yyyy/MM/dd")
        $RetentionTime = Get-Date -Date $($UTCDate + " " + $AzureVMProtectionPolicy.RetentionPolicy.DailySchedule.RetentionTimes[0].toString("HH:mm"))
        $DisableTime = $RetentionTime.AddHours(-1 * $DisableHours)
        $Now = (Get-Date).ToUniversalTime()

        $Log.Info($AzureVMProtectionPolicy.Name + "�̗L�������ԑт� �`" + $DisableTime.ToLocalTime().ToString("yyyy/MM/dd HH:mm") + "�܂łł��B" + $RetentionTime.ToLocalTime().ToString("yyyy/MM/dd HH:mm") + "�ڍs�ɍėL�����\�ł��B")
        if(($Now -gt $RetentionTime) -or ($Now -le $DisableTime)) {
          $Log.Info($AzureVMProtectionPolicy.Name + "�̗L�����������J�n���܂��B")
        
          $SettingFile = $AzureVMProtectionPolicy.Name + ".xml"
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
            $BackupItem = Get-AzRecoveryServicesBackupItem -Container $Container -WorkloadType AzureVM 
            foreach($AzureVM in $BackupPolicyConfig.BackupPolicy.VM) {
              if($BackupItem.ProtectionPolicyName) {
                $Log.Info($Container.FriendlyName + "�͗L�����ςł��B")
                break
              } elseif($Container.FriendlyName -eq $AzureVM.Name) {
                ############################
                # �L�����o�b�N�O���E���h���s
                ############################
                $EnableJob = {
                  param([string]$VaultName, [string]$VMName, [string]$PolicyName)
                  try {
                    Get-AzRecoveryServicesVault -Name $VaultName | Set-AzRecoveryServicesVaultContext
                    $Container = Get-AzRecoveryServicesBackupContainer -ContainerType "AzureVM" -Status "Registered" -FriendlyName $VMName
                    $Item = Get-AzRecoveryServicesBackupItem -Container $Container -WorkloadType AzureVM 
                    $AzureVMProtectionPolicy = Get-AzRecoveryServicesBackupProtectionPolicy -Name $PolicyName
                    $EnabledItem = Enable-AzRecoveryServicesBackupProtection -Item $Item -Policy $AzureVMProtectionPolicy
                    Write-Host("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $EnabledItem.WorkloadName + "��Azure Backup��L�������܂����B")
                  } catch {
                    Write-Host("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $VMName + "��Azure Backu�L�����Ɏ��s���܂����B")
                    throw
                  } 
                }
                Start-Job $EnableJob -ArgumentList $Vault.Name, $Container.FriendlyName, $AzureVMProtectionPolicy.Name
                $Log.Info($Container.FriendlyName + "��Azure Backup�W���u��L�������܂����B")
                break
              } else {
                Continue
              }
            }
          }
        } else {
          $Log.Info($AzureVMProtectionPolicy.Name + "�͗L���������̑ΏۊO�ł��B")
        }
      }
      Get-Job | Wait-Job
      $Log.Info($(Get-Job | Receive-Job))
      Get-Job | Remove-Job
      $Log.Info("Azure Backup�L��������:����")
    } else {
      ############################
      # Azure Backup(IaaS)�̖�����
      ############################
      $Log.Info("Azure Backup����������:�J�n")
      foreach($AzureVMProtectionPolicy in $AzureVMProtectionPolicies) {
        $UTCDate = (Get-Date).AddHours($DisableHours).ToUniversalTime().ToString("yyyy/MM/dd")
        $RetentionTime = Get-Date -Date $($UTCDate + " " + $AzureVMProtectionPolicy.RetentionPolicy.DailySchedule.RetentionTimes[0].toString("HH:mm"))
        $DisableTime = $RetentionTime.AddHours(-1 * $DisableHours)
        $Now = (Get-Date).ToUniversalTime()

        $Log.Info($AzureVMProtectionPolicy.Name + "�̖��������ԑт� " + $DisableTime.ToLocalTime().ToString("yyyy/MM/dd HH:mm") + "�`" + $RetentionTime.ToLocalTime().ToString("yyyy/MM/dd HH:mm") + "�ł��B")
        if(($DisableTime -le $Now) -and ($Now -lt $RetentionTime)) {
          $Log.Info($AzureVMProtectionPolicy.Name + "�̖������������J�n���܂��B")
          foreach($Container in $RegisterdVMsContainer) {
            $BackupItem = Get-AzRecoveryServicesBackupItem -Container $Container -WorkloadType AzureVM 
            if($BackupItem.ProtectionPolicyName -eq $AzureVMProtectionPolicy.Name) {
            ############################
            # �������o�b�N�O���E���h���s
            ############################
              $DisabaleJob = {
                param([string]$VaultName, [string]$VMName)
                try {
                  Get-AzRecoveryServicesVault -Name $VaultName | Set-AzRecoveryServicesVaultContext
                  $Container = Get-AzRecoveryServicesBackupContainer -ContainerType "AzureVM" -Status "Registered" -FriendlyName $VMName
                  $Item = Get-AzRecoveryServicesBackupItem -Container $Container -WorkloadType AzureVM 
                  $DisabledItem = Disable-AzRecoveryServicesBackupProtection -Item $Item -Force
                  Write-Host("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $DisabledItem.WorkloadName + "��Azure Backup�𖳌������܂����B")
                } catch {
                  Write-Host("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $VMName + "��Azure Backup�������Ɏ��s���܂����B")
                  throw
                } 
              }
              Start-Job $DisabaleJob -ArgumentList $Vault.Name, $Container.FriendlyName
              $Log.Info($Container.FriendlyName + "��Azure Backup���������o�b�N�O���E���h�W���u�Ŏ��s���܂����B")
              Continue
            } elseif(-not $BackupItem.ProtectionPolicyName) {
              $Log.Info($Container.FriendlyName  + "�͖������ς݂ł��B")
            } else {
              Continue
            }
          }
        } else {
          $Log.Info($AzureVMProtectionPolicy.Name + "�͖����������̑ΏۊO�ł��B")
        }
      }
      Get-Job | Wait-Job
      $Log.Info($(Get-Job | Receive-Job))
      Get-Job | Remove-Job
      $Log.Info("Azure Backup����������:����")
    }
  }
} catch {
    $Log.Error("�������ɃG���[���������܂����B")
    $Log.Error($_.Exception)
    exit 99
}
exit 0