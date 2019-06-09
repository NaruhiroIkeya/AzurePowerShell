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
# 固定値 
##########################

Set-Variable -Name "ConstantPolicyName" -Value "CooperationJobSchedulerDummyPolicy" -Option Constant
Set-Variable -Name "DisableHours" -Value 1 -Option Constant

##########################
# パラメータチェック
##########################
if ($EnableAzureBakup -xor $DisableAzureBakup) {
  if ($EnableAzureBakup) {
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Azure Backupを有効化します。")
  } else {
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Azure Backupを無効化します。")
  }
} else {
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Syntax Error:実行時に -EnableAzureBackup / -DisableAzureBackup を指定してください。")
    exit 9
}

##########################
# 警告の表示抑止
##########################
Set-Item Env:\SuppressAzurePowerShellBreakingChangeWarnings "true"

try {
  ##########################
  # 認証情報取得
  ##########################
  $SettingFilePath = Split-Path $MyInvocation.MyCommand.Path -Parent | Split-Path -Parent | Join-Path -ChildPath etc -Resolve
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] 設定ファイルPath：" + $SettingFilePath)
  $SettingFile = "AzureCredential.xml"
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] 設定ファイル名：" + $SettingFile)

  $Config = [xml](Get-Content (Join-Path $SettingFilePath -ChildPath $SettingFile -Resolve))
  if(-not $Config) { 
      Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] 既定のファイルから認証情報が読み込めませんでした。")
      exit 9
  } elseif (-not $Config.Configuration.Key) {
    ##########################
    # Azureへのログイン
    ##########################
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Azureへログイン:開始")
    $LoginInfo = Login-AzAccount -Tenant $Config.Configuration.TennantID -WarningAction Ignore
  } else {
    ##########################
    # Azureへのログイン
    ##########################
    $Config.Configuration.Key
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] サービスプリンシパルを利用しAzureへログイン:開始")
    $SecPasswd = ConvertTo-SecureString $Config.Configuration.Key -AsPlainText -Force
    $MyCreds = New-Object System.Management.Automation.PSCredential ($Config.Configuration.ApplicationID, $secpasswd)
    $LoginInfo = Login-AzAccount  -ServicePrincipal -Tenant $Config.Configuration.TennantID -Credential $MyCreds  -WarningAction Ignore
  }
  if(-not $LoginInfo) { 
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Azureへログイン:失敗")
    exit 9
  }
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Azureへログイン:完了")

  $RecoveryServicesVaults = Get-AzRecoveryServicesVault
  foreach($Vault in $RecoveryServicesVaults) {
    Set-AzRecoveryServicesVaultContext -Vault $Vault
    if(-not $AzureVMBackupPolicyName) {
      $AzureVMProtectionPolicies = Get-AzRecoveryServicesBackupProtectionPolicy -WorkloadType "AzureVM" 
    } else {
      $AzureVMProtectionPolicies = Get-AzRecoveryServicesBackupProtectionPolicy | ? { $_.Name -eq $AzureVMBackupPolicyName }
      if((-not $AzureVMProtectionPolicies) -and $DisableAzureBakup) {
        Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] 指定されたBackup Policyが見つかりません。:$AzureVMBackupPolicyName")
        exit 9
      } elseif(-not $AzureVMProtectionPolicies) {
        Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Azureへログイン:完了")
      }
    }
    $RegisterdVMsContainer = Get-AzRecoveryServicesBackupContainer -ContainerType "AzureVM" -Status "Registered"
    if($EnableAzureBakup) {
      Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Azure Backup有効化処理:開始")
      if(-not $AzureVMProtectionPolicy) {
        ##########################
        # Backup Policyの新規作成
        ##########################
        $SchedulePolicyObject = Get-AzRecoveryServicesBackupSchedulePolicyObject -WorkloadType "AzureVM"
        if(-not $SchedulePolicyObject) { 
          Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] SchedulePolicyObjectの生成に失敗しました。")
          exit 9
        }
        $UtcTime = Get-Date -Date ((Get-Date).ToString("yyyy/MM/dd") + " 12:00:00")
        $UtcTime = $UtcTime.ToUniversalTime()
        $SchedulePolicyObject.ScheduleRunTimes[0] = $UtcTime
        
        $RetentionPolicyObject = Get-AzRecoveryServicesBackupRetentionPolicyObject -WorkloadType "AzureVM"
        if(-not $RetentionPolicyObject) { 
          Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] RetentionPolicyObjectの生成に失敗しました。")
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
          Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] バックアップポリシーの作成に失敗しました。")
          exit 9
        }
      } else {


      }
      Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Azure Backup有効化処理:完了")
    } else {
      ############################
      # Azure Backup(IaaS)の無効化
      ############################
      Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Azure Backup無効化処理:開始")
      foreach($AzureVMProtectionPolicy in $AzureVMProtectionPolicies) {
        $RetentionTime = $AzureVMProtectionPolicy.RetentionPolicy.DailySchedule.RetentionTimes[0].toString("HHmm")
        $DisableTime = $AzureVMProtectionPolicy.RetentionPolicy.DailySchedule.RetentionTimes[0].AddHours(-1 * $DisableHours).toString("HHmm")
        $Now = ((Get-Date).ToUniversalTime()).ToString("HHmm") 
        Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $AzureVMProtectionPolicy.Name + "の無効化時間帯は " + $DisableTime + "～" + $RetentionTime + "(UTC)です。")
        if($DisableTime -le $Now -and $Now -lt $RetentionTime) {
          Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $AzureVMProtectionPolicy.Name + "の無効化処理を開始します。")
          foreach($Container in $RegisterdVMsContainer) {
            $BackupItem = Get-AzRecoveryServicesBackupItem -Container $Container -WorkloadType AzureVM 
            if($BackupItem.ProtectionPolicyName -eq $AzureVMProtectionPolicy.Name) {
              $DisabledItem = Disable-AzRecoveryServicesBackupProtection -Item $BackupItem -Force
              Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $DisabledItem.WorkloadName + "のAzure Backupジョブを無効化しました。")
              Continue
            } elseif(-not $BackupItem.ProtectionPolicyName) {
              Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $Container.FriendlyName  + "は無効化済みです。")
            } else {
              Continue
            }
          }
        } else {
          Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $AzureVMProtectionPolicy.Name + "は無効化処理の対象外です。")
        }
      }
      Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Azure Backup無効化処理:完了")
    }
  }
} catch {
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] 処理中にエラーが発生しました。")
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $error[0] | Format-List --DisplayError)
    exit 99
}
exit 0
