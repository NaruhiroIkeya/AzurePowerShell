<################################################################################
## Copyright(c) 2019 BeeX Inc. All rights reserved.
## @auther#Naruhiro Ikeya
##
## @name:LogController.ps1
## @summary:Log Controller
##
## @since:2019/06/12
## @version:1.0
## @see:
## @parameter
##  1:Stdout：標準出力
##  2:EventLog：イベントログ出力
##  3:FullPath：ファイル出力パス
##
## @return:
################################################################################>

Class LogController {
  [bool] $StdOut
  [bool] $EventLog
  [int] $EventID = 6338
  [String] $EventSource
  [String] $FullPath
  [bool] $Generation
  [string]$LogDir

  LogController() {
    $this.EventLog = $false
    $this.StdOut = $true
  }

  LogController([bool] $EventLog, [string] $EventSource) {
    $this.EventLog = $EventLog
    $this.EventSource = $EventSource
    $this.StdOut = $true

    if ([System.Diagnostics.EventLog]::SourceExists($EventSource) -eq $false) {
        [System.Diagnostics.EventLog]::CreateEventSource($EventSource, "Application")
    }
  }

  LogController([String] $FullPath, [bool]$Generation) {
    $this.FullPath = $FullPath
    $this.Generation = $Generation

    #####################################
    # ログフォルダーが存在しなかったら作成
    #####################################
    $this.LogDir = Split-Path $FullPath -Parent
    if(-not (Test-Path($this.LogDir))) {
      New-Item $this.LogDir -Type Directory
    }
    if($Generation){
      $this.FullPath = $FullPath + ".log"
    } else {
      $this.FullPath = $FullPath + $(Get-Date -UFormat "%Y%m%d%H%M") + ".log"
    }
  }

  LogController([String] $FullPath, [bool]$Generation, [bool] $EventLog, [string] $EventSource, $StdOut) {
    $this.FullPath = $FullPath
    $this.Generation = $Generation
    $this.EventLog = $EventLog
    $this.EventSource = $EventSource
    $this.StdOut = $StdOut

    #####################################
    # ログフォルダーが存在しなかったら作成
    #####################################
    $this.LogDir = Split-Path $FullPath -Parent
    if(-not (Test-Path($this.LogDir))) {
      New-Item $this.LogDir -Type Directory
    }
    if($Generation){
      $this.FullPath = $FullPath + ".log"
    } else {
      $this.FullPath = $FullPath + $(Get-Date -UFormat "%Y%m%d%H%M") + ".log"
    }
  }
   
  [void] info([string] $Message) {
    if($this.StdOut) { [Console]::WriteLine("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] $message") }
    if($this.EventLog) { Write-EventLog -LogName Application -EntryType Information -S $this.EventSource -EventId $this.EventID -Message $Message }
    if($this.FullPath -ne $null) {
      # ログ出力
      Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] INFO $message") | Out-File -FilePath $this.FullPath -Encoding Default -append
    }
  }

  [void] warn([string] $Message) {
    if($this.StdOut) { [Console]::WriteLine("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] $message") }
    if($this.EventLog) { Write-EventLog -LogName Application -EntryType Warning -S $this.EventSource -EventId $this.EventID -Message $Message }
    if($this.FullPath -ne $null) {
      # ログ出力
      Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] WARN $message") | Out-File -FilePath $this.FullPath -Encoding Default -append
    }
  }

  [void] error([string] $Message) {
    if($this.StdOut) { [Console]::WriteLine("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] $message") }
    if($this.EventLog) { Write-EventLog -LogName Application -EntryType Error -S $this.EventSource -EventId $this.EventID -Message $Message }
    if($this.FullPath -ne $null) {
      # ログ出力
      Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] ERROR $message") | Out-File -FilePath $this.FullPath -Encoding Default -append
    }
  }

  [void] RotateLog([int]$Generation) {
    if(-not $this.Generation) { exit }
    [Console]::WriteLine($this.FullPath + " AAA")
    [Console]::WriteLine($Generation)
    for($cntr = $Generation - 0; $cntr -ge 1; $cntr--) {
    [Console]::WriteLine($cntr)
      $LogFile = $this.FullPath + "_" + [string]$Generation + ".log"
      [Console]::WriteLine($LogFile)
      if(Test-Path($Logfile)) {
        Remove-Item $LogFile -Force
        Continue
      } else {
        $LogFile = $this.FullPath + [string]$cntr 
        if(Test-Path($LogFile)){
          Move-Item $LogFile $this.FullPath + ($cntr + 1)
        }
      }
    }
  }

  [void] DeleteLog([int] $Days) {
      $Today = Get-Date
  }

  [string] getLogInfo(){ return [Console]::WriteLine("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] ログファイル名:" + $this.FullPath) }
}