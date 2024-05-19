<################################################################################
## Copyright(c) 2020 BeeX Inc. All rights reserved.
## @auther#Naruhiro Ikeya
##
## @name:AzureVMBootController.ps1
## @summary:Azure VM Boot / Shutdown Controller
##
## @since:2019/06/24
## @version:1.0
## @see:
## @parameter
##  1:ResourceGroup��
##  2:AzureVM��
##  3:�N���������[�h
##  4:��~�������[�h
##  5:�W���o��
##
## @return:0:Success 1:�p�����[�^�G���[ 2:Az command���s�G���[ 9:Exception
################################################################################>

##########################
# �p�����[�^�ݒ�
##########################
param (
  [parameter(mandatory=$true)][string]$ResourceGroupName,
  [parameter(mandatory=$true)][string]$AzureVMName,
  [switch]$Boot,
  [switch]$Shutdown,
  [switch]$Eventlog=$false,
  [switch]$Stdout=$false
)

##########################
# ���W���[���̃��[�h
##########################
. .\LogController.ps1
. .\AzureLogonFunction.ps1

##########################
# �Œ�l 
##########################
[string]$CredenticialFile = "AzureCredential_Secure.xml"
[int]$SaveDays = 7

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
  $LogFileName = $LogBaseName + "_" + $AzureVMName + ".log"
  $Log = New-Object LogController($($LogFilePath + "\" + $LogFileName), $false, $true, $LogBaseName, $false)
  $Log.DeleteLog($SaveDays)
  $Log.Info("���O�t�@�C����:$($Log.GetLogInfo())")
}

##########################
# �p�����[�^�`�F�b�N
##########################
if(-not ($Boot -xor $Shutdown)) {
  $Log.Error("-Boot / -Shutdown ���ꂩ�̃I�v�V������ݒ肵�Ă��������B")
  exit 9
}

try {
  ##########################
  # Azure���O�I������
  ##########################
  $CredenticialFilePath = Split-Path $MyInvocation.MyCommand.Path -Parent | Split-Path -Parent | Join-Path -ChildPath etc -Resolve
  $CredenticialFileFullPath = $CredenticialFilePath + "\" + $CredenticialFile 
  $Connect = New-Object AzureLogonFunction($CredenticialFileFullPath)
  if($Connect.Initialize($Log)) {
    if(-not $Connect.Logon()) {
      exit 9
    }
  } else {
    exit 9
  }

  ############################
  # ResourceGroup���̃`�F�b�N
  ############################
  $ResourceGroup = Get-AzResourceGroup | Where-Object{$_.ResourceGroupName -eq $ResourceGroupName}
  if(-not $ResourceGroup) {
    $Log.Error("ResourceGroup�����s���ł��B" + $ResourceGroupName)
    exit 9
  }

  ############################
  # AzureVM���̃`�F�b�N
  ############################
  $AzureVM = Get-AzVM -ResourceGroupName $ResourceGroupName | Where-Object{$_.Name -eq $AzureVMName}
  if(-not $AzureVM) { 
    $Log.Error("AzureVM�����s���ł��B" + $AzureVMName)
    exit 9
  }
 
  ##############################
  # AzureVM�̃X�e�[�^�X�`�F�b�N
  ##############################
  $Log.Info("$AzureVMName �̃X�e�[�^�X���擾���܂��B")
  $AzureVMStatus = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $AzureVMName -Status | Select-Object @{n="Status"; e={$_.Statuses[1].Code}}
  if(-not $AzureVMStatus) { 
    $Log.Error("AzureVM�̃X�e�[�^�X���擾�ł��܂���ł����B")
    exit 9
  } else {
    $Log.Info("���݂̃X�e�[�^�X�� [" + $AzureVMStatus.Status + "] �ł��B")
  }

  if($Boot) {
    ##############################
    # AzureVM�̋N��
    ##############################
    if(($AzureVMStatus.Status -eq "PowerState/deallocated") -or ($AzureVMStatus.Status -eq "PowerState/stopped")) { 
      $Log.Info("AzureVM���N�����܂��B")
      $JobResult = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $AzureVMName | ForEach-Object { Start-AzVM -ResourceGroupName $_.ResourceGroupName -Name $_.Name }
      if($JobResult.Status -eq "Failed") {
        $Log.Error("AzureVM�N���W���u���G���[�I�����܂����B")
        $Log.Error($($JobResult | Format-List | Out-String -Stream))
        exit 9
      } else {
        $Log.Info("AzureVM�N���W���u���������܂����B")
        exit 0
      }
    } else {
      $Log.Info("AzureVM�N���������L�����Z�����܂��B���݂̃X�e�[�^�X�� [" + $AzureVMStatus.Status + "] �ł��B")
      exit 0
    }
  } elseif($Shutdown) {
    ##############################
    # AzureVM�̒�~
    ##############################
    if($AzureVMStatus.Status -eq "PowerState/running") { 
      $Log.Info("AzureVM���~���܂��B")
      $JobResult = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $AzureVMName | ForEach-Object { Stop-AzVM -ResourceGroupName $_.ResourceGroupName -Name $_.Name -Force }
      if($JobResult.Status -eq "Failed") {
        $Log.Error("AzureVM��~�W���u���G���[�I�����܂����B")
        $Log.Error($($JobResult | Format-List | Out-String -Stream))
        exit 9
      } else {
        $Log.Info("AzureVM��~�W���u���������܂����B")
        exit 0
      }
    } else {
      $Log.Info("AzureVM��~�������L�����Z�����܂��B���݂̃X�e�[�^�X�� [" + $AzureVMStatus.Status + "] �ł��B")
      exit 0
    }
  } else {
    $Log.Error("-Boot / -Shutdown ���ꂩ�̃I�v�V������ݒ肵�Ă��������B")
    exit 9
  }
  #################################################
  # �G���[�n���h�����O
  #################################################
} catch {
    $Log.Error("AzureVM�̋N��/��~�������ɃG���[���������܂����B")
    $Log.Error($_.Exception)
    exit 9
}
exit 0