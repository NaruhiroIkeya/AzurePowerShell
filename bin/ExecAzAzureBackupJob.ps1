<################################################################################
## Copyright(c) 2019 BeeX Inc. All rights reserved.
## @auther#Naruhiro Ikeya
##
## @name:AzureBackup.ps1
## @summary:ExecAzureBackupJob.ps1 Wrapper
##
## @since:2019/06/24
## @version:1.0
## @see:
## @parameter
##  1:AzureVM��
##  2:Recovery Service�R���e�i�[��
##  3:Azure Backup�W���u���s�҂��^�C���A�E�g�l
##
## @return:0:Success 1:�p�����[�^�G���[ 2:Azure Backup���s�G���[ 9:Exception
################################################################################>

##########################
# �p�����[�^�ݒ�
##########################
param (
  [parameter(mandatory=$true)][string]$AzureVMName,
  [parameter(mandatory=$true)][string]$RecoveryServiceVaultName,
  [parameter(mandatory=$true)][int64]$JobTimeout,
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
if($JobTimeout -lt 0) {
  $Log.Info("�^�C���A�E�g�l��0�ȏ��ݒ肵�Ă��������B`r`n")
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
  $Log.Info("Recovery Service�R���e�i�[��������擾���܂��B")
  $RecoveryServiceVault = Get-AzRecoveryServicesVault -Name $RecoveryServiceVaultName
  if(-not $RecoveryServiceVault) { 
    $Log.Info("Recovery Service�R���e�i�[�����s���ł��B")
    exit 1
  }
  Set-AzRecoveryServicesVaultContext -Vault $RecoveryServiceVault

  #################################################
  # Azure Backup(IaaS) �ݒ�ς݃T�[�o ���擾
  #################################################
  $Log.Info("Azure Backup�����s���܂��B")
  $BackupContainer = Get-AzRecoveryServicesBackupContainer -ContainerType "AzureVM" -Status "Registered" -FriendlyName $AzureVMName
  if(-not $BackupContainer) { 
    $Log.Info("Recovery Service�R���e�i�[�Ƀo�b�N�A�b�v�Ώۂ����݂��܂���B")
    exit 1
  }
  $BackupItem = Get-AzRecoveryServicesBackupItem -Container $BackupContainer -WorkloadType "AzureVM"
  $Job = Backup-AzRecoveryServicesBackupItem -Item $BackupItem

  #################################################
  # Azure Backup(IaaS) ���s
  #################################################
  $JobResult = Wait-AzRecoveryServicesBackupJob -Job $Job -Timeout $JobTimeout

  #################################################
  # �G���[�n���h�����O
  #################################################
  if($JobResult.Status -eq "Failed") {
    $Log.Error("Azure Backup�W���u���G���[�I�����܂����B")
    $Log.Error($($JobResult | Format-List -DisplayError))
    exit 9
  } elseif($JobResult.Status -eq "InProgress") {
    $Log.Warn("Azure Backup�҂����^�C���A�E�g���܂����B")
    $Log.Warn($($JobResult | Format-List -DisplayError))
  } elseif($JobResult.Status -eq "Completed") {
    $Log.Info("Azure Backup���������܂����B")
    exit 0
  } else {
    $Log.Warn("Azure Backup�����s���ł��B")
    $Log.Warn($($JobResult | Format-List -DisplayError))
  } 
} catch {
    $log.Error("Azure Backup���s���ɃG���[���������܂����B")
    $Log.Error($_.Exception)
    exit 99
}
exit 0