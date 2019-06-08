<################################################################################
## Copyright(c) 2019 BeeX Inc. All rights reserved.
## @auther#Naruhiro Ikeya
##
## @name:RemoveSnapshot.ps1
## @summary:�����؂�X�i�b�v�V���b�g�̍폜
##
## @since:2019/03/16
## @version:1.0
## @see:
## @parameter
##  1:Azure VM���\�[�X�O���[�v��
##
## @return:0:Success 9:�G���[�I��
################################################################################>

##########################
# �p�����[�^�ݒ�
##########################
param (
  [parameter(mandatory=$true)][string]$AzureVMResourceGroupName
)

##########################
# �F�؏��ݒ�
##########################
$TennantID="2ab73ef2-d066-4ce0-923e-94235755e2a2"
$Key="AgndRfEIsRJ+8VjN0oQjy5T+vfnlcIQUUuYsXj780FM="
$ApplicationID="ea70cdb1-df24-4928-9bf4-4ff6b6963463"

##########################
# �x���̕\���}�~
##########################
Set-Item Env:\SuppressAzurePowerShellBreakingChangeWarnings "true"

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

  ###################################
  # �p�����[�^�`�F�b�N
  ###################################
  $Result = Get-AzResourceGroup -Name $AzureVMResourceGroupName
  if(-not $Result) {
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] �w�肳�ꂽ���\�[�X�O���[�v������܂���:$AzureVMResourceGroupName")
    exit 9
  }

  ###################################
  # AzureVM Snapshot����Ǘ�
  ###################################
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] $AzureVMResourceGroupName �����؂�SnapShot�폜:�J�n")
  $RemoveSnapshots = Get-AzSnapshot -ResourceGroupName $AzureVMResourceGroupName | Where-Object { $_.Tags.ExpireDate -ne $null -and [DateTime]::Parse($_.Tags.ExpireDate) -lt (Get-Date) }
  foreach ($Snapshot in $RemoveSnapshots) {
    Remove-AzSnapshot -ResourceGroupName $Snapshot.ResourceGroupName -SnapshotName $Snapshot.Name -Force | % { Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $Snapshot.Name + " : " + $_.Status) }
  }
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] $AzureVMResourceGroupName �����؂�SnapShot�폜:����")

} catch {
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] �Ǘ��f�B�X�N�̃X�i�b�v�V���b�g�폜���ɃG���[���������܂����B")
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $error[0] | Format-List --DisplayError)
    exit 99
}
exit 0