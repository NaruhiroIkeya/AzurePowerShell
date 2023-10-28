<################################################################################
## Copyright(c) 2023 BeeX Inc. All rights reserved.
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
    }
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

  $FullPath = "$Path\$Files"
  $ReturnObj = Invoke-Command "dir" $env:comspec "/C DIR /B `"$FullPath`""
  if (-not $ReturnObj.ExitCode) {
    $Log.Info("$($FullPath)`r`n$($ReturnObj.StdOut)")
  } else {
    $Log.Error("$($FullPath)`r`n$($ReturnObj.StdErr)")
  }
}

##########################
# 関数定義
##########################
# 期限切れファイルの削除
Function Remove-ExpiredFiles($Path, $FileExt, $Term) {

  $Log.Info("ファイルローテーション開始:")
  $Log.Info("ファイルローテーション開始:$($Term)日以前のファイルを削除します。")
  $Log.Info("対象フォルダ:$($Path)")
  $ReturnObj = Invoke-Command "forfiles" $env:comspec "/C FORFILES /P `"$Path`" /M *.$FileExt /D -$Term /C `"CMD /C IF @isdir==FALSE ECHO @path 2>nul`""
  if (-not $ReturnObj.ExitCode) {
    $Log.Info("削除対象ファイル`r`n$($ReturnObj.StdOut)")
    $ReturnObj = Invoke-Command "forfiles" $env:comspec "/C FORFILES /P `"$Path`" /M *.$FileExt /D -$Term /C `"CMD /C IF @isdir==FALSE DEL /Q @path`""
    if (-not $ReturnObj.ExitCode) {
      $Log.Info("ローカルファイル削除`r`n$($ReturnObj.StdOut)")
    } else {
      $Log.Warn("$($ReturnObj.StdErr)")
      return 9
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
  if (($ConfigFile) -and (-not $(Test-Path $ConfigFile))) {
    $Log.Error("制御ファイルが存在しません。")
    exit 9 
  } else {
    $Log.Info("制御ファイルパス：" + (Split-Path $ConfigFile -Parent))
    $Log.Info("制御ファイル名：" + (Get-ChildItem $ConfigFile).Name)
    if ($(Test-Path $ConfigFile)) { $ConfigInfo = [xml](Get-Content $ConfigFile) }
    if(-not $ConfigInfo) { 
      $Log.Error("既定のファイルから制御情報が読み込めませんでした。")
      exit 9 
     } 
  }
    
  if ($ConfigInfo) {
    foreach ($Target in $ConfigInfo.Configuration.Target) {
      $Log.Info("$($Target.Title):開始")
      $Log.Info("$($Target.RemoteHost)に接続します")
      $connectTestResult = Test-NetConnection -ComputerName $Target.RemoteHost -Port 445
      if (-not ($connectTestResult.TcpTestSucceeded)) {
        $Log.Error("共有ディスクに接続できませんでした。")
        $ErrorFlg = $true
        break
      }

      switch($Target.Mode) {
        "Mirror" {
          ##########################
          # 退避処理開始
          ##########################
          # 再起動時にドライブが維持されるように、パスワードを保存する
          cmd.exe /C "cmdkey /add:`"$($Target.RemoteHost)`" /user:`"$($Target.RemoteUser)`" /pass:`"$($Target.RemotePass)`""

          # 共有フォルダをドライブをマウントする
          $Log.Info("\\$($Target.RemoteHost)\$($Target.RemotePath)を$($Target.RemoteDrive)ドライブにマウントします")
          New-PSDrive -Name $Target.RemoteDrive -PSProvider FileSystem -Root "\\$($Target.RemoteHost)\$($Target.RemotePath)" -Persist

          ##########################
          # ローカルファイル一覧
          ##########################
          $SourcePath = "$($Target.LocalPath)"
          Get-FileList $SourcePath "*.$($Target.FileExt)"

          ##########################
          # リモートファイル一覧
          ##########################
          $TargetPath = "$($Target.RemoteDrive):"
          Get-FileList $TargetPath "*.$($Target.FileExt)"

          ##########################
          # ファイルコピー
          ##########################
          $Log.Info("コピー元ファイル:$SourcePath")
          $Log.Info("コピー先フォルダ:$TargetPath")
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
          Get-FileList $SourcePath "*.$($Target.FileExt)"

          ##########################
          # リモートファイル一覧
          ##########################
          Get-FileList $TargetPath "*.$($Target.FileExt)"

          # 共有フォルダのアンマウント
          Get-PSDrive $Target.RemoteDrive | Remove-PSDrive
        }

        "DateDirectory" {
          ##########################
          # 退避処理開始
          ##########################
          if ($connectTestResult.TcpTestSucceeded) {
            # 再起動時にドライブが維持されるように、パスワードを保存する
            cmd.exe /C "cmdkey /add:`"$($Target.RemoteHost)`" /user:`"$($Target.RemoteUser)`" /pass:`"$($Target.RemotePass)`""

            # 共有フォルダをドライブをマウントする
            $Log.Info("\\$($Target.RemoteHost)\$($Target.RemotePath)を$($Target.RemoteDrive)ドライブにマウントします")
            New-PSDrive -Name $Target.RemoteDrive -PSProvider FileSystem -Root "\\$($Target.RemoteHost)\$($Target.RemotePath)" -Persist

            ##########################
            # ローカルファイル一覧
            ##########################
            $SourcePath = "$($Target.LocalPath)"
            Get-FileList $SourcePath "*.$($Target.FileExt)"

            ##########################
            # リモートファイル一覧
            ##########################
            $TargetPath = "$($Target.RemoteDrive):"
            Get-FileList $TargetPath "*.$($Target.FileExt)"

            ##########################
            # ファイルコピー
            ##########################
            $Log.Info("コピー元ファイル:$SourcePath")
            $Log.Info("コピー先フォルダ:$(Join-Path $TargetPath (Get-Date).ToString("yyyyMMdd"))")
            $ReturnObj = Invoke-Command "robocopy" $env:comspec "/C ROBOCOPY `"$SourcePath`" $(Join-Path $TargetPath (Get-Date).ToString("yyyyMMdd")) /MIR /DCOPY:DAT /NP /MT:8"
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
                $RemoveDir = $(Join-Path $TargetPath (Get-Date).AddDays(-1 * $Target.RemoteTerm).ToString("yyyyMMdd"))
                if (Test-Path $RemoveDir) {
                  $Return = Remove-Item -Recurse $RemoveDir -Force
                  $Log.Info("ディレクトリ削除:$($RemoveDir)完了")
                } else {
                  $Log.Warn("ディレクトリ削除:$($RemoveDir)がありません")
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
            Get-FileList $SourcePath "*.$($Target.FileExt)"

            ##########################
            # リモートファイル一覧
            ##########################
            Get-FileList $TargetPath "*.$($Target.FileExt)"

            # 共有フォルダのアンマウント
            Get-PSDrive $Target.RemoteDrive | Remove-PSDrive
          }
        }

        "RemoteCopy" {
          ##########################
          # 退避処理開始
          ##########################
          if ($connectTestResult.TcpTestSucceeded) {
            # 再起動時にドライブが維持されるように、パスワードを保存する
            cmd.exe /C "cmdkey /add:`"$($Target.RemoteHost)`" /user:`"$($Target.RemoteUser)`" /pass:`"$($Target.RemotePass)`""

            # 共有フォルダをドライブをマウントする
            $Log.Info("\\$($Target.RemoteHost)\$($Target.RemotePath)を$($Target.RemoteDrive)ドライブにマウントします")
            New-PSDrive -Name $Target.RemoteDrive -PSProvider FileSystem -Root "\\$($Target.RemoteHost)\$($Target.RemotePath)" -Persist

            ##########################
            # ローカルファイル一覧
            ##########################
            $SourcePath = "$($Target.LocalPath)"
            Get-FileList $SourcePath "*.$($Target.FileExt)"

            ##########################
            # リモートファイル一覧
            ##########################
            $TargetPath = "$($Target.RemoteDrive):"
            Get-FileList $TargetPath "*.$($Target.FileExt)"

            ##########################
            # ファイルコピー
            ##########################
            $Log.Info("コピー元ファイル:$SourcePath")
            $Log.Info("コピー先フォルダ:$TargetPath")
            $ReturnObj = Invoke-Command "robocopy" $env:comspec "/C ROBOCOPY `"$SourcePath`" $TargetPath *.$($Target.FileExt) /DCOPY:DAT /NP /MT:8"
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
                $Return = Remove-ExpiredFiles $TargetPath $Target.FileExt $Target.RemoteTerm
                if (-not $Return) {
                  $Log.Info("ファイル削除:完了")
                } else {
                  $Log.Warn("ファイル削除:エラー終了")
                }

                ##########################
                # ローカルファイル削除
                ##########################
                $Log.Info("ファイル削除:開始")
                $Return = Remove-ExpiredFiles $SourcePath $Target.FileExt $Target.LocalTerm
                if (-not $Return) {
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
            Get-FileList $SourcePath "*.$($Target.FileExt)"

            ##########################
            # リモートファイル一覧
            ##########################
            Get-FileList $TargetPath "*.$($Target.FileExt)"

            # 共有フォルダのアンマウント
            Get-PSDrive $Target.RemoteDrive | Remove-PSDrive
          }
        }

        default {
          $Log.Error("モード`($($Target.Mode)`)の指定が誤ってます。")
          break
        }
      }
      $Log.Info("$($Target.Title):完了")
    }
  } else { exit 9 }

  if($ErrorFlg) { exit 9 }
  else { exit 0 }

} catch {
  $Log.Error("処理中にエラーが発生しました。")
  $Log.Error($("" + $Error[0] | Format-List --DisplayError))
  Get-PSDrive $Target.RemoteDrive | Remove-PSDrive
  exit 9 
}
