<################################################################################
## Copyright(c) 2019 BeeX Inc. All rights reserved.
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
  [switch]$Stdout
)

##########################
# モジュールのロード
##########################
. .\LogController.ps1
. .\AzureLogonFunction.ps1

##########################
# 固定値 
##########################

###############################
# LogController オブジェクト生成
###############################
if($Stdout) {
  $Log = New-Object LogController
} else {
  $LogFilePath = Split-Path $MyInvocation.MyCommand.Path -Parent | Split-Path -Parent | Join-Path -ChildPath log -Resolve
  $LogFile = (Get-ChildItem $MyInvocation.MyCommand.Path).BaseName + ".log"
  $Log = New-Object LogController($($LogFilePath + "\" + $LogFile), $false)
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
  $SettingFilePath = Split-Path $MyInvocation.MyCommand.Path -Parent | Split-Path -Parent | Join-Path -ChildPath etc -Resolve
  $SettingFile = "AzureCredential.xml"
  $SettingFileFull = $SettingFilePath + "\" + $SettingFile 
  $Connect = New-Object AzureLogonFunction($SettingFileFull)
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
    $Log.Info("AzureVMのステータスが取得できませんでした。")
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
      $JobResult = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $AzureVMName | % { Start-AzVM -ResourceGroupName $_.ResourceGroupName -Name $_.Name }
      if($JobResult.Status -eq "Failed") {
        $Log.Info("AzureVM起動ジョブがエラー終了しました。")
        $JobResult | Format-List -DisplayError
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
      $JobResult = Get-AzVM -ResourceGroupName $ResourceGroupName  -Name $AzureVMName | % { Stop-AzVM -ResourceGroupName $_.ResourceGroupName -Name $_.Name -Force }
      if($JobResult.Status -eq "Failed") {
        $Log.Info("AzureVM停止ジョブがエラー終了しました。")
        $JobResult | Format-List -DisplayError
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
  }
  #################################################
  # エラーハンドリング
  #################################################
} catch {
    $Log.Error("AzureVMの起動処理中にエラーが発生しました。")
    $Log.Error($($error[0] | Format-List -DisplayError))
    exit 99
}
exit 0