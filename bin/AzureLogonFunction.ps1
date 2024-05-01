<################################################################################
## Copyright(c) 2020 BeeX Inc. All rights reserved.
## @auther#Naruhiro Ikeya
##
## @name:AzureLogonFunction.ps1
## @summary:Azure Logon 
##
## @since:2024/05/01
## @version:1.2
## @see:
## @parameter
##  1:Azure Login�F�؃t�@�C���p�X
##
## @return:$true:Success $false:Error 
################################################################################>

Import-Module .\LogController.ps1

Class AzureLogonFunction {
  
  [string]$ConfigPath
  [string]$ConfigPathSecureString
  [object]$ConfigInfo
  [object]$Log

  AzureLogonFunction([string] $ConfigPath) {
    $this.ConfigPath = $ConfigPath
  }

  AzureLogonFunction([string] $FullPath, [string] $FileName) {
    $this.ConfigPath = $FullPath + "/" + $FileName
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
      if (($this.ConfigPath) -and (-not $(Test-Path $this.ConfigPath))) {
        $this.log.error("�F�؏��t�@�C�������݂��܂���B")
        return $false
      } else {
        $this.log.info("�F�؏��t�@�C���p�X�F" + (Split-Path $this.ConfigPath -Parent))
        $this.log.info("�F�؏��t�@�C�����F" + (Get-ChildItem $this.ConfigPath).Name)
        if ($(Test-Path $this.ConfigPath)) { $this.ConfigInfo = [xml](Get-Content $this.ConfigPath) }
        if(-not $this.ConfigInfo) { 
          $this.log.error("����̃t�@�C������F�؏�񂪓ǂݍ��߂܂���ł����B")
          return $false
        } 
      }
      return $true
    } catch {
      $this.Log.Error("�������ɃG���[���������܂����B")
      $this.Log.Error($("" + $Error[0] | Format-List --DisplayError))
      return $false
    }
  }

  [bool] Logon() {
    try {
      $LoginInfo = $null
      $Subscription = $null
      if (-not $this.Log) { if (-not $this.Initialize()) {return $false} }
      if ($this.ConfigInfo) {
        switch ($this.ConfigInfo.Configuration.AuthenticationMethod) {
          "ServicePrincipal" {
            ##########################
            # Azure�ւ̃��O�C��(ServicePrincipal)
            ##########################
            $this.ConfigInfo.Configuration.Key
            $this.Log.info("Azure�փ��O�C��:�J�n�i�T�[�r�X�v�����V�p���j")
            $decrypt = ConvertTo-SecureString -String $this.ConfigInfo.Configuration.Key
            $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($decrypt)
            $Password = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
            $SecPasswd = ConvertTo-SecureString $Password -AsPlainText -Force
            $MyCreds = New-Object System.Management.Automation.PSCredential($this.ConfigInfo.Configuration.ApplicationID, $SecPasswd)
            $LoginInfo = Connect-AzAccount -ServicePrincipal -Tenant $this.ConfigInfo.Configuration.TennantID -Credential $MyCreds -WarningAction Ignore
            Enable-AzContextAutosave
          }
          "ManagedID" {
            $this.Log.info("Azure�փ��O�C��:�J�n�i�}�l�[�W�hID�j")
            $LoginInfo = Connect-AzAccount -Identity
          }
          "User" {
            ##########################
            # Azure�ւ̃��O�C��(���[�U�[�F��)
            ##########################
            $this.log.info("Azure�փ��O�C��:�J�n�i���[�U�[�F�؁j")
            $LoginInfo = Connect-AzAccount -Tenant $this.ConfigInfo.Configuration.TennantID 
          }
          default {
            $this.Log.error("Azure�փ��O�C��:���s:�F�ؕ����ݒ�s��")
            return $false 
          }
        }
        ##########################
        # �T�u�X�N���v�V�����̕ύX
        ##########################
        if($this.ConfigInfo.Configuration.SubscriptionID) {
          $Subscription = Get-AzSubscription -SubscriptionId $this.ConfigInfo.Configuration.SubscriptionID | Select-AzSubscription
          if(-not $Subscription) {
            $this.Log.info("SubscriptionID�����݂��܂���B:" + $this.ConfigInfo.Configuration.SubscriptionID)
          }
        }
      }
      if(-not $LoginInfo -and -not $Subscription) { 
        $this.Log.error("Azure�փ��O�C��:���s")
        return $false 
      }
      if($LoginInfo) {
        $this.Log.info("Azure�փ��O�C��:����")
        $this.Log.info("TennantName:" + $LoginInfo.Context.Tenant.Name)
        $this.Log.info("TennantNameId:" + $LoginInfo.Context.Tenant.Id)
        $this.Log.info("SubscriptionName:" + $Subscription.Subscription.Name)
        $this.Log.info("SubscriptionId:" + $Subscription.Subscription.Id)
        $this.Log.info("Account:" + $Subscription.Account.Id)
      }
      return $true
    } catch {
      $this.Log.Error("�������ɃG���[���������܂����B")
      $this.Log.Error($_.Exception)
      return $false
    }
  }

  [bool] ConvertSecretKeytoSecureString([string] $NewCredFileName) {
    try {
      if (-not $this.Log) { if (-not $this.Initialize()) {return $false} }
      $Secure = ConvertTo-SecureString -String $this.ConfigInfo.Configuration.Key -AsPlainText -Force
      $Encrypt = ConvertFrom-SecureString -SecureString $Secure
      $this.Log.info($Encrypt) 
      $this.ConfigInfo.Configuration.Key = [string] $Encrypt
      $this.ConfigPathSecureString = $(Split-Path $this.ConfigPath -Parent) + "\" + $NewCredFileName
      $this.log.info("�F�؏��t�@�C���p�X�F" + (Split-Path $this.ConfigPathSecureString -Parent))
      $this.log.info("�F�؏��t�@�C�����F" + (Get-ChildItem $this.ConfigPathSecureString).Name)
      $this.ConfigInfo.Save($this.ConfigPathSecureString)
      return $true
    } catch {
      $this.Log.Error("�������ɃG���[���������܂����B")
      $this.Log.Error($_.Exception)
      return $false
    }
  }
}
