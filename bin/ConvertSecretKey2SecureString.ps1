<################################################################################
## Copyright(c) 2020 BeeX Inc. All rights reserved.
## @auther#Naruhiro Ikeya
##
## @name:ConvertSecretKey2SecureString.ps1
## @summary:Convert Service Principal Secret Key to SecureString
##
## @since:2020/05/01
## @version:1.0
## @see:
## @parameter
##  1:�W���o��
##
## @return:0:Success 1:�p�����[�^�G���[ 2:Az command���s�G���[ 9:Exception
################################################################################>

##########################
# �p�����[�^�ݒ�
##########################
param (
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
[string]$CredenticialFile = "AzureCredential.xml"
[string]$SecureCredenticialFile = "AzureCredential_Secure.xml"
[int]$SaveDays = 7

##########################
# �x���̕\���}�~
##########################
# Set-Item Env:\SuppressAzurePowerShellBreakingChangeWarnings "true"

###############################
# LogController �I�u�W�F�N�g����
###############################
if($Stdout) {
  $Log = New-Object LogController($true, (Get-ChildItem $MyInvocation.MyCommand.Path).Name)
} else {
  $LogFilePath = Split-Path $MyInvocation.MyCommand.Path -Parent | Split-Path -Parent | Join-Path -ChildPath log -Resolve
  $LogFile = (Get-ChildItem $MyInvocation.MyCommand.Path).BaseName + ".log"
  $Log = New-Object LogController($($LogFilePath + "\" + $LogFile), $false, $true, (Get-ChildItem $MyInvocation.MyCommand.Path).Name, $false)
  $Log.DeleteLog($SaveDays)
}

try {
  ##########################
  # Azure���O�I������
  ##########################
  $Connect = New-Object AzureLogonFunction($(Split-Path $MyInvocation.MyCommand.Path -Parent | Split-Path -Parent | Join-Path -ChildPath etc -Resolve), $CredenticialFile)
  $Connect.ConvertSecretKeytoSecureString($SecureCredenticialFile) 
  
  $Log.Info("���O�I���e�X�g�����{���܂��B")
  $Connect = New-Object AzureLogonFunction($(Split-Path $MyInvocation.MyCommand.Path -Parent | Split-Path -Parent | Join-Path -ChildPath etc -Resolve), $SecureCredenticialFile)
  if($Connect.Initialize($Log)) {
    if(-not $Connect.Logon()) {
      exit 9
    }
  } else {
    exit 9
  }
} catch {
    $Log.Error("���O�I���e�X�g���ɃG���[���������܂����B")
    $Log.Error($_.Exception)
    return $false
}
exit 0