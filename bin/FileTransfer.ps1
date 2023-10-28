<################################################################################
## Copyright(c) 2023 BeeX Inc. All rights reserved.
## @auther#Naruhiro Ikeya
##
## @name:FileTransfer.ps1
## @summary:File Transer(from TOKIUM to ERP) 
##
## @since:2023/10/27
## @version:1.0
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
  # ������擾
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
    $SFTP_Home = $ConfigInfo.Configuration.TargetPath
    if (-not $(Test-Path $SFTP_Home)) {
      New-Item ($SFTP_Home) -ItemType Directory 2>&1 > $null
    }
    Set-Location -Path $SFTP_Home

    $SFTP_Send_Dir = $(Join-Path(Split-Path $SFTP_Home -Parent) "send")
    if(-not (Test-Path $SFTP_Send_Dir)) {
      New-Item $SFTP_Send_Dir -ItemType Directory 2>&1 > $null
    }

    $SFTP_Back_Dir = $(Join-Path(Split-Path $SFTP_Home -Parent) "back")
    if(-not (Test-Path $SFTP_Back_Dir)) {
      New-Item $SFTP_Back_Dir -ItemType Directory 2>&1 > $null
    }

    $SFTP_Fail_Dir = $(Join-Path(Split-Path $SFTP_Home -Parent) "fail")
    if(-not (Test-Path $SFTP_Fail_Dir)) {
      New-Item $SFTP_Fail_Dir -ItemType Directory 2>&1 > $null
    }
    $SendDate = $((Get-Date).ToString("yyyyMMddHHmm"))
    
    foreach ($FileInfo in $ConfigInfo.Configuration.TargetFiles.File) {
      $Log.Info("$($FileInfo.Name)�F�t�@�C���]�������J�n")
      $TargetFile = Join-Path $SFTP_Home $FileInfo.Name
      if ($(Test-Path $TargetFile)) {
        $Log.Info("$($TargetFile)��$($SFTP_Send_Dir)�ֈړ����܂��B")
        Move-Item $TargetFile $SFTP_Send_Dir
        Write-VolumeCache $(Split-Path $TargetFile -Qualifier).Replace(':', '')
        $Log.Info("$($TargetFile)��$($SFTP_Send_Dir)�ֈړ����܂����B")
        Set-Location -Path $SFTP_Send_Dir
        $TargetFile = Join-Path $SFTP_Send_Dir $FileInfo.Name
        ##########################
        # FTP�]������
        ##########################
        if ($(Test-Path $TargetFile)) {
          $Log.Info("$($TargetFile)��FTP�T�[�o$($ConfigInfo.Configuration.TransferInfo.Host)�֓]�����܂��B")
          $Result = Test-NetConnection $ConfigInfo.Configuration.TransferInfo.Host -port 21 -InformationLevel Quiet
          if ($Result) {
            $Username = $ConfigInfo.Configuration.TransferInfo.User
            $Password = $ConfigInfo.Configuration.TransferInfo.Pass
            $RemoteURI = "ftp://$($ConfigInfo.Configuration.TransferInfo.Host)/$($ConfigInfo.Configuration.TransferInfo.Path)/$($FileInfo.Name)"
 
            $Uri = New-Object System.Uri($RemoteURI)
            $FileBytes = [System.IO.File]::ReadAllBytes($TargetFile)

            $FtpRequest = [System.Net.FtpWebRequest]([System.net.WebRequest]::Create($Uri))
            $FtpRequest.Method = [System.Net.WebRequestMethods+Ftp]::UploadFile
            $FtpRequest.Credentials = New-Object System.Net.NetworkCredential($Username, $Password)
            $FtpRequest.UsePassive = $true
            $FtpRequest.ContentLength = $FileBytes.Length;

            $Log.Info("FTP�T�[�o�֐ڑ����܂��B")
            $Log.Info("���[�U�[���F$Username")
            try {
              $RequestStream = $FtpRequest.GetRequestStream()
            } catch {
              $Log.Error("�T�[�o�ڑ����ɃG���[���������܂����B")
              $ErrorFlg = $True
              continue
            }
            $Log.Info("�t�@�C���]�����J�n���܂��B")

            try {
              $RequestStream.Write($FileBytes, 0, $FileBytes.Length)
            } catch {
              $Log.Error("�t�@�C���]�����ɃG���[���������܂����B")
            } finally {
              $RequestStream.Dispose()
            }

            try {
              $FTPResponse = [System.Net.FtpWebResponse]($FtpRequest.GetResponse())
              $Log.Info("$($Uri.AbsoluteUri)�փA�b�v���[�h���܂����B")
              $Log.Info("Status�F$($FTPResponse.StatusDescription)")
              if ((250 -eq $FTPResponse.StatusCode) -or (226 -eq $FTPResponse.StatusCode)) {
                ##########################
                # ���폈��
                ##########################
                $SFTP_Back_Date = Join-Path $SFTP_Back_Dir $SendDate
                if(-not (Test-Path $SFTP_Back_Date)) { New-Item $SFTP_Back_Date -ItemType Directory 2>&1 > $null }
                $Log.Info("$($TargetFile)��$($SFTP_Back_Date)�ֈړ����܂��B")
                Move-Item $TargetFile $SFTP_Back_Date
                Write-VolumeCache $(Split-Path $SFTP_Back_Date -Qualifier).Replace(':', '')
                $Log.Info("$($TargetFile)��$($SFTP_Back_Date)�ֈړ����܂����B")
                ###############################
                # ���폈��(�t���O�t�@�C���쐬)
                ###############################
                $TriggerFile = $FileInfo.Name + "." +$ConfigInfo.Configuration.TransferInfo.Ext
                $TriggerPath = Join-Path $SFTP_Send_Dir $TriggerFile
                New-Item -ItemType file $TriggerFile -Force 2>&1 > $null
                ###############################
                # ���폈��(�t���O�t�@�C���]��)
                ###############################
                $RemoteURI = "ftp://$($ConfigInfo.Configuration.TransferInfo.Host)/"
                $ServerPath = "/$($ConfigInfo.Configuration.TransferInfo.Path)/$TriggerFile"
                $webClient = New-Object System.Net.WebClient;
                $webClient.Credentials = New-Object System.Net.NetworkCredential($Username, $Password)
                $webClient.BaseAddress = $RemoteURI
                $webClient.UploadFile($ServerPath, $TriggerPath);
                $webClient.Dispose(); 
                Remove-Item $TriggerFile -Force
              } else {
                ##########################
                # �ُ폈��
                ##########################
                $SFTP_Fail_Date = Join-Path $SFTP_Fail_Dir $SendDate
                if(-not (Test-Path $SFTP_Back_Date)) { New-Item $SFTP_Fail_Date -ItemType Directory 2>&1 > $null }
                $Log.Error("$($TargetFile)��$($SFTP_Fail_Date)�ֈړ����܂��B")
                Move-Item $TargetFile $SFTP_Fail_Date
                Write-VolumeCache $(Split-Path $SFTP_Fail_Date -Qualifier).Replace(':', '')
                $Log.Error("$($TargetFile)��$($SFTP_Fail_Date)�ֈړ����܂����B")
              }
            } finally {
              if ($null -ne $FTPResponse) {
                $FTPResponse.Close()
              }
            }
          } else {
            $Log.Error("FTP�T�[�o$($ConfigInfo.Configuration.TransferInfo.Host)�ɐڑ��ł��܂���B")
            $ErrorFlg = $True
          }
        } else {
          $Log.Info("$($TargetFile) �����݂��܂���ł����B")
          continue
        }
      } else {
        $Log.Info("$($TargetFile) �����݂��܂���ł����B")
      }
      $Log.Info("�ߋ��t�@�C���̍폜�����{���܂��B")
      Get-ChildItem $SFTP_Back_Dir -Recurse | Where-Object {($_.Mode -eq "d-----") -and ($_.CreationTime -lt (Get-Date).AddDays(-1 * $FileInfo.LocalTerm))} | Remove-Item -Recurse -Force
      Get-ChildItem $SFTP_Fail_Dir -Recurse | Where-Object {($_.Mode -eq "d-----") -and ($_.CreationTime -lt (Get-Date).AddDays(-1 * $FileInfo.LocalTerm))} | Remove-Item -Recurse -Force
      $Log.Info("$($FileInfo.Name)�F�t�@�C���]����������")
    }
  } else { exit 9 }

  if($ErrorFlg) { exit 9 }
  else { exit 0 }

} catch {
  $Log.Error("�������ɃG���[���������܂����B")
  $Log.Error($("" + $Error[0] | Format-List --DisplayError))
  exit 9 
} finally {
}
