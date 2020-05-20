<################################################################################
## Copyright(c) 2020 BeeX Inc. All rights reserved.
## @auther#Naruhiro Ikeya
##
## @name:VMDiskSnapshots.ps1
## @summary:Azure VM Disk Snapshots Controller
##
## @since:2020/05/02
## @version:1.0
## @see:
## @parameter
##  1:Snapshot�쐬���[�h
##  2:Snapshot�폜���[�h
##  3:Azure VM���\�[�X�O���[�v��
##  4:Azure VM��
##  5:LUN
##  6:Snapshot�ۑ�����
##  7:�W���o��
##  8:Snapshot���s�t���O
##
## @return:0:Success 9:�G���[�I��
################################################################################>

##########################
# �p�����[�^�ݒ�
##########################
param (
  [parameter(mandatory=$false)][switch]$CreateSnapshot,
  [parameter(mandatory=$false)][switch]$RemoveSnapshot,
  [parameter(mandatory=$false)][string]$ResourceGroupName,
  [parameter(mandatory=$false)][string]$AzureVMName,
  [parameter(mandatory=$false)][string]$Luns="ALL",
  [parameter(mandatory=$false)][int]$ExpireDays,
  [parameter(mandatory=$false)][switch]$DataDiskOnly,
  [parameter(mandatory=$false)][switch]$Reboot,
  [parameter(mandatory=$false)][switch]$Eventlog=$false,
  [parameter(mandatory=$false)][switch]$Stdout,
  [parameter(mandatory=$false)][switch]$Force
)

##########################
# ���W���[���̃��[�h
##########################
. .\LogController.ps1
. .\AzureLogonFunction.ps1

##########################
# �Œ�l 
##########################
[string]$CredenticialFile = "AzureCredential_Secure.xml"
[int]$SaveDays = 7
[string]$SnapshotSuffix = "_Snapshot_" + (Get-Date).ToString("yyyyMMddHHmm")

##########################
# �x���̕\���}�~
##########################
# Set-Item Env:\SuppressAzurePowerShellBreakingChangeWarnings "true"

