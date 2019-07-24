<################################################################################
## Copyright(c) 2019 BeeX Inc. All rights reserved.
## @auther#Yasutoshi Tamura
##
## @name:ConvertDisk-DR.ps1
## @summary:DR用ストレージアカウントのVHDを管理ディスクへ変換
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
    ## ストレージアカウント、コンテナの情報取得
    ##############################################
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] ストレージアカウント/コンテナ情報取得:開始")
    $StoragAaccountkey = Get-AzStorageAccountKey -ResourceGroupName $AzureProc.drResourceGroup -Name $AzureProc.drStorageAccount
    if(-not $StoragAaccountkey){
        Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] ストレージアカウントキーの取得に失敗しました。")
        exit $ErrorCode
    }
    $Storagecontext = New-AzStorageContext -StorageAccountName $AzureProc.drStorageAccount -StorageAccountKey $StoragAaccountkey[0].Value
    if(-not $Storagecontext){
        Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] ストレージコンテキストの作成に失敗しました。")
        exit $ErrorCode
    }
    $Destcontainer = Get-AzStorageContainer -Name $AzureProc.drContainer -Context $Storagecontext
    if(-not $Destcontainer){
        Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] コンテナの指定に失敗しました。")
        exit $ErrorCode
    }
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] ストレージアカウント/コンテナ情報取得:完了")


    ######################################
    ## コンテナ内のページBlob 情報の取得
    ######################################
    $blobs = Get-AzStorageBlob -Container $AzureProc.drContainer -Context $Storagecontext
    if(-not $blobs){
        Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] コンテナ内の Blob 情報が取得できませんでした。")
        exit $ErrorCode
    }

    ##################################
    ## Blob を管理ディスクへ変換
    ##################################
    foreach($blob in $blobs){
        Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $blob.Name + " 管理ディスクの変換:開始")
        $vhdUri = "https://" + $AzureProc.drStorageAccount + ".blob.core.windows.net/" + $AzureProc.drContainer + "/" + ($blob.Name)
        $disk = New-AzDisk -DiskName $blob.Name -Disk (New-AzDiskConfig -AccountType $AzureProc.drdiskAccountType -Location $AzureProc.drLocation -CreateOption Import -SourceUri $vhdUri) -ResourceGroupName $AzureProc.drResourceGroup
        if(-not $disk){
            Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] 管理ディスクへの変換に失敗しました。" + $blob.Name)
            $ReturnCode = $ErrorCode
            break
        }
        Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $blob.Name + " 管理ディスクの変換:完了")
    }

} catch {
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] 管理ディスクのエクスポート/変換にエラーが発生しました。")
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $error[0] | Format-List --DisplayError)
    exit $ErrorCode
}

exit $ReturnCode
