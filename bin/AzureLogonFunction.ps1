<################################################################################
## Copyright(c) 2020 BeeX Inc. All rights reserved.
## @auther#Naruhiro Ikeya
##
## @name:AzureLogonFunction.ps1
## @summary:Azure Logon 
##
## @since:2020/05/01
## @version:1.1
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
      if (-not $(Test-Path $this.ConfigPath)) {
        ##########################
        # Azureへのログイン
        ##########################
        $this.log.info("Azureへログイン:開始")
        $LoginInfo = Login-AzAccount
      } elseif ($this.ConfigInfo) {
        if ((-not $this.ConfigInfo.Configuration.Key) -or (-not $this.ConfigInfo.Configuration.ApplicationID)) {
          ##########################
          # Azureへのログイン
          ##########################
          $this.log.info("Azureへログイン:開始")
          $LoginInfo = Login-AzAccount -Tenant $this.ConfigInfo.Configuration.TennantID 
        } else {
          ##########################
          # Azureへのログイン
          ##########################
          $this.ConfigInfo.Configuration.Key
          $this.Log.info("サービスプリンシパルを利用しAzureへログイン:開始")
          $decrypt = ConvertTo-SecureString -String $this.ConfigInfo.Configuration.Key
          $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($decrypt)
          $Password = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
          $SecPasswd = ConvertTo-SecureString $Password -AsPlainText -Force
          $MyCreds = New-Object System.Management.Automation.PSCredential ($this.ConfigInfo.Configuration.ApplicationID, $SecPasswd)
          $LoginInfo = Login-AzAccount -ServicePrincipal -Tenant $this.ConfigInfo.Configuration.TennantID -Credential $MyCreds -WarningAction Ignore
        }
        $Subscription = Get-AzSubscription -SubscriptionId $this.ConfigInfo.Configuration.SubscriptionID | Select-AzSubscription
      }
      if(-not $LoginInfo) { 
        $this.Log.error("Azureへログイン:失敗")
        return $false 
      }
      Enable-AzContextAutosave
      $this.Log.info("Azureへログイン:成功")
      $this.Log.info("Account:" + $LoginInfo.Context.Account.Id)
      $this.Log.info("Subscription:" + $Subscription.Name)
      $this.Log.info("TennantId:" + $LoginInfo.Context.Tenant.Id)
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
