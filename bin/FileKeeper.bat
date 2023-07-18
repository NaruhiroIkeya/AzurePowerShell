:: Copyright(c) 2023 BeeX Inc. All rights reserved.
:: @auther:Naruhiro Ikeya
::
:: @name:FileKeeper.bat
:: @summary:FileKeeper.ps1 Wrapper
::
:: @since:2023/07/16
:: @version:1.0
:: @see:
:: @parameter
::  1:Configuration File名
::
:: @return:0:Success -1:Error
::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
@ECHO OFF
SETLOCAL ENABLEDELAYEDEXPANSION

:::::::::::::::::::::::::::::
::      環境変数設定       ::
:::::::::::::::::::::::::::::
SET __LOG_CYCLE__=7
SET __APL_PS1__=%~n0.ps1
SET __ERROR_CODE__=-1

:::::::::::::::::::::::::::::::::::
::      パラメータチェック       ::
:::::::::::::::::::::::::::::::::::
SET __ARGC__=0
FOR %%a IN ( %* ) DO SET /A __ARGC__+=1

IF %__ARGC__% neq 1 (
  SET __TIME__=%TIME:~0,8%
  SET __TIME__=!__TIME__: =0!
  ECHO [%DATE% !__TIME__!] Usage:%~n0 ConfigurationFile名
  EXIT /B %__ERROR_CODE__%
) 

SET __CNFFILENAME__=%1

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
SET __LOGFILE__=%__LOGPATH__%\%~n0_%~n1_%__NOW__%.log

::::::::::::::::::::::::::::::::::::::::::::::
::      出力ログファイルローテーション      ::
::::::::::::::::::::::::::::::::::::::::::::::
FORFILES /P %__LOGPATH__% /M *.log /D -%__LOG_CYCLE__% /C "CMD /C IF @isdir==FALSE DEL /Q @path" > NUL 2>&1

::::::::::::::::::::::::::::::::::::::
::      スクリプト本体存在確認      ::
::::::::::::::::::::::::::::::::::::::
SET __PS_SCRIPT__=%~dp0%__APL_PS1__%
IF NOT EXIST %__PS_SCRIPT__% (
  CALL :__ECHO__ ファイル制御スクリプトが存在しません。
  EXIT /B %__ERROR_CODE__%
)

:::::::::::::::::::::::::::::::::::::
::      制御ファイル存在確認      ::
::::::::::::::::::::::::::::::::::::::
FOR /F "usebackq" %%L IN (`powershell -command "Split-Path %~dp0 -Parent | Join-Path -ChildPath etc"`) DO SET __CNFPATH__=%%L
IF NOT EXIST %__CNFPATH__% MKDIR %__CNFPATH__% 
SET __CNFFILE__=%__CNFPATH__%\%__CNFFILENAME__%
IF NOT EXIST %__CNFFILE__% (
  CALL :__ECHO__ 制御ファイルが存在しません。
  EXIT /B %__ERROR_CODE__%
)

CD /d %~dp0
::::::::::::::::::::::::::::::::::
::      スクリプト本体実行      ::
::::::::::::::::::::::::::::::::::
CALL :__ECHO__ ファイル制御処理（%__PS_SCRIPT__%）を開始します。
if "%PROCESSOR_ARCHITECTURE%" EQU "x86" (
    set EXEC_POWERSHELL="C:\Windows\sysnative\WindowsPowerShell\v1.0\powershell.exe"
)
if "%PROCESSOR_ARCHITECTURE%" EQU "AMD64" (
    set EXEC_POWERSHELL="C:\Windows\system32\WindowsPowerShell\v1.0\powershell.exe"
)

%EXEC_POWERSHELL% -NoProfile -inputformat none -command "%__PS_SCRIPT__% %__CNFFILE__% -Stdout;exit $LASTEXITCODE" >>"%__LOGFILE__%"
::::::::::::::::::::::::::::::::::::::::::
::      スクリプト本体実行結果確認      ::
::::::::::::::::::::::::::::::::::::::::::
IF ERRORLEVEL 1 (
  CALL :__ECHO__ ファイル制御処理中にエラーが発生しました。
  EXIT /B %__ERROR_CODE__%
)
CALL :__ECHO__ ファイル制御処理が完了しました。

:__QUIT__
EXIT /B 0

:__ECHO__
SET __TIME__=%TIME:~0,8%
ECHO [%DATE% %__TIME__: =0%] %*
ECHO [%DATE% %__TIME__: =0%] %* >>"%__LOGFILE__%"
EXIT /B 0
