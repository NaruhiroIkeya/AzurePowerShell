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
##  1:ResourceGroup名
##  2:AzureVM名
##  3:起動処理モード
##  4:停止処理モード
##  5:標準出力
##
## @return:0:Success 1:パラメータエラー 2:Az command実行エラー 9:Exception
################################################################################>

##########################
# パラメータ設定
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
# モジュールのロード
##########################
. .\LogController.ps1
. .\AzureLogonFunction.ps1

##########################
# 固定値 
##########################
[string]$CredenticialFile = "AzureCredential_Secure.xml"
[int]$SaveDays = 7

##########################
# 警告の表示抑止
##########################
# Set-Item Env:\SuppressAzurePowerShellBreakingChangeWarnings "true"

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
  $LogFileName = $LogBaseName + "_" + $AzureVMName + ".log"
  $Log = New-Object LogController($($LogFilePath + "\" + $LogFileName), $false, $true, $LogBaseName, $false)
  $Log.DeleteLog($SaveDays)
  $Log.Info("ログファイル名:$($Log.GetLogInfo())")
}

##########################
# パラメータチェック
##########################
if(-not ($Boot -xor $Shutdown)) {
  $Log.Error("-Boot / -Shutdown 何れかのオプションを設定してください。")
  exit 9
}

try {
  ##########################
  # Azureログオン処理
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
  # ResourceGroup名のチェック
  ############################
  $ResourceGroup = Get-AzResourceGroup | Where-Object{$_.ResourceGroupName -eq $ResourceGroupName}
  if(-not $ResourceGroup) {
    $Log.Error("ResourceGroup名が不正です。" + $ResourceGroupName)
    exit 9
  }

  ############################
  # AzureVM名のチェック
  ############################
  $AzureVM = Get-AzVM -ResourceGroupName $ResourceGroupName | Where-Object{$_.Name -eq $AzureVMName}
  if(-not $AzureVM) { 
    $Log.Error("AzureVM名が不正です。" + $AzureVMName)
    exit 9
  }
 
  ##############################
  # AzureVMのステータスチェック
  ##############################
  $Log.Info("$AzureVMName のステータスを取得します。")
  $AzureVMStatus = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $AzureVMName -Status | Select-Object @{n="Status"; e={$_.Statuses[1].Code}}
  if(-not $AzureVMStatus) { 
    $Log.Error("AzureVMのステータスが取得できませんでした。")
    exit 9
  } else {
    $Log.Info("現在のステータスは [" + $AzureVMStatus.Status + "] です。")
  }

  if($Boot) {
    ##############################
    # AzureVMの起動
    ##############################
    if(($AzureVMStatus.Status -eq "PowerState/deallocated") -or ($AzureVMStatus.Status -eq "PowerState/stopped")) { 
      $Log.Info("AzureVMを起動します。")
      $JobResult = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $AzureVMName | ForEach-Object { Start-AzVM -ResourceGroupName $_.ResourceGroupName -Name $_.Name }
      if($JobResult.Status -eq "Failed") {
        $Log.Error("AzureVM起動ジョブがエラー終了しました。")
        $Log.Error($($JobResult | Format-List | Out-String -Stream))
        exit 9
      } else {
        $Log.Info("AzureVM起動ジョブが完了しました。")
        exit 0
      }
    } else {
      $Log.Info("AzureVM起動処理をキャンセルします。現在のステータスは [" + $AzureVMStatus.Status + "] です。")
      exit 0
    }
  } elseif($Shutdown) {
    ##############################
    # AzureVMの停止
    ##############################
    if($AzureVMStatus.Status -eq "PowerState/running") { 
      $Log.Info("AzureVMを停止します。")
      $JobResult = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $AzureVMName | ForEach-Object { Stop-AzVM -ResourceGroupName $_.ResourceGroupName -Name $_.Name -Force }
      if($JobResult.Status -eq "Failed") {
        $Log.Error("AzureVM停止ジョブがエラー終了しました。")
        $Log.Error($($JobResult | Format-List | Out-String -Stream))
        exit 9
      } else {
        $Log.Info("AzureVM停止ジョブが完了しました。")
        exit 0
      }
    } else {
      $Log.Info("AzureVM停止処理をキャンセルします。現在のステータスは [" + $AzureVMStatus.Status + "] です。")
      exit 0
    }
  } else {
    $Log.Error("-Boot / -Shutdown 何れかのオプションを設定してください。")
    exit 9
  }
  #################################################
  # エラーハンドリング
  #################################################
} catch {
    $Log.Error("AzureVMの起動/停止処理中にエラーが発生しました。")
    $Log.Error($_.Exception)
    exit 9
}
exit 0