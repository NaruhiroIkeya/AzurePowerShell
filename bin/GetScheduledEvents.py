#!/usr/bin/python
################################################################################
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
################################################################################

import json
import socket
import urllib.request
import datetime

metadata_url = "http://169.254.169.254/metadata/scheduledevents?api-version=2019-01-01"
this_host = socket.gethostname()

def main():
  req = urllib.request.Request(metadata_url)
  req.add_header('Metadata', 'true')
  resp = urllib.request.urlopen(req)
  data = json.loads(resp.read().decode('utf-8'))

  for evt in data['Events']:
    eventid = evt['EventId']
    status = evt['EventStatus']
    resources = evt['Resources']
    eventtype = evt['EventType']
    resourcetype = evt['ResourceType']
    timestring = evt['NotBefore'].replace(' GMT', '+0000')
    datetime_utc = datetime.datetime.strptime(timestring, "%a, %d %b %Y %H:%M:%S%z")
    datetime_jst = datetime_utc.astimezone(datetime.timezone(datetime.timedelta(hours=+9)))
    NotBefore_jst = datetime.datetime.strftime(datetime_jst, "%a, %d %b %Y %H:%M:%S %Z")
    if status == 'Scheduled' and resourcetype == 'VirtualMachine' and eventtype != 'Terminate':
      for this_host in resources:
        print("Scheduled Event. This host " + this_host + " is scheduled for " + eventtype + " not before " + NotBefore_jst)
        print(json.dumps(data, indent=2))

if __name__ == '__main__':
  main()
