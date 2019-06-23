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
##  1:Azure Login認証ファイルパス
##
## @return:0:Success 9:エラー終了 / 99:Exception
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
      # 認証情報取得
      ##########################
      $this.log.info("認証情報ファイルパス：" + (Split-Path $this.ConfigPath -Parent))
      $this.log.info("認証情報ファイル名：" + (Get-ChildItem $this.ConfigPath).Name)
      $this.ConfigInfo = [xml](Get-Content $this.ConfigPath)
      if(-not $this.ConfigInfo) { 
        $this.log.error("既定のファイルから認証情報が読み込めませんでした。")
        return $false
      } else { return $true }
    } catch {
      $this.Log.Error("処理中にエラーが発生しました。")
      $this.Log.Error($("" + $Error[0] | Format-List --DisplayError))
      return $false
    }
  }

  [bool] Logon() {
    try {
      if (-not $this.Log) { $this.Initialize() }
      if (-not $this.ConfigInfo.Configuration.Key) {
        ##########################
        # Azureへのログイン
        ##########################
        $this.log.info("Azureへログイン:開始")
        $LoginInfo = Login-AzAccount -Tenant $this.ConfigInfo.Configuration.TennantID -WarningAction Ignore
      } else {
        ##########################
        # Azureへのログイン
        ##########################
        $this.ConfigInfo.Configuration.Key
        $this.Log.info("サービスプリンシパルを利用しAzureへログイン:開始")
        $SecPasswd = ConvertTo-SecureString $this.ConfigInfo.Configuration.Key -AsPlainText -Force
        $MyCreds = New-Object System.Management.Automation.PSCredential ($this.ConfigInfo.Configuration.ApplicationID, $secpasswd)
        $LoginInfo = Login-AzAccount  -ServicePrincipal -Tenant $this.ConfigInfo.Configuration.TennantID -Credential $MyCreds  -WarningAction Ignore
      }
      if(-not $LoginInfo) { 
        $this.Log.error("Azureへログイン:失敗")
        return $false   
      }
      Enable-AzContextAutosave
      $this.Log.info("Azureへログイン:成功")
      return $true
    } catch {
      $this.Log.Error("処理中にエラーが発生しました。")
      $this.Log.Error($_.Exception)
      exit $false
    }
  }
}
