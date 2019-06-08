<################################################################################
## Copyright(c) 2019 BeeX Inc. All rights reserved.
## @auther#Naruhiro Ikeya
##
## @name:NSGFlowLogConverter.ps1
## @summary:NSG FlowLogの成形
##
## @since:2019/05/29
## @version:1.0
## @see:
## @parameter
##  1:NSG FlowLogファイル名
##
## @return:0:Success 9:エラー終了
################################################################################>

##########################
# パラメータ設定
##########################
param (
  [parameter(mandatory=$true)][string]$FlowLogFileName
)

###################################
# パラメータチェック
###################################
if(!(Test-Path $FlowLogFileName)) {
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] 指定されたファイルがありません:$FlowLogFileName")
  exit 9
}

$Array=@()

$NSGFlowLog = Get-Content $FlowLogFileName -Encoding UTF8 -Raw | ConvertFrom-Json
$FlowTuples = $NSGFlowLog.records | % { $_.properties.flows } | % { $_.flows } | % { $_.flowTuples } | sort
foreach($FlowTuple in $FlowTuples) {
    $Log = $FlowTuple -split ","
    $Origin = New-Object -Type DateTime -ArgumentList 1970, 1, 1, 0, 0, 0, 0
    $Obj = New-Object PSCustomObject
    $Obj | Add-Member -NotePropertyMembers @{
        Timestamp = $Origin.AddSeconds($Log[0])
        SourceIP = $Log[1]
        DestinationIP = $Log[2]
        SourcePort = $Log[3]
        DistinationPort = $Log[4]
        Protocol = if($Log[5] -eq "T") { Write-Output "TCP" } else { Write-Output "UDP" }
        Direction = if($Log[6] -eq "I") { Write-Output "InBound" } else { Write-Output "OutBound" }
        Action = if($Log[7] -eq "A") { Write-Output "Allow" } else { Write-Output "Deny" }
    }
    $Array += ($obj | Select-Object Timestamp, SourceIP, SourcePort, DestinationIP, DistinationPort, Protocol, Direction, Action)
}
$Array | FT