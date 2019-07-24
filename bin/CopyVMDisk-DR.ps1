<################################################################################
## Copyright(c) 2019 BeeX Inc. All rights reserved.
## @auther#Yasutoshi Tamura
##
## @name:CopyVMDisk-DR.ps1
## @summary:Azure Snapshot�̎擾
##          �擾����Snapshot����Ǘ��f�B�X�N�̍쐬
## @since:2019/07/09
## @version:1.0
## @see:
## @parameter
##  1:Azure VM��
##  2:Azure VM���\�[�X�O���[�v��
##
## @return:0:Success 9:�G���[�I��
################################################################################>

##########################
# �p�����[�^�ݒ�
##########################
param (
    [parameter(mandatory=$true)][string]$AzureVMName
)

##########################
# �x���̕\���}�~
##########################
Set-Item Env:\SuppressAzurePowerShellBreakingChangeWarnings "true"

##########################
# �p�����[�^�ݒ�
##########################
$error.Clear()
$ReturnCode = 0
$ErrorCode = 9

## �X�N���v�g�i�[�f�B���N�g���Ǝ������g�̃X�N���v�g�����擾
$scriptDir = Split-Path $MyInvocation.MyCommand.Path -Parent
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)

try {
    $commonFunc = Join-Path $scriptDir -ChildPath "CommonFunction.ps1"
    . $commonFunc
} catch [Exception] {
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] ${commonFunc}�̓Ǎ��݂Ɏ��s���܂����B")
    Exit $ErrorCode
}

##########################
# �R���t�B�O�t�@�C���Ǎ�
##########################
$AzureProc = AzureProc
$ret = $AzureProc.load("${scriptDir}\config")

if ($ret -ne 0 ) {
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] �R���t�B�O�t�@�C���̓Ǎ��݂Ɏ��s���܂����B")
    Exit $ErrorCode
}

$Diskprefix = $AzureProc.getParam("config/common/diskprefix")
$AzureProc.setVMInfo($AzureVMName)


try {
    ##########################
    # Azure�ւ̃��O�C��
    ##########################
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] �T�[�r�X�v�����V�p���𗘗p��Azure�փ��O�C�����܂��B")
    $ret = $AzureProc.AzureLogin()
    if ($ret -ne 0) {
        Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Azure�փ��O�C���ł��܂���ł����B")
        exit $ErrorCode
    }

    ##########################
    # �T�u�X�N���v�V�����̃Z�b�g
    ##########################
    $ret = $AzureProc.setSubscription($AzureVMName)

    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Subscription���w�肵�܂��B[" + $AzureProc.subscriptionName + "]")
    if ($ret -ne 0) {
        Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Subscription�̎w�肪�ł��܂���ł����B")
        Exit $ErrorCode
    }

    ###################################
    # AzureVM �m�F
    ###################################
    $SnapshotSuffix = "_Snapshot_" + (Get-Date).ToString("yyyyMMddHHmm")
    $AzureVMInfo = Get-AzVM -ResourceGroupName $AzureProc.resourceGroup -Name $AzureVMName
    if(-not $AzureVMInfo) {
        Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Azure VM��������܂���B")
        exit $ErrorCode
    }
  
    $disks = @()
    $disks += $AzureVMInfo.StorageProfile.OsDisk.Name
    $disks += $AzureVMInfo.StorageProfile.DataDisks.Name

    #################################
    ## �O�񕡐������f�B�X�N�̍폜
    #################################
    $oldDisks = Get-AzDisk -ResourceGroupName $AzureProc.resourceGroup | where-object Name -like $Diskprefix-$AzureVMName*

    if ($oldDisks){
        foreach($oldDisk in $oldDisks){
            Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $oldDisk.Name + " �O��f�B�X�N�폜:�J�n")
            $RemoveResult = Remove-AzDisk -ResourceGroupName $AzureProc.resourceGroup -DiskName $oldDisk.Name -Force
            if($RemoveResult.Status -ne "Succeeded") {
                Write-Output($RemoveResult | format-list -DisplayError)
                Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] �O��̃f�B�X�N���폜�ł��܂���ł����B:" + $oldDisk.Name)
                exit $ErrorCode
            }
            Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $oldDisk.Name + " �O��f�B�X�N�폜:����")
        }
    }
    ###################################
    # AzureVM Snapshot�쐬
    ###################################
    ## �f�B�X�N���擾
    Get-AzDisk -ResourceGroupName $AzureProc.resourceGroup | where { $_.Name -cin($disks) } | ForEach {
        Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $_.Name + " SnapShot�쐬:�J�n")

        $SnapshotConfig = New-AzSnapshotConfig -SourceResourceId $_.Id -Location $_.Location -CreateOption copy
        $DiskSnap =  New-AzSnapshot -Snapshot $SnapshotConfig -SnapshotName ($_.Name + $SnapshotSuffix) -ResourceGroupName $AzureProc.resourceGroup 
        if(-not $DiskSnap){
            Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $_.Name + " SnapShot�̍쐬�����s���܂����B")
            $ReturnCode = $ErrorCode
            break
        }

        Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $_.Name + " SnapShot�쐬:����")

        Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $_.Name + " �Ǘ��f�B�X�N�쐬:�J�n")
        ### �X�i�b�v�V���b�g����Ǘ��f�B�X�N�쐬
        $diskConfig = New-AzDiskConfig -Location $_.Location -SourceResourceId $DiskSnap.Id -CreateOption Copy
        if(-not $diskConfig){
            Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $_.Name + " �Ǘ��f�B�X�N�̍\�������s���܂����B")
            $ReturnCode = $ErrorCode
            break
        }
        $DRDisk = New-AzDisk -Disk $diskConfig -ResourceGroupName $AzureProc.resourceGroup -DiskName ("${Diskprefix}-${AzureVMName}-"+ $_.Name)
        if(-not $DRDisk){
            Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $_.Name + " �Ǘ��f�B�X�N�̍쐬�����s���܂����B")
            $ReturnCode = $ErrorCode
            break
        }
        Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $_.Name + " �Ǘ��f�B�X�N�쐬:����")

        ### �X�i�b�v�V���b�g�̍폜
        Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $_.Name + " SnapShot�폜:�J�n")
        $RemoveResult = Remove-AzSnapshot -ResourceGroupName $AzureProc.resourceGroup -SnapshotName $DiskSnap.Name -Force
        if($RemoveResult.Status -ne "Succeeded") {
            Write-Output($RemoveResult | format-list -DisplayError)
            Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] �X�i�b�v�V���b�g���폜�ł��܂���ł����B:" + $DiskSnap.Name)
            $ReturnCode = $ErrorCode
            break
        }
        Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $_.Name + " SnapShot�폜:����")
    }

} catch {
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] �Ǘ��f�B�X�N�̃X�i�b�v�V���b�g/�Ǘ��f�B�X�N�쐬���ɃG���[���������܂����B")
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $error[0] | Format-List --DisplayError)
    exit $ErrorCode
}

exit $ReturnCode

