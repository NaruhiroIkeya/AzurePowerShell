<################################################################################
## Copyright(c) 2023 BeeX Inc. All rights reserved.
## @auther#Naruhiro Ikeya
##
## @name:NetworkDriveMountOnly.ps1
## @summary:Network Drive Mount
##
## @since:2023/10/10
## @version:1.1
## @see:
## @parameter
##  1:��`�t�@�C��
##  2:�C�x���g���O��������
##  3:�W���o��
##
## @return:0:Success 1:�p�����[�^�G���[  9:Exception
################################################################################>

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

##########################
## �Œ�l 
##########################
[bool]$ErrorFlg = $false

##########################
## �x���̕\���}�~
##########################
## Set-Item Env:\SuppressAzurePowerShellBreakingChangeWarnings "true"

##########################
## �֐���`
##########################
## �O���R�}���h���s
Function Invoke-Command($commandTitle, $commandPath, $commandArguments) {
  Try {
    $PSInfo = New-Object System.Diagnostics.ProcessStartInfo
    $PSInfo.FileName = $commandPath
    $PSInfo.RedirectStandardError = $true
    $PSInfo.RedirectStandardOutput = $true
    $PSInfo.UseShellExecute = $false
    $PSInfo.Arguments = $commandArguments
    $Proc = New-Object System.Diagnostics.Process
    $Proc.StartInfo = $PSInfo
    $Proc.Start() | Out-Null
    $Proc.WaitForExit()
    [pscustomobject]@{
        CommandTitle = $commandTitle
        StdOut = $Proc.StandardOutput.ReadToEnd()
        StdErr = $Proc.StandardError.ReadToEnd()
        ExitCode = $Proc.ExitCode
    }
  }
  Catch {
     Exit 9
  }
}

##########################
## �֐���`
##########################
## �t�@�C���ꗗ�擾
Function Get-FileList($Path, $Files) {

  $FullPath = "$Path\$Files"
  $ReturnObj = Invoke-Command "dir" $env:comspec "/C DIR /B `"$FullPath`""
  if (-not $ReturnObj.ExitCode) {
    $Log.Info("$($FullPath)`r`n$($ReturnObj.StdOut)")
  } else {
    $Log.Error("$($FullPath)`r`n$($ReturnObj.StdErr)")
  }
}

##########################
# �֐���`
##########################
# �����؂�t�@�C���̍폜
Function Remove-ExpiredFiles($Path, $FileExt, $Term) {

  $Log.Info("�t�@�C�����[�e�[�V�����J�n:")
  $Log.Info("�t�@�C�����[�e�[�V�����J�n:$($Term)���ȑO�̃t�@�C�����폜���܂��B")
  $Log.Info("�Ώۃt�H���_:$($Path)")
  $ReturnObj = Invoke-Command "forfiles" $env:comspec "/C FORFILES /P `"$Path`" /M *.$FileExt /D -$Term /C `"CMD /C IF @isdir==FALSE ECHO @path 2>nul`""
  if (-not $ReturnObj.ExitCode) {
    $Log.Info("�폜�Ώۃt�@�C��`r`n$($ReturnObj.StdOut)")
    $ReturnObj = Invoke-Command "forfiles" $env:comspec "/C FORFILES /P `"$Path`" /M *.$FileExt /D -$Term /C `"CMD /C IF @isdir==FALSE DEL /Q @path`""
    if (-not $ReturnObj.ExitCode) {
      $Log.Info("���[�J���t�@�C���폜`r`n$($ReturnObj.StdOut)")
    } else {
      $Log.Warn("$($ReturnObj.StdErr)")
      return 9
    }
  } else {
    $Log.Warn("$($ReturnObj.StdErr)")
    return 9
  }
  return 0
}

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
    foreach ($Target in $ConfigInfo.Configuration.Target) {
      $Log.Info("$($Target.Title):�J�n")
      ##########################
      # �ޔ������J�n
      ##########################
      $Log.Info("$($Target.RemoteHost)�ɐڑ����܂�")
      $connectTestResult = Test-NetConnection -ComputerName $Target.RemoteHost -Port 445
      if ($connectTestResult.TcpTestSucceeded) {
        # �ċN�����Ƀh���C�u���ێ������悤�ɁA�p�X���[�h��ۑ�����
        cmd.exe /C "cmdkey /add:`"$($Target.RemoteHost)`" /user:`"$($Target.RemoteUser)`" /pass:`"$($Target.RemotePass)`""
        # ���L�t�H���_���h���C�u���}�E���g����
        $Log.Info("\\$($Target.RemoteHost)\$($Target.RemotePath)��$($Target.RemoteDrive)�h���C�u�Ƀ}�E���g���܂�")
        New-PSDrive -Name $Target.RemoteDrive -PSProvider FileSystem -Root "\\$($Target.RemoteHost)\$($Target.RemotePath)" -Persist
        pause
      }
      $Log.Info("$($Target.Title):����")
    }
  } else { exit 9 }

  if($ErrorFlg) { exit 9 }
  else { exit 0 }
} catch {
  $Log.Error("�������ɃG���[���������܂����B")
  $Log.Error($("" + $Error[0] | Format-List --DisplayError))
  Get-PSDrive $Target.RemoteDrive | Remove-PSDrive
  exit 9 
}
