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
  $Log.error("Syntax Error:���s���� -EnableAzureBackup / -DisableAzureBackup ���w�肵�Ă��������B")
  exit 9
}

##########################
# �x���̕\���}�~
##########################
Set-Item Env:\SuppressAzurePowerShellBreakingChangeWarnings "true"

try {
  $SettingFilePath = Split-Path $MyInvocation.MyCommand.Path -Parent | Split-Path -Parent | Join-Path -ChildPath etc -Resolve
  $SettingFile = "AzureCredential.xml"
  $Connect = New-Object AzureLogonFunction("C:\Users\naruhiro.ikeya\Documents\GitHub\AzurePowerShell\etc\AzureCredential.xml")
  if($Connect.Initialize($Log)) { if(-not $Connect.Logon()) { exit 9 } }

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
      if(-not $AzureVMProtectionPolicy) {
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
          $Log.error("�o�b�N�A�b�v�|���V�[�̍쐬�Ɏ��s���܂����B")
          exit 9
        }
      } 
      ############################
      # Azure Backup(IaaS)�̗L����
      ############################
      foreach($AzureVMProtectionPolicy in $AzureVMProtectionPolicies) {
        $RetentionTime = $AzureVMProtectionPolicy.RetentionPolicy.DailySchedule.RetentionTimes[0].toString("HHmm")
        $Now = ((Get-Date).ToUniversalTime()).ToString("HHmm") 
        $Log.Info("" + $AzureVMProtectionPolicy.Name + "�̗L�������ԑт� " + $RetentionTime + "�`(UTC)�ł��B")
        if($Now -gt $RetentionTime) {
          $Log.Info("" + $AzureVMProtectionPolicy.Name + "�̗L�����������J�n���܂��B")
        
          $SettingFile = $AzureVMProtectionPolicy.Name + ".xml"
          $Log.Info("Backup Policy�t�@�C�����F" + $SettingFile)
          if(-not (Test-Path(Join-Path $SettingFilePath -ChildPath $SettingFile))) {
            $Log.Info("Backup Policy�t�@�C�������݂��܂���B")
            break
          }
          $BackupPolicyConfig = [xml](Get-Content (Join-Path $SettingFilePath -ChildPath $SettingFile -Resolve))
          if(-not $BackupPolicyConfig) { 
            $Log.Info("����̃t�@�C������ݒ��񂪓ǂݍ��߂܂���ł����B")
            exit 9
          } 
          foreach($Container in $RegisterdVMsContainer) {
            $BackupItem = Get-AzRecoveryServicesBackupItem -Container $Container -WorkloadType AzureVM 
            foreach($AzureVM in $BackupPolicyConfig.BackupPolicy.VM) {
              if($BackupItem.ProtectionPolicyName) {
                $Log.Info("" + $Container.FriendlyName + "�͗L�����ςł��B")
                break
              } elseif($Container.FriendlyName -eq $AzureVM.Name) {
                $EnabledItem = Enable-AzRecoveryServicesBackupProtection -Item $BackupItem -Policy $AzureVMProtectionPolicy
                $Log.Info("" + $EnabledItem.WorkloadName + "��Azure Backup�W���u��L�������܂����B")
                break
              } else {
                Continue
              }
            }
          }
        } else {
          $Log.Info("" + $AzureVMProtectionPolicy.Name + "�͗L���������̑ΏۊO�ł��B")
        }
      }
      $Log.Info("zure Backup�L��������:����")
    } else {
      ############################
      # Azure Backup(IaaS)�̖�����
      ############################
      $Log.Info("zure Backup����������:�J�n")
      foreach($AzureVMProtectionPolicy in $AzureVMProtectionPolicies) {
        $RetentionTime = $AzureVMProtectionPolicy.RetentionPolicy.DailySchedule.RetentionTimes[0].toString("HHmm")
        $DisableTime = $AzureVMProtectionPolicy.RetentionPolicy.DailySchedule.RetentionTimes[0].AddHours(-1 * $DisableHours).toString("HHmm")
        $Now = ((Get-Date).ToUniversalTime()).ToString("HHmm") 
        $Log.Info("" + $AzureVMProtectionPolicy.Name + "�̖��������ԑт� " + $DisableTime + "�`" + $RetentionTime + "(UTC)�ł��B")
        if($DisableTime -le $Now -and $Now -lt $RetentionTime) {
          $Log.Info("" + $AzureVMProtectionPolicy.Name + "�̖������������J�n���܂��B")
          foreach($Container in $RegisterdVMsContainer) {
            $BackupItem = Get-AzRecoveryServicesBackupItem -Container $Container -WorkloadType AzureVM 
            if($BackupItem.ProtectionPolicyName -eq $AzureVMProtectionPolicy.Name) {
              $DisabledItem = Disable-AzRecoveryServicesBackupProtection -Item $BackupItem -Force
              $Log.Info("" + $DisabledItem.WorkloadName + "��Azure Backup�W���u�𖳌������܂����B")
              Continue
            } elseif(-not $BackupItem.ProtectionPolicyName) {
              $Log.Info("" + $Container.FriendlyName  + "�͖������ς݂ł��B")
            } else {
              Continue
            }
          }
        } else {
          $Log.Info("" + $AzureVMProtectionPolicy.Name + "�͖����������̑ΏۊO�ł��B")
        }
      }
      $Log.Info("Azure Backup����������:����")
    }
  }
} catch {
    $Log.Info("�������ɃG���[���������܂����B")
    $Log.Info($("" + $error[0] | Format-List --DisplayError))
    exit 99
}

exit 0