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
# �Œ�l 
##########################
[string]$QoSPolicyName = "AzureMigrateReplicationPolicy"
[UInt64]$ThrottleRate = 3MB
[UInt16]$IPPort = 443
[string]$IPProtocol = "TCP"
$Policy = $null
$ErrorActionPreference = "silentlycontinue"

$ScriptName = Join-Path([System.IO.FileInfo]$MyInvocation.MyCommand.Path).DirectoryName ([System.IO.FileInfo]$MyInvocation.MyCommand.Path).BaseName
$LogfileName = $ScriptName + "_" + (Get-Date -Format "yyyy-MM-dd") + ".log"
Start-Transcript $LogfileName -Append | Out-Null
$Policy = Get-NetQosPolicy | Where-Object {$_.Name -eq $QoSPolicyName}
if($Policy) {
  Remove-NetQosPolicy -Name $QoSPolicyName -Confirm:$false
} else {
  New-NetQosPolicy -Name $QoSPolicyName -IPPort $IPPort -IPProtocol $IPProtocol -ThrottleRateActionBitsPerSecond $ThrottleRate
}

Stop-Transcript | Out-Null