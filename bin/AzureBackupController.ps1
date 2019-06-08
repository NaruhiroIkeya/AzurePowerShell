


  ##########################
  # �F�؏��擾
  ##########################
  $SettingFilePath = Split-Path $MyInvocation.MyCommand.Path -Parent | Split-Path -Parent | Join-Path -ChildPath etc -Resolve
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] �ݒ�t�@�C��Path�F" + $SettingFilePath)
  $SettingFile = "AzureCredential.xml"
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] �ݒ�t�@�C�����F" + $SettingFile)

  $Config = [xml](Get-Content (Join-Path $SettingFilePath -ChildPath $SettingFile -Resolve))
  if(-not $Config) { 
    ##########################
    # Azure�ւ̃��O�C��
    ##########################
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Azure�փ��O�C��:�J�n")
    $LoginInfo = Login-AzAccount -Tenant $Config.Configuration.TennantID -WarningAction Ignore
    if(-not $LoginInfo) { 
      Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Azure�փ��O�C���ł��܂���ł����B")
      exit 9
    }
  } else {
    ##########################
    # Azure�ւ̃��O�C��
    ##########################
    Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] �T�[�r�X�v�����V�p���𗘗p��Azure�փ��O�C��:�J�n")
    $secpasswd = ConvertTo-SecureString $Config.Configuration.Key -AsPlainText -Force
    $mycreds = New-Object System.Management.Automation.PSCredential ($Config.Configuration.ApplicationID, $secpasswd)
    $LoginInfo = Login-AzAccount  -ServicePrincipal -Tenant $Config.Configuration.TennantID -Credential $mycreds  -WarningAction Ignore
    if(-not $LoginInfo) { 
      Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Azure�փ��O�C���ł��܂���ł����B")
      exit 9
    }
  }
  Write-Output("`[$(Get-Date -UFormat "%Y/%m/%d %H:%M:%S")`] Azure�փ��O�C��:����")



