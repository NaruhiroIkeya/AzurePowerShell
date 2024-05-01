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
##  1:Azure Login認証ファイルパス
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
      # 認証情報取得
      ##########################
      if (($this.ConfigPath) -and (-not $(Test-Path $this.ConfigPath))) {
        $this.log.error("認証情報ファイルが存在しません。")
        return $false
      } else {
        $this.log.info("認証情報ファイルパス：" + (Split-Path $this.ConfigPath -Parent))
        $this.log.info("認証情報ファイル名：" + (Get-ChildItem $this.ConfigPath).Name)
        if ($(Test-Path $this.ConfigPath)) { $this.ConfigInfo = [xml](Get-Content $this.ConfigPath) }
        if(-not $this.ConfigInfo) { 
          $this.log.error("既定のファイルから認証情報が読み込めませんでした。")
          return $false
        } 
      }
      return $true
    } catch {
      $this.Log.Error("処理中にエラーが発生しました。")
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
            # Azureへのログイン(ServicePrincipal)
            ##########################
            $this.ConfigInfo.Configuration.Key
            $this.Log.info("Azureへログイン:開始（サービスプリンシパル）")
            $decrypt = ConvertTo-SecureString -String $this.ConfigInfo.Configuration.Key
            $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($decrypt)
            $Password = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
            $SecPasswd = ConvertTo-SecureString $Password -AsPlainText -Force
            $MyCreds = New-Object System.Management.Automation.PSCredential($this.ConfigInfo.Configuration.ApplicationID, $SecPasswd)
            $LoginInfo = Connect-AzAccount -ServicePrincipal -Tenant $this.ConfigInfo.Configuration.TennantID -Credential $MyCreds -WarningAction Ignore
            Enable-AzContextAutosave
          }
          "ManagedID" {
            $this.Log.info("Azureへログイン:開始（マネージドID）")
            $LoginInfo = Connect-AzAccount -Identity
          }
          "User" {
            ##########################
            # Azureへのログイン(ユーザー認証)
            ##########################
            $this.log.info("Azureへログイン:開始（ユーザー認証）")
            $LoginInfo = Connect-AzAccount -Tenant $this.ConfigInfo.Configuration.TennantID 
          }
          default {
            $this.Log.error("Azureへログイン:失敗:認証方式設定不備")
            return $false 
          }
        }
        ##########################
        # サブスクリプションの変更
        ##########################
        if($this.ConfigInfo.Configuration.SubscriptionID) {
          $Subscription = Get-AzSubscription -SubscriptionId $this.ConfigInfo.Configuration.SubscriptionID | Select-AzSubscription
          if(-not $Subscription) {
            $this.Log.info("SubscriptionIDが存在しません。:" + $this.ConfigInfo.Configuration.SubscriptionID)
          }
        }
      }
      if(-not $LoginInfo -and -not $Subscription) { 
        $this.Log.error("Azureへログイン:失敗")
        return $false 
      }
      if($LoginInfo) {
        $this.Log.info("Azureへログイン:成功")
        $this.Log.info("TennantName:" + $LoginInfo.Context.Tenant.Name)
        $this.Log.info("TennantNameId:" + $LoginInfo.Context.Tenant.Id)
        $this.Log.info("SubscriptionName:" + $Subscription.Subscription.Name)
        $this.Log.info("SubscriptionId:" + $Subscription.Subscription.Id)
        $this.Log.info("Account:" + $Subscription.Account.Id)
      }
      return $true
    } catch {
      $this.Log.Error("処理中にエラーが発生しました。")
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
      $this.log.info("認証情報ファイルパス：" + (Split-Path $this.ConfigPathSecureString -Parent))
      $this.log.info("認証情報ファイル名：" + (Get-ChildItem $this.ConfigPathSecureString).Name)
      $this.ConfigInfo.Save($this.ConfigPathSecureString)
      return $true
    } catch {
      $this.Log.Error("処理中にエラーが発生しました。")
      $this.Log.Error($_.Exception)
      return $false
    }
  }
}
