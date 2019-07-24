<################################################################################
## Copyright(c) 2019 BeeX Inc. All rights reserved.
## @auther#Yasutoshi Tamura
##
## @name:RemoveDisk-DR.ps1
## @summary:DR用管理ディスクの削除
##
## @since:2019/07/09
## @version:1.0
## @see:
## @parameter
##  1:Azure VM名
##
## @return:0:Success 9:エラー終了
################################################################################>

##########################
# パラメータ設定
##########################
param (
    [parameter(mandatory=$true)][string]$AzureVMName
)

##########################
# 警告の表示抑止
##########################
Set-Item Env:\SuppressAzurePowerShellBreakingChangeWarnings "true"

##########################
# パラメータ設定
##########################
$error.Clear()
$ReturnCode = 0
$ErrorCode = 9

## スクリプト格納ディレクトリと自分自身のスクリプト名を取得
$scriptDir = Split-Path $MyInvocation.MyCommand.Path -Parent
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)

try {
    $commonFunc = Join-Path $scriptDir -ChildPath "CommonFunction.ps1"
    . $commonFunc
} catch [Exception] {
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] ${commonFunc}の読込みに失敗しました。")
    Exit $ErrorCode
}

##########################
# コンフィグファイル読込
##########################
$AzureProc = AzureProc
$ret = $AzureProc.load("${scriptDir}\config")

if ($ret -ne 0 ) {
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] コンフィグファイルの読込みに失敗しました。")
    Exit $ErrorCode
}

$AzureProc.setVMInfo($AzureVMName)
$generation = $AzureProc.getParam("config/common/drdiskgeneration")


try {
    ##########################
    # Azureへのログイン
    ##########################
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] サービスプリンシパルを利用しAzureへログインします。")
    $ret = $AzureProc.AzureLogin()
    if ($ret -ne 0) {
        Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Azureへログインできませんでした。")
        exit $ErrorCode
    }

    ##########################
    # サブスクリプションのセット
    ##########################
    $ret = $AzureProc.setSubscription($AzureVMName)

    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Subscriptionを指定します。[" + $AzureProc.subscriptionName + "]")
    if ($ret -ne 0) {
        Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Subscriptionの指定ができませんでした。")
        Exit $ErrorCode
    }

    ##############################################
    ## 削除対象管理ディスクの取得
    ##############################################
    $VMdiskCount = (Get-AzDisk -ResourceGroupName $AzureProc.drResourceGroup | where {$_.ManagedBy -match "."}).count
    $skipCount = $VMdiskCount * $generation

    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] 管理ディスク削除:開始 保持世代数：${generation}")
 
    $TargetDisks = Get-AzDisk -ResourceGroupName $AzureProc.drResourceGroup |where { $_.ManagedBy -notmatch "."} |sort TimeCreated -Descending |select -Skip $skipCount 

    if($TargetDisks.count -eq 0){
        Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] 管理ディスク削除:完了 保持世代数：${generation}")
        exit $ReturnCode
    }

    ##############################################
    ## 管理ディスクの削除
    ##############################################
    $RemoveDiskResult  = $TargetDisks | Remove-AzDisk -Force 
    if($RemoveDiskResult.Status -ne "Succeeded"){
        Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] 管理ディスク削除に失敗しました。")
        exit $ErrorCode
    }
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] 管理ディスク削除:完了 保持世代数：${generation}")
    

} catch {
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] 管理ディスクのエクスポート/変換にエラーが発生しました。")
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $error[0] | Format-List --DisplayError)
    exit $ErrorCode
}

exit $ReturnCode
