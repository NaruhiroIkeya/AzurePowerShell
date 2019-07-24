<################################################################################
## Copyright(c) 2019 BeeX Inc. All rights reserved.
## @auther#Yasutoshi Tamura
##
## @name:ExportDisk-DR.ps1
## @summary:DR用管理ディスクをDRリージョンのストレージアカウントにエクスポートする
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

$Diskprefix = $AzureProc.getParam("config/common/diskprefix")
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

    ###################################################
    ## 前回blobファイルの削除
    ###################################################
    Get-AzStorageBlob -Container $AzureProc.drContainer -Context $storagecontext | where {$_.Name -match "^${Diskprefix}-${AzureVMName}"} | Remove-AzureStorageBlob
    $blobInfo = Get-AzStorageBlob -Container $AzureProc.drContainer -Context $storagecontext | where {$_.Name -match "^${Diskprefix}-${AzureVMName}"}
    if ($blobInfo){
        Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] 前回Blobの削除に失敗しました。")
        exit $ErrorCode
    }

    ###################################################
    ## コピーディスクの情報取得と西日本へのエクスポート
    ###################################################
    $ManagedDisks = Get-AzDisk -ResourceGroupName $AzureProc.resourceGroup | where-object Name -like $Diskprefix-$AzureVMName*
    if(-not $ManagedDisks){
        Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] エクスポートするDisk が見つかりません。")
        exit $ErrorCode
    }

    $DestDiskNames = @()
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] 管理ディスクのエクスポート:開始")
    foreach($diskname in $ManagedDisks.Name){
        ########################################
        ### SAS URL の作成とBlob名の定義
        ########################################
        $mdiskURL = Grant-AzDiskAccess -ResourceGroupName $AzureProc.resourceGroup -DiskName $diskname -Access Read -DurationInSecond 3600
        if(-not $mdiskURL){
            Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] SAS URL の取得が失敗しました。" + $diskname)
            $ReturnCode = $ErrorCode
            break
        }
        $destdiskname = $diskname
        $sourceSASurl = $mdiskURL.AccessSAS
        $DestDiskNames += $diskname

        #############################################################
        ### コピーディスクの西日本ストレージアカウントへのエクスポート
        #############################################################
        $ops = Start-AzStorageBlobCopy -AbsoluteUri $sourceSASurl -DestBlob $destdiskname -DestContainer $Destcontainer.Name -DestContext $Storagecontext -Force
        if(-not $ops){
            Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] 管理ディスクのエクスポートが失敗しました。" + $diskname)
            $ReturnCode = $ErrorCode
            break
        }
    }

    ########################################
    ### エクスポートの終了ステータス取得
    ########################################
    foreach($destdisk in $DestDiskNames){
        $blobcopyJob = Get-AzStorageBlobCopyState -Container $Destcontainer.Name -Blob $destdisk -Context $storagecontext -WaitForComplete
    }

    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] 管理ディスクのエクスポート:完了")

} catch {
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] 管理ディスクのエクスポート/変換にエラーが発生しました。")
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $error[0] | Format-List --DisplayError)
    exit $ErrorCode
}

exit $ReturnCode
