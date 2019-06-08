<################################################################################
## Copyright(c) 2019 BeeX Inc. All rights reserved.
## @auther#Naruhiro Ikeya
##
## @name:MicrosoftOnlineSecurityNSG.ps1
## @summary:Microsoft Online Security NSG�����ݒ�
##
## @since:2019/05/20
## @version:1.0
## @see:
## @parameter
##  1:Azure VM��
##  2:Azure VM���\�[�X�O���[�v��
##  3:Recovery Services�R���e�i�[��
##
## @return:0:Success 9:�G���[�I��
################################################################################>

##########################
# �p�����[�^�ݒ�
##########################
param (
  [parameter(mandatory=$true)][string]$NSGName,
  [parameter(mandatory=$true)][string]$NSGResourceGroupName,
  [parameter(mandatory=$true)][string]$NSGRuleConfigName,
  [parameter(mandatory=$true)][string]$NSGRuleConfigPriority  
)

##########################
# Microsoft Online�֘A���
##########################
$AzureLogonServers = @("login.microsoftonline.com", "aadcdn.msauth.net", "secure.aadcdn.microsoftonline-p.com", "ocsp.msocsp.com")
$AddressList = $AzureLogonServers | % { Resolve-DnsName $_ } | % { $_.IP4Address } | ? { $_ } | % {  $_ + "`/32" }

##########################
# �x���̕\���}�~
##########################
Set-Item Env:\SuppressAzurePowerShellBreakingChangeWarnings "true"

try {
  Import-Module Az

  ##########################
  # �F�؏��擾
  ##########################
  $SettingFilePath = Split-Path $MyInvocation.MyCommand.Path -Parent | Split-Path -Parent | Join-Path -ChildPath etc -Resolve
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] �ݒ�t�@�C��Path�F" + $SettingFilePath)
  $SettingFile = "AzureCredential.xml"
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] �ݒ�t�@�C�����F" + $SettingFile)

  $Config = [xml](Get-Content (Join-Path $SettingFilePath -ChildPath $SettingFile -Resolve))

  ##########################
  # Azure�ւ̃��O�C��
  ##########################
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] �T�[�r�X�v�����V�p���𗘗p��Azure�փ��O�C�����܂��B")
  $secpasswd = ConvertTo-SecureString $Config.Configuration.Key -AsPlainText -Force
  $mycreds = New-Object System.Management.Automation.PSCredential ($Config.Configuration.ApplicationID, $secpasswd)
  $LoginInfo = Login-AzAccount  -ServicePrincipal -Tenant $Config.Configuration.TennantID -Credential $mycreds  -WarningAction Ignore
  if(-not $LoginInfo) { 
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Azure�փ��O�C���ł��܂���ł����B")
    exit 9
  }

  Write-Output("[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Network Security Group�̍X�V�������J�n���܂��B")
  $NSG = Get-AzNetworkSecurityGroup -Name $NSGName -ResourceGroupName $NSGResourceGroupName
  if(-not $NSG) {
    Write-Output("[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Network Security Group�̏�񂪎擾�ł��܂���B")
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
  # �G���[�n���h�����O
  #################################################
} catch {
  Write-Output("`r`n`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Network Security Group�̍X�V�������ɃG���[���������܂����B")
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $error[0] | Format-List --DisplayError)
  exit 99
}
exit 0