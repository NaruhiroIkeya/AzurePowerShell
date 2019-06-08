<################################################################################
## Copyright(c) 2019 BeeX Inc. All rights reserved.
## @auther#Naruhiro Ikeya
##
## @name:MicrosoftOnlineSecurityNSG.ps1
## @summary:Microsoft Online Security NSG自動設定
##
## @since:2019/05/20
## @version:1.0
## @see:
## @parameter
##  1:Azure VM名
##  2:Azure VMリソースグループ名
##  3:Recovery Servicesコンテナー名
##
## @return:0:Success 9:エラー終了
################################################################################>

##########################
# パラメータ設定
##########################
param (
  [parameter(mandatory=$true)][string]$NSGName,
  [parameter(mandatory=$true)][string]$NSGResourceGroupName,
  [parameter(mandatory=$true)][string]$NSGRuleConfigName,
  [parameter(mandatory=$true)][string]$NSGRuleConfigPriority  
)

##########################
# Microsoft Online関連情報
##########################
$AzureLogonServers = @("login.microsoftonline.com", "aadcdn.msauth.net", "secure.aadcdn.microsoftonline-p.com", "ocsp.msocsp.com")
$AddressList = $AzureLogonServers | % { Resolve-DnsName $_ } | % { $_.IP4Address } | ? { $_ } | % {  $_ + "`/32" }

##########################
# 警告の表示抑止
##########################
Set-Item Env:\SuppressAzurePowerShellBreakingChangeWarnings "true"

try {
  Import-Module Az

  ##########################
  # 認証情報取得
  ##########################
  $SettingFilePath = Split-Path $MyInvocation.MyCommand.Path -Parent | Split-Path -Parent | Join-Path -ChildPath etc -Resolve
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] 設定ファイルPath：" + $SettingFilePath)
  $SettingFile = "AzureCredential.xml"
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] 設定ファイル名：" + $SettingFile)

  $Config = [xml](Get-Content (Join-Path $SettingFilePath -ChildPath $SettingFile -Resolve))

  ##########################
  # Azureへのログイン
  ##########################
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] サービスプリンシパルを利用しAzureへログインします。")
  $secpasswd = ConvertTo-SecureString $Config.Configuration.Key -AsPlainText -Force
  $mycreds = New-Object System.Management.Automation.PSCredential ($Config.Configuration.ApplicationID, $secpasswd)
  $LoginInfo = Login-AzAccount  -ServicePrincipal -Tenant $Config.Configuration.TennantID -Credential $mycreds  -WarningAction Ignore
  if(-not $LoginInfo) { 
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Azureへログインできませんでした。")
    exit 9
  }

  Write-Output("[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Network Security Groupの更新処理を開始します。")
  $NSG = Get-AzNetworkSecurityGroup -Name $NSGName -ResourceGroupName $NSGResourceGroupName
  if(-not $NSG) {
    Write-Output("[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Network Security Groupの情報が取得できません。")
    exit 9
  }
  $NSGRuleConfig = Get-AzNetworkSecurityRuleConfig -NetworkSecurityGroup $NSG | ? { $_.Name -eq $NSGRuleConfigName }
  Write-Output("[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] $AddressList")  
  if(-not $NSGRuleConfig) {
    $NSG = Add-AzNetworkSecurityRuleConfig -Name $NSGRuleConfigName -DestinationAddressPrefix $AddressList -NetworkSecurityGroup $NSG -Protocol "TCP" -SourcePortRange "*" -DestinationPortRange "443" -SourceAddressPrefix "VirtualNetwork" -Access "Allow" -Priority $NSGRuleConfigPriority -Direction "Outbound"
  } else {
    $NSG = Set-AzNetworkSecurityRuleConfig -Name $NSGRuleConfigName -DestinationAddressPrefix $AddressList -NetworkSecurityGroup $NSG -Protocol "TCP" -SourcePortRange "*" -DestinationPortRange "443" -SourceAddressPrefix "VirtualNetwork" -Access "Allow" -Priority $NSGRuleConfigPriority -Direction "Outbound"
  }
  $NSG = Set-AzNetworkSecurityGroup -NetworkSecurityGroup $NSG

  #################################################
  # エラーハンドリング
  #################################################
} catch {
  Write-Output("`r`n`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Network Security Groupの更新処理中にエラーが発生しました。")
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $error[0] | Format-List --DisplayError)
  exit 99
}
exit 0