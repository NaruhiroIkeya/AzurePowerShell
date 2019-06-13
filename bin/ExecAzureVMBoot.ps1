<################################################################################
## Copyright(c) 2019 BeeX Inc. All rights reserved.
## @auther#Naruhiro Ikeya
##
## @name:ExecAzureVMBoot.ps1
## @summary:Azure VM Boot
##
## @since:2019/01/17
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
  [parameter(mandatory=$true)][string]$AzureVMName
)

##########################
# 認証情報設定
##########################
$TennantID="e2fb1fde-e67c-4a07-8478-5ab2b9a0577f"
$Key="I9UCoQXrv/G/EqC93RC7as8eyWARVd77UUC/fxRdGTw="
$ApplicationID="1cb16aa7-59a6-4d8e-89ef-3b896d9f1718"

try {
  ##########################
  # Azureへのログイン
  ##########################
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] サービスプリンシパルを利用しAzureへログインします。")
  $SecPasswd = ConvertTo-SecureString $Key -AsPlainText -Force
  $MyCreds = New-Object System.Management.Automation.PSCredential ($ApplicationID, $SecPasswd)
  $LoginInfo = Login-AzAccount  -ServicePrincipal -Tenant $TennantID -Credential $MyCreds
  if(-not $LoginInfo) { 
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Azureへログインできませんでした。")
    exit 9
  }

  ############################
  # ResourceGroup名のチェック
  ############################
  $ResourceGroup = Get-AzResourceGroup | Where-Object{$_.ResourceGroupName -eq "$ResourceGroupName"}
  if(-not $ResourceGroup) { 
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] ResourceGroup名が不正です。")
    exit 1
  }

  ############################
  # AzureVM名のチェック
  ############################
  $AzureVM = Get-AzVM -ResourceGroupName $ResourceGroupName | Where-Object{$_.Name -eq "$AzureVMName"}
  if(-not $AzureVM) { 
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] AzureVM名が不正です。")
    exit 1
  }
 
  ##############################
  # AzureVMのステータスチェック
  ##############################
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] $AzureVMName のステータスを取得します。")
  $AzureVMStatus = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $AzureVMName -Status | Select @{n="Status"; e={$_.Statuses[1].Code}}
  if(-not $AzureVMStatus) { 
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] AzureVMのステータスが取得できませんでした。")
    exit 1
  } else {
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] 現在のステータスは [" + $AzureVMStatus.Status + "] です。")
  }

  ##############################
  # AzureVMの起動
  ##############################
  if($AzureVMStatus.Status -eq "PowerState/deallocated") { 
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] AzureVMを起動します。")
    $JobResult = Get-AzVM -Name $AzureVMName | Start-AzVM -ResourceGroupName $ResourceGroupName -Id $_.Id
    if($JobResult.Status -eq "Failed") {
      Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] AzureVM起動ジョブがエラー終了しました。")
　  　$JobResult | Format-List -DisplayError
      exit 2
    } else {
      Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] AzureVM起動ジョブが完了しました。")
    }
  } else {
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] AzureVM起動処理をキャンセルします。現在のステータスは [" + $AzureVMStatus.Status + "] です。")
  }
  #################################################
  # エラーハンドリング
  #################################################
} catch {
    Write-Output("`r`n`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] AzureVMの起動処理中にエラーが発生しました。")
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $error[0] | Format-List -DisplayError)
    exit 9
}
exit 0