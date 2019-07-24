<################################################################################
## Copyright(c) 2019 BeeX Inc. All rights reserved.
## @auther#Yasutoshi Tamura
##
## @name:CopyVMDisk-DR.ps1
## @summary:Azure Snapshotの取得
##          取得したSnapshotから管理ディスクの作成
## @since:2019/07/09
## @version:1.0
## @see:
## @parameter
##  1:Azure VM名
##  2:Azure VMリソースグループ名
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

    ###################################
    # AzureVM 確認
    ###################################
    $SnapshotSuffix = "_Snapshot_" + (Get-Date).ToString("yyyyMMddHHmm")
    $AzureVMInfo = Get-AzVM -ResourceGroupName $AzureProc.resourceGroup -Name $AzureVMName
    if(-not $AzureVMInfo) {
        Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Azure VMが見つかりません。")
        exit $ErrorCode
    }
  
    $disks = @()
    $disks += $AzureVMInfo.StorageProfile.OsDisk.Name
    $disks += $AzureVMInfo.StorageProfile.DataDisks.Name

    #################################
    ## 前回複製したディスクの削除
    #################################
    $oldDisks = Get-AzDisk -ResourceGroupName $AzureProc.resourceGroup | where-object Name -like $Diskprefix-$AzureVMName*

    if ($oldDisks){
        foreach($oldDisk in $oldDisks){
            Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $oldDisk.Name + " 前回ディスク削除:開始")
            $RemoveResult = Remove-AzDisk -ResourceGroupName $AzureProc.resourceGroup -DiskName $oldDisk.Name -Force
            if($RemoveResult.Status -ne "Succeeded") {
                Write-Output($RemoveResult | format-list -DisplayError)
                Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] 前回のディスクを削除できませんでした。:" + $oldDisk.Name)
                exit $ErrorCode
            }
            Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $oldDisk.Name + " 前回ディスク削除:完了")
        }
    }
    ###################################
    # AzureVM Snapshot作成
    ###################################
    ## ディスク情報取得
    Get-AzDisk -ResourceGroupName $AzureProc.resourceGroup | where { $_.Name -cin($disks) } | ForEach {
        Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $_.Name + " SnapShot作成:開始")

        $SnapshotConfig = New-AzSnapshotConfig -SourceResourceId $_.Id -Location $_.Location -CreateOption copy
        $DiskSnap =  New-AzSnapshot -Snapshot $SnapshotConfig -SnapshotName ($_.Name + $SnapshotSuffix) -ResourceGroupName $AzureProc.resourceGroup 
        if(-not $DiskSnap){
            Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $_.Name + " SnapShotの作成が失敗しました。")
            $ReturnCode = $ErrorCode
            break
        }

        Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $_.Name + " SnapShot作成:完了")

        Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $_.Name + " 管理ディスク作成:開始")
        ### スナップショットから管理ディスク作成
        $diskConfig = New-AzDiskConfig -Location $_.Location -SourceResourceId $DiskSnap.Id -CreateOption Copy
        if(-not $diskConfig){
            Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $_.Name + " 管理ディスクの構成が失敗しました。")
            $ReturnCode = $ErrorCode
            break
        }
        $DRDisk = New-AzDisk -Disk $diskConfig -ResourceGroupName $AzureProc.resourceGroup -DiskName ("${Diskprefix}-${AzureVMName}-"+ $_.Name)
        if(-not $DRDisk){
            Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $_.Name + " 管理ディスクの作成が失敗しました。")
            $ReturnCode = $ErrorCode
            break
        }
        Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $_.Name + " 管理ディスク作成:完了")

        ### スナップショットの削除
        Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $_.Name + " SnapShot削除:開始")
        $RemoveResult = Remove-AzSnapshot -ResourceGroupName $AzureProc.resourceGroup -SnapshotName $DiskSnap.Name -Force
        if($RemoveResult.Status -ne "Succeeded") {
            Write-Output($RemoveResult | format-list -DisplayError)
            Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] スナップショットを削除できませんでした。:" + $DiskSnap.Name)
            $ReturnCode = $ErrorCode
            break
        }
        Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $_.Name + " SnapShot削除:完了")
    }

} catch {
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] 管理ディスクのスナップショット/管理ディスク作成中にエラーが発生しました。")
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $error[0] | Format-List --DisplayError)
    exit $ErrorCode
}

exit $ReturnCode

