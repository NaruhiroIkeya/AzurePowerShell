<################################################################################
## Copyright(c) 2020 BeeX Inc. All rights reserved.
## @auther#Naruhiro Ikeya
##
## @name:AzureLogonFunction.ps1
## @summary:Azure Logon 
##
## @since:2020/05/01
## @version:1.1
## @see:
## @parameter
##  1:Azure Login�F�؃t�@�C���p�X
##
## @return:0:Success 1:�p�����[�^�G���[  9:Exception
################################################################################>

##########################
# �p�����[�^�ݒ�
##########################
param (
  [parameter(mandatory=$true)][string]$ConfigFile,
  [switch]$Eventlog=$false,
  [switch]$Stdout=$false
)

##########################
# ���W���[���̃��[�h
##########################
. .\LogController.ps1

##########################
# �Œ�l 
##########################
[bool]$ErrorFlg = $false

##########################
# �x���̕\���}�~
##########################
# Set-Item Env:\SuppressAzurePowerShellBreakingChangeWarnings "true"

##########################
# �֐���`
##########################
# �O���R�}���h���s
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
# �֐���`
##########################
# �t�@�C���ꗗ�擾
Function Get-FileList($FilePath, $Files) {

  $FullPath = "$FilePath\$Files"
  $ReturnObj = Invoke-Command "dir" $env:comspec "/C DIR /B `"$FullPath`""
  if (-not $ReturnObj.ExitCode) {
    $Log.Info("$($FullPath)`r`n$($ReturnObj.StdOut)")
  } else {
    $Log.Error("$($FullPath)`r`n$($ReturnObj.StdErr)")
  }
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
      switch($Target.Mode) {
        "RemoteCopy" {
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

            ##########################
            # ���[�J���t�@�C���ꗗ
            ##########################
            $SourcePath = "$($Target.LocalPath)"
            Get-FileList $SourcePath "*.$($Target.FileExt)"

            ##########################
            # �����[�g�t�@�C���ꗗ
            ##########################
            $TargetPath = "$($Target.RemoteDrive):"
            Get-FileList $TargetPath "*.$($Target.FileExt)"

            ##########################
            # �t�@�C���R�s�[
            ##########################

            $Log.Info("�R�s�[���t�@�C��:$SourcePath")
            $Log.Info("�R�s�[��t�H���_:$TargetPath")
            $ReturnObj = Invoke-Command "robocopy" $env:comspec "/C ROBOCOPY `"$SourcePath`" $TargetPath *.$($Target.FileExt) /DCOPY:DAT /NP /MT:8"
            switch($ReturnObj.ExitCode) {
              # �R�s�[�����t�@�C�����Ȃ�
              0 {
                $Log.Info("�R�s�[�Ώۂ̃t�@�C��������܂���ł����B")
                $Log.Info("�t�@�C���R�s�[����`r`n$($ReturnObj.StdOut)")
                break
              }
              # �R�s�[�����t�@�C��������
              ({$_ -ge 1 -and $_ -le 8}) {
                $Log.Info("�t�@�C���R�s�[����`r`n$($ReturnObj.StdOut)")

                ##########################
                # �����[�g�t�@�C���폜
                ##########################
                $Log.Info("�����[�g�t�@�C�����[�e�[�V�����J�n:$($Target.RemoteTerm)���ȑO�̃t�@�C�����폜���܂��B")
                $ReturnObj = Invoke-Command "forfiles" $env:comspec "/C FORFILES /P $TargetPath /M *.$($Target.FileExt) /D -$($Target.RemoteTerm) /C `"CMD /C IF @isdir==FALSE DEL /Q @path`""
                if (-not $ReturnObj.ExitCode) {
                  $Log.Info("�����[�g�t�@�C���폜`r`n$($ReturnObj.StdOut)")
                } else {
                  $Log.Warn("$($ReturnObj.StdErr)")
                }

                ##########################
                # ���[�J���t�@�C���폜
                ##########################
                $Log.Info("���[�J���t�@�C�����[�e�[�V�����J�n:$($Target.LocalTerm)���ȑO�̃t�@�C�����폜���܂��B")
                $ReturnObj = Invoke-Command "forfiles" $env:comspec "/C FORFILES /P $SourcePath /M *.$($Target.FileExt) /D -$($Target.LocalTerm) /C `"CMD /C IF @isdir==FALSE DEL /Q @path`""
                if (-not $ReturnObj.ExitCode) {
                  $Log.Info("���[�J���t�@�C���폜`r`n$($ReturnObj.StdOut)")
                } else {
                  $Log.Warn("$($ReturnObj.StdErr)")
                }
                break
              }
              # �G���[�𔺂��R�s�[�����t�@�C��������B
              ({$_ -gt 8}) {
                $Log.Info("�G���[���������܂����B")
                $Log.Info("�t�@�C���R�s�[����`r`n$($ReturnObj.StdOut)")
                $ErrorFlg = $true
                break
              }
              default {
                $Log.Info("Other")
              }
            }

            ##########################
            # ���[�J���t�@�C���ꗗ
            ##########################
            Get-FileList $SourcePath "*.$($Target.FileExt)"

            ##########################
            # �����[�g�t�@�C���ꗗ
            ##########################
            Get-FileList $TargetPath "*.$($Target.FileExt)"

            # ���L�t�H���_�̃A���}�E���g
            Get-PSDrive $Target.RemoteDrive | Remove-PSDrive
          } else {
            $Log.Error("���L�f�B�X�N�ɐڑ��ł��܂���ł����B")
            break
          }
        }
        default {
          $Log.Error("���[�h`($($Target.Mode)`)�̎w�肪����Ă܂��B")
          break
        }
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
