<################################################################################
## Copyright(c) 2023 BeeX Inc. All rights reserved.
## @auther#Naruhiro Ikeya
##
## @name: Get-SecurePassword.ps1
## @summary: Create Encription Key and Secure Password
##
## @since:2023/08/04
## @version:1.1
## @see:
## @parameter:Plain Password
##
## @return:0:Success 9:Error
################################################################################>
Param([parameter(mandatory=$true)] [string] $PlainPassword)


$EncryptedKey = New-Object Byte[] 24

[Security.Cryptography.RNGCryptoServiceProvider]::Create().GetBytes($EncryptedKey)
$KeyString = $EncryptedKey -join ","


$SecureString = ConvertTo-SecureString -String $PlainPassword -AsPlainText -Force
$EncryptedPassword = ConvertFrom-SecureString -SecureString $SecureString -key $EncryptedKey

Write-Host "If your password string contains special characters, please escape them with backquote (``). ex.) `$`,`&```"`'"
Write-host "<encryptedkey>$KeyString</encryptedkey>"
Write-host "<encryptedpass>$EncryptedPassword</encryptedpass>"
