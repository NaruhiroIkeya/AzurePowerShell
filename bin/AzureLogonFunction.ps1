<################################################################################
## Copyright(c) 2019 BeeX Inc. All rights reserved.
## @auther#Naruhiro Ikeya
##
## @name:AzureLogonFunction.ps1
## @summary:Azure Logon 
##
## @since:2019/06/04
## @version:1.0
## @see:
## @parameter
##  1:Azure Login�F�؃t�@�C���p�X
##
## @return:0:Success 9:�G���[�I�� / 99:Exception
################################################################################>

Import-Module .\LogController.ps1

Class AzureLogonFunction {
  
  [string]$ConfigPath
  [object]$ConfigInfo
  [object]$Log

  AzureLogonFunction([string] $ConfigPath) {
    $this.ConfigPath = $ConfigPath
  }

  [bool] Initialize() {
    $LogFilePath = Convert-Path . | Split-Path -Parent | Join-Path -ChildPath log -Resolve
    $LogFile = "AzureLogonFunction.log"
    $this.Log = New-Object LogController($($LogFilePath + "\" + $LogFile), $true)
    if($this.Initialize($this.Log)) {return $true} else {return $false}
  }

  [bool] Initialize([object] $Log) {
    try {
      $this.Log = $Log
      ##########################
      # �F�؏��擾
      ##########################
      $this.log.info("�F�؏��t�@�C���p�X�F" + (Split-Path $this.ConfigPath -Parent))
      $this.log.info("�F�؏��t�@�C�����F" + (Get-ChildItem $this.ConfigPath).Name)
      $this.ConfigInfo = [xml](Get-Content $this.ConfigPath)
      if(-not $this.ConfigInfo) { 
        $this.log.error("����̃t�@�C������F�؏�񂪓ǂݍ��߂܂���ł����B")
        return $false
      } else { return $true }
    } catch {
      $this.Log.Error("�������ɃG���[���������܂����B")
      $this.Log.Error($("" + $Error[0] | Format-List --DisplayError))
      return $false
    }
  }

  [bool] Logon() {
    try {
      if (-not $this.Log) { $this.Initialize() }
      if (-not $this.ConfigInfo.Configuration.Key) {
        ##########################
        # Azure�ւ̃��O�C��
        ##########################
        $this.log.info("Azure�փ��O�C��:�J�n")
        $LoginInfo = Login-AzAccount -Tenant $this.ConfigInfo.Configuration.TennantID -WarningAction Ignore
      } else {
        ##########################
        # Azure�ւ̃��O�C��
        ##########################
        $this.ConfigInfo.Configuration.Key
        $this.Log.info("�T�[�r�X�v�����V�p���𗘗p��Azure�փ��O�C��:�J�n")
        $SecPasswd = ConvertTo-SecureString $this.ConfigInfo.Configuration.Key -AsPlainText -Force
        $MyCreds = New-Object System.Management.Automation.PSCredential ($this.ConfigInfo.Configuration.ApplicationID, $secpasswd)
        $LoginInfo = Login-AzAccount  -ServicePrincipal -Tenant $this.ConfigInfo.Configuration.TennantID -Credential $MyCreds  -WarningAction Ignore
      }
      if(-not $LoginInfo) { 
        $this.Log.error("Azure�փ��O�C��:���s")
        return $false   
      }
      Enable-AzContextAutosave
      $this.Log.info("Azure�փ��O�C��:����")
      return $true
    } catch {
      $this.Log.Error("�������ɃG���[���������܂����B")
      $this.Log.Error($_.Exception)
      exit $false
    }
  }
}
