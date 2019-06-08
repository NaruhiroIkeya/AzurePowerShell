


  ##########################
  # 認証情報取得
  ##########################
  $SettingFilePath = Split-Path $MyInvocation.MyCommand.Path -Parent | Split-Path -Parent | Join-Path -ChildPath etc -Resolve
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] 設定ファイルPath：" + $SettingFilePath)
  $SettingFile = "AzureCredential.xml"
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] 設定ファイル名：" + $SettingFile)

  $Config = [xml](Get-Content (Join-Path $SettingFilePath -ChildPath $SettingFile -Resolve))
  if(-not $Config) { 
    ##########################
    # Azureへのログイン
    ##########################
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Azureへログイン:開始")
    $LoginInfo = Login-AzAccount -Tenant $Config.Configuration.TennantID -WarningAction Ignore
    if(-not $LoginInfo) { 
      Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Azureへログインできませんでした。")
      exit 9
    }
  } else {
    ##########################
    # Azureへのログイン
    ##########################
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] サービスプリンシパルを利用しAzureへログイン:開始")
    $secpasswd = ConvertTo-SecureString $Config.Configuration.Key -AsPlainText -Force
    $mycreds = New-Object System.Management.Automation.PSCredential ($Config.Configuration.ApplicationID, $secpasswd)
    $LoginInfo = Login-AzAccount  -ServicePrincipal -Tenant $Config.Configuration.TennantID -Credential $mycreds  -WarningAction Ignore
    if(-not $LoginInfo) { 
      Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Azureへログインできませんでした。")
      exit 9
    }
  }
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Azureへログイン:完了")



