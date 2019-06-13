<################################################################################
## Copyright(c) 2019 BeeX Inc. All rights reserved.
## @auther#Naruhiro Ikeya
##
## @name:AzreBackupController.ps1
## @summary:Azure Backup Recovery Point Retention Controller
##
## @since:2019/06/04
## @version:1.0
## @see:
## @parameter
##  1:Azure VM名
##  2:Azure VMリソースグループ名
##  3:保存日数
##
## @return:0:Success 9:エラー終了 / 99:Exception
################################################################################>

##########################
# パラメータ設定
##########################
param (
  [String]$AzureVMBackupPolicyName,
  [Switch]$EnableAzureBakup,
  [Switch]$DisableAzureBakup
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
Set-Variable -Name "DisableHours" -Value 1 -Option Constant

###############################
# LogController オブジェクト生成
###############################
$LogFilePath = Split-Path $MyInvocation.MyCommand.Path -Parent | Split-Path -Parent | Join-Path -ChildPath log -Resolve
$LogFile = (Get-ChildItem $MyInvocation.MyCommand.Path).BaseName + ".log"
$Log = New-Object LogController($($LogFilePath + "\" + $LogFile), $true)
$Log.RotateLog(7)

##########################
# パラメータチェック
##########################
if ($EnableAzureBakup -xor $DisableAzureBakup) {
  if ($EnableAzureBakup) {
    $Log.Info("Azure Backupを有効化します。")
  } else {
    $Log.Info("Azure Backupを無効化します。")
  }
} else {
  $Log.error("Syntax Error:実行時に -EnableAzureBackup / -DisableAzureBackup を指定してください。")
  exit 9
}

##########################
# 警告の表示抑止
##########################
Set-Item Env:\SuppressAzurePowerShellBreakingChangeWarnings "true"

try {
  $SettingFilePath = Split-Path $MyInvocation.MyCommand.Path -Parent | Split-Path -Parent | Join-Path -ChildPath etc -Resolve
  $SettingFile = "AzureCredential.xml"
  $Connect = New-Object AzureLogonFunction("C:\Users\naruhiro.ikeya\Documents\GitHub\AzurePowerShell\etc\AzureCredential.xml")
  if($Connect.Initialize($Log)) { if(-not $Connect.Logon()) { exit 9 } }

  $RecoveryServicesVaults = Get-AzRecoveryServicesVault
  foreach($Vault in $RecoveryServicesVaults) {
    Set-AzRecoveryServicesVaultContext -Vault $Vault
    if(-not $AzureVMBackupPolicyName) {
      $AzureVMProtectionPolicies = Get-AzRecoveryServicesBackupProtectionPolicy -WorkloadType "AzureVM" 
    } else {
      $AzureVMProtectionPolicies = Get-AzRecoveryServicesBackupProtectionPolicy | ? { $_.Name -eq $AzureVMBackupPolicyName }
      if((-not $AzureVMProtectionPolicies) -and $DisableAzureBakup) {
        $Log.Info("指定されたBackup Policyが見つかりません。:$AzureVMBackupPolicyName")
        exit 9
      } elseif((-not $AzureVMProtectionPolicies) -and $EnableAzureBakup) {
        $Log.Info("指定されたポリシーを新規作成します。:$AzureVMBackupPolicyName")
      }
    }

    $RegisterdVMsContainer = Get-AzRecoveryServicesBackupContainer -ContainerType "AzureVM" -Status "Registered"
    if($EnableAzureBakup) {
      $Log.Info("Azure Backup有効化処理:開始")
      if(-not $AzureVMProtectionPolicy) {
        ##########################
        # Backup Policyの新規作成
        ##########################
        $SchedulePolicyObject = Get-AzRecoveryServicesBackupSchedulePolicyObject -WorkloadType "AzureVM"
        if(-not $SchedulePolicyObject) { 
          $Log.Info("SchedulePolicyObjectの生成に失敗しました。")
          exit 9
        }
        $UtcTime = Get-Date -Date ((Get-Date).ToString("yyyy/MM/dd") + " 12:00:00")
        $UtcTime = $UtcTime.ToUniversalTime()
        $SchedulePolicyObject.ScheduleRunTimes[0] = $UtcTime
        
        $RetentionPolicyObject = Get-AzRecoveryServicesBackupRetentionPolicyObject -WorkloadType "AzureVM"
        if(-not $RetentionPolicyObject) { 
          $Log.Info("RetentionPolicyObjectの生成に失敗しました。")
          exit 9
        }
        $RetentionPolicyObject.IsWeeklyScheduleEnabled = $false
        $RetentionPolicyObject.IsMonthlyScheduleEnabled = $false
        $RetentionPolicyObject.IsYearlyScheduleEnabled = $false
        $RetentionPolicyObject.DailySchedule.DurationCountInDays = 7
        $UtcTime = Get-Date -Date ((Get-Date).ToString("yyyy/MM/dd") + " 15:00:00")
        $UtcTime = $UtcTime.ToUniversalTime()
        $RetentionPolicyObject.DailySchedule.RetentionTimes[0] = $UtcTime

        $AzureVMProtectionPolicy = New-AzRecoveryServicesBackupProtectionPolicy -Name $AzureVMBackupPolicyName -WorkloadType "AzureVM" -RetentionPolicy $RetentionPolicyObject -SchedulePolicy $SchedulePolicyObject
        if(-not $AzureVMProtectionPolicy) { 
          $Log.error("バックアップポリシーの作成に失敗しました。")
          exit 9
        }
      } 
      ############################
      # Azure Backup(IaaS)の有効化
      ############################
      foreach($AzureVMProtectionPolicy in $AzureVMProtectionPolicies) {
        $RetentionTime = $AzureVMProtectionPolicy.RetentionPolicy.DailySchedule.RetentionTimes[0].toString("HHmm")
        $Now = ((Get-Date).ToUniversalTime()).ToString("HHmm") 
        $Log.Info("" + $AzureVMProtectionPolicy.Name + "の有効化時間帯は " + $RetentionTime + "～(UTC)です。")
        if($Now -gt $RetentionTime) {
          $Log.Info("" + $AzureVMProtectionPolicy.Name + "の有効化処理を開始します。")
        
          $SettingFile = $AzureVMProtectionPolicy.Name + ".xml"
          $Log.Info("Backup Policyファイル名：" + $SettingFile)
          if(-not (Test-Path(Join-Path $SettingFilePath -ChildPath $SettingFile))) {
            $Log.Info("Backup Policyファイルが存在しません。")
            break
          }
          $BackupPolicyConfig = [xml](Get-Content (Join-Path $SettingFilePath -ChildPath $SettingFile -Resolve))
          if(-not $BackupPolicyConfig) { 
            $Log.Info("既定のファイルから設定情報が読み込めませんでした。")
            exit 9
          } 
          foreach($Container in $RegisterdVMsContainer) {
            $BackupItem = Get-AzRecoveryServicesBackupItem -Container $Container -WorkloadType AzureVM 
            foreach($AzureVM in $BackupPolicyConfig.BackupPolicy.VM) {
              if($BackupItem.ProtectionPolicyName) {
                $Log.Info("" + $Container.FriendlyName + "は有効化済です。")
                break
              } elseif($Container.FriendlyName -eq $AzureVM.Name) {
                $EnabledItem = Enable-AzRecoveryServicesBackupProtection -Item $BackupItem -Policy $AzureVMProtectionPolicy
                $Log.Info("" + $EnabledItem.WorkloadName + "のAzure Backupジョブを有効化しました。")
                break
              } else {
                Continue
              }
            }
          }
        } else {
          $Log.Info("" + $AzureVMProtectionPolicy.Name + "は有効化処理の対象外です。")
        }
      }
      $Log.Info("zure Backup有効化処理:完了")
    } else {
      ############################
      # Azure Backup(IaaS)の無効化
      ############################
      $Log.Info("zure Backup無効化処理:開始")
      foreach($AzureVMProtectionPolicy in $AzureVMProtectionPolicies) {
        $RetentionTime = $AzureVMProtectionPolicy.RetentionPolicy.DailySchedule.RetentionTimes[0].toString("HHmm")
        $DisableTime = $AzureVMProtectionPolicy.RetentionPolicy.DailySchedule.RetentionTimes[0].AddHours(-1 * $DisableHours).toString("HHmm")
        $Now = ((Get-Date).ToUniversalTime()).ToString("HHmm") 
        $Log.Info("" + $AzureVMProtectionPolicy.Name + "の無効化時間帯は " + $DisableTime + "～" + $RetentionTime + "(UTC)です。")
        if($DisableTime -le $Now -and $Now -lt $RetentionTime) {
          $Log.Info("" + $AzureVMProtectionPolicy.Name + "の無効化処理を開始します。")
          foreach($Container in $RegisterdVMsContainer) {
            $BackupItem = Get-AzRecoveryServicesBackupItem -Container $Container -WorkloadType AzureVM 
            if($BackupItem.ProtectionPolicyName -eq $AzureVMProtectionPolicy.Name) {
              $DisabledItem = Disable-AzRecoveryServicesBackupProtection -Item $BackupItem -Force
              $Log.Info("" + $DisabledItem.WorkloadName + "のAzure Backupジョブを無効化しました。")
              Continue
            } elseif(-not $BackupItem.ProtectionPolicyName) {
              $Log.Info("" + $Container.FriendlyName  + "は無効化済みです。")
            } else {
              Continue
            }
          }
        } else {
          $Log.Info("" + $AzureVMProtectionPolicy.Name + "は無効化処理の対象外です。")
        }
      }
      $Log.Info("Azure Backup無効化処理:完了")
    }
  }
} catch {
    $Log.Info("処理中にエラーが発生しました。")
    $Log.Info($("" + $error[0] | Format-List --DisplayError))
    exit 99
}

exit 0