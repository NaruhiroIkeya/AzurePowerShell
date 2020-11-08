<################################################################################
## Copyright(c) 2020 BeeX Inc. All rights reserved.
## @auther#Naruhiro Ikeya
##
## @name:ServiceControl.ps1
## @summary:Service Start / Stop Function
##          PowerShell Set-ExecutionPolicy RemoteSigned
## @since:2020/11/08
## @version:1.0
## @see:
##
## @param:server: Server Name
## @param:service: Service Name
## @param:mode:start/stop
## @return:0:Success 1:Error
#################################################################################>


Import-Module .\LogController.ps1

Class ServiceController {

  [String]$HostName
  [String]$ServiceName
  [object]$SVCStatus
  [object]$Log

  ServiceController([string] $ServiceName) {
    $this.HostName = "localhost"
    $this.ServiceName = $ServiceName
  }
    
  ServiceController([string] $HostName, [string] $ServiceName) {
    $this.HostName = $HostName
    $this.ServiceName = $ServiceName
  }
  
  [bool] Initialize() {
    $LogFilePath = Convert-Path . | Split-Path -Parent | Join-Path -ChildPath log -Resolve
    $LogFile = "ServiceController.log"
    $this.Log = New-Object LogController($($LogFilePath + "\" + $LogFile), $true)
    if($this.Initialize($this.Log)) {return $true} else {return $false}
  }

  [bool] Initialize([object] $Log) {
    try {
      $this.Log = $Log
      ##########################
      # �T�[�o�[�ڑ��e�X�g
      ##########################
      if (Test-Connection $this.HostName -quiet) {
        $this.SVCStatus = Get-Service $this.ServiceName -ComputerName $this.HostName -ErrorVariable getServiceError -ErrorAction SilentlyContinue
        if ($getServiceError -and ($getServiceError | ForEach-Object {$_.FullyQualifiedErrorId -like "*NoServiceFoundForGivenName*"})) {
          $this.Log.Error("�w�肳�ꂽ�T�[�r�X������܂���B")
          return $false
        }
      } else {
        $this.Log.Error("�w�肳�ꂽ�T�[�o�ɐڑ��ł��܂���B")
        return $false
      } 
    } catch {
      $this.Log.Error("�������ɃG���[���������܂����B")
      $this.Log.Error($("" + $Error[0] | Format-List --DisplayError))
      return $false
    }
    return $true
  }

  [bool]Start() {
    if (-not $this.Log) { if (-not $this.Initialize()) {return $false} }
    do {
      if ($this.GetStaus() -eq "Stopped") {
        $this.SVCStatus = Get-Service $this.ServiceName -ComputerName $this.HostName -ErrorVariable getServiceError -ErrorAction SilentlyContinue | Start-Service -PassThru
        if ($getServiceError -and ($getServiceError | ForEach-Object {$_.FullyQualifiedErrorId -like "*NoServiceFoundForGivenName*"})) {
          $this.Log.Error("�w�肳�ꂽ�T�[�r�X$($this.ServiceName)������܂���B")
          return $false
        }
        if (-not $this.SVCStatus) {
          $this.Log.Error("�T�[�r�X���N���o���܂���ł����B")
          return $false
        }
        Start-Sleep 5
        $this.Log.Info("�T�[�r�X���N�����ł��BStatas = " + $this.SVCStatus)
      }
    } while ($this.GetStatus() -ne "Started")
    $this.Log.Info($this.ServiceName + "�T�[�r�X���N�����܂����B")
    return true
  }

  [bool]Stop() {
    if (-not $this.Log) { if (-not $this.Initialize()) {return $false} }
    do {
      if ($this.GetStatus() -eq "Running") {
        $this.SVCStatus = Get-Service $this.ServiceName -ComputerName $this.HostName -ErrorVariable getServiceError -ErrorAction SilentlyContinue | Stop-Service -PassThru -Force
        if ($getServiceError -and ($getServiceError | ForEach-Object {$_.FullyQualifiedErrorId -like "*NoServiceFoundForGivenName*"})) {
          $this.Log.Error("�w�肳�ꂽ�T�[�r�X$($this.ServiceName)������܂���B")
          return $false
        }
        if (-not $this.SVCStatus) {
          $this.Log.Error("�T�[�r�X���~�o���܂���ł����B")
          return $false
        }
        Start-Sleep 5
        $this.Log.Info("�T�[�r�X���~���ł��BStatas = " + $this.SVCStatus)
      }
    } while ($this.GetStatus() -ne "Stopped")
    $this.Log.Info($this.ServiceName + "�T�[�r�X���~���܂����B")
    return true
  }

  [string]GetStatus() {
    $this.SVCStatus = Get-Service $this.ServiceName -ComputerName $this.HostName -ErrorVariable getServiceError -ErrorAction SilentlyContinue
    if ($getServiceError -and ($getServiceError | ForEach-Object {$_.FullyQualifiedErrorId -like "*NoServiceFoundForGivenName*"})) {
      $this.Log.Error("�w�肳�ꂽ�T�[�r�X$($this.ServiceName)������܂���B")
      return ""
    }
    return $this.SVCStatus.Status
  }
}