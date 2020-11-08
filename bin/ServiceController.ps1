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
      # サーバー接続テスト
      ##########################
      if (Test-Connection $this.HostName -quiet) {
        $this.SVCStatus = Get-Service $this.ServiceName -ComputerName $this.HostName -ErrorVariable getServiceError -ErrorAction SilentlyContinue
        if ($getServiceError -and ($getServiceError | ForEach-Object {$_.FullyQualifiedErrorId -like "*NoServiceFoundForGivenName*"})) {
          $this.Log.Error("指定されたサービスがありません。")
          return $false
        }
      } else {
        $this.Log.Error("指定されたサーバに接続できません。")
        return $false
      } 
    } catch {
      $this.Log.Error("処理中にエラーが発生しました。")
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
          $this.Log.Error("指定されたサービス$($this.ServiceName)がありません。")
          return $false
        }
        if (-not $this.SVCStatus) {
          $this.Log.Error("サービスを起動出来ませんでした。")
          return $false
        }
        Start-Sleep 5
        $this.Log.Info("サービスを起動中です。Statas = " + $this.SVCStatus)
      }
    } while ($this.GetStatus() -ne "Started")
    $this.Log.Info($this.ServiceName + "サービスを起動しました。")
    return true
  }

  [bool]Stop() {
    if (-not $this.Log) { if (-not $this.Initialize()) {return $false} }
    do {
      if ($this.GetStatus() -eq "Running") {
        $this.SVCStatus = Get-Service $this.ServiceName -ComputerName $this.HostName -ErrorVariable getServiceError -ErrorAction SilentlyContinue | Stop-Service -PassThru -Force
        if ($getServiceError -and ($getServiceError | ForEach-Object {$_.FullyQualifiedErrorId -like "*NoServiceFoundForGivenName*"})) {
          $this.Log.Error("指定されたサービス$($this.ServiceName)がありません。")
          return $false
        }
        if (-not $this.SVCStatus) {
          $this.Log.Error("サービスを停止出来ませんでした。")
          return $false
        }
        Start-Sleep 5
        $this.Log.Info("サービスを停止中です。Statas = " + $this.SVCStatus)
      }
    } while ($this.GetStatus() -ne "Stopped")
    $this.Log.Info($this.ServiceName + "サービスを停止しました。")
    return true
  }

  [string]GetStatus() {
    $this.SVCStatus = Get-Service $this.ServiceName -ComputerName $this.HostName -ErrorVariable getServiceError -ErrorAction SilentlyContinue
    if ($getServiceError -and ($getServiceError | ForEach-Object {$_.FullyQualifiedErrorId -like "*NoServiceFoundForGivenName*"})) {
      $this.Log.Error("指定されたサービス$($this.ServiceName)がありません。")
      return ""
    }
    return $this.SVCStatus.Status
  }
}