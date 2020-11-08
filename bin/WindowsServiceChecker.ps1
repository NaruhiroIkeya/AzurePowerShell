<################################################################################
## Copyright(c) 2020 BeeX Inc. All rights reserved.
## @auther#Naruhiro Ikeya
##
## @name:WindowsServiceChecker.ps1
## @summary:Windows Service Running Check
##
## @since:2020/11/08
## @version:1.0
## @see:
## @parameter
##  1:�T�[�r�X��
##
## @return:0:Success 9:�G���[�I��
################################################################################>

##########################
# �p�����[�^�ݒ�
##########################
param (
  [string]$ServiceName=$null,
  [string]$HostName=$null,
  [switch]$Eventlog,
  [switch]$Stdout
)

##########################
# ���W���[���̃��[�h
##########################
. .\LogController.ps1
. .\ServiceController.ps1

##########################
# �Œ�l 
##########################
$Stdout = $true
$Eventlog = $true

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
if (-not $ServiceName) {
  $Log.Error("Syntax Error:���s���� -ServiceName ���w�肵�Ă��������B")
  exit 9
}
  
try {
  ##########################
  # ServiceController�I�u�W�F�N�g����
  ##########################
  [object]$Service = $null

  $Service = New-Object ServiceController($ServiceName)
  if($Service.Initialize($Log)) {    
    if($Service.GetStatus() -ne "Running") {
      $Log.Error($ServiceName + "�T�[�r�X���N�����Ă��܂���B")
    }
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