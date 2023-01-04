::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
:: Copyright(c) 2020 BeeX Inc. All rights reserved.
:: @auther:Naruhiro Ikeya
::
:: @name:MonitoringAzureBackupJob.bat
:: @summary:MonitoringAzureBackupJob.ps1 Wrapper
::
:: @since:2019/01/28
:: @version:1.0
:: @see:
:: @parameter
::  1:AzureVM名
::  2:Recovery Serviceコンテナー名
::  3:Azure Backupジョブポーリング間隔（秒）
::
:: @return:0:Success 1:パラメータエラー 99:異常終了
::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
@ECHO OFF
SETLOCAL ENABLEDELAYEDEXPANSION

:::::::::::::::::::::::::::::
::      環境変数設定       ::
:::::::::::::::::::::::::::::
SET __LOG_CYCLE__=7

:::::::::::::::::::::::::::::::::::
::      パラメータチェック       ::
:::::::::::::::::::::::::::::::::::
SET __ARGC__=0
FOR %%a IN ( %* ) DO SET /A __ARGC__+=1

IF %__ARGC__% neq 3 (
  SET __TIME__=%TIME:~0,8%
  SET __TIME__=!__TIME__: =0!
  ECHO [%DATE% !__TIME__!] Usage:%~nx0 AzureVM名 RecoveryServiceコンテナー名 Backupジョブポーリング間隔
  EXIT /B 1
) 

SET __VMNAME__=%1
SET __R_S_CONTAINER__=%2
SET /A __JOB_TIMEOUT__=%3

::::::::::::::::::::::::::::::::::
::      タイムスタンプ生成      ::
::::::::::::::::::::::::::::::::::
SET __TODAY__=%DATE:/=%
SET __TIME__=%TIME::=%
SET __TIME__=%__TIME__:.=%
SET __NOW__=%__TODAY__%%__TIME__: =0%

::::::::::::::::::::::::::::::::::::
::      出力ログファイル生成      ::
::::::::::::::::::::::::::::::::::::
FOR /F "usebackq" %%L IN (`powershell -command "Split-Path %~dp0 -Parent | Join-Path -ChildPath log"`) DO SET __LOGPATH__=%%L
IF NOT EXIST %__LOGPATH__% MKDIR %__LOGPATH__%
SET __LOGFILE__=%__LOGPATH__%\%~n0_%_VMNAME__%_%__NOW__%.log

::::::::::::::::::::::::::::::::::::::::::::::
::      出力ログファイルローテーション      ::
::::::::::::::::::::::::::::::::::::::::::::::
FORFILES /P %__LOGPATH__% /M *.log /D -%__LOG_CYCLE__% /C "CMD /C IF @isdir==FALSE DEL /Q @path" > NUL 2>&1

::::::::::::::::::::::::::::::::::::::
::      スクリプト本体存在確認      ::
::::::::::::::::::::::::::::::::::::::
IF NOT EXIST %~dpn0.ps1 (
  CALL :__ECHO__ Azure Backup監視スクリプト（%~n0.ps1）が存在しません。
  EXIT /B 99
)

CD /d %~dp0

::::::::::::::::::::::::::::::::::
::      スクリプト本体監視      ::
::::::::::::::::::::::::::::::::::
CALL :__ECHO__ Azure Backup監視処理（%~n0.ps1）を開始します。
powershell -ExecutionPolicy RemoteSigned -NoProfile -inputformat none -command "%~dpn0.ps1 -Stdout %__VMNAME__% %__R_S_CONTAINER__% %__JOB_TIMEOUT__%;exit $LASTEXITCODE" >>"%__LOGFILE__%"

::::::::::::::::::::::::::::::::::::::::::
::      スクリプト本体監視結果確認      ::
::::::::::::::::::::::::::::::::::::::::::
IF ERRORLEVEL 9 (
  CALL :__ECHO__ Azure Backup監視処理中にエラーが発生しました。
  EXIT /B 99
)
IF ERRORLEVEL 2 (
  CALL :__ECHO__ Azure Backup監視処理（Take Snapshotフェーズ）が完了しました。
  EXIT /B 0
)
IF ERRORLEVEL 1 (
  CALL :__ECHO__ Azure Bakup監視処理中にパラメータエラーが発生しました。
  EXIT /B 1
)
CALL :__ECHO__ Azure Backup監視処理が完了しました。

:__QUIT__
EXIT /B 0

:__ECHO__
SET __TIME__=%TIME:~0,8%
ECHO [%DATE% %__TIME__: =0%] %*
ECHO [%DATE% %__TIME__: =0%] %* >>"%__LOGFILE__%"
EXIT /B 0
