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
# �C�x���g�擾��̐ݒ�
###############################################
$LocalHostIP = "169.254.169.254"
$ScheduledEventURI = 'http://{0}/metadata/scheduledevents?api-version=2019-01-01' -f $localHostIP 

###############################################
# �C�x���g�̎擾
###############################################
$ScheduledEvents = Invoke-RestMethod -Headers @{"Metadata"="true"} -URI $ScheduledEventURI -Method get
$json = ConvertTo-Json $ScheduledEvents
Write-Host "Received following events: `n" $json
$Json.Events
foreach($Event in $ScheduledEvents.Events) {
  ###############################################
  # �C�x���g��Frreze��������A�������ێ������e�i���X�̒ʒm 
  ###############################################
  if($Event.EventType -eq "Freeze" -eq $Event.EventType -eq "Reboot"){
    Write-Host "�����e�i���X���n�܂�܂��B$($Event.NotBefore)"
  }
}