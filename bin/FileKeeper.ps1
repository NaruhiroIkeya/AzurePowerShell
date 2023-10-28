<################################################################################
## Copyright(c) 2023 BeeX Inc. All rights reserved.
## @auther#Naruhiro Ikeya
##
## @name:FileKeeper.ps1
## @summary:External Storage File Management 
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
$ErrorActionPreference = "Stop"

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
      $Log.Info("$($Target.RemoteHost)�ɐڑ����܂�")
      $connectTestResult = Test-NetConnection -ComputerName $Target.RemoteHost -Port 445
      if (-not ($connectTestResult.TcpTestSucceeded)) {
        $Log.Error("���L�f�B�X�N�ɐڑ��ł��܂���ł����B")
        $ErrorFlg = $true
        break
      }

      switch($Target.Mode) {
        "Mirror" {
          ##########################
          # �ޔ������J�n
          ##########################
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
          $ReturnObj = Invoke-Command "robocopy" $env:comspec "/C ROBOCOPY `"$SourcePath`" $TargetPath /MIR /DCOPY:DAT /NP /MT:8"
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
        }

        "DateDirectory" {
          ##########################
          # �ޔ������J�n
          ##########################
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
            $Log.Info("�R�s�[��t�H���_:$(Join-Path $TargetPath (Get-Date).ToString("yyyyMMdd"))")
            $ReturnObj = Invoke-Command "robocopy" $env:comspec "/C ROBOCOPY `"$SourcePath`" $(Join-Path $TargetPath (Get-Date).ToString("yyyyMMdd")) /MIR /DCOPY:DAT /NP /MT:8"
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
                # �����[�g�f�B���N�g���폜
                ##########################
                $Log.Info("�f�B���N�g���폜:�J�n")
                $RemoveDir = $(Join-Path $TargetPath (Get-Date).AddDays(-1 * $Target.RemoteTerm).ToString("yyyyMMdd"))
                if (Test-Path $RemoveDir) {
                  $Return = Remove-Item -Recurse $RemoveDir -Force
                  $Log.Info("�f�B���N�g���폜:$($RemoveDir)����")
                } else {
                  $Log.Warn("�f�B���N�g���폜:$($RemoveDir)������܂���")
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
          }
        }

        "RemoteCopy" {
          ##########################
          # �ޔ������J�n
          ##########################
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
                $Log.Info("�t�@�C���폜:�J�n")
                $Return = Remove-ExpiredFiles $TargetPath $Target.FileExt $Target.RemoteTerm
                if (-not $Return) {
                  $Log.Info("�t�@�C���폜:����")
                } else {
                  $Log.Warn("�t�@�C���폜:�G���[�I��")
                }

                ##########################
                # ���[�J���t�@�C���폜
                ##########################
                $Log.Info("�t�@�C���폜:�J�n")
                $Return = Remove-ExpiredFiles $SourcePath $Target.FileExt $Target.LocalTerm
                if (-not $Return) {
                  $Log.Info("�t�@�C���폜:����")
                } else {
                  $Log.Warn("�t�@�C���폜:�G���[�I��")
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
