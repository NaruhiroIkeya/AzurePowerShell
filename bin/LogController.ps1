<################################################################################
## Copyright(c) 2020 BeeX Inc. All rights reserved.
## @auther#Naruhiro Ikeya
##
## @name:LogController.ps1
## @summary:Log Controller
##
## @since:2019/06/12
## @version:1.0
## @see:
## @parameter
##  1:Stdout�F�W���o��
##  2:EventLog�F�C�x���g���O�o��
##  3:FullPath�F�t�@�C���o�̓p�X
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
  [hashtable] $Saverity = @{info = 1; warn = 2; err = 3}
  [hashtable] $EventType = @{1 = "Information"; 2 = "Warning"; 3 = "Error"}
  [hashtable] $LogType = @{1 = "INFO"; 2 = "WARN"; 3 = "ERROR"}

  #####################################
  # �W���o�͂̂�
  #####################################
  LogController() {
    $this.EventLog = $false
    $this.StdOut = $true
  }

  #####################################
  # �W���o�� + �C�x���g���O
  #####################################
  LogController([bool] $EventLog, [string] $EventSource) {
    $this.EventLog = $EventLog
    $this.EventSource = $EventSource
    $this.StdOut = $true

    #####################################
    # EventLog�������ݗp�\�[�X���o�^
    #####################################
    if($EventLog -and (-not $EventSource)) { $this.EventSource=$(Get-ChildItem $MyInvocation.MyCommand.Path).Name } 
    if($EventLog -and (-not $EventSource)) {
      if ([System.Diagnostics.EventLog]::SourceExists($EventSource) -eq $false) {
          [System.Diagnostics.EventLog]::CreateEventSource($EventSource, "Application")
      }
    }
  }

  #####################################
  # �W���o�� + �t�@�C���o��
  #####################################
  LogController([String] $FullPath, [bool]$Generation) {
    $this.FullPath = $FullPath
    $this.Generation = $Generation
    $this.StdOut = $true

    $this.InitializeLog()
  }

  #####################################
  # �W���o�� / �t�@�C���o�� / �C�x���g���O
  #####################################
  LogController([String] $FullPath, [bool]$Generation, [bool] $EventLog, [string] $EventSource, $StdOut) {
    $this.FullPath = $FullPath
    $this.Generation = $Generation
    $this.EventLog = $EventLog
    $this.EventSource = $EventSource
    $this.StdOut = $StdOut

    #####################################
    # EventLog�������ݗp�\�[�X���o�^
    #####################################
    if($EventLog -and (-not $EventSource)) { $this.EventSource=$(Get-ChildItem $MyInvocation.MyCommand.Path).Name } 
    if($EventLog -and $EventSource) {
      if ([System.Diagnostics.EventLog]::SourceExists($EventSource) -eq $false) {
          [System.Diagnostics.EventLog]::CreateEventSource($EventSource, "Application")
      }
    }

    $this.InitializeLog()
  }
   
  [void] info([string] $Message) {
    $this.Log($message, $this.Saverity.info)
  }

  [void] warn([string] $Message) {
    $this.Log($message, $this.Saverity.warn)
  }

  [void] error([string] $Message) {
    $this.Log($message, $this.Saverity.err)
  }

  hidden [void] Log([string]$Message, [int]$Saverity) {
    #if($this.StdOut) { [Console]::WriteLine("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] $message") }
    if($this.StdOut) { Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $this.LogType[$Saverity]  + " " + $message) | Out-Host }
    if($this.EventLog) { Write-EventLog -LogName Application -EntryType $this.EventType[$Saverity] -S $this.EventSource -EventId $this.EventID -Message $Message }
    if($null -ne $this.FullPath) {
      # ���O�o��
      Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] " + $this.LogType[$Saverity]  + " " + $message) | Out-File -FilePath $this.FullPath -Encoding Default -append
    }
  }

  #####################################
  # ���O�t�@�C��������
  #####################################
  hidden [void] InitializeLog() {
    #####################################
    # ���O�t�H���_�[�����݂��Ȃ�������쐬
    #####################################
    $this.LogDir = Split-Path $this.FullPath -Parent
    if(-not (Test-Path($this.LogDir))) {
      New-Item $this.LogDir -Type Directory
    }
    if(-not $this.Generation) {
      $this.FullPath = $($this.LogDir + "\" + [System.IO.Path]::GetFileNameWithoutExtension($this.FullPath) + "_" + (Get-Date -UFormat "%Y%m%d%H%M") + [System.IO.Path]::GetExtension($this.FullPath))
    }
  }

  #####################################
  # ���O���[�e�[�V����
  #####################################
  [void] RotateLog([int]$Generation) {
    $this.info("���O���[�e�[�V�����������J�n���܂��B")
    if(-not $this.Generation) { exit }
    foreach($cntr in ($Generation)..1) {
      if($cntr -ne 1) {
        $SourceFile = $($this.LogDir + "\" + (Get-ChildItem $this.FullPath).BaseName + "_" + $($cntr - 1) + (Get-ChildItem $this.FullPath).Extension)
        $TargetFile = $($this.LogDir + "\" + (Get-ChildItem $this.FullPath).BaseName + "_" + $($cntr) + (Get-ChildItem $this.FullPath).Extension)
      } else {
        $SourceFile = $($this.LogDir + "\" + (Get-ChildItem $this.FullPath).BaseName + (Get-ChildItem $this.FullPath).Extension)
        $TargetFile = $($this.LogDir + "\" + (Get-ChildItem $this.FullPath).BaseName + "_" + $($cntr) + (Get-ChildItem $this.FullPath).Extension)
      }
      if((Test-Path($TargetFile)) -and ($cntr -eq $Generation)) {
        Remove-Item $TargetFile -Force
        Move-Item $SourceFile $TargetFile
        Continue
      } elseif((Test-Path($SourceFile)) -and (-not (Test-Path($TargetFile)))) {
        Move-Item $SourceFile $TargetFile
      }
    }
    $this.info("���O���[�e�[�V�����������������܂����B")
  }

  #####################################
  # �ߋ����O�폜
  #####################################
  [void] DeleteLog([int] $Days) {
    $this.info("���O�폜�������J�n���܂��B")
    Get-ChildItem -Path $this.LogDir | Where-Object {($_.Name -like $((Get-ChildItem $this.FullPath).BaseName)) -and ($_.Mode -eq "-a----") -and ($_.CreationTime -lt (Get-Date).AddDays(-1 * $Days))} | Remove-Item -Recurse -Force
    $this.info("���O�폜�������������܂����B")
  }

  #####################################
  # ���O�t�@�C�����擾
  #####################################
  [string] getLogInfo(){ return $this.FullPath }
}