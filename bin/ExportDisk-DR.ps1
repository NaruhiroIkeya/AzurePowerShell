<################################################################################
## Copyright(c) 2019 BeeX Inc. All rights reserved.
## @auther#Yasutoshi Tamura
##
## @name:ExportDisk-DR.ps1
## @summary:DR�p�Ǘ��f�B�X�N��DR���[�W�����̃X�g���[�W�A�J�E���g�ɃG�N�X�|�[�g����
##
## @since:2019/07/09
## @version:1.0
## @see:
## @parameter
##  1:Azure VM��
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


    ##############################################
    ## �X�g���[�W�A�J�E���g�A�R���e�i�̏��擾
    ##############################################
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] �X�g���[�W�A�J�E���g/�R���e�i���擾:�J�n")
    $StoragAaccountkey = Get-AzStorageAccountKey -ResourceGroupName $AzureProc.drResourceGroup -Name $AzureProc.drStorageAccount
    if(-not $StoragAaccountkey){
        Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] �X�g���[�W�A�J�E���g�L�[�̎擾�Ɏ��s���܂����B")
        exit $ErrorCode
    }
    $Storagecontext = New-AzStorageContext -StorageAccountName $AzureProc.drStorageAccount -StorageAccountKey $StoragAaccountkey[0].Value
    if(-not $Storagecontext){
        Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] �X�g���[�W�R���e�L�X�g�̍쐬�Ɏ��s���܂����B")
        exit $ErrorCode
    }
    $Destcontainer = Get-AzStorageContainer -Name $AzureProc.drContainer -Context $Storagecontext
    if(-not $Destcontainer){
        Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] �R���e�i�̎w��Ɏ��s���܂����B")
        exit $ErrorCode
    }
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] �X�g���[�W�A�J�E���g/�R���e�i���擾:����")

    ###################################################
    ## �O��blob�t�@�C���̍폜
    ###################################################
    Get-AzStorageBlob -Container $AzureProc.drContainer -Context $storagecontext | where {$_.Name -match "^${Diskprefix}-${AzureVMName}"} | Remove-AzureStorageBlob
    $blobInfo = Get-AzStorageBlob -Container $AzureProc.drContainer -Context $storagecontext | where {$_.Name -match "^${Diskprefix}-${AzureVMName}"}
    if ($blobInfo){
        Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] �O��Blob�̍폜�Ɏ��s���܂����B")
        exit $ErrorCode
    }

    ###################################################
    ## �R�s�[�f�B�X�N�̏��擾�Ɛ����{�ւ̃G�N�X�|�[�g
    ###################################################
    $ManagedDisks = Get-AzDisk -ResourceGroupName $AzureProc.resourceGroup | where-object Name -like $Diskprefix-$AzureVMName*
    if(-not $ManagedDisks){
        Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] �G�N�X�|�[�g����Disk ��������܂���B")
        exit $ErrorCode
    }

    $DestDiskNames = @()
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] �Ǘ��f�B�X�N�̃G�N�X�|�[�g:�J�n")
    foreach($diskname in $ManagedDisks.Name){
        ########################################
        ### SAS URL �̍쐬��Blob���̒�`
        ########################################
        $mdiskURL = Grant-AzDiskAccess -ResourceGroupName $AzureProc.resourceGroup -DiskName $diskname -Access Read -DurationInSecond 3600
        if(-not $mdiskURL){
            Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] SAS URL �̎擾�����s���܂����B" + $diskname)
            $ReturnCode = $ErrorCode
            break
        }
        $destdiskname = $diskname
        $sourceSASurl = $mdiskURL.AccessSAS
        $DestDiskNames += $diskname

        #############################################################
        ### �R�s�[�f�B�X�N�̐����{�X�g���[�W�A�J�E���g�ւ̃G�N�X�|�[�g
        #############################################################
        $ops = Start-AzStorageBlobCopy -AbsoluteUri $sourceSASurl -DestBlob $destdiskname -DestContainer $Destcontainer.Name -DestContext $Storagecontext -Force
        if(-not $ops){
            Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] �Ǘ��f�B�X�N�̃G�N�X�|�[�g�����s���܂����B" + $diskname)
            $ReturnCode = $ErrorCode
            break
        }
    }

    ########################################
    ### �G�N�X�|�[�g�̏I���X�e�[�^�X�擾
    ########################################
    foreach($destdisk in $DestDiskNames){
        $blobcopyJob = Get-AzStorageBlobCopyState -Container $Destcontainer.Name -Blob $destdisk -Context $storagecontext -WaitForComplete
    }

    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] �Ǘ��f�B�X�N�̃G�N�X�|�[�g:����")

} catch {
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] �Ǘ��f�B�X�N�̃G�N�X�|�[�g/�ϊ��ɃG���[���������܂����B")
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $error[0] | Format-List --DisplayError)
    exit $ErrorCode
}

exit $ReturnCode
