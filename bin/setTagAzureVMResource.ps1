<################################################################################
## Copyright(c) 2019 BeeX Inc. All rights reserved.
## @auther#Naruhiro Ikeya
##
## @name:ReCreateAzureVM.ps1
## @summary:VHDリカバリ後の仮想マシンの再構築スクリプト
##
## @since:2019/02/03
## @version:1.0
## @see:
## @parameter
##  1:Azure VM名
##  2:Azure VMリソースグループ名
##  3:Recovery Servicesコンテナー名
##  4:Boot診断ストレージアカウント名
##  5:Boot診断ストレージアカウントリソースグループ名
##
## @return:0:Success 9:エラー終了
################################################################################>

##########################
# パラメータ設定
##########################
param (
  [parameter(mandatory=$true)][string]$AzureVMName,
  [parameter(mandatory=$true)][string]$CompanyTagName,
  [parameter(mandatory=$true)][string]$SystemTagName
)

##########################
# 認証情報設定
##########################
$TennantID="2ab73ef2-d066-4ce0-923e-94235755e2a2"
$Key="AgndRfEIsRJ+8VjN0oQjy5T+vfnlcIQUUuYsXj780FM="
$ApplicationID="ea70cdb1-df24-4928-9bf4-4ff6b6963463"

try {
  Import-Module Az

  ##########################
  # Azureへのログイン
  ##########################
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] サービスプリンシパルを利用しAzureへログインします。")
  $SecPasswd = ConvertTo-SecureString $Key -AsPlainText -Force
  $MyCreds = New-Object System.Management.Automation.PSCredential ($ApplicationID, $SecPasswd)
  $LoginInfo = Login-AzAccount -ServicePrincipal -Tenant $TennantID -Credential $MyCreds -WarningAction Ignore
  if(-not $LoginInfo) { 
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Azureへログインできませんでした。")
    exit 9
  }

  Get-AzResource | ?{ $_.Name -match $AzureVMName } | %{ Set-AzResource -Tag @{ Company=$CompanyTagName; System=$SystemTagName; Server=$_.Name } -ResourceID  $_.ResourceId -Force }

} catch {
    Write-Output("`r`n`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] 仮想マシンの復元処理中にエラーが発生しました。")
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $error[0] | Format-List --DisplayError)
    exit 99
}
exit 0