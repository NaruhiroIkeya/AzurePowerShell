<################################################################################
## Copyright(c) 2020 BeeX Inc. All rights reserved.
## @auther#Naruhiro Ikeya
##
## @name:AzreBackupController.ps1
## @summary:Azure Backup Recovery Point Retention Controller
##
## @since:2019/06/04
## @version:1.0
## @see:
## @parameter
##  1:バックアップポリシー名
##  2:有効化フラグ
##  3:無効化フラグ
##
## @return:0:Success 9:エラー終了 / 99:Exception
################################################################################>

##########################
# パラメータ設定
##########################
param (
  [string]$RecoveryServicesVaultName=$null,
  [string]$AzureVMBackupPolicyName=$null,
  [switch]$EnableAzureBackup,
  [switch]$DisableAzureBackup,
  [switch]$Eventlog=$false,
  [switch]$Stdout=$false
)

##########################
# モジュールのロード
##########################
. .\LogController.ps1
. .\AzureLogonFunction.ps1

##########################
# 固定値 
##########################
Set-Variable -Name "ConstantPolicyName" -Value "CooperationJobSchedulerDummyPolicy" -Option Constant
Set-Variable -Name "DisableHours" -Value 3 -Option Constant
[string]$CredenticialFile = "AzureCredential_Secure.xml"
[int]$SaveDays = 7

##########################
# 警告の表示抑止
##########################
# Set-Item Env:\SuppressAzurePowerShellBreakingChangeWarnings "true"

###############################
# LogController オブジェクト生成
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
  $Log.Info("ログファイル名:$($Log.GetLogInfo())")
}

##########################
# パラメータチェック
##########################
if ($EnableAzureBackup -xor $DisableAzureBackup) {
  if ($EnableAzureBackup) {
    $Log.Info("Azure Backupを有効化します。")
    $StatusString="有効化"
  } else {
    $Log.Info("Azure Backupを無効化します。")
    $StatusString="無効化"
  }
} else {
  $Log.Error("Syntax Error:実行時に -EnableAzureBackup / -DisableAzureBackup を指定してください。")
  exit 9
}

