<################################################################################
## Copyright(c) 2019 BeeX Inc. All rights reserved.
## @auther#Naruhiro Ikeya
##
## @name:CreateSnapshot.ps1
## @summary:Azure VM�f�[�^�f�B�X�N��Snapshot
##
## @since:2019/03/16
## @version:1.0
## @see:
## @parameter
##  1:Azure VM��
##  2:Azure VM���\�[�X�O���[�v��
##  3:�ۑ�����
##
## @return:0:Success 9:�G���[�I��
################################################################################>

##########################
# �p�����[�^�ݒ�
##########################
param (
  [parameter(mandatory=$true)][string]$AzureVMName,
  [parameter(mandatory=$true)][string]$AzureVMResourceGroupName,
  [parameter(mandatory=$false)][string]$Luns="ALL",
  [parameter(mandatory=$true)][int]$ExpireDays
)

##########################
# �p�����[�^�`�F�b�N
##########################
if($ExpireDays -lt 1) {
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] �ێ�������1�ȏ��ݒ肵�Ă��������B")
  exit 1
}

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
  # AzureVM �m�F
  ###################################
  $SnapshotSuffix = "_Snapshot_" + (Get-Date).ToString("yyyyMMddHHmm")
  $AzureVMInfo = Get-AzVM -ResourceGroupName $AzureVMResourceGroupName -Name $AzureVMName
  if(-not $AzureVMInfo) {
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Azure VM��������܂���B")
    exit 9
  }

  ###################################
  # AzureVM Snapshot�쐬
  ###################################
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] $AzureVMName SnapShot�쐬:�J�n")
  $CreateDate=(Get-Date).ToString("yyyy/MM/dd HH:mm")
  if($Luns -eq "ALL") {
    $AzureVMInfo.StorageProfile.DataDisks | ForEach-Object { New-AzSnapshotConfig -SourceUri $_.ManagedDisk.Id -Location $AzureVMInfo.Location -Tag @{ SourceVMName=$AzureVMInfo.Name; SourceDiskName=$_.Name; SourceLun=[string]$_.Lun; CreateDate=$CreateDate; ExpireDate=(Get-Date).AddDays($ExpireDays).ToString("yyyy/MM/dd") } -CreateOption copy } | % { New-AzSnapshot -Snapshot $_ -SnapshotName ($_.Tags.SourceDiskName + $SnapshotSuffix) -ResourceGroupName $AzureVMInfo.ResourceGroupName } | % { Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $_.Name + " : " + $_.ProvisioningState) }
  } else {
    foreach($Lun in $($Luns -split ",")) {
      $AzureVMInfo.StorageProfile.DataDisks | ? { $_.Lun -eq $Lun } | ForEach-Object { New-AzSnapshotConfig -SourceUri $_.ManagedDisk.Id -Location $AzureVMInfo.Location -Tag @{ SourceVMName=$AzureVMInfo.Name; SourceDiskName=$_.Name; SourceLun=[string]$_.Lun; CreateDate=$CreateDate; ExpireDate=(Get-Date).AddDays($ExpireDays).ToString("yyyy/MM/dd") } -CreateOption copy } | % { New-AzSnapshot -Snapshot $_ -SnapshotName ($_.Tags.SourceDiskName + $SnapshotSuffix) -ResourceGroupName $AzureVMInfo.ResourceGroupName } | % { Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $_.Name + " : " + $_.ProvisioningState) }
    }
  }
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] $AzureVMName SnapShot�쐬:����")

  ########################################
  # AzureVM �ɕt�^����Ă���^�O��ǉ�
  ########################################
  if($null -ne $AzureVMInfo.Tags) {
    $DiskSnapshots = Get-AzResource -ResourceGroupName $AzureVMInfo.ResourceGroupName -ResourceType Microsoft.Compute/snapshots | ? { $_.Tags.SourceVMName -eq $AzureVMInfo.Name }
    foreach($Snapshot in $DiskSnapshots) {
      $ResourceTags = (Get-AzResource -ResourceId $Snapshot.Id).Tags
      if($ResourceTags) {
        foreach($Key in $AzureVMInfo.Tags.Keys) {
          if (-not($ResourceTags.ContainsKey($key))) {
            $ResourceTags.Add($Key, $AzureVMInfo.Tags[$Key])
          }
        }
        $Result = Set-AzResource -Tag $ResourceTags -ResourceId $Snapshot.ResourceId -Force
      } else {
        $Result = Set-AzResource -Tag $AzureVMInfo.Tags -ResourceId $Snapshot.ResourceId -Force
      }
    }
  }
  
} catch {
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] �Ǘ��f�B�X�N�̃X�i�b�v�V���b�g�쐬���ɃG���[���������܂����B")
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $error[0] | Format-List --DisplayError)
    exit 99
}
exit 0