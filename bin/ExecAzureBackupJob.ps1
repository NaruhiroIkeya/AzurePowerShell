<################################################################################
## Copyright(c) 2019 BeeX Inc. All rights reserved.
## @auther#Naruhiro Ikeya
##
## @name:ExecAzureBackupJob.ps1
## @summary:Azure�o�b�N�A�b�v���s�{��
##
## @since:2019/01/28
## @version:1.0
## @see:
## @parameter
##  1:AzureVM��
##  2:Recovery Service�R���e�i�[��
##  3:Azure Backup�W���u�|�[�����O�Ԋu�i�b�j
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
  [int]$ReturnMode=0
)

##########################
# �F�؏��ݒ�
##########################
$TennantID="e2fb1fde-e67c-4a07-8478-5ab2b9a0577f"
$Key="I9UCoQXrv/G/EqC93RC7as8eyWARVd77UUC/fxRdGTw="
$ApplicationID="1cb16aa7-59a6-4d8e-89ef-3b896d9f1718"

##########################
# �p�����[�^�`�F�b�N
##########################
if($JobTimeout -le 0) {
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] �|�[�����O�Ԋu�i�b�j��1�ȏ��ݒ肵�Ă��������B")
  exit 1
}
if($AddDays -le 0) {
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] �o�b�N�A�b�v�ێ�������1�ȏ��ݒ肵�Ă��������B")
  exit 1
}

try {
  Import-Module AzureRM

  New-Variable -Name ReturnState -Value @("Take Snapshot","Transfer data to vault") -Option ReadOnly

  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $AzureVMName + "�̃o�b�N�A�b�v���J�n���܂��B")
  ##########################
  # Azure�ւ̃��O�C��
  ##########################
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] �T�[�r�X�v�����V�p���𗘗p��Azure�փ��O�C�����܂��B")
  $SecPasswd = ConvertTo-SecureString $Key -AsPlainText -Force
  $MyCreds = New-Object System.Management.Automation.PSCredential ($ApplicationID, $SecPasswd)
  $LoginInfo = Login-AzureRmAccount  -ServicePrincipal -Tenant $TennantID -Credential $MyCreds
  if(-not $LoginInfo) { 
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Azure�փ��O�C���ł��܂���ł����B")
    exit 9
  }

  #################################################
  # Recovery Service �R���e�i�[�̃R���e�L�X�g�̐ݒ�
  #################################################
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Recovery Services �R���e�i�[��������擾���܂��B")
  $RecoveryServiceVault = Get-AzureRmRecoveryServicesVault -Name $RecoveryServiceVaultName
  if(-not $RecoveryServiceVault) { 
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Recovery Service�R���e�i�[�����s���ł��B")
    exit 1
  }
  Set-AzureRmRecoveryServicesVaultContext -Vault $RecoveryServiceVault

  #################################################
  # Azure Backup(IaaS) �ݒ�ς݃T�[�o ���擾
  #################################################
  $BackupContainer = Get-AzureRmRecoveryServicesBackupContainer -ContainerType "AzureVM" -Status "Registered" -FriendlyName $AzureVMName
  if(-not $BackupContainer) { 
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Recovery Services �R���e�i�[�Ƀo�b�N�A�b�v�Ώہi" + $AzureVMName + "�j�����݂��܂���B")
    exit 1
  }
  $BackupItem = Get-AzureRmRecoveryServicesBackupItem -Container $BackupContainer -WorkloadType "AzureVM"
  ##########################################################################################################################
  # -ExpiryDateTimeUTC�ɂ́A�o�b�N�A�b�v�ۊǊ��Ԃ��w��i�uUTC�v���W���u���s�^�C�~���O����u1����v�`�u99�N��v�Ŏw��j
  ##########################################################################################################################
  $ExpiryDateUTC = [DateTime](Get-Date).ToUniversalTime().AddDays($AddDays).ToString("yyyy/MM/dd")
  #################################################
  # Azure Backup(IaaS) ���s
  #################################################
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Azure Backup�W���u�����s���܂��B")
  $Job = Backup-AzureRmRecoveryServicesBackupItem -Item $BackupItem -ExpiryDateTimeUTC $ExpiryDateUTC
  if($Job.Status -eq "Failed") {
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Azure Backup�W���u���G���[�I�����܂����B")
�@�@$Job | Format-List -DisplayError
    exit 9
  }

  #################################################
  # �W���u�I���ҋ@(Snapshot�擾�҂�)
  #################################################
  $JobResult = Wait-AzureRmRecoveryServicesBackupJob -Job $Job -Timeout $JobTimeout
  While(($($JobResult.SubTasks | ? {$_.Name -eq $ReturnState[$ReturnMode]} | % {$_.Status}) -ne "Completed") -and ($JobResult.Status -ne "Failed" -and $JobResult.Status -ne "Cancelled")) {
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $ReturnState[$ReturnMode] + "�t�F�[�Y�̊�����ҋ@���Ă��܂��B")    
    $JobResult = Wait-AzureRmRecoveryServicesBackupJob -Job $Job -Timeout $JobTimeout
  }
  if($JobResult.Status -eq "InProgress") {
    $SubTasks = $(Get-AzureRmRecoveryServicesBackupJobDetails -JobId $JobResult.JobId).SubTasks
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Azure Backup�W���u�Ď��𒆒f���܂��BJob ID=" +  $JobResult.JobId)
    Foreach($SubTask in $SubTasks) {
      Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $SubTask.Name + " " +  $SubTask.Status)
    }
    exit 2
  } elseif($JobResult.Status -eq "Cancelled") {
    $SubTasks = $(Get-AzureRmRecoveryServicesBackupJobDetails -JobId $JobResult.JobId).SubTasks
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Azure Backup�W���u���L�����Z������܂����BJob ID=" +  $JobResult.JobId)
    Foreach($SubTask in $SubTasks) {
      Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $SubTask.Name + " " +  $SubTask.Status)
    }
    exit 0
  }

  #################################################
  # �G���[�n���h�����O
  #################################################
  if($JobResult.Status -eq "Failed") {
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Azure Backup�W���u���G���[�I�����܂����B")
�@�@$JobResult | Format-List -DisplayError
    exit 9
  } else {
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Azure Backup�W���u���������܂����B")
  }
} catch {
    Write-Output("`r`n`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Azure Backup���s���ɃG���[���������܂����B")
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $error[0] | Format-List --DisplayError)
    exit 99
}
exit 0