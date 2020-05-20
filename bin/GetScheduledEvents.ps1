<################################################################################
## Copyright(c) 2020 BeeX Inc. All rights reserved.
## @auther#Naruhiro Ikeya
##
## @name:GetSheduledEvents.ps1
## @summary:Get Azure VMs Sheduled Events 
##
## @since:2020/05/21
## @version:1.0
## @see:
## @parameter
##
## @return:$true:Success $false:Error 
################################################################################>

###############################################
# イベント取得先の設定
###############################################
$LocalHostIP = "169.254.169.254"
$ScheduledEventURI = 'http://{0}/metadata/scheduledevents?api-version=2019-01-01' -f $localHostIP 

###############################################
# イベントの取得
###############################################
$ScheduledEvents = Invoke-RestMethod -Headers @{"Metadata"="true"} -URI $ScheduledEventURI -Method get
$json = ConvertTo-Json $ScheduledEvents
Write-Host "Received following events: `n" $json
$Json.Events
foreach($Event in $ScheduledEvents.Events) {
  ###############################################
  # イベントがFrrezeだったら、メモリ保持メンテナンスの通知 
  ###############################################
  if($Event.EventType -eq "Freeze" -eq $Event.EventType -eq "Reboot"){
    Write-Host "メンテナンスが始まります。$($Event.NotBefore)"
  }
}