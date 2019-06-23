<################################################################################
## Copyright(c) 2019 BeeX Inc. All rights reserved.
## @auther#Naruhiro Ikeya
##
## @name:ExecAzureBackupJob.ps1
## @summary:Azure�o�b�N�A�b�v���s�{��
##
## @since:2019/06/24
## @version:1.0
## @see:
## @parameter
##  1:AzureVM��
##  2:Recovery Service�R���e�i�[��
##  3:�o�b�N�A�b�v�ۊǓ���
##  4:Azure Backup�W���u�|�[�����O�Ԋu�i�b�j
##  5:���^�[���X�e�[�^�X�i�X�i�b�v�V���b�g�҂��A�����҂��j
##
## @return:0:Success 
##         1:���̓p�����[�^�G���[
##         2:Azure Backup�W���u�Ď����f�iTake Snapshot�����j
##         9:Azure Backup���s�G���[
##         99:Exception
################################################################################>

##########################
# �p�����[�^�ݒ�
##########################
param (
  [parameter(mandatory=$true)][string]$AzureVMName,
  [parameter(mandatory=$true)][string]$RecoveryServiceVaultName,
  [parameter(mandatory=$true)][int]$AddDays,
  [parameter(mandatory=$true)][int64]$JobTimeout,
  [int]$ReturnMode=0,
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
New-Variable -Name ReturnState -Value @("Take Snapshot","Transfer data to vault") -Option ReadOnly

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
if($JobTimeout -le 0) {
  $Log.Info("�|�[�����O�Ԋu�i�b�j��1�ȏ��ݒ肵�Ă��������B")
  exit 1
}
if($AddDays -le 0) {
  $Log.Info("�o�b�N�A�b�v�ێ�������1�ȏ��ݒ肵�Ă��������B")
  exit 1
}

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

  #################################################
  # Recovery Service �R���e�i�[�̃R���e�L�X�g�̐ݒ�
  #################################################
  $Log.Info($AzureVMName + "�̃o�b�N�A�b�v���J�n���܂��B")
  $Log.Info("Recovery Services �R���e�i�[��������擾���܂��B")
  $RecoveryServiceVault = Get-AzRecoveryServicesVault -Name $RecoveryServiceVaultName
  if(-not $RecoveryServiceVault) { 
    $Log.Info("Recovery Service�R���e�i�[�����s���ł��B")
    exit 1
  }
  Set-AzRecoveryServicesVaultContext -Vault $RecoveryServiceVault

  #################################################
  # Azure Backup(IaaS) �ݒ�ς݃T�[�o ���擾
  #################################################
  $BackupContainer = Get-AzRecoveryServicesBackupContainer -ContainerType "AzureVM" -Status "Registered" -FriendlyName $AzureVMName
  if(-not $BackupContainer) { 
    $Log.Info("Recovery Services �R���e�i�[�Ƀo�b�N�A�b�v�Ώہi" + $AzureVMName + "�j�����݂��܂���B")
    exit 1
  }
  $BackupItem = Get-AzRecoveryServicesBackupItem -Container $BackupContainer -WorkloadType "AzureVM"
  ##########################################################################################################################
  # -ExpiryDateTimeUTC�ɂ́A�o�b�N�A�b�v�ۊǊ��Ԃ��w��i�uUTC�v���W���u���s�^�C�~���O����u1����v�`�u99�N��v�Ŏw��j
  ##########################################################################################################################
  $ExpiryDateUTC = [DateTime](Get-Date).ToUniversalTime().AddDays($AddDays).ToString("yyyy/MM/dd")
  #################################################
  # Azure Backup(IaaS) ���s
  #################################################
  $Log.Info("Azure Backup�W���u�����s���܂��B")
  $Job = Backup-AzRecoveryServicesBackupItem -Item $BackupItem -ExpiryDateTimeUTC $ExpiryDateUTC
  if($Job.Status -eq "Failed") {
    $Log.Error("Azure Backup�W���u���G���[�I�����܂����B")
�@�@$Job | Format-List -DisplayError
    exit 9
  }

  #################################################
  # �W���u�I���ҋ@(Snapshot�擾�҂�)
  #################################################
  $JobResult = Wait-AzRecoveryServicesBackupJob -Job $Job -Timeout $JobTimeout
  While(($($JobResult.SubTasks | ? {$_.Name -eq $ReturnState[$ReturnMode]} | % {$_.Status}) -ne "Completed") -and ($JobResult.Status -ne "Failed" -and $JobResult.Status -ne "Cancelled")) {
    $Log.Info($ReturnState[$ReturnMode] + "�t�F�[�Y�̊�����ҋ@���Ă��܂��B")    
    $JobResult = Wait-AzRecoveryServicesBackupJob -Job $Job -Timeout $JobTimeout
  }
  if($JobResult.Status -eq "InProgress") {
    $SubTasks = $(Get-AzRecoveryServicesBackupJobDetails -JobId $JobResult.JobId).SubTasks
    $Log.Info("Azure Backup�W���u�Ď��𒆒f���܂��BJob ID=" +  $JobResult.JobId)
    Foreach($SubTask in $SubTasks) {
      $Log.Info($SubTask.Name + " " +  $SubTask.Status)
    }
    exit 2
  } elseif($JobResult.Status -eq "Cancelled") {
    $SubTasks = $(Get-AzRecoveryServicesBackupJobDetails -JobId $JobResult.JobId).SubTasks
    $Log.Warn("Azure Backup�W���u���L�����Z������܂����BJob ID=" +  $JobResult.JobId)
    Foreach($SubTask in $SubTasks) {
      $Log.Warn($SubTask.Name + " " +  $SubTask.Status)
    }
    exit 0
  }

  #################################################
  # �G���[�n���h�����O
  #################################################
  if($JobResult.Status -eq "Failed") {
    $Log.Info("Azure Backup�W���u���G���[�I�����܂����B")
�@�@$JobResult | Format-List -DisplayError
    exit 9
  } else {
    $Log.Info("Azure Backup�W���u���������܂����B")
    exit 0
  }
} catch {
    $Log.Error("Azure Backup���s���ɃG���[���������܂����B")
    $Log.Error($($error[0] | Format-List --DisplayError))
    exit 99
}
exit 0