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
##  1:定義ファイル
##  2:イベントログ書き込み
##  3:標準出力
##
## @return:0:Success 1:パラメータエラー  9:Exception
################################################################################>

##########################
## パラメータ設定
##########################
param (
  [parameter(mandatory=$true)][string]$ConfigFile,
  [switch]$Eventlog=$false,
  [switch]$Stdout=$false
)

##########################
## モジュールのロード
##########################
. .\LogController.ps1

##########################
## 固定値 
##########################
[bool]$ErrorFlg = $false
$ErrorActionPreference = "Stop"

##########################
## 警告の表示抑止
##########################
## Set-Item Env:\SuppressAzurePowerShellBreakingChangeWarnings "true"

###############################
# LogController オブジェクト生成
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
  $Log.Info("ログファイル名:$($Log.GetLogInfo())")
}

##########################
# パラメータチェック
##########################

try {
  ##########################
  # 制御情報取得
  ##########################
  if (($ConfigFile) -and (-not $(Test-Path $ConfigFile))) {
    $Log.Error("制御ファイルが存在しません。")
    exit 9 
  } else {
    $Log.Info("制御ファイルパス：" + (Split-Path $ConfigFile -Parent))
    $Log.Info("制御ファイル名：" + (Get-ChildItem $ConfigFile).Name)
    if ($(Test-Path $ConfigFile)) { $ConfigInfo = [xml](Get-Content $ConfigFile) }
    if(-not $ConfigInfo) { 
      $Log.Error("既定のファイルから制御情報が読み込めませんでした。")
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
      $Log.Info("$($FileInfo.Name)：ファイル転送処理開始")
      $TargetFile = Join-Path $SFTP_Home $FileInfo.Name
      if ($(Test-Path $TargetFile)) {
        $Log.Info("$($TargetFile)を$($SFTP_Send_Dir)へ移動します。")
        Move-Item $TargetFile $SFTP_Send_Dir
        Write-VolumeCache $(Split-Path $TargetFile -Qualifier).Replace(':', '')
        $Log.Info("$($TargetFile)を$($SFTP_Send_Dir)へ移動しました。")
        Set-Location -Path $SFTP_Send_Dir
        $TargetFile = Join-Path $SFTP_Send_Dir $FileInfo.Name
        ##########################
        # FTP転送処理
        ##########################
        if ($(Test-Path $TargetFile)) {
          $Log.Info("$($TargetFile)をFTPサーバ$($ConfigInfo.Configuration.TransferInfo.Host)へ転送します。")
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

            $Log.Info("FTPサーバへ接続します。")
            $Log.Info("ユーザー名：$Username")
            try {
              $RequestStream = $FtpRequest.GetRequestStream()
            } catch {
              $Log.Error("サーバ接続中にエラーが発生しました。")
              $ErrorFlg = $True
              continue
            }
            $Log.Info("ファイル転送を開始します。")

            try {
              $RequestStream.Write($FileBytes, 0, $FileBytes.Length)
            } catch {
              $Log.Error("ファイル転送中にエラーが発生しました。")
            } finally {
              $RequestStream.Dispose()
            }

            try {
              $FTPResponse = [System.Net.FtpWebResponse]($FtpRequest.GetResponse())
              $Log.Info("$($Uri.AbsoluteUri)へアップロードしました。")
              $Log.Info("Status：$($FTPResponse.StatusDescription)")
              if ((250 -eq $FTPResponse.StatusCode) -or (226 -eq $FTPResponse.StatusCode)) {
                ##########################
                # 正常処理
                ##########################
                $SFTP_Back_Date = Join-Path $SFTP_Back_Dir $SendDate
                if(-not (Test-Path $SFTP_Back_Date)) { New-Item $SFTP_Back_Date -ItemType Directory 2>&1 > $null }
                $Log.Info("$($TargetFile)を$($SFTP_Back_Date)へ移動します。")
                Move-Item $TargetFile $SFTP_Back_Date
                Write-VolumeCache $(Split-Path $SFTP_Back_Date -Qualifier).Replace(':', '')
                $Log.Info("$($TargetFile)を$($SFTP_Back_Date)へ移動しました。")
                ###############################
                # 正常処理(フラグファイル作成)
                ###############################
                $TriggerFile = $FileInfo.Name + "." +$ConfigInfo.Configuration.TransferInfo.Ext
                $TriggerPath = Join-Path $SFTP_Send_Dir $TriggerFile
                New-Item -ItemType file $TriggerFile -Force 2>&1 > $null
                ###############################
                # 正常処理(フラグファイル転送)
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
                # 異常処理
                ##########################
                $SFTP_Fail_Date = Join-Path $SFTP_Fail_Dir $SendDate
                if(-not (Test-Path $SFTP_Back_Date)) { New-Item $SFTP_Fail_Date -ItemType Directory 2>&1 > $null }
                $Log.Error("$($TargetFile)を$($SFTP_Fail_Date)へ移動します。")
                Move-Item $TargetFile $SFTP_Fail_Date
                Write-VolumeCache $(Split-Path $SFTP_Fail_Date -Qualifier).Replace(':', '')
                $Log.Error("$($TargetFile)を$($SFTP_Fail_Date)へ移動しました。")
              }
            } finally {
              if ($null -ne $FTPResponse) {
                $FTPResponse.Close()
              }
            }
          } else {
            $Log.Error("FTPサーバ$($ConfigInfo.Configuration.TransferInfo.Host)に接続できません。")
            $ErrorFlg = $True
          }
        } else {
          $Log.Info("$($TargetFile) が存在しませんでした。")
          continue
        }
      } else {
        $Log.Info("$($TargetFile) が存在しませんでした。")
      }
      $Log.Info("過去ファイルの削除を実施します。")
      Get-ChildItem $SFTP_Back_Dir -Recurse | Where-Object {($_.Mode -eq "d-----") -and ($_.CreationTime -lt (Get-Date).AddDays(-1 * $FileInfo.LocalTerm))} | Remove-Item -Recurse -Force
      Get-ChildItem $SFTP_Fail_Dir -Recurse | Where-Object {($_.Mode -eq "d-----") -and ($_.CreationTime -lt (Get-Date).AddDays(-1 * $FileInfo.LocalTerm))} | Remove-Item -Recurse -Force
      $Log.Info("$($FileInfo.Name)：ファイル転送処理完了")
    }
  } else { exit 9 }

  if($ErrorFlg) { exit 9 }
  else { exit 0 }

} catch {
  $Log.Error("処理中にエラーが発生しました。")
  $Log.Error($("" + $Error[0] | Format-List --DisplayError))
  exit 9 
} finally {
}
