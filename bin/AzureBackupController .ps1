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
  [switch]$EnableAzureBakup,
  [switch]$DisableAzureBakup,
  [switch]$Eventlog=$false,
  [switch]$Stdout
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
  $LogFile = (Get-ChildItem $MyInvocation.MyCommand.Path).BaseName + ".log"
  $Log = New-Object LogController($($LogFilePath + "\" + $LogFile), $false, $true, (Get-ChildItem $MyInvocation.MyCommand.Path).Name, $false)
  $Log.DeleteLog($SaveDays)
}

##########################
# パラメータチェック
##########################
if ($EnableAzureBakup -xor $DisableAzureBakup) {
  if ($EnableAzureBakup) {
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
      if((-not $AzureVMProtectionPolicies) -and $DisableAzureBakup) {
        $Log.Info("指定されたBackup Policyが見つかりません。:$AzureVMBackupPolicyName")
        exit 9
      } 
    }

    $RegisterdVMsContainer = Get-AzRecoveryServicesBackupContainer -VaultId $Vault.ID -ContainerType "AzureVM" -Status "Registered"
    $Log.Info("Azure Backup" + $StatusString + "処理:開始")
    foreach($AzureVMProtectionPolicy in $AzureVMProtectionPolicies) {
      ############################
      # 日次スケジュールジョブ
      ############################
      if($AzureVMProtectionPolicy.RetentionPolicy.IsDailyScheduleEnabled) {
        $RetaintionTime = $AzureVMProtectionPolicy.RetentionPolicy.DailySchedule.RetentionTimes[0].toString("HH:mm")

        $UTCDate = (Get-Date).AddHours($DisableHours).ToUniversalTime().ToString("yyyy/MM/dd")
        $RetentionTime = Get-Date -Date $($UTCDate + " " + $RetaintionTime)
        $DisableTime = $RetentionTime.AddHours(-1 * $DisableHours)
        $Now = (Get-Date).ToUniversalTime()
      ############################
      # 週次スケジュールジョブ
      ############################
      } elseif($AzureVMProtectionPolicy.RetentionPolicy.IsWeeklyScheduleEnabled) {
        $RetaintionTime = $AzureVMProtectionPolicy.RetentionPolicy.WeeklySchedule.RetentionTimes[0].toString("HH:mm")

        $Today = Get-Date
        if($Today.DayOfWeek -eq $AzureVMProtectionPolicy.RetentionPolicy.WeeklySchedule.DaysOfTheWeek) {
          $UTCDate = $Today.AddHours($DisableHours).ToUniversalTime().ToString("yyyy/MM/dd")
        } else {
          $UTCDate = ($Today.AddDays((6 - $Today.DayOfWeek + [DayOfWeek]::$($AzureVMProtectionPolicy.RetentionPolicy.WeeklySchedule.DaysOfTheWeek)) % 7 + 1)).AddHours($DisableHours).ToUniversalTime().ToString("yyyy/MM/dd")
        }
        $RetentionTime = Get-Date -Date $($UTCDate + " " + $RetaintionTime)
        $DisableTime = $RetentionTime.AddHours(-1 * $DisableHours)
        $Now = (Get-Date).ToUniversalTime()
      ############################
      # 月次スケジュールジョブ
      ############################
      } elseif($AzureVMProtectionPolicy.RetentionPolicy.IsMonthlyScheduleEnabled) {
        $RetaintionTime = $AzureVMProtectionPolicy.RetentionPolicy.MonthlySchedule.RetentionTimes[0].toString("HH:mm")
      ############################
      # 年次スケジュールジョブ
      ############################
      } elseif($AzureVMProtectionPolicy.RetentionPolicy.IsYearlyScheduleEnabled) {
        $RetaintionTime = $AzureVMProtectionPolicy.RetentionPolicy.YearlySchedule.RetentionTimes[0].toString("HH:mm")
      }

      if($EnableAzureBakup -and ($Now -gt $RetentionTime) -or ($Now -le $DisableTime)) {
        $Log.Info($AzureVMProtectionPolicy.Name + "の有効化時間帯は ～" + $DisableTime.ToLocalTime().ToString("yyyy/MM/dd HH:mm") + "までです。" + $RetentionTime.ToLocalTime().ToString("yyyy/MM/dd HH:mm") + "移行に再有効化可能です。")
        $Log.Info($AzureVMProtectionPolicy.Name + "の有効化処理を開始します。")
      } elseif($DisableAzureBakup -and ($DisableTime -le $Now) -and ($Now -lt $RetentionTime)) {
        $Log.Info($AzureVMProtectionPolicy.Name + "の無効化時間帯は " + $DisableTime.ToLocalTime().ToString("yyyy/MM/dd HH:mm") + "～" + $RetentionTime.ToLocalTime().ToString("yyyy/MM/dd HH:mm") + "です。")
        $Log.Info("Azure Backup無効化処理:開始")
      } else {
        $Log.Info($AzureVMProtectionPolicy.Name + "は" + $StatusString + "処理の対象外です。")
        break
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
          if($EnableAzureBakup -and $BackupItem.ProtectionPolicyName) {
            $Log.Info($Container.FriendlyName + "は" + $StatusString + "済です。")
            break
          } elseif($DisableAzureBakup -and $null -eq $BackupItem.ProtectionPolicyName) {
            $Log.Info($Container.FriendlyName + "は" + $StatusString + "済です。")
            break
          } elseif(($AzureVMProtectionPolicy.Name -eq $BackupItem.ProtectionPolicyName) -and ($Container.FriendlyName -eq $AzureVM.Name)) {
            ############################
            # 有効化バックグラウンド実行
            ############################
            if($EnableAzureBakup) {
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
            ############################
            # 無効化バックグラウンド実行
            ############################
            } elseif($DisableAzureBakup) {
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
            }
            Start-Job $BackgroundJob -ArgumentList $Vault.Name, $Container.FriendlyName, $AzureVMProtectionPolicy.Name
            $Log.Info($Container.FriendlyName + "のAzure Backupジョブを" + $StatusString + "しました。")
            break
          } else {
            Continue
          }
        }
      }
    }
    Get-Job | Wait-Job
    $Log.Info($(Get-Job | Receive-Job))
    Get-Job | Remove-Job
    $Log.Info("Azure Backup" + $StatusString + "処理:完了")
  }
} catch {
    $Log.Error("処理中にエラーが発生しました。")
    $Log.Error($_.Exception)
    exit 99
}
exit 0