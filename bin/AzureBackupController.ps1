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
# �Œ�l 
##########################

Set-Variable -Name "ConstantPolicyName" -Value "CooperationJobSchedulerDummyPolicy" -Option Constant
Set-Variable -Name "DisableHours" -Value 1 -Option Constant

##########################
# �p�����[�^�`�F�b�N
##########################
if ($EnableAzureBakup -xor $DisableAzureBakup) {
  if ($EnableAzureBakup) {
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Azure Backup��L�������܂��B")
  } else {
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Azure Backup�𖳌������܂��B")
  }
} else {
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Syntax Error:���s���� -EnableAzureBackup / -DisableAzureBackup ���w�肵�Ă��������B")
    exit 9
}

##########################
# �x���̕\���}�~
##########################
Set-Item Env:\SuppressAzurePowerShellBreakingChangeWarnings "true"

try {
  ##########################
  # �F�؏��擾
  ##########################
  $SettingFilePath = Split-Path $MyInvocation.MyCommand.Path -Parent | Split-Path -Parent | Join-Path -ChildPath etc -Resolve
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] �ݒ�t�@�C��Path�F" + $SettingFilePath)
  $SettingFile = "AzureCredential.xml"
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] �ݒ�t�@�C�����F" + $SettingFile)

  $Config = [xml](Get-Content (Join-Path $SettingFilePath -ChildPath $SettingFile -Resolve))
  if(-not $Config) { 
      Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] ����̃t�@�C������F�؏�񂪓ǂݍ��߂܂���ł����B")
      exit 9
  } elseif (-not $Config.Configuration.Key) {
    ##########################
    # Azure�ւ̃��O�C��
    ##########################
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Azure�փ��O�C��:�J�n")
    $LoginInfo = Login-AzAccount -Tenant $Config.Configuration.TennantID -WarningAction Ignore
  } else {
    ##########################
    # Azure�ւ̃��O�C��
    ##########################
    $Config.Configuration.Key
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] �T�[�r�X�v�����V�p���𗘗p��Azure�փ��O�C��:�J�n")
    $SecPasswd = ConvertTo-SecureString $Config.Configuration.Key -AsPlainText -Force
    $MyCreds = New-Object System.Management.Automation.PSCredential ($Config.Configuration.ApplicationID, $secpasswd)
    $LoginInfo = Login-AzAccount  -ServicePrincipal -Tenant $Config.Configuration.TennantID -Credential $MyCreds  -WarningAction Ignore
  }
  if(-not $LoginInfo) { 
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Azure�փ��O�C��:���s")
    exit 9
  }
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Azure�փ��O�C��:����")

  $RecoveryServicesVaults = Get-AzRecoveryServicesVault
  foreach($Vault in $RecoveryServicesVaults) {
    Set-AzRecoveryServicesVaultContext -Vault $Vault
    if(-not $AzureVMBackupPolicyName) {
      $AzureVMProtectionPolicies = Get-AzRecoveryServicesBackupProtectionPolicy -WorkloadType "AzureVM" 
    } else {
      $AzureVMProtectionPolicies = Get-AzRecoveryServicesBackupProtectionPolicy | ? { $_.Name -eq $AzureVMBackupPolicyName }
      if((-not $AzureVMProtectionPolicies) -and $DisableAzureBakup) {
        Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] �w�肳�ꂽBackup Policy��������܂���B:$AzureVMBackupPolicyName")
        exit 9
      } elseif(-not $AzureVMProtectionPolicies) {
        Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Azure�փ��O�C��:����")
      }
    }
    $RegisterdVMsContainer = Get-AzRecoveryServicesBackupContainer -ContainerType "AzureVM" -Status "Registered"
    if($EnableAzureBakup) {
      Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Azure Backup�L��������:�J�n")
      if(-not $AzureVMProtectionPolicy) {
        ##########################
        # Backup Policy�̐V�K�쐬
        ##########################
        $SchedulePolicyObject = Get-AzRecoveryServicesBackupSchedulePolicyObject -WorkloadType "AzureVM"
        if(-not $SchedulePolicyObject) { 
          Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] SchedulePolicyObject�̐����Ɏ��s���܂����B")
          exit 9
        }
        $UtcTime = Get-Date -Date ((Get-Date).ToString("yyyy/MM/dd") + " 12:00:00")
        $UtcTime = $UtcTime.ToUniversalTime()
        $SchedulePolicyObject.ScheduleRunTimes[0] = $UtcTime
        
        $RetentionPolicyObject = Get-AzRecoveryServicesBackupRetentionPolicyObject -WorkloadType "AzureVM"
        if(-not $RetentionPolicyObject) { 
          Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] RetentionPolicyObject�̐����Ɏ��s���܂����B")
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
          Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] �o�b�N�A�b�v�|���V�[�̍쐬�Ɏ��s���܂����B")
          exit 9
        }
      } else {


      }
      Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Azure Backup�L��������:����")
    } else {
      ############################
      # Azure Backup(IaaS)�̖�����
      ############################
      Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Azure Backup����������:�J�n")
      foreach($AzureVMProtectionPolicy in $AzureVMProtectionPolicies) {
        $RetentionTime = $AzureVMProtectionPolicy.RetentionPolicy.DailySchedule.RetentionTimes[0].toString("HHmm")
        $DisableTime = $AzureVMProtectionPolicy.RetentionPolicy.DailySchedule.RetentionTimes[0].AddHours(-1 * $DisableHours).toString("HHmm")
        $Now = ((Get-Date).ToUniversalTime()).ToString("HHmm") 
        Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $AzureVMProtectionPolicy.Name + "�̖��������ԑт� " + $DisableTime + "�`" + $RetentionTime + "(UTC)�ł��B")
        if($DisableTime -le $Now -and $Now -lt $RetentionTime) {
          Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $AzureVMProtectionPolicy.Name + "�̖������������J�n���܂��B")
          foreach($Container in $RegisterdVMsContainer) {
            $BackupItem = Get-AzRecoveryServicesBackupItem -Container $Container -WorkloadType AzureVM 
            if($BackupItem.ProtectionPolicyName -eq $AzureVMProtectionPolicy.Name) {
              $DisabledItem = Disable-AzRecoveryServicesBackupProtection -Item $BackupItem -Force
              Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $DisabledItem.WorkloadName + "��Azure Backup�W���u�𖳌������܂����B")
              Continue
            } elseif(-not $BackupItem.ProtectionPolicyName) {
              Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $Container.FriendlyName  + "�͖������ς݂ł��B")
            } else {
              Continue
            }
          }
        } else {
          Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $AzureVMProtectionPolicy.Name + "�͖����������̑ΏۊO�ł��B")
        }
      }
      Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Azure Backup����������:����")
    }
  }
} catch {
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] �������ɃG���[���������܂����B")
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $error[0] | Format-List --DisplayError)
    exit 99
}
exit 0
