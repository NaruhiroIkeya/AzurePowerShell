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

  $Log.Info("�Ώۃt�H���_:$($Path)")
  $Log.Info("�t�@�C�����[�e�[�V�����J�n:$($Term)���ȑO�̃t�@�C�����폜���܂��B")
  $ReturnObj = Invoke-Command "forfiles" $env:comspec "/C FORFILES /P `"$Path`" /M *.$FileExt /S /D -$Term /C `"CMD /C IF @isdir==FALSE ECHO @file`""
  if (-not $ReturnObj.ExitCode) {
    $Log.Info("�폜�Ώۃt�@�C��`r`n$($ReturnObj.StdOut)")
    $ReturnObj = Invoke-Command "forfiles" $env:comspec "/C FORFILES /P `"$Path`" /M *.$FileExt /S /D -$Term /C `"CMD /C IF @isdir==FALSE DEL /Q @path`""
    if (-not $ReturnObj.ExitCode) {
      $Log.Info("�t�@�C���폜`r`n$($ReturnObj.StdOut)")
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

##########################
# �֐���`
##########################
# ��t�H���_�̍폜
Function Remove-EmptyFolders($Path) {

  $Log.Info("��t�H���_�̍폜")
  $ReturnObj = Invoke-Command "for" $env:comspec "/C FOR /f `"delims=`" %d in ('dir `"$Path`" /ad /b /s ^| sort /r') do @ECHO `"%d`""
  if (-not $ReturnObj.ExitCode) {
    $Log.Info("�폜�Ώۃt�H���_`r`n$($ReturnObj.StdOut)")
    $ReturnObj = Invoke-Command "for" $env:comspec "/C FOR /f `"delims=`" %d in ('dir `"$Path`" /ad /b /s ^| sort /r') do @RD `"%d`" /q 2>nul"
    if (-not $ReturnObj.ExitCode) {
      $Log.Info("��t�H���_���폜���܂����B")
    } else {
      $Log.Info("��t�H���_������܂���ł����B")
      return 0
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
    foreach ($TargetConfig in $ConfigInfo.Configuration.Target) {
      $Log.Info("$($TargetConfig.Title):�J�n")
      $Log.Info("$($TargetConfig.RemoteHost)�ɐڑ����܂�")
      $ConResult = Test-NetConnection -ComputerName $TargetConfig.RemoteHost -Port 445
      if (-not ($ConResult.TcpTestSucceeded)) {
        $Log.Error("���L�f�B�X�N�ɐڑ��ł��܂���ł����B")
        $ErrorFlg = $true
        break
      }

      switch($TargetConfig.Mode) {
        "Mirror" {
          if ($ConResult.TcpTestSucceeded) {
            ##########################
            # �ޔ������J�n
            ##########################
            # �ċN�����Ƀh���C�u���ێ������悤�ɁA�p�X���[�h��ۑ�����
            cmd.exe /C "cmdkey /add:`"$($TargetConfig.RemoteHost)`" /user:`"$($TargetConfig.RemoteUser)`" /pass:`"$($TargetConfig.RemotePass)`""

            # ���L�t�H���_���h���C�u���}�E���g����
            $Log.Info("\\$($TargetConfig.RemoteHost)\$($TargetConfig.RemotePath)��$($TargetConfig.RemoteDrive)�h���C�u�Ƀ}�E���g���܂�")
            New-PSDrive -Name $TargetConfig.RemoteDrive -PSProvider FileSystem -Root "\\$($TargetConfig.RemoteHost)\$($TargetConfig.RemotePath)" -Persist

            ##########################
            # ���[�J���t�@�C���ꗗ
           ##########################
            $SourcePath = "$($TargetConfig.LocalPath)"
            Get-FileList $SourcePath "*.$($TargetConfig.FileExt)"

            ##########################
            # �����[�g�t�@�C���ꗗ
            ##########################
            $TargetPath = "$($TargetConfig.RemoteDrive):"
            Get-FileList $TargetPath "*.$($TargetConfig.FileExt)"

            ##########################
            # �t�@�C���R�s�[
            ##########################
            $Log.Info("�R�s�[���t�H���_:$SourcePath")
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
            Get-FileList $SourcePath "*.$($TargetConfig.FileExt)"

            ##########################
            # �����[�g�t�@�C���ꗗ
            ##########################
            Get-FileList $TargetPath "*.$($TargetConfig.FileExt)"

            # ���L�t�H���_�̃A���}�E���g
            Get-PSDrive $TargetConfig.RemoteDrive | Remove-PSDrive
          }
        }

        "DateDirectory" {
          ##########################
          # �ޔ������J�n
          ##########################
          if ($ConResult.TcpTestSucceeded) {
            # �ċN�����Ƀh���C�u���ێ������悤�ɁA�p�X���[�h��ۑ�����
            cmd.exe /C "cmdkey /add:`"$($TargetConfig.RemoteHost)`" /user:`"$($TargetConfig.RemoteUser)`" /pass:`"$($TargetConfig.RemotePass)`""

            # ���L�t�H���_���h���C�u���}�E���g����
            $Log.Info("\\$($TargetConfig.RemoteHost)\$($TargetConfig.RemotePath)��$($TargetConfig.RemoteDrive)�h���C�u�Ƀ}�E���g���܂�")
            New-PSDrive -Name $TargetConfig.RemoteDrive -PSProvider FileSystem -Root "\\$($TargetConfig.RemoteHost)\$($TargetConfig.RemotePath)" -Persist

            ##########################
            # ���[�J���t�@�C���ꗗ
            ##########################
            $SourcePath = "$($TargetConfig.LocalPath)"
            Get-FileList $SourcePath "*.$($TargetConfig.FileExt)"

            ##########################
            # �����[�g�t�@�C���ꗗ
            ##########################
            $TargetPath = "$($TargetConfig.RemoteDrive):"
            Get-FileList $TargetPath "*.$($TargetConfig.FileExt)"

            ##########################
            # �t�@�C���R�s�[
            ##########################
            $Log.Info("�R�s�[���t�H���_:$SourcePath")
            $Log.Info("�R�s�[��t�H���_:$(Join-Path $TargetPath (Get-Date).ToString("yyyyMMdd"))")
            $CopyLog = $(Split-Path $MyInvocation.MyCommand.Path -Parent | Split-Path -Parent | Join-Path -ChildPath log -Resolve) + "\" + (Get-ChildItem $MyInvocation.MyCommand.Path).BaseName + "_Robocopy_" + $(Get-Date -Format "yyyyMMddHHmmss") + ".log"
            $ReturnObj = Invoke-Command "robocopy" $env:comspec "/C ROBOCOPY `"$SourcePath`" $(Join-Path $TargetPath (Get-Date).ToString("yyyyMMdd")) /MT:4 /J /R:2 /W:1 /MIR /IT /COPY:DAT /DCOPY:DAT /NP /FFT /COMPRESS /LOG:$CopyLog"
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
                Get-ChildItem $TargetPath -Recurse | Where-Object {($_.Mode -eq "d-----") -and ($_.Name -lt (Get-Date).AddDays(-1 * $ConfigInfo.Configuration.LocalTerm).ToString("yyyyMMdd"))} | Remove-Item -Recurse -Force
#                $RemoveDir = $(Join-Path $TargetPath (Get-Date).AddDays(-1 * $TargetConfig.RemoteTerm).ToString("yyyyMMdd"))
#                if (Test-Path $RemoveDir) {
#                  $Return = Remove-Item -Recurse $RemoveDir -Force
#                  $Log.Info("�f�B���N�g���폜:$($RemoveDir)����")
#                } else {
#                  $Log.Warn("�f�B���N�g���폜:$($RemoveDir)������܂���")
#                }
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
            Get-FileList $SourcePath "*.$($TargetConfig.FileExt)"

            ##########################
            # �����[�g�t�@�C���ꗗ
            ##########################
            Get-FileList $TargetPath "*.$($TargetConfig.FileExt)"

            # ���L�t�H���_�̃A���}�E���g
            Get-PSDrive $TargetConfig.RemoteDrive | Remove-PSDrive
          }
        }

        "TimestampDir" {
          ##########################
          # �ޔ������J�n
          ##########################
          if ($ConResult.TcpTestSucceeded) {
            # �ċN�����Ƀh���C�u���ێ������悤�ɁA�p�X���[�h��ۑ�����
            cmd.exe /C "cmdkey /add:`"$($TargetConfig.RemoteHost)`" /user:`"$($TargetConfig.RemoteUser)`" /pass:`"$($TargetConfig.RemotePass)`""

            # ���L�t�H���_���h���C�u���}�E���g����
            $Log.Info("\\$($TargetConfig.RemoteHost)\$($TargetConfig.RemotePath)��$($TargetConfig.RemoteDrive)�h���C�u�Ƀ}�E���g���܂�")
            New-PSDrive -Name $TargetConfig.RemoteDrive -PSProvider FileSystem -Root "\\$($TargetConfig.RemoteHost)\$($TargetConfig.RemotePath)" -Persist

            ##########################
            # ���[�J���t�@�C���ꗗ
            ##########################
            $SourcePath = "$($TargetConfig.LocalPath)"
            Get-FileList $SourcePath "*.$($TargetConfig.FileExt)"

            ##########################
            # �����[�g�t�@�C���ꗗ
            ##########################
            $TargetPath = "$($TargetConfig.RemoteDrive):"
            Get-FileList $TargetPath "*.$($TargetConfig.FileExt)"

            ##########################
            # �t�@�C���R�s�[
            ##########################
            $Log.Info("�R�s�[���t�H���_:$SourcePath")
            $TargetFiles = Get-ChildItem $SourcePath "*.$($TargetConfig.FileExt)"
            foreach($Target in $TargetFiles){
              $Log.Info("�R�s�[�Ώۃt�@�C��:$($Target.Name)")
              $Log.Info("�R�s�[��t�H���_:$(Join-Path $TargetPath $Target.CreationTime.ToString("yyyymmdd"))")
              $CopyLog = $(Split-Path $MyInvocation.MyCommand.Path -Parent | Split-Path -Parent | Join-Path -ChildPath log -Resolve) + "\" + (Get-ChildItem $MyInvocation.MyCommand.Path).BaseName + "_Robocopy_" + $(Get-Date -Format "yyyyMMdd") + ".log"
              $ReturnObj = Invoke-Command "robocopy" $env:comspec "/C ROBOCOPY `"$SourcePath`" $(Join-Path $TargetPath $Target.CreationTime.ToString("yyyyMMdd")) $($Target.Name) /MT:4 /J /R:2 /W:1 /COPY:DAT /DCOPY:DAT /NP /FFT /COMPRESS /LOG+:$CopyLog"
              switch($ReturnObj.ExitCode) {
                # �R�s�[�����t�@�C�����Ȃ�
                0 {
                  $Log.Info("�R�s�[�ς݂ł��B")
                  $Log.Info("�t�@�C���R�s�[����`r`n$($ReturnObj.StdOut)")
                  break
                }
                # �R�s�[�����t�@�C��������
                ({$_ -ge 1 -and $_ -le 8}) {
                  $Log.Info("�t�@�C���R�s�[����`r`n$($ReturnObj.StdOut)")
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
            }

            if(-not $ErrorFlg) {
              ##########################
              # �����[�g�t�@�C���폜
              ##########################
              $Log.Info("$($TargetConfig.RemoteTerm)���ȏ�O�̃t�@�C���폜:�J�n")
              $Return = Remove-ExpiredFiles $TargetPath $TargetConfig.FileExt $TargetConfig.RemoteTerm
              if (-not $Return) {
                $Log.Info("�t�@�C���폜:����")
              } else {
                $Log.Warn("�t�@�C���폜:�G���[�I��")
              }
              $Return = Remove-EmptyFolders $TargetPath

              ##########################
              # ���[�J���t�@�C���폜
              ##########################
              $Log.Info("$($TargetConfig.LocalTerm)���ȏ�O�̃t�@�C���폜:�J�n")
              $Return = Remove-ExpiredFiles $SourcePath $TargetConfig.FileExt $TargetConfig.LocalTerm
              if (-not $Return) {
                $Log.Info("�t�@�C���폜:����")
              } else {
                $Log.Warn("�t�@�C���폜:�G���[�I��")
              }
              break
            }
          }
          ##########################
          # ���[�J���t�@�C���ꗗ
          ##########################
          Get-FileList $SourcePath "*.$($TargetConfig.FileExt)"

          ##########################
          # �����[�g�t�@�C���ꗗ
          ##########################
          Get-FileList $TargetPath "*.$($TargetConfig.FileExt)"

          # ���L�t�H���_�̃A���}�E���g
          Get-PSDrive $TargetConfig.RemoteDrive | Remove-PSDrive
        }

        "RemoteCopy" {
          ##########################
          # �ޔ������J�n
          ##########################
          if ($ConResult.TcpTestSucceeded) {
            # �ċN�����Ƀh���C�u���ێ������悤�ɁA�p�X���[�h��ۑ�����
            cmd.exe /C "cmdkey /add:`"$($TargetConfig.RemoteHost)`" /user:`"$($TargetConfig.RemoteUser)`" /pass:`"$($TargetConfig.RemotePass)`""

            # ���L�t�H���_���h���C�u���}�E���g����
            $Log.Info("\\$($TargetConfig.RemoteHost)\$($TargetConfig.RemotePath)��$($TargetConfig.RemoteDrive)�h���C�u�Ƀ}�E���g���܂�")
            New-PSDrive -Name $TargetConfig.RemoteDrive -PSProvider FileSystem -Root "\\$($TargetConfig.RemoteHost)\$($TargetConfig.RemotePath)" -Persist

            ##########################
            # ���[�J���t�@�C���ꗗ
            ##########################
            $SourcePath = "$($TargetConfig.LocalPath)"
            Get-FileList $SourcePath "*.$($TargetConfig.FileExt)"

            ##########################
            # �����[�g�t�@�C���ꗗ
            ##########################
            $TargetPath = "$($TargetConfig.RemoteDrive):"
            Get-FileList $TargetPath "*.$($TargetConfig.FileExt)"

            ##########################
            # �t�@�C���R�s�[
            ##########################
            $Log.Info("�R�s�[���t�H���_:$SourcePath")
            $Log.Info("�R�s�[��t�H���_:$TargetPath")
            $ReturnObj = Invoke-Command "robocopy" $env:comspec "/C ROBOCOPY `"$SourcePath`" $TargetPath *.$($TargetConfig.FileExt) /DCOPY:DAT /NP /MT:8"
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
                $Return = Remove-ExpiredFiles $TargetPath $TargetConfig.FileExt $TargetConfig.RemoteTerm
                if (-not $Return) {
                  $Log.Info("�t�@�C���폜:����")
                } else {
                  $Log.Warn("�t�@�C���폜:�G���[�I��")
                }

                ##########################
                # ���[�J���t�@�C���폜
                ##########################
                $Log.Info("�t�@�C���폜:�J�n")
                $Return = Remove-ExpiredFiles $SourcePath $TargetConfig.FileExt $TargetConfig.LocalTerm
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
            Get-FileList $SourcePath "*.$($TargetConfig.FileExt)"

            ##########################
            # �����[�g�t�@�C���ꗗ
            ##########################
            Get-FileList $TargetPath "*.$($TargetConfig.FileExt)"

            # ���L�t�H���_�̃A���}�E���g
            Get-PSDrive $TargetConfig.RemoteDrive | Remove-PSDrive
          }
        }

        default {
          $Log.Error("���[�h`($($TargetConfig.Mode)`)�̎w�肪����Ă܂��B")
          break
        }
      }
      $Log.Info("$($TargetConfig.Title):����")
    }
  } else { exit 9 }

  if($ErrorFlg) { exit 9 }
  else { exit 0 }

} catch {
  $Log.Error("�������ɃG���[���������܂����B")
  $Log.Error($("" + $Error[0] | Format-List --DisplayError))
  Get-PSDrive $TargetConfig.RemoteDrive | Remove-PSDrive
  exit 9 
}
