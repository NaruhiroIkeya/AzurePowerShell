## Copyright(c) 2020 BeeX Inc. All rights reserved.
## @auther#Naruhiro Ikeya
##
## @name:StartInstance.ps1
## @summary:SAPシステム起動
##
## @since:2023/08/01
## @version:1.1
## @see:
## @parameter
##  1:Azure Login認証ファイルパス
##
## @return:0:Success 1:Error
#################################################################################>

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
. .\ServiceController.ps1

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
    # 制御取得
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
    $Log.Info("すべてのサービスが起動しました。`r`n")

$nowfmt = Get-Date -Format "yyyy/MM/dd HH:mm:ss.ff"
Write-Host "[$nowfmt] SAP インスタンスを起動します。`r`n"
foreach($Instance in $SAPConfig.Configuration.SAP.SID) {
    foreach($saphost in $Instance.host) {
        $nowfmt = Get-Date -Format "yyyy/MM/dd HH:mm:ss.ff"
        Write-Host "[$nowfmt]" $Instance.name $saphost.name $saphost.nr "インスタンスを起動します。`r`n"
        $sapctrlparam = "-prot PIPE -host " + $saphost.name + " -nr " + $saphost.nr + " -function StartWait " + $saphost.timeout + " " + $saphost.delay
        $result = Start-Process -FilePath "sapcontrol.exe" -ArgumentList $sapctrlparam -PassThru -Wait
        if ($result.ExitCode -ne 0) {
            Write-Host $Hostname $Instance.name "が起動できませんでした。`r`n"
            exit 1
        }
    }
    Start-Sleep 5
}
$nowfmt = Get-Date -Format "yyyy/MM/dd HH:mm:ss.ff"
Write-Host "[$nowfmt] すべてのインスタンスが起動しました。`r`n"

Exit 0
