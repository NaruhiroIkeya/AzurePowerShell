<################################################################################
## Copyright(c) 2019 BeeX Inc. All rights reserved.
## @auther#Naruhiro Ikeya
##
## @name:CreateSnapshot.ps1
## @summary:Azure VM�f�[�^�f�B�X�N��Snapshot
##
## @since:2019/06/24
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
  [parameter(mandatory=$true)][int]$ExpireDays,
  [switch]$Stdout
)

##########################
# ���W���[���̃��[�h
##########################
. .\LogController.ps1
. .\AzureLogonFunction.ps1

##########################
# �Œ�l 
##########################

##########################
# �x���̕\���}�~
##########################
Set-Item Env:\SuppressAzurePowerShellBreakingChangeWarnings "true"

###############################
# LogController �I�u�W�F�N�g����
###############################
if($Stdout) {
  $Log = New-Object LogController
} else {
  $LogFilePath = Split-Path $MyInvocation.MyCommand.Path -Parent | Split-Path -Parent | Join-Path -ChildPath log -Resolve
  $LogFile = (Get-ChildItem $MyInvocation.MyCommand.Path).BaseName + ".log"
  $Log = New-Object LogController($($LogFilePath + "\" + $LogFile), $false)
}

##########################
# �p�����[�^�`�F�b�N
##########################
if($ExpireDays -lt 1) {
  $Log.Info("�ێ�������1�ȏ��ݒ肵�Ă��������B")
  exit 1
}

try {
  ##########################
  # Azure���O�I������
  ##########################
  $SettingFilePath = Split-Path $MyInvocation.MyCommand.Path -Parent | Split-Path -Parent | Join-Path -ChildPath etc -Resolve
  $SettingFile = "AzureCredential.xml"
  $SettingFileFull = $SettingFilePath + "\" + $SettingFile 
  $Connect = New-Object AzureLogonFunction($SettingFileFull)
  if($Connect.Initialize($Log)) {
    if(-not $Connect.Logon()) {
      exit 9
    }
  } else {
    exit 9
  }
  
  ###################################
  # AzureVM �m�F
  ###################################
  $SnapshotSuffix = "_Snapshot_" + (Get-Date).ToString("yyyyMMddHHmm")
  $AzureVMInfo = Get-AzVM -ResourceGroupName $AzureVMResourceGroupName -Name $AzureVMName
  if(-not $AzureVMInfo) {
    $Log.Info("Azure VM��������܂���B")
    exit 9
  }

  ###################################
  # AzureVM Snapshot�쐬
  ###################################
  $Log.Info("$AzureVMName SnapShot�쐬:�J�n")
  $CreateDate=(Get-Date).ToString("yyyy/MM/dd HH:mm")
  if($Luns -eq "ALL") {
    $AzureVMInfo.StorageProfile.DataDisks | ForEach-Object { New-AzSnapshotConfig -SourceUri $_.ManagedDisk.Id -Location $AzureVMInfo.Location -Tag @{ SourceVMName=$AzureVMInfo.Name; SourceDiskName=$_.Name; SourceLun=[string]$_.Lun; CreateDate=$CreateDate; ExpireDate=(Get-Date).AddDays($ExpireDays).ToString("yyyy/MM/dd") } -CreateOption copy } | % { New-AzSnapshot -Snapshot $_ -SnapshotName ($_.Tags.SourceDiskName + $SnapshotSuffix) -ResourceGroupName $AzureVMInfo.ResourceGroupName } | % { $Log.Info("" + $_.Name + " : " + $_.ProvisioningState) }
  } else {
    foreach($Lun in $($Luns -split ",")) {
      $AzureVMInfo.StorageProfile.DataDisks | ? { $_.Lun -eq $Lun } | ForEach-Object { New-AzSnapshotConfig -SourceUri $_.ManagedDisk.Id -Location $AzureVMInfo.Location -Tag @{ SourceVMName=$AzureVMInfo.Name; SourceDiskName=$_.Name; SourceLun=[string]$_.Lun; CreateDate=$CreateDate; ExpireDate=(Get-Date).AddDays($ExpireDays).ToString("yyyy/MM/dd") } -CreateOption copy } | % { New-AzSnapshot -Snapshot $_ -SnapshotName ($_.Tags.SourceDiskName + $SnapshotSuffix) -ResourceGroupName $AzureVMInfo.ResourceGroupName } | % { $Log.Info("" + $_.Name + " : " + $_.ProvisioningState) }
    }
  }
  $Log.Info("$AzureVMName SnapShot�쐬:����")

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
    $Log.Error("�Ǘ��f�B�X�N�̃X�i�b�v�V���b�g�쐬���ɃG���[���������܂����B")
    $Log.Error($_.Exception)
    exit 99
}
exit 0