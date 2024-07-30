##########################
## �p�����[�^�ݒ�
##########################
param (
  [parameter(mandatory=$true)][string]$ConfigFile,
  [switch]$Eventlog=$false,
  [switch]$Stdout=$false
)

##########################
## ���W���[���̃��[�h
##########################
. C:\Scripts\bin\LogController.ps1

##########################
## �Œ�l 
##########################
[bool]$ErrorFlg = $false
[int]$LogCycle = 180
$ErrorActionPreference = "Stop"

##########################
## �x���̕\���}�~
##########################
## Set-Item Env:\SuppressAzurePowerShellBreakingChangeWarnings "true"

##########################
## �֐���`
##########################
## �O���R�}���h���s
Function Invoke-Command($commandTitle, $commandPath, $commandArguments) {
  Try {
    $PSInfo = New-Object System.Diagnostics.ProcessStartInfo
    $PSInfo.FileName = $commandPath
    $PSInfo.RedirectStandardError = $true
    $PSInfo.RedirectStandardOutput = $true
    $PSInfo.UseShellExecute = $false
    $PSInfo.Arguments = $commandArguments
    $Proc = New-Object System.Diagnostics.Process
    $Proc.StartInfo = $PSInfo
    $Proc.Start() | Out-Null
    $Proc.WaitForExit()
    [pscustomobject]@{
        CommandTitle = $commandTitle
        StdOut = $Proc.StandardOutput.ReadToEnd()
        StdErr = $Proc.StandardError.ReadToEnd()
        ExitCode = $Proc.ExitCode
    }
  }
  Catch {
     Exit 9
  }
}

###############################
# LogController �I�u�W�F�N�g����
###############################
if($Stdout -and $Eventlog) {
  $Log = New-Object LogController($true, (Get-ChildItem $MyInvocation.MyCommand.Path).Name)
} elseif($Stdout) {
  $Log = New-Object LogController
} else {
  $LogFilePath = Split-Path $MyInvocation.MyCommand.Path -Parent | Split-Path -Parent | Join-Path -ChildPath log -Resolve
  if($MyInvocation.ScriptName -eq "") {
    $LogBaseName = (Get-ChildItem $MyInvocation.MyCommand.Path).BaseName
  } else {
    $LogBaseName = (Get-ChildItem $MyInvocation.ScriptName).BaseName
  }
  $LogFileName = $LogBaseName + ".log"
  $Log = New-Object LogController($($LogFilePath + "\" + $LogFileName), $false, $true, $LogBaseName, $false)
  $Log.DeleteLog($LogCycle)
  $Log.Info("LogFileName:$($Log.GetLogInfo())")
}

##########################
# �p�����[�^�`�F�b�N
##########################

try {
  ##########################
  # ����擾
  ##########################
  $ConfigPath = Split-Path $MyInvocation.MyCommand.Path -Parent | Split-Path -Parent | Join-Path -ChildPath conf -Resolve
  $ConfigFilePath = $ConfigPath | Join-Path -ChildPath $ConfigFile
  if (($ConfigFilePath) -and (-not $(Test-Path $ConfigFilePath))) {
    $Log.Info("Configuration file path�F" + (Split-Path $ConfigFilePath -Parent))
    $Log.Error("Configuration file does not exist.")
    exit 9 
  } else {
    $Log.Info("Configuration file path�F" + (Split-Path $ConfigFilePath -Parent))
    $Log.Info("Configuration file name�F" + (Get-ChildItem $ConfigFilePath).Name)
    if ($(Test-Path $ConfigFilePath)) { $ConfigInfo = [xml](Get-Content $ConfigFilePath) }
    if(-not $ConfigInfo) { 
      $Log.Error("Can not read configuration file.")
      exit 9 
     } 
  }
    
  if ($ConfigInfo) {
    foreach ($TargetConfig in $ConfigInfo.Configuration.Target) {
      $Log.Info("$($TargetConfig.Title):Start")
      $Log.Info("Testing network connectivity to $($TargetConfig.HostName)")
      $ConResult = Test-NetConnection -ComputerName $TargetConfig.HostName -Port 443 
      if (-not ($ConResult.TcpTestSucceeded)) {
        $Log.Error("Can not access Storage Account")
        $ErrorFlg = $true
        break
      } else {
        $azcopy_path=Join-Path $TargetConfig.CommandPath "azcopy.exe"
        $copy_source=$TargetConfig.SourcePath
        $copy_target=$TargetConfig.TargetPath
        $sas=$TargetConfig.SAS
        $log_level=$TargetConfig.LogLevel
        $plan_path=$TargetConfig.PlanPath
        $log_path=$TargetConfig.LogPath
        
        $Log.Info("azcopy_path:$azcopy_path")
        $Log.Info("copy_source:$copy_source")
        $Log.Info("copy_target:$copy_target")
##        $Log.Info("sas:$sas")
        $Log.Info("log_level:$log_level")
        $Log.Info("plan_path:$plan_path")
        $Log.Info("log_path:$log_path")

        if(-not $(Test-Path (Split-Path $plan_path -Parent))) { New-Item (Split-Path $plan_path -Parent) -ItemType Directory -ErrorAction SilentlyContinue }
        else { Get-ChildItem $plan_path -Include *.log -Recurse | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-1 * $LogCycle) } | Remove-Item -Force }
        if(-not $(Test-Path (Split-Path $log_path -Parent))) { New-Item (Split-Path $log_path -Parent) -ItemType Directory -ErrorAction SilentlyContinue }
        else { Get-ChildItem $plan_path -Include *.log -Recurse | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-1 * $LogCycle) } | Remove-Item -Force }
        $env:AZCOPY_JOB_PLAN_LOCATION="$plan_path"
        $env:AZCOPY_LOG_LOCATION="$log_path"

        $ReturnObj = Invoke-Command $TargetConfig.Title $azcopy_path $("copy ""$copy_source" + "?" + "$sas"" ""$copy_target" + "?" + "$sas"" --overwrite=false --log-level=$log_level")
        if($ReturnObj.ExitCode) {
          $Log.Error($ReturnObj.Stdout)
          exit 9
        } else {
          $Log.Info($ReturnObj.Stdout)
        }
      }
    }
  } else { exit 9 }

  if($ErrorFlg) { exit 9 }
  else { exit 0 }

} catch {
  $Log.Error("�������ɃG���[���������܂����B")
  $Log.Error($("" + $Error[0] | Format-List --DisplayError))
  exit 9 
}
