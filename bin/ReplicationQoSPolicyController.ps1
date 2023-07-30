##########################
# �p�����[�^�ݒ�
##########################
<#
param (
  [switch]$SetQoS,
  [switch]$RemoveQoS
)
#>

##########################
# �p�����[�^�`�F�b�N
##########################
<#
if(-not ($SetQos -xor $RemoveQoS)) {
  echo("-SetQoS / -RemoveQoS ���ꂩ�̃I�v�V������ݒ肵�Ă��������B")
  exit 9
}
#>

##########################
# �X�g���[�W�A�J�E���g
##########################
[string]$StorageAccountName = "migratee58bblsa937879.blob.core.windows.net"
[string]$StartWorkHour = "6:00:00"
[UInt32]$WorkHourBandwidth = 10MB
[string]$EndWorkHour = "22:00:00"
[UInt32]$NonWorkHourBandwidth = 3MB

##########################
# �Œ�l 
##########################
$Settings = $null
$ErrorActionPreference = "silentlycontinue"

$ScriptName = Join-Path([System.IO.FileInfo]$MyInvocation.MyCommand.Path).DirectoryName ([System.IO.FileInfo]$MyInvocation.MyCommand.Path).BaseName
$LogfileName = $ScriptName + "_" + (Get-Date -Format "yyyy-MM-dd") + ".log"
Start-Transcript $LogfileName -Append | Out-Null
$Settings = Get-OBMachineSetting
if($Settings) {
  Set-OBMachineSetting -NoThrottle
} else {
  Resolve-DnsName $StorageAccountName
  $mon = [System.DayOfWeek]::Monday
  $tue = [System.DayOfWeek]::Tuesday
  $wed = [System.DayOfWeek]::Wednesday
  $thu = [System.DayOfWeek]::Thursday
  $fri = [System.DayOfWeek]::Friday
  Set-OBMachineSetting -WorkDay $mon, $tue, $wed, $thu, $fri -StartWorkHour $StartWorkHour -EndWorkHour $EndWorkHour -WorkHourBandwidth $WorkHourBandWidth -NonWorkHourBandwidth $NonWorkHourBandwidth 
}

Stop-Transcript | Out-Null
