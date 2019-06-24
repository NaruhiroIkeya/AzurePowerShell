<################################################################################
## Copyright(c) 2019 BeeX Inc. All rights reserved.
## @auther#Naruhiro Ikeya
##
## @name:RemoveSnapshot.ps1
## @summary:�����؂�X�i�b�v�V���b�g�̍폜
##
## @since:2019/03/16
## @version:1.0
## @see:
## @parameter
##  1:Azure VM���\�[�X�O���[�v��
##
## @return:0:Success 9:�G���[�I��
################################################################################>

##########################
# �p�����[�^�ݒ�
##########################
param (
  [string]$AzureVMResourceGroupName,
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

##########################
# �x���̕\���}�~
##########################
Set-Item Env:\SuppressAzurePowerShellBreakingChangeWarnings "true"

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
 
  ###################################
  # �p�����[�^�`�F�b�N
  ###################################
  $RemoveSnapshots = $null
  if(-not $AzureVMResourceGroupName) {
    $RemoveSnapshots = Get-AzSnapshot | Where-Object { $_.Tags.ExpireDate -ne $null -and [DateTime]::Parse($_.Tags.ExpireDate) -lt (Get-Date) }
  } else {
    $ResourceGroups = Get-AzResourceGroup -Name $AzureVMResourceGroupName
    if(-not $ResourceGroups) {
      $Log.Info("�w�肳�ꂽ���\�[�X�O���[�v������܂���:$AzureVMResourceGroupName")
      exit 9
    }
    $RemoveSnapshots = Get-AzSnapshot -ResourceGroupName $ResourceGroups.ResourceGroupName | Where-Object { $_.Tags.ExpireDate -ne $null -and [DateTime]::Parse($_.Tags.ExpireDate) -lt (Get-Date) }
  }
  if(-not $RemoveSnapshots){
      $Log.Info("�폜�Ώۂ�Snapshot������܂���B")
      exit 0
  }

  ###################################
  # AzureVM Snapshot����Ǘ�
  ###################################
  $Log.Info("�����؂�SnapShot�폜:�J�n")
  foreach ($Snapshot in $RemoveSnapshots) {
    Remove-AzSnapshot -ResourceGroupName $Snapshot.ResourceGroupName -SnapshotName $Snapshot.Name -Force | % { $Log.Info("�����؂�Snapshot�폜:" + $Snapshot.Name + " : " + $_.Status) }
  }
  $Log.Info("�����؂�SnapShot�폜:����")
} catch {
    $Log.Error("�Ǘ��f�B�X�N�̃X�i�b�v�V���b�g�폜���ɃG���[���������܂����B")
    $Log.Error($_.Exception)
    exit 99
}
exit 0