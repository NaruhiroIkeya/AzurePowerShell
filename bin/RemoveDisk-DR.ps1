<################################################################################
## Copyright(c) 2019 BeeX Inc. All rights reserved.
## @auther#Yasutoshi Tamura
##
## @name:RemoveDisk-DR.ps1
## @summary:DR�p�Ǘ��f�B�X�N�̍폜
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

$AzureProc.setVMInfo($AzureVMName)
$generation = $AzureProc.getParam("config/common/drdiskgeneration")


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
    ## �폜�ΏۊǗ��f�B�X�N�̎擾
    ##############################################
    $VMdiskCount = (Get-AzDisk -ResourceGroupName $AzureProc.drResourceGroup | where {$_.ManagedBy -match "."}).count
    $skipCount = $VMdiskCount * $generation

    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] �Ǘ��f�B�X�N�폜:�J�n �ێ����㐔�F${generation}")
 
    $TargetDisks = Get-AzDisk -ResourceGroupName $AzureProc.drResourceGroup |where { $_.ManagedBy -notmatch "."} |sort TimeCreated -Descending |select -Skip $skipCount 

    if($TargetDisks.count -eq 0){
        Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] �Ǘ��f�B�X�N�폜:���� �ێ����㐔�F${generation}")
        exit $ReturnCode
    }

    ##############################################
    ## �Ǘ��f�B�X�N�̍폜
    ##############################################
    $RemoveDiskResult  = $TargetDisks | Remove-AzDisk -Force 
    if($RemoveDiskResult.Status -ne "Succeeded"){
        Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] �Ǘ��f�B�X�N�폜�Ɏ��s���܂����B")
        exit $ErrorCode
    }
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] �Ǘ��f�B�X�N�폜:���� �ێ����㐔�F${generation}")
    

} catch {
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] �Ǘ��f�B�X�N�̃G�N�X�|�[�g/�ϊ��ɃG���[���������܂����B")
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $error[0] | Format-List --DisplayError)
    exit $ErrorCode
}

exit $ReturnCode