try {
  ##########################
  # Azureログオン処理
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

  if($RecoveryServicesVaultName) {
    $RecoveryServicesVaults = Get-AzRecoveryServicesVault -Name $RecoveryServicesVaultName
    if(-not $RecoveryServicesVaults) {
      $Log.Error("指定されたRecovery Service コンテナー($RecoveryServicesVaultName)が存在しません。")
      exit 9
    }
  } else {
    $RecoveryServicesVaults = Get-AzRecoveryServicesVault
    if(-not $RecoveryServicesVaults) {
      $Log.Error("Recovery Service コンテナーが存在しません。")
      exit 9
    }
  }

  foreach($Vault in $RecoveryServicesVaults) {
    $Log.Info("Recovery Service コンテナー:" + $Vault.Name)
    if(-not $AzureVMBackupPolicyName) {
      $AzureVMProtectionPolicies = Get-AzRecoveryServicesBackupProtectionPolicy -VaultId $Vault.ID -WorkloadType "AzureVM" 
    } else {
      $AzureVMProtectionPolicies = Get-AzRecoveryServicesBackupProtectionPolicy -VaultId $Vault.ID | Where-Object { $_.Name -eq $AzureVMBackupPolicyName }
      if((-not $AzureVMProtectionPolicies) -and $DisableAzureBackup) {
        $Log.Error("指定されたBackup Policyが見つかりません。:$AzureVMBackupPolicyName")
        exit 9
      } 
    }

    $RegisterdVMsContainer = Get-AzRecoveryServicesBackupContainer -VaultId $Vault.ID -ContainerType "AzureVM" -Status "Registered"
    $Log.Info("Azure Backup" + $StatusString + "処理:開始")
    foreach($AzureVMProtectionPolicy in $AzureVMProtectionPolicies) {
      ############################
      # 日次スケジュールジョブ
      ############################
      if($AzureVMProtectionPolicy.SchedulePolicy.ScheduleRunFrequency -eq "Daily") {
        $UTCNow = (Get-Date).ToUniversalTime()
        ########################################################
        # バックアップ時間を過ぎてたら次回のバックアップは翌日
        ########################################################
        if ($AzureVMProtectionPolicy.SchedulePolicy.ScheduleRunTimes[0].TimeOfDay -gt $UTCNow.TimeOfDay) {
          $RunDate = $UTCNow.ToString("yyyy/MM/dd")
        } else {
          $RunDate = $UTCNow.AddDays(1).tostring("yyyy/MM/dd")
        }
        $BackupTime = Get-Date -Date $($RunDate + " " + $AzureVMProtectionPolicy.SchedulePolicy.ScheduleRunTimes[0].toString("HH:mm"))

      ############################
      # 週次スケジュールジョブ
      ############################
      } elseif($AzureVMProtectionPolicy.SchedulePolicy.ScheduleRunFrequency -eq "Weekly") {
        $UTCNow = (Get-Date).ToUniversalTime()
        ########################################################
        # 曜日が異なっていたら次回のバックアップ日を算出
        # バックアップ時間を過ぎてたら次回のバックアップは翌週
        ########################################################
        $RunDayOfWeek = $AzureVMProtectionPolicy.SchedulePolicy.ScheduleRunDays[0]
        $RunTimeOfDay = $AzureVMProtectionPolicy.SchedulePolicy.ScheduleRunTimes[0].TimeOfDay 
        if(($UTCNow.DayOfWeek -eq $RunDayOfWeek) -and ($UTCNow.TimeOfDay -lt $RunTimeOfDay)) {
          $RunDate = $UTCNow.ToString("yyyy/MM/dd")
        } else {
          $AddDaysVaule = (6 - $UTCNow.DayOfWeek + [DayOfWeek]::$($AzureVMProtectionPolicy.SchedulePolicy.ScheduleRunDays[0])) % 7 + 1
          $RunDate = ($UTCNow.AddDays($AddDaysVaule)).ToString("yyyy/MM/dd")
        }
        $RunTime = $AzureVMProtectionPolicy.SchedulePolicy.ScheduleRunTimes[0].toString("HH:mm")
        $BackupTime = (Get-Date -Date $("$RunDate $Runtime +00:00")).ToUniversalTime()
      }
      $DisableTime = $BackupTime.AddHours(-1 * $DisableHours)

      if($EnableAzureBackup -and (($UTCNow -gt $BackupTime) -or ($UTCNow -le $DisableTime))) {
        $Log.Info($AzureVMProtectionPolicy.Name + "の有効化処理を開始します。")
      } elseif($DisableAzureBackup -and (($DisableTime -le $UTCNow) -and ($UTCNow -lt $BackupTime))) {
        $Log.Info($AzureVMProtectionPolicy.Name + "の無効化処理を開始します。")
      } else {
        if($EnableAzureBackup) { $Log.Info($AzureVMProtectionPolicy.Name + "の有効化可能時間帯は ～" + $DisableTime.ToLocalTime().ToString("yyyy/MM/dd HH:mm") + "までです。" + $BackupTime.ToLocalTime().ToString("yyyy/MM/dd HH:mm") + "以降に再有効化可能です。") }
        if($DisableAzureBackup) { $Log.Info($AzureVMProtectionPolicy.Name + "の無効化可能時間帯は " + $DisableTime.ToLocalTime().ToString("yyyy/MM/dd HH:mm") + "～" + $BackupTime.ToLocalTime().ToString("yyyy/MM/dd HH:mm") + "です。") }
        continue
      }

      $SettingFilePath = Split-Path $MyInvocation.MyCommand.Path -Parent | Split-Path -Parent | Join-Path -ChildPath etc -Resolve
      $SettingFile = $Vault.Name + "_" + $AzureVMProtectionPolicy.Name + ".xml"
      $Log.Info("Backup Policyファイル名：" + $SettingFile)
      if(-not (Test-Path(Join-Path $SettingFilePath -ChildPath $SettingFile))) {
        $Log.Warn("Backup Policyファイルが存在しません。")
        break
      }
      $BackupPolicyConfig = [xml](Get-Content (Join-Path $SettingFilePath -ChildPath $SettingFile -Resolve))
      if(-not $BackupPolicyConfig) { 
        $Log.Error("既定のファイルから設定情報が読み込めませんでした。")
        exit 9
      } 
      foreach($Container in $RegisterdVMsContainer) {
        $BackupItem = Get-AzRecoveryServicesBackupItem -VaultId $Vault.ID -Container $Container -WorkloadType AzureVM 
        foreach($AzureVM in $BackupPolicyConfig.BackupPolicy.VM) {
          if($EnableAzureBackup -and $BackupItem.ProtectionPolicyName) {
            $Log.Info($Container.FriendlyName + "は" + $StatusString + "済です。")
            break
          } elseif($DisableAzureBackup -and ($null -eq $BackupItem.ProtectionPolicyName)) {
            $Log.Info($Container.FriendlyName + "は" + $StatusString + "済です。")
            break
          } elseif($EnableAzureBackup -and ($Container.FriendlyName -eq $AzureVM.Name)) {
            ############################
            # 有効化バックグラウンド実行
            ############################
            $BackgroundJob = {
              param([string]$VaultName, [string]$VMName, [string]$PolicyName)
              try {
                $Vault = Get-AzRecoveryServicesVault -Name $VaultName
                $Container = Get-AzRecoveryServicesBackupContainer -VaultId $Vault.ID -ContainerType "AzureVM" -Status "Registered" -FriendlyName $VMName
                $Item = Get-AzRecoveryServicesBackupItem -VaultId $Vault.ID -Container $Container -WorkloadType AzureVM 
                $AzureVMProtectionPolicy = Get-AzRecoveryServicesBackupProtectionPolicy -VaultId $Vault.ID -Name $PolicyName
                $EnabledItem = Enable-AzRecoveryServicesBackupProtection -VaultId $Vault.ID -Item $Item -Policy $AzureVMProtectionPolicy
                Write-Host("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $EnabledItem.WorkloadName + "のAzure Backupを有効化しました。")
              } catch {
                Write-Host("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $VMName + "のAzure Backu有効化に失敗しました。")
                throw
              } 
            }
            $JobResult = Start-Job $BackgroundJob -ArgumentList $Vault.Name, $Container.FriendlyName, $AzureVMProtectionPolicy.Name
            $Log.Info($Container.FriendlyName + "のAzure Backup" + $StatusString + "ジョブを実行しました。JobID = " + $JobResult.Id)
            break
          } elseif($DisableAzureBackup -and ($AzureVMProtectionPolicy.Name -eq $BackupItem.ProtectionPolicyName) -and ($Container.FriendlyName -eq $AzureVM.Name)) {
            ############################
            # 無効化バックグラウンド実行
            ############################
            $BackgroundJob = {
              param([string]$VaultName, [string]$VMName)
              try {
                $Vault = Get-AzRecoveryServicesVault -Name $VaultName
                $Container = Get-AzRecoveryServicesBackupContainer -VaultId $Vault.ID -ContainerType "AzureVM" -Status "Registered" -FriendlyName $VMName
                $Item = Get-AzRecoveryServicesBackupItem -VaultId $Vault.ID -Container $Container -WorkloadType AzureVM
                $DisabledItem = Disable-AzRecoveryServicesBackupProtection -VaultId $Vault.ID -Item $Item -Force
                Write-Host("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $DisabledItem.WorkloadName + "のAzure Backupを無効化しました。")
              } catch {
                Write-Host("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $VMName + "のAzure Backup無効化に失敗しました。")
                throw
              } 
            }
            $JobResult = Start-Job $BackgroundJob -ArgumentList $Vault.Name, $Container.FriendlyName, $AzureVMProtectionPolicy.Name
            $Log.Info($Container.FriendlyName + "のAzure Backup" + $StatusString + "ジョブを実行しました。JobID = " + $JobResult.Id)
            $Log.Info($BackupTime.ToLocalTime().ToString("yyyy/MM/dd HH:mm") + " のバックアップジョブをスキップします。")
            break
          }
        }
      }
    }
    ######################################
    # バックグラウンドジョブの完了待ち
    ######################################
    $Log.Info("バックグラウンドジョブ完了待ち")
    $JobResults=Get-Job | Wait-Job -Timeout 600
    foreach($JobResult in $JobResults) { 
      $Log.Info("Id:$($JobResult.Id) State:$($JobResult.JobStateInfo.State)")
    } 
    ######################################
    # バックグラウンドジョブの削除
    ######################################
    Get-Job | Remove-Job
    $Log.Info("Azure Backup" + $StatusString + "処理:完了")
  }
#################################################
# エラーハンドリング
#################################################
} catch {
    $Log.Error("処理中にエラーが発生しました。")
    $Log.Error($_.Exception)
    exit 9
}
exit 0