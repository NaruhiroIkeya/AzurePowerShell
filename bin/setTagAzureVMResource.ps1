<################################################################################
## Copyright(c) 2019 BeeX Inc. All rights reserved.
## @auther#Naruhiro Ikeya
##
## @name:ReCreateAzureVM.ps1
## @summary:VHD���J�o����̉��z�}�V���̍č\�z�X�N���v�g
##
## @since:2019/02/03
## @version:1.0
## @see:
## @parameter
##  1:Azure VM��
##  2:Azure VM���\�[�X�O���[�v��
##  3:Recovery Services�R���e�i�[��
##  4:Boot�f�f�X�g���[�W�A�J�E���g��
##  5:Boot�f�f�X�g���[�W�A�J�E���g���\�[�X�O���[�v��
##
## @return:0:Success 9:�G���[�I��
################################################################################>

##########################
# �p�����[�^�ݒ�
##########################
param (
  [parameter(mandatory=$true)][string]$AzureVMName,
  [parameter(mandatory=$true)][string]$CompanyTagName,
  [parameter(mandatory=$true)][string]$SystemTagName
)

##########################
# �F�؏��ݒ�
##########################
$TennantID="2ab73ef2-d066-4ce0-923e-94235755e2a2"
$Key="AgndRfEIsRJ+8VjN0oQjy5T+vfnlcIQUUuYsXj780FM="
$ApplicationID="ea70cdb1-df24-4928-9bf4-4ff6b6963463"

try {
  Import-Module Az

  ##########################
  # Azure�ւ̃��O�C��
  ##########################
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] �T�[�r�X�v�����V�p���𗘗p��Azure�փ��O�C�����܂��B")
  $SecPasswd = ConvertTo-SecureString $Key -AsPlainText -Force
  $MyCreds = New-Object System.Management.Automation.PSCredential ($ApplicationID, $SecPasswd)
  $LoginInfo = Login-AzAccount -ServicePrincipal -Tenant $TennantID -Credential $MyCreds -WarningAction Ignore
  if(-not $LoginInfo) { 
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Azure�փ��O�C���ł��܂���ł����B")
    exit 9
  }

  Get-AzResource | ?{ $_.Name -match $AzureVMName } | %{ Set-AzResource -Tag @{ Company=$CompanyTagName; System=$SystemTagName; Server=$_.Name } -ResourceID  $_.ResourceId -Force }

} catch {
    Write-Output("`r`n`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] ���z�}�V���̕����������ɃG���[���������܂����B")
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $error[0] | Format-List --DisplayError)
    exit 99
}
exit 0