###############################
# LogController �I�u�W�F�N�g����
###############################
if($Stdout -and $Eventlog) {
  $Log = New-Object LogController($true, (Get-ChildItem $MyInvocation.MyCommand.Path).Name)
} elseif($Stdout) {
  $Log = New-Object LogController
} else {
  $LogFilePath = Split-Path $MyInvocation.MyCommand.Path -Parent | Split-Path -Parent | Join-Path -ChildPath log -Resolve
  if($MyInvocation.ScriptName -eq "") {
    $LogBaseName = (Get-ChildItem $MyInvocation.MyCommand.Path).BaseName
  } else {
    $LogBaseName = (Get-ChildItem $MyInvocation.ScriptName).BaseName
  }
  $LogFileName = $LogBaseName + ".log"
  $Log = New-Object LogController($($LogFilePath + "\" + $LogFileName), $false, $true, $LogBaseName, $false)
  $Log.DeleteLog($SaveDays)
  $Log.Info("���O�t�@�C����:$($Log.GetLogInfo())")
}

##########################
# �p�����[�^�`�F�b�N
##########################
if (-not ($CreateSnapshot -xor $RemoveSnapshot)) {
  $Log.Error("Syntax Error:���s���� -CreateSnapshot / -RemoveSnapshot ���w�肵�Ă��������B")
  $Log.Info("�X�i�b�v�V���b�g�쐬���ɕK�{�̃I�v�V�����F")
  $Log.Info("�@-ResourceGroupName:���\�[�X�O���[�v��")
  $Log.Info("�@-AzureVMName:VM��")
  $Log.Info("�@-ExpireDays:�ێ������i1�ȏ��ݒ�j")
  $Log.Info("Option:�@-Luns:LUNs �J���}��؂�iDefault:ALL�j")
  $Log.Info("�X�i�b�v�V���b�g�폜���ɕK�{�̃I�v�V�����F�iOption�̎w�肪�����ꍇ�́A�S�Ă̊����؂�Snapshot���폜�Ώہj")
  $Log.Info("Option:�@-ResourceGroupName:���\�[�X�O���[�v���i���\�[�X�O���[�v��Snapshot�폜�Ώێw��j")
  $Log.Info("Option:�@-AzureVMName:VM���iVM��Snapshot�폜�Ώێw��j")
  exit 9
}

if($CreateSnapshot) {
  if(-not $ResourceGroupName) {
    $Log.Error("���\�[�X�O���[�v�����w�肵�Ă��������B")
    exit 9
  }
  if(-not $AzureVMName) {
    $Log.Error("VM�����w�肵�Ă��������B")
    exit 9
  }
  if($ExpireDays -lt 1) {
    $Log.Info("�ێ�������1�ȏ��ݒ肵�Ă��������B")
    exit 1
  }
}


try {
  ##########################
  # Azure���O�I������
  ##########################
  $CredenticialFilePath = Split-Path $MyInvocation.MyCommand.Path -Parent | Split-Path -Parent | Join-Path -ChildPath etc -Resolve
  $CredenticialFileFullPath = $CredenticialFilePath + "\" + $CredenticialFile 
  $Connect = New-Object AzureLogonFunction($CredenticialFileFullPath)
  if($Connect.Initialize($Log)) {
    if(-not $Connect.Logon()) {
      exit 9
    }
  } else {
    exit 9
  }
  
  if($CreateSnapshot) {
    ###################################
    # AzureVM �m�F
    ###################################
    $ResourceGroups = Get-AzResourceGroup -Name $ResourceGroupName
    if(-not $ResourceGroups) {
      $Log.Info("�w�肳�ꂽ���\�[�X�O���[�v������܂���:$ResourceGroupName")
      exit 9
    }
    $AzureVMInfo = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $AzureVMName
    if(-not $AzureVMInfo) {
      $Log.Info("�w�肳�ꂽAzure VM��������܂���:$AzureVMName")
      exit 9
    }

    ###################################
    # �ċN�����{���f
    ###################################
    $Log.Info("$AzureVMName �̃X�e�[�^�X���擾���܂��B")
    $AzureVMStatus = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $AzureVMName -Status | Select-Object @{n="Status"; e={$_.Statuses[1].Code}}
    if(-not $AzureVMStatus) { 
      $Log.Info("AzureVM�̃X�e�[�^�X���擾�ł��܂���ł����B")
      $Log.Info("AzureVM�̍ċN���͎��{���܂���B")
      $Reboot = $false
    } else {
      $Log.Info("���݂̃X�e�[�^�X�� [" + $AzureVMStatus.Status + "] �ł��B")
      $EnableBoot = if(($AzureVMStatus.Status -eq "PowerState/deallocated") -or ($AzureVMStatus.Status -eq "PowerState/stopped")) { Write-Output 0 } else { Write-Output 1 }
    }

    ###################################
    # �ċN�����[�h�̎���VM��~
    ###################################
    if($Reboot -and $EnableBoot) {
      $Log.Info("AzureVM���~���܂��B")
      $JobResult = Get-AzVM -ResourceGroupName $ResourceGroupName  -Name $AzureVMName | ForEach-Object { Stop-AzVM -ResourceGroupName $_.ResourceGroupName -Name $_.Name -Force }
      if($JobResult.Status -eq "Failed") {
        $Log.Error("AzureVM��~�W���u���G���[�I�����܂����B")
        $Log.Error($($JobResult | Format-List | Out-String -Stream))
        exit 9
      } else {
        $Log.Info("AzureVM��~�W���u���������܂����B")
        exit 0
      }
    }

    ###################################
    # AzureVM Snapshot�쐬
    ###################################
    $Log.Info("$AzureVMName SnapShot�쐬:�J�n")
    $CreateDate=(Get-Date).ToString("yyyy/MM/dd HH:mm")
    if(-not $DataDiskOnly) {
      $AzureVMInfo.StorageProfile.OsDisk | ForEach-Object { New-AzSnapshotConfig -SourceUri $_.ManagedDisk.Id -Location $AzureVMInfo.Location -Tag @{ SourceVMName=$AzureVMInfo.Name; SourceDiskName=$_.Name; SourceLun="OS"; CreateDate=$CreateDate; ExpireDate=(Get-Date).AddDays($ExpireDays).ToString("yyyy/MM/dd") } -CreateOption copy } | ForEach-Object { New-AzSnapshot -Snapshot $_ -SnapshotName ($_.Tags.SourceDiskName + $SnapshotSuffix) -ResourceGroupName $AzureVMInfo.ResourceGroupName } | ForEach-Object { $Log.Info("" + $_.Name + " : " + $_.ProvisioningState) }
      $Log.Info("$AzureVMName OS Disk SnapShot �쐬:����")
    }
    if($Luns -eq "ALL") {
      $AzureVMInfo.StorageProfile.DataDisks | ForEach-Object { New-AzSnapshotConfig -SourceUri $_.ManagedDisk.Id -Location $AzureVMInfo.Location -Tag @{ SourceVMName=$AzureVMInfo.Name; SourceDiskName=$_.Name; SourceLun=[string]$_.Lun; CreateDate=$CreateDate; ExpireDate=(Get-Date).AddDays($ExpireDays).ToString("yyyy/MM/dd") } -CreateOption copy } | ForEach-Object { New-AzSnapshot -Snapshot $_ -SnapshotName ($_.Tags.SourceDiskName + $SnapshotSuffix) -ResourceGroupName $AzureVMInfo.ResourceGroupName } | ForEach-Object { $Log.Info("" + $_.Name + " : " + $_.ProvisioningState) }
    } else {
      foreach($Lun in $($Luns -split ",")) {
        $AzureVMInfo.StorageProfile.DataDisks | Where-Object { $_.Lun -eq $Lun } | ForEach-Object { New-AzSnapshotConfig -SourceUri $_.ManagedDisk.Id -Location $AzureVMInfo.Location -Tag @{ SourceVMName=$AzureVMInfo.Name; SourceDiskName=$_.Name; SourceLun=[string]$_.Lun; CreateDate=$CreateDate; ExpireDate=(Get-Date).AddDays($ExpireDays).ToString("yyyy/MM/dd") } -CreateOption copy } | ForEach-Object { New-AzSnapshot -Snapshot $_ -SnapshotName ($_.Tags.SourceDiskName + $SnapshotSuffix) -ResourceGroupName $AzureVMInfo.ResourceGroupName } | ForEach-Object { $Log.Info("" + $_.Name + " : " + $_.ProvisioningState) }
      }
    }
    $Log.Info("$AzureVMName Data Disk SnapShots �쐬:����")

    ########################################
    # AzureVM �ɕt�^����Ă���^�O��ǉ�
    ########################################
    if($null -ne $AzureVMInfo.Tags) {
      $DiskSnapshots = Get-AzResource -ResourceGroupName $AzureVMInfo.ResourceGroupName -ResourceType Microsoft.Compute/snapshots | Where-Object { $_.Tags.SourceVMName -eq $AzureVMInfo.Name }
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
        if($Result) {}
      }
    }

    ###################################
    # �ċN�����[�h�̎���VM�N��
    ###################################
    if($Reboot -and $EnableBoot) {
      $Log.Info("AzureVM���N�����܂��B")
      $JobResult = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $AzureVMName | ForEach-Object { Start-AzVM -ResourceGroupName $_.ResourceGroupName -Name $_.Name }
      if($JobResult.Status -eq "Failed") {
        $Log.Error("AzureVM�N���W���u���G���[�I�����܂����B")
        $Log.Error($($JobResult | Format-List | Out-String -Stream))
        exit 9
      } else {
        $Log.Info("AzureVM�N���W���u���������܂����B")
        exit 0
      }
    }
  } elseif($RemoveSnapshot) {
    $RemoveSnapshots = $null
    if(-not $ResourceGroupName) {
      if($Force) {
        $RemoveSnapshots = Get-AzSnapshot
      } else {
        $RemoveSnapshots = Get-AzSnapshot | Where-Object { $_.Tags.ExpireDate -ne $null -and [DateTime]::Parse($_.Tags.ExpireDate) -lt (Get-Date) }
      }
    } elseif($ResourceGroupName) {
      $ResourceGroups = Get-AzResourceGroup -Name $ResourceGroupName
      if(-not $ResourceGroups) {
        $Log.Info("�w�肳�ꂽ���\�[�X�O���[�v������܂���:$ResourceGroupName")
        exit 9
      }
      if($Force) {
        $RemoveSnapshots = Get-AzSnapshot -ResourceGroupName $ResourceGroups.ResourceGroupName
      } else {
        $RemoveSnapshots = Get-AzSnapshot -ResourceGroupName $ResourceGroups.ResourceGroupName | Where-Object { $_.Tags.ExpireDate -ne $null -and [DateTime]::Parse($_.Tags.ExpireDate) -lt (Get-Date) }
      }
    } else {
      $ResourceGroups = Get-AzResourceGroup -Name $ResourceGroupName
      if(-not $ResourceGroups) {
        $Log.Info("�w�肳�ꂽ���\�[�X�O���[�v������܂���:$ResourceGroupName")
        exit 9
      }
      if($Force) {
        $RemoveSnapshots = Get-AzSnapshot -ResourceGroupName $ResourceGroups.ResourceGroupName -SnapshotName $($AzureVMName + "*") | Where-Object { $_.Tags.SourceVMName -eq $AzureVMName }
      } else {
        $RemoveSnapshots = Get-AzSnapshot -ResourceGroupName $ResourceGroups.ResourceGroupName -SnapshotName $($AzureVMName + "*") | Where-Object { $_.Tags.ExpireDate -ne $null -and [DateTime]::Parse($_.Tags.ExpireDate) -lt (Get-Date) -and $_.Tags.SourceVMName -eq $AzureVMName }
      }
    }
    if(-not $RemoveSnapshots){
      $Log.Info("�폜�Ώۂ�Snapshot������܂���B")
      exit 0
    }

    ###################################
    # AzureVM Snapshot����Ǘ�
    ###################################
    $Log.Info("�����؂�SnapShot�폜:�J�n")
    foreach ($Snapshot in $RemoveSnapshots) {
      Remove-AzSnapshot -ResourceGroupName $Snapshot.ResourceGroupName -SnapshotName $Snapshot.Name -Force | ForEach-Object { $Log.Info("�����؂�Snapshot�폜:" + $Snapshot.Name + " : " + $_.Status) }
    }
    $Log.Info("�����؂�SnapShot�폜:����")
  } else {
    $Log.Error("Logic Error!!")
    exit 99
  }
} catch {
    $Log.Error("�Ǘ��f�B�X�N�̃X�i�b�v�V���b�g�쐬���ɃG���[���������܂����B")
    $Log.Error($_.Exception)
    exit 99
}
exit 0