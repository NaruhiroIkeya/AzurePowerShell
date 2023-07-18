::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
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
::  1:Configuration File��
::
:: @return:0:Success -1:Error
::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
@ECHO OFF
SETLOCAL ENABLEDELAYEDEXPANSION

:::::::::::::::::::::::::::::
::      ���ϐ��ݒ�       ::
:::::::::::::::::::::::::::::
SET __LOG_CYCLE__=7
SET __APL_PS1__=%~n0.ps1
SET __ERROR_CODE__=-1

:::::::::::::::::::::::::::::::::::
::      �p�����[�^�`�F�b�N       ::
:::::::::::::::::::::::::::::::::::
SET __ARGC__=0
FOR %%a IN ( %* ) DO SET /A __ARGC__+=1

IF %__ARGC__% neq 1 (
  SET __TIME__=%TIME:~0,8%
  SET __TIME__=!__TIME__: =0!
  ECHO [%DATE% !__TIME__!] Usage:%~n0 ConfigurationFile��
  EXIT /B %__ERROR_CODE__%
) 

SET __CNFFILENAME__=%1

::::::::::::::::::::::::::::::::::
::      �^�C���X�^���v����      ::
::::::::::::::::::::::::::::::::::
SET __TODAY__=%DATE:/=%
SET __TIME__=%TIME::=%
SET __TIME__=%__TIME__:.=%
SET __NOW__=%__TODAY__%%__TIME__: =0%

::::::::::::::::::::::::::::::::::::
::      �o�̓��O�t�@�C������      ::
::::::::::::::::::::::::::::::::::::
FOR /F "usebackq" %%L IN (`powershell -command "Split-Path %~dp0 -Parent | Join-Path -ChildPath log"`) DO SET __LOGPATH__=%%L
IF NOT EXIST %__LOGPATH__% MKDIR %__LOGPATH__% 
SET __LOGFILE__=%__LOGPATH__%\%~n0_%~n1_%__NOW__%.log

::::::::::::::::::::::::::::::::::::::::::::::
::      �o�̓��O�t�@�C�����[�e�[�V����      ::
::::::::::::::::::::::::::::::::::::::::::::::
FORFILES /P %__LOGPATH__% /M *.log /D -%__LOG_CYCLE__% /C "CMD /C IF @isdir==FALSE DEL /Q @path" > NUL 2>&1

::::::::::::::::::::::::::::::::::::::
::      �X�N���v�g�{�̑��݊m�F      ::
::::::::::::::::::::::::::::::::::::::
SET __PS_SCRIPT__=%~dp0%__APL_PS1__%
IF NOT EXIST %__PS_SCRIPT__% (
  CALL :__ECHO__ �t�@�C������X�N���v�g�����݂��܂���B
  EXIT /B %__ERROR_CODE__%
)

:::::::::::::::::::::::::::::::::::::
::      ����t�@�C�����݊m�F      ::
::::::::::::::::::::::::::::::::::::::
FOR /F "usebackq" %%L IN (`powershell -command "Split-Path %~dp0 -Parent | Join-Path -ChildPath etc"`) DO SET __CNFPATH__=%%L
IF NOT EXIST %__CNFPATH__% MKDIR %__CNFPATH__% 
SET __CNFFILE__=%__CNFPATH__%\%__CNFFILENAME__%
IF NOT EXIST %__CNFFILE__% (
  CALL :__ECHO__ ����t�@�C�������݂��܂���B
  EXIT /B %__ERROR_CODE__%
)

CD /d %~dp0
::::::::::::::::::::::::::::::::::
::      �X�N���v�g�{�̎��s      ::
::::::::::::::::::::::::::::::::::
CALL :__ECHO__ �t�@�C�����䏈���i%__PS_SCRIPT__%�j���J�n���܂��B
if "%PROCESSOR_ARCHITECTURE%" EQU "x86" (
    set EXEC_POWERSHELL="C:\Windows\sysnative\WindowsPowerShell\v1.0\powershell.exe"
)
if "%PROCESSOR_ARCHITECTURE%" EQU "AMD64" (
    set EXEC_POWERSHELL="C:\Windows\system32\WindowsPowerShell\v1.0\powershell.exe"
)

%EXEC_POWERSHELL% -NoProfile -inputformat none -command "%__PS_SCRIPT__% %__CNFFILE__% -Stdout;exit $LASTEXITCODE" >>"%__LOGFILE__%"
::::::::::::::::::::::::::::::::::::::::::
::      �X�N���v�g�{�̎��s���ʊm�F      ::
::::::::::::::::::::::::::::::::::::::::::
IF ERRORLEVEL 1 (
  CALL :__ECHO__ �t�@�C�����䏈�����ɃG���[���������܂����B
  EXIT /B %__ERROR_CODE__%
)
CALL :__ECHO__ �t�@�C�����䏈�����������܂����B

:__QUIT__
EXIT /B 0

:__ECHO__
SET __TIME__=%TIME:~0,8%
ECHO [%DATE% %__TIME__: =0%] %*
ECHO [%DATE% %__TIME__: =0%] %* >>"%__LOGFILE__%"
EXIT /B 0
