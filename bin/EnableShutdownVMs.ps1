<################################################################################
## Copyright(c) 2024 BeeX Inc. All rights reserved.
## @auther#Naruhiro Ikeya
##
## @name:EnableShutdownVMs.ps1
## @summary:Azure VM Shutdown Controller
##
## @since:2024/03/22
## @version:1.0
## @see:
## @parameter
##  1:ResourceGroup名
##  2:AzureVM名
##
## @return:0:Success 1:パラメータエラー 2:Az command実行エラー 9:Exception
################################################################################>

##########################
# パラメータ設定
##########################
param (
  [parameter(mandatory=$true)][string]$SubscriptionName,
  [parameter(mandatory=$true)][string]$ResourceGroupName,
  [parameter(mandatory=$true)][ValidatePattern("^\d{2}\:\d{2}$")][string]$ShutdownTime = "21:00",
  [parameter(mandatory=$true)][string]$Mail,
  [parameter()][string]$AzureVMName
)

Connect-AzAccount
Get-AzSubscription
$Subscription = Select-AzSubscription -SubscriptionName $SubscriptionName
$VMs = Get-AzVM -ResourceGroupName $ResourceGroupName

if([String]::IsNullOrEmpty($AzureVMName)) {
  $VMs = Get-AzVM -ResourceGroupName $ResourceGroupName
} else {
  $VMs = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $AzureVMName
}

foreach($vm in $VMs) {
  New-AzResource -Location JapanEast -ResourceId $("/subscriptions/$($Subscription.Subscription.Id)/resourceGroups/$ResourceGroupName/providers/microsoft.devtestlab/schedules/shutdown-computevm-" + $vm.Name) -Properties @{
    status = 'Enabled'
    taskType = 'ComputeVmShutdownTask'
    dailyRecurrence = @{ time = $ShutdownTime } 
    timeZoneId = 'Tokyo Standard Time'
    notificationSettings = @{ status = 'Enabled'; timeInMinutes = 15; emailRecipient = $Mail ; notificationLocale = 'ja' }
    targetResourceId = $vm.Id
  } -Force
}
  