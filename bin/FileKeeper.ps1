<################################################################################
## Copyright(c) 2024 BeeX Inc. All rights reserved.
## @auther#Naruhiro Ikeya
##
## @name:FileKeeper.ps1
## @summary:External Storage File Management 
##
## @since:2023/10/10
## @version:1.1
## @see:
## @parameter
##  1:定義ファイル
##  2:イベントログ書き込み
##  3:標準出力
##
## @return:0:Success 1:パラメータエラー  9:Exception
################################################################################>

##########################
## パラメータ設定
##########################
param (
  [parameter(mandatory=$true)][string]$ConfigFile,
  [switch]$Eventlog=$false,
  [switch]$Stdout=$false
)

##########################
## モジュールのロード
##########################
. .\LogController.ps1

##########################
## 固定値 
##########################
[bool]$ErrorFlg = $false
$ErrorActionPreference = "Stop"

##########################
## 警告の表示抑止
##########################
## Set-Item Env:\SuppressAzurePowerShellBreakingChangeWarnings "true"

##########################
## 関数定義
##########################
## 外部コマンド実行
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
    } | Format-List
  }
  Catch {
     Exit 9
  }
}

##########################
## 関数定義
##########################
## ファイル一覧取得
Function Get-FileList($Path, $Files) {

  $FullPath = Join-Path $Path $Files
  $ReturnObj = Get-ChildItem $FullPath
  if($ReturnObj) {
    foreach($File in $ReturnObj) {
      $Log.Info($(Join-Path $Path $File.Name))
    }
  } else {
    $Log.Error("ファイル一覧の取得に失敗しました。")
  }
}

##########################
# 関数定義
##########################
# 期限切れファイルの削除
Function Remove-ExpiredFiles($Path, $FileExt, $Term) {

  $ErrorFlg = $false
  $Counter = 1
  $Log.Info("対象フォルダ:$($Path)")
  $Log.Info("ファイルローテーション開始:$($Term)日以前のファイルを削除します。")
  $ReturnObj = Get-ChildItem -Path $Path -Recurse | Where-Object{($_.Name -match $("." + $FileExt)) -and  ($_.CreationTime -lt (Get-Date).AddDays(-1 * $Term)) -and $(! $_.PSIsContainer) } | Sort-Object -Property CreationTime
  $Log.Info("対象オブジェクト数:$($ReturnObj.Count)")
  foreach($DeleteFile in $ReturnObj) {
    if($DeleteFile) {
      $Log.Info("$("{0:0000}" -f $Counter):ファイル名:$($DeleteFile.FullName):	作成日:$($DeleteFile.CreationTime)")
      $Counter++
    } else {
      $Log.Warm("Null Objects")
      $ErrorFlg = $true
    }
  }

  foreach($DeleteFile in $ReturnObj) {
    if($DeleteFile) {
      Remove-Item $DeleteFile.FullName -Force -ErrorAction Ignore
    } else {
      $Log.Warm("Null Objects")
      $ErrorFlg = $true
    }
  }
  if($ErrorFlg) { return 9 } else { return 0 }
}

##########################
# 関数定義
##########################
# 空フォルダの削除
Function Remove-EmptyFolders($Path) {

  $Log.Info("空フォルダの削除")
  $ReturnObj = Invoke-Command "for" $env:comspec "/C FOR /f `"delims=`" %d in ('dir `"$Path`" /ad /b /s ^| sort /r') do @ECHO `"%d`""
  if(-not $ReturnObj.ExitCode) {
    $Log.Info("削除対象フォルダ`r`n$($ReturnObj.StdOut)")
    $ReturnObj = Invoke-Command "for" $env:comspec "/C FOR /f `"delims=`" %d in ('dir `"$Path`" /ad /b /s ^| sort /r') do @RD `"%d`" /q 2>nul"
    if(-not $ReturnObj.ExitCode) {
      $Log.Info("空フォルダを削除しました。")
    } else {
      $Log.Info("空フォルダがありませんでした。")
      return 0
    }
  } else {
    $Log.Warn("$($ReturnObj.StdErr)")
    return 9
  }
  return 0
}

###############################
# LogController オブジェクト生成
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
  $Log.DeleteLog($SaveDays)
  $Log.Info("ログファイル名:$($Log.GetLogInfo())")
}

##########################
# パラメータチェック
##########################

try {
  ##########################
  # 制御取得
  ##########################
  if(($ConfigFile) -and (-not $(Test-Path $ConfigFile))) {
    $Log.Error("制御ファイルが存在しません。")
    exit 9 
  } else {
    $Log.Info("制御ファイルパス：" + (Split-Path $ConfigFile -Parent))
    $Log.Info("制御ファイル名：" + (Get-ChildItem $ConfigFile).Name)
    if($(Test-Path $ConfigFile)) { $ConfigInfo = [xml](Get-Content $ConfigFile) }
    if(-not $ConfigInfo) { 
      $Log.Error("既定のファイルから制御情報が読み込めませんでした。")
      exit 9 
     } 
  }
    
  if($ConfigInfo) {
    foreach($TargetConfig in $ConfigInfo.Configuration.Target) {
      $MountFlg = $false
      $Log.Info("$($TargetConfig.Title):開始")
      $Log.Info("$($TargetConfig.RemoteHost)に接続します。")
      $ConResult = Test-NetConnection -ComputerName $TargetConfig.RemoteHost -Port 445
      if(-not ($ConResult.TcpTestSucceeded)) {
        $Log.Error("共有ディスクに接続できませんでした。")
        $ErrorFlg = $true
        break
      } else {
        if($DriveInfo = Get-PSDrive -Name $TargetConfig.RemoteDrive -ErrorAction Ignore) {
          $MountFlg = $true
          $Log.Info("$($DriveInfo.Name)はマウントされています。")
        } else {
          $Log.Info("\\$($TargetConfig.RemoteHost)\$($TargetConfig.RemotePath)を$($TargetConfig.RemoteDrive)ドライブにマウントします。")
          # 再起動時にドライブが維持されるように、パスワードを保存する
          if(-not ($cred = Get-StoredCredential -Target $($TargetConfig.RemoteHost))) {
            $Result = New-StoredCredential -Target $($TargetConfig.RemoteHost) -UserName $($TargetConfig.RemoteUser) -Password $($TargetConfig.RemotePass) -Persist Enterprise
            $Log.Info("$($Result.Comment)")
          }
          # 共有フォルダをドライブをマウントする
          $SecurePass = ConvertTo-SecureString $TargetConfig.RemotePass -AsPlainText -Force
          $cred =  New-Object System.Management.Automation.PSCredential $TargetConfig.RemoteUser, $SecurePass
          if($Result = New-PSDrive -Name $TargetConfig.RemoteDrive -PSProvider FileSystem -Root "\\$($TargetConfig.RemoteHost)\$($TargetConfig.RemotePath)" -Persist -Credential $cred -ErrorAction Ignore) {
            $Log.Info("\\$($TargetConfig.RemoteHost)\$($TargetConfig.RemotePath)を$($TargetConfig.RemoteDrive)ドライブにマウントしました。")
          } else {
            $Log.Info("共有ディスクのマウントに失敗しました。")
            $ErrorFlg = $true
            break
          }
        }
      }

      switch($TargetConfig.Mode) {
        "Mirror" {
          if($ConResult.TcpTestSucceeded) {
            ##########################
            # 退避処理開始
            ##########################

            ##########################
            # ローカルファイル一覧
           ##########################
            $SourcePath = "$($TargetConfig.LocalPath)"
            $Log.Info("コピー元フォルダ:$SourcePath")
            Get-FileList $SourcePath "*.$($TargetConfig.FileExt)"

            ##########################
            # リモートファイル一覧
            ##########################
            $TargetPath = "$($TargetConfig.RemoteDrive):"
            $Log.Info("コピー先フォルダ:$TargetPath")
            Get-FileList $TargetPath "*.$($TargetConfig.FileExt)"

            ##########################
            # ファイルコピー
            ##########################
            $ReturnObj = Invoke-Command "robocopy" $env:comspec "/C ROBOCOPY `"$SourcePath`" $TargetPath /MIR /DCOPY:DAT /NP /MT:8"
            switch($ReturnObj.ExitCode) {
              # コピーしたファイルがない
              0 {
                $Log.Info("コピー対象のファイルがありませんでした。")
                $Log.Info("ファイルコピー結果`r`n$($ReturnObj.StdOut)")
                break
              }
              # コピーしたファイルがある
              ({$_ -ge 1 -and $_ -le 8}) {
                $Log.Info("ファイルコピー結果`r`n$($ReturnObj.StdOut)")
                break
              }
              # エラーを伴うコピーしたファイルがある。
              ({$_ -gt 8}) {
                $Log.Info("エラーが発生しました。")
                $Log.Info("ファイルコピー結果`r`n$($ReturnObj.StdOut)")
                $ErrorFlg = $true
                break
              }
              default {
                $Log.Info("Other")
              }
            }
            ##########################
            # ローカルファイル一覧
            ##########################
            Get-FileList $SourcePath "*.$($TargetConfig.FileExt)"

            ##########################
            # リモートファイル一覧
            ##########################
            Get-FileList $TargetPath "*.$($TargetConfig.FileExt)"

          }
        }

        "DateDirectory" {
          ##########################
          # 退避処理開始
          ##########################
          if($ConResult.TcpTestSucceeded) {

            ##########################
            # ローカルファイル一覧
            ##########################
            $SourcePath = "$($TargetConfig.LocalPath)"
            $Log.Info("コピー元フォルダ:$SourcePath")
            Get-FileList $SourcePath "*.$($TargetConfig.FileExt)"

            ##########################
            # リモートファイル一覧
            ##########################
            $TargetPath = "$($TargetConfig.RemoteDrive):"
            $Log.Info("コピー先フォルダ:$(Join-Path $TargetPath (Get-Date).ToString("yyyyMMdd"))")
            Get-FileList $TargetPath "*.$($TargetConfig.FileExt)"

            ##########################
            # ファイルコピー
            ##########################
            $CopyLog = $(Split-Path $MyInvocation.MyCommand.Path -Parent | Split-Path -Parent | Join-Path -ChildPath log -Resolve) + "\" + (Get-ChildItem $MyInvocation.MyCommand.Path).BaseName + "_Robocopy_" + $(Get-Date -Format "yyyyMMddHHmmss") + ".log"
            $ReturnObj = Invoke-Command "robocopy" $env:comspec "/C ROBOCOPY `"$SourcePath`" $(Join-Path $TargetPath (Get-Date).ToString("yyyyMMdd")) /MT:4 /J /R:2 /W:1 /MIR /IT /COPY:DAT /DCOPY:DAT /NP /FFT /COMPRESS /LOG:$CopyLog"
            switch($ReturnObj.ExitCode) {
              # コピーしたファイルがない
              0 {
                $Log.Info("コピー対象のファイルがありませんでした。")
                $Log.Info("ファイルコピー結果`r`n$($ReturnObj.StdOut)")
                break
              }
              # コピーしたファイルがある
              ({$_ -ge 1 -and $_ -le 8}) {
                $Log.Info("ファイルコピー結果`r`n$($ReturnObj.StdOut)")
                ##########################
                # リモートディレクトリ削除
                ##########################
                $Log.Info("ディレクトリ削除:開始")
                Get-ChildItem $TargetPath -Recurse | Where-Object {($_.Mode -eq "d-----") -and ($_.Name -lt (Get-Date).AddDays(-1 * $ConfigInfo.Configuration.LocalTerm).ToString("yyyyMMdd"))} | Remove-Item -Recurse -Force
#                $RemoveDir = $(Join-Path $TargetPath (Get-Date).AddDays(-1 * $TargetConfig.RemoteTerm).ToString("yyyyMMdd"))
#                if(Test-Path $RemoveDir) {
#                  $Return = Remove-Item -Recurse $RemoveDir -Force
#                  $Log.Info("ディレクトリ削除:$($RemoveDir)完了")
#                } else {
#                  $Log.Warn("ディレクトリ削除:$($RemoveDir)がありません")
#                }
                break
              }
              # エラーを伴うコピーしたファイルがある。
              ({$_ -gt 8}) {
                $Log.Info("エラーが発生しました。")
                $Log.Info("ファイルコピー結果`r`n$($ReturnObj.StdOut)")
                $ErrorFlg = $true
                break
              }
              default {
                $Log.Info("Other")
              }
            }
            ##########################
            # ローカルファイル一覧
            ##########################
            Get-FileList $SourcePath "*.$($TargetConfig.FileExt)"

            ##########################
            # リモートファイル一覧
            ##########################
            Get-FileList $TargetPath "*.$($TargetConfig.FileExt)"

          }
        }

        "TimestampDir" {
          ##########################
          # 退避処理開始
          ##########################
          if($ConResult.TcpTestSucceeded) {

            ##########################
            # ローカルファイル一覧
            ##########################
            $SourcePath = "$($TargetConfig.LocalPath)"
            $Log.Info("コピー元フォルダ:$SourcePath")
            Get-FileList $SourcePath "*.$($TargetConfig.FileExt)"

            ##########################
            # リモートファイル一覧(nothing)
            ##########################
            $TargetPath = "$($TargetConfig.RemoteDrive):"
#            Get-FileList $TargetPath "*.$($TargetConfig.FileExt)"

            ##########################
            # ファイルコピー
            ##########################
            $TargetFiles = Get-ChildItem $SourcePath "*.$($TargetConfig.FileExt)"
            foreach($Target in $TargetFiles){
              $Log.Info("コピー対象ファイル:$($Target.Name)")
              $Log.Info("コピー先フォルダ:$(Join-Path $TargetPath $Target.CreationTime.ToString("yyyyMMdd"))")
              $CopyLog = $(Split-Path $MyInvocation.MyCommand.Path -Parent | Split-Path -Parent | Join-Path -ChildPath log -Resolve) + "\" + (Get-ChildItem $MyInvocation.MyCommand.Path).BaseName + "_Robocopy_" + $(Get-Date -Format "yyyyMMdd") + ".log"
              $ReturnObj = Invoke-Command "robocopy" $env:comspec "/C ROBOCOPY `"$SourcePath`" $(Join-Path $TargetPath $Target.CreationTime.ToString("yyyyMMdd")) `"$($Target.Name)`" /MT:4 /J /R:2 /W:1 /COPY:DAT /DCOPY:DAT /NP /FFT /COMPRESS /LOG+:$CopyLog"
              switch($ReturnObj.ExitCode) {
                # コピーしたファイルがない
                0 {
                  $Log.Info("コピー済みです。")
                  $Log.Info("ファイルコピー結果`r`n$($ReturnObj.StdOut)")
                  break
                }
                # コピーしたファイルがある
                ({$_ -ge 1 -and $_ -le 8}) {
                  $Log.Info("ファイルコピー結果`r`n$($ReturnObj.StdOut)")
                }
                # エラーを伴うコピーしたファイルがある。
                ({$_ -gt 8}) {
                  $Log.Info("エラーが発生しました。")
                  $Log.Info("ファイルコピー結果`r`n$($ReturnObj.StdOut)")
                  $ErrorFlg = $true
                  break
                }
                default {
                  $Log.Info("Other")
                }
              }
            }

            if(-not $ErrorFlg) {
              ##########################
              # リモートファイル削除
              ##########################
              $Log.Info("$($TargetConfig.RemoteTerm)日以上前のファイル削除:開始")
              $Return = Remove-ExpiredFiles $TargetPath $TargetConfig.FileExt $TargetConfig.RemoteTerm
              if(-not $Return) {
                $Log.Info("ファイル削除:完了")
              } else {
                $Log.Warn("ファイル削除:エラー終了")
              }
              $Return = Remove-EmptyFolders $TargetPath

              ##########################
              # ローカルファイル削除
              ##########################
              $Log.Info("$($TargetConfig.LocalTerm)日以上前のファイル削除:開始")
              $Return = Remove-ExpiredFiles $SourcePath $TargetConfig.FileExt $TargetConfig.LocalTerm
              if(-not $Return) {
                $Log.Info("ファイル削除:完了")
              } else {
                $Log.Warn("ファイル削除:エラー終了")
              }
              break
            }
          }
          ##########################
          # ローカルファイル一覧
          ##########################
          Get-FileList $SourcePath "*.$($TargetConfig.FileExt)"

          ##########################
          # リモートファイル一覧
          ##########################
          Get-FileList $TargetPath "*.$($TargetConfig.FileExt)"

        }

        "RemoteCopy" {
          ##########################
          # 退避処理開始
          ##########################
          if($ConResult.TcpTestSucceeded) {

            ##########################
            # ローカルファイル一覧
            ##########################
            $SourcePath = "$($TargetConfig.LocalPath)"
            $Log.Info("コピー元フォルダ:$SourcePath")
            Get-FileList $SourcePath "*.$($TargetConfig.FileExt)"

            ##########################
            # リモートファイル一覧
            ##########################
            $TargetPath = "$($TargetConfig.RemoteDrive):"
            $Log.Info("コピー先フォルダ:$TargetPath")
            Get-FileList $TargetPath "*.$($TargetConfig.FileExt)"

            ##########################
            # ファイルコピー
            ##########################
            $ReturnObj = Invoke-Command "robocopy" $env:comspec "/C ROBOCOPY `"$SourcePath`" $TargetPath *.$($TargetConfig.FileExt) /DCOPY:DAT /NP /MT:8"
            switch($ReturnObj.ExitCode) {
              # コピーしたファイルがない
              0 {
                $Log.Info("コピー対象のファイルがありませんでした。")
                $Log.Info("ファイルコピー結果`r`n$($ReturnObj.StdOut)")
                break
              }
              # コピーしたファイルがある
              ({$_ -ge 1 -and $_ -le 8}) {
                $Log.Info("ファイルコピー結果`r`n$($ReturnObj.StdOut)")

                ##########################
                # リモートファイル削除
                ##########################
                $Log.Info("ファイル削除:開始")
                $Return = Remove-ExpiredFiles $TargetPath $TargetConfig.FileExt $TargetConfig.RemoteTerm
                if(-not $Return) {
                  $Log.Info("ファイル削除:完了")
                } else {
                  $Log.Warn("ファイル削除:エラー終了")
                }

                ##########################
                # ローカルファイル削除
                ##########################
                $Log.Info("ファイル削除:開始")
                $Return = Remove-ExpiredFiles $SourcePath $TargetConfig.FileExt $TargetConfig.LocalTerm
                if(-not $Return) {
                  $Log.Info("ファイル削除:完了")
                } else {
                  $Log.Warn("ファイル削除:エラー終了")
                }
                break
              }
              # エラーを伴うコピーしたファイルがある。
              ({$_ -gt 8}) {
                $Log.Info("エラーが発生しました。")
                $Log.Info("ファイルコピー結果`r`n$($ReturnObj.StdOut)")
                $ErrorFlg = $true
                break
              }
              default {
                $Log.Info("Other")
              }
            }
            ##########################
            # ローカルファイル一覧
            ##########################
            Get-FileList $SourcePath "*.$($TargetConfig.FileExt)"

            ##########################
            # リモートファイル一覧
            ##########################
            Get-FileList $TargetPath "*.$($TargetConfig.FileExt)"
          }
        }

        default {
          $Log.Error("モード`($($TargetConfig.Mode)`)の指定が誤ってます。")
          break
        }
      }
      # 共有フォルダのアンマウント
      if(-not $MountFlg) {
        $Log.Info("$($TargetConfig.Title):完了")
        Get-PSDrive $TargetConfig.RemoteDrive | Remove-PSDrive
      }
      $Log.Info("$($TargetConfig.Title):完了")
    }
  } else { exit 9 }

  if($ErrorFlg) { exit 9 }
  else { exit 0 }

} catch {
  $Log.Error("処理中にエラーが発生しました。")
  $Log.Error($("" + $Error[0] | Format-List --DisplayError))
  if(-not $MountFlg) {
    if(Get-PSDrive -Name $TargetConfig.RemoteDrive -ErrorAction Ignore) {
      Get-PSDrive $TargetConfig.RemoteDrive | Remove-PSDrive
    }
  }
  exit 9 
}
