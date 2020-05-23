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
# �C�x���g�擾��̐ݒ�
###############################################
$LocalHostIP = "169.254.169.254"
$ScheduledEventURI = 'http://{0}/metadata/scheduledevents?api-version=2019-01-01' -f $LocalHostIP
###############################################
# �C�x���g�o�͐�i�C�x���g���O�j�̐ݒ�
###############################################
$EventSource=$(Get-ChildItem $MyInvocation.MyCommand.Path).Name
$EventID=6339
[hashtable] $EventType = @{1 = "Information"; 2 = "Warning"; 3 = "Error"}
$Message=$null

if ([System.Diagnostics.EventLog]::SourceExists($EventSource) -eq $false) {
  [System.Diagnostics.EventLog]::CreateEventSource($EventSource, "Application")
}

###############################################
# �C�x���g�̎擾
###############################################
$ScheduledEvents = Invoke-RestMethod -Headers @{"Metadata"="true"} -URI $ScheduledEventURI -Method get
if($null -ne $ScheduledEvents) {
  foreach($Event in $ScheduledEvents.Events) {
    ###############################################
    # �C�x���g��Freeze��������A�������ێ������e�i���X�̒ʒm
    ###############################################
    if(($Event.EventStatus -eq "Scheduled") -and ($Evetnt.ResouceType -eq "VirtualMachine") -and ($Event.EventType -ne "Terminate")){
      $JSTTime = [DateTime]$Event.NotBefore
      foreach($Resouce in $Event.Resources) {
        $HostName = $Resouce
        $Message += "HostName:$($HostName) �Ń����e�i���X�i$($Event.EventType)�j���n�܂�܂��B$JSTTime`n"
      }
      $Saverity = 3
    } else {
      $Message += "�X�P�W���[�����ꂽ�����e�i���X������܂���B`n"
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