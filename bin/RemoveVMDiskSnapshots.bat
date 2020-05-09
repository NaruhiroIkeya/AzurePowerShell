::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
:: Copyright(c) 2020 BeeX Inc. All rights reserved.
:: @auther:Naruhiro Ikeya
::
:: @name:RemoveVMDiskSnapshots.bat
:: @summary:DiskSnapshotsController.ps1 Wrapper
::
:: @since:2020/05/04
:: @version:1.0
:: @see:
:: @parameter
::  1:ResourceGroupName
::  2:AzureVMName
::
:: @return:0:Success 1:Error
::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
@ECHO OFF
SETLOCAL ENABLEDELAYEDEXPANSION

:::::::::::::::::::::::::::::
::      環境変数設定       ::
:::::::::::::::::::::::::::::
SET __LOG_CYCLE__=7
SET __APL_PS1__=DiskSnapshotsController.ps1
SET __ERROR_CODE__=1

:::::::::::::::::::::::::::::::::::
::      パラメータチェック       ::
:::::::::::::::::::::::::::::::::::
SET __ARGC__=0
FOR %%a IN ( %* ) DO SET /A __ARGC__+=1

IF %__ARGC__% geq 3 (
  SET __TIME__=%TIME:~0,8%
  SET __TIME__=!__TIME__: =0!
  ECHO [%DATE% !__TIME__!] Usage:%~n0 リソースグループ名 AzureVM名
  EXIT /B %__ERROR_CODE__%
) 

SET __RESOURCEGROUPNAME__=%1
SET __VMNAME__=%2

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
SET __LOGFILE__=%__LOGPATH__%\%~n0_%__NOW__%.log

::::::::::::::::::::::::::::::::::::::::::::::
::      出力ログファイルローテーション      ::
::::::::::::::::::::::::::::::::::::::::::::::
FORFILES /P %__LOGPATH__% /M *.log /D -%__LOG_CYCLE__% /C "CMD /C IF @isdir==FALSE DEL /Q @path" > NUL 2>&1

::::::::::::::::::::::::::::::::::::::
::      スクリプト本体存在確認      ::
::::::::::::::::::::::::::::::::::::::
SET __PS_SCRIPT__=%~dp0%__APL_PS1__%
IF NOT EXIST %__PS_SCRIPT__% (
  CALL :__ECHO__ Snapshot削除スクリプトが存在しません。
  EXIT /B %__ERROR_CODE__%
)

::::::::::::::::::::::::::::::::::
::      スクリプト本体実行      ::
::::::::::::::::::::::::::::::::::
CALL :__ECHO__ Snapshot削除処理（%~n0.ps1）を開始します。
if "%PROCESSOR_ARCHITECTURE%" EQU "x86" (
    set EXEC_POWERSHELL="C:\Windows\sysnative\WindowsPowerShell\v1.0\powershell.exe"
)
if "%PROCESSOR_ARCHITECTURE%" EQU "AMD64" (
    set EXEC_POWERSHELL="C:\Windows\system32\WindowsPowerShell\v1.0\powershell.exe"
)

if "%__RESOURCEGROUPNAME__%" NEQ "" (
  SET __OPTIONS__= -ResourceGroupName %__RESOURCEGROUPNAME__%
  if "%__VMNAME__%" NEQ "" (
    SET __OPTIONS__=%__OPTIONS__% -AzureVMName %__VMNAME__%
  )
)

%EXEC_POWERSHELL% -NoProfile -inputformat none -command "%__PS_SCRIPT__% -RemoveSnapshot -Stdout %__OPTIONS__%;exit $LASTEXITCODE" >>"%__LOGFILE__%"

::::::::::::::::::::::::::::::::::::::::::
::      スクリプト本体実行結果確認      ::
::::::::::::::::::::::::::::::::::::::::::
IF ERRORLEVEL 1 (
  CALL :__ECHO__ Snapshot削除処理中にエラーが発生しました。
  EXIT /B 100
)
CALL :__ECHO__ Snapshot削除処理が完了しました。

:__QUIT__
EXIT /B 0

:__ECHO__
SET __TIME__=%TIME:~0,8%
ECHO [%DATE% %__TIME__: =0%] %*
ECHO [%DATE% %__TIME__: =0%] %* >>"%__LOGFILE__%"
EXIT /B 0
