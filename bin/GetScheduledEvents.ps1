<################################################################################
## Copyright(c) 2020 BeeX Inc. All rights reserved.
## @auther#Naruhiro Ikeya
##
## @name:GetSheduledEvents.ps1
## @summary:Azure VM Sheduled Events(Azure Metadata Service)
##
## @since:2020/05/21
## @version:1.0
## @see:
## @parameter
##
## @return:0:Success 9:Error
################################################################################>

###############################################
# イベント取得先の設定
###############################################
$LocalHostIP = "169.254.169.254"
$ScheduledEventURI = 'http://{0}/metadata/scheduledevents?api-version=2019-01-01' -f $LocalHostIP
###############################################
# イベント出力先（イベントログ）の設定
###############################################
$EventSource=$(Get-ChildItem $MyInvocation.MyCommand.Path).Name
$EventID=6339
[hashtable] $EventType = @{1 = "Information"; 2 = "Warning"; 3 = "Error"}
$Message=$null

if ([System.Diagnostics.EventLog]::SourceExists($EventSource) -eq $false) {
  [System.Diagnostics.EventLog]::CreateEventSource($EventSource, "Application")
}

###############################################
# イベントの取得
###############################################
$ScheduledEvents = Invoke-RestMethod -Headers @{"Metadata"="true"} -URI $ScheduledEventURI -Method get
if($null -ne $ScheduledEvents) {
  foreach($Event in $ScheduledEvents.Events) {
    ###############################################
    # イベントがFreezeだったら、メモリ保持メンテナンスの通知
    ###############################################
    if(($Event.EventStatus -eq "Scheduled") -and ($Evetnt.ResouceType -eq "VirtualMachine") -and ($Event.EventType -ne "Terminate")){
      $JSTTime = [DateTime]$Event.NotBefore
      foreach($Resouce in $Event.Resources) {
        $HostName = $Resouce
        $Message += "HostName:$($HostName) でメンテナンス（$($Event.EventType)）が始まります。$JSTTime`n"
      }
      $Saverity = 3
    } else {
      $Message += "スケジュールされたメンテナンスがありません。`n"
      $Saverity = 1
    }
    $json = ConvertTo-Json $ScheduledEvents
    $Message += "Received following events: `n" + $json + "`n"
    Write-EventLog -LogName Application -EntryType $EventType[$Saverity] -S $EventSource -EventId $EventID -Message $Message
  }
}else {
 exit 9
}
exit 0