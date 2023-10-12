## Copyright(c) 2020 BeeX Inc. All rights reserved.
## @auther#Naruhiro Ikeya
##
## @name:StartInstance.ps1
## @summary:SAP�V�X�e���N��
##
## @since:2023/08/01
## @version:1.1
## @see:
## @parameter
##  1:Azure Login�F�؃t�@�C���p�X
##
## @return:0:Success 1:Error
#################################################################################>

##########################
## �p�����[�^�ݒ�
##########################
param (
  [parameter(mandatory=$true)][string]$ConfigFile,
  [switch]$Eventlog=$false,
  [switch]$Stdout=$false
)

##########################
## ���W���[���̃��[�h
##########################
. .\LogController.ps1
. .\ServiceController.ps1

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
  
  try {
    ##########################
    # ����擾
    ##########################
    if (($ConfigFile) -and (-not $(Test-Path $ConfigFile))) {
      $Log.Error("����t�@�C�������݂��܂���B")
      exit 9 
    } else {
      $Log.Info("����t�@�C���p�X�F" + (Split-Path $ConfigFile -Parent))
      $Log.Info("����t�@�C�����F" + (Get-ChildItem $ConfigFile).Name)
      if ($(Test-Path $ConfigFile)) { $ConfigInfo = [xml](Get-Content $ConfigFile) }
      if(-not $ConfigInfo) { 
        $Log.Error("����̃t�@�C�����琧���񂪓ǂݍ��߂܂���ł����B")
        exit 9 
      } 
    }

    if ($ConfigInfo) {
      $Hostname = $ConfigInfo.Configuration.Services.Host.Name
      foreach($Service in $ConfigInfo.Configuration.Services.Host.service) {
        $Log.Info("$Hostname $($Service.name) Start. `r`n")
        $rc = (ServiceControl $Hostname $Service.name "START")
        if ($rc -ne 0) {
          $Log.Info("$Hostname $($Service.name) Start Error. `r`n")
          Exit 1
        }
        Start-Sleep $Service.delay
      }
    }
    $Log.Info("���ׂẴT�[�r�X���N�����܂����B`r`n")

$nowfmt = Get-Date -Format "yyyy/MM/dd HH:mm:ss.ff"
Write-Host "[$nowfmt] SAP �C���X�^���X���N�����܂��B`r`n"
foreach($Instance in $SAPConfig.Configuration.SAP.SID) {
    foreach($saphost in $Instance.host) {
        $nowfmt = Get-Date -Format "yyyy/MM/dd HH:mm:ss.ff"
        Write-Host "[$nowfmt]" $Instance.name $saphost.name $saphost.nr "�C���X�^���X���N�����܂��B`r`n"
        $sapctrlparam = "-prot PIPE -host " + $saphost.name + " -nr " + $saphost.nr + " -function StartWait " + $saphost.timeout + " " + $saphost.delay
        $result = Start-Process -FilePath "sapcontrol.exe" -ArgumentList $sapctrlparam -PassThru -Wait
        if ($result.ExitCode -ne 0) {
            Write-Host $Hostname $Instance.name "���N���ł��܂���ł����B`r`n"
            exit 1
        }
    }
    Start-Sleep 5
}
$nowfmt = Get-Date -Format "yyyy/MM/dd HH:mm:ss.ff"
Write-Host "[$nowfmt] ���ׂẴC���X�^���X���N�����܂����B`r`n"

Exit 0
