::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
:: Copyright(c) 2019 BeeX Inc. All rights reserved.
:: @auther:Naruhiro Ikeya
::
:: @name:ExecAzureVMBoot.bat
:: @summary:ExecAzureVMBoot.ps1 Wrapper
::
:: @since:2019/01/17
:: @version:1.0
:: @see:
:: @parameter
::  1:ResourceGroup��
::  2:AzureVM��
::
:: @return:0:Success 1:Error
::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
@ECHO OFF
SETLOCAL ENABLEDELAYEDEXPANSION

:::::::::::::::::::::::::::::
::      ���ϐ��ݒ�       ::
:::::::::::::::::::::::::::::
SET __LOG_CYCLE__=7

:::::::::::::::::::::::::::::::::::
::      �p�����[�^�`�F�b�N       ::
:::::::::::::::::::::::::::::::::::
SET __ARGC__=0
FOR %%a IN ( %* ) DO SET /A __ARGC__+=1

IF %__ARGC__% neq 2 (
  SET __TIME__=%TIME:~0,8%
  SET __TIME__=!__TIME__: =0!
  ECHO [%DATE% !__TIME__!] Usage:%~n0 ResourceGroup�� AzureVM��
  EXIT /B 1
) 

SET __RESOURCEGROUPNAME__=%1
SET __VMNAME__=%2

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
SET __LOGFILE__=%__LOGPATH__%\%~n0_%__NOW__%.log

::::::::::::::::::::::::::::::::::::::::::::::
::      �o�̓��O�t�@�C�����[�e�[�V����      ::
::::::::::::::::::::::::::::::::::::::::::::::
FORFILES /P %__LOGPATH__% /M *.log /D -%__LOG_CYCLE__% /C "CMD /C IF @isdir==FALSE DEL /Q @path" > NUL 2>&1

::::::::::::::::::::::::::::::::::::::
::      �X�N���v�g�{�̑��݊m�F      ::
::::::::::::::::::::::::::::::::::::::
SET __PS_SCRIPT__=%~dp0AzureVMBootController.ps1
IF NOT EXIST %__PS_SCRIPT__% (
  CALL :__ECHO__ AzureVM�N���X�N���v�g�����݂��܂���B
  EXIT /B 1
)

::::::::::::::::::::::::::::::::::
::      �X�N���v�g�{�̎��s      ::
::::::::::::::::::::::::::::::::::
CALL :__ECHO__ AzureVM�N�������i%__PS_SCRIPT__%�j���J�n���܂��B
powershell -NoProfile -inputformat none -command "%__PS_SCRIPT__% -Boot -Stdout %__RESOURCEGROUPNAME__% %__VMNAME__%;exit $LASTEXITCODE" >>"%__LOGFILE__%"

::::::::::::::::::::::::::::::::::::::::::
::      �X�N���v�g�{�̎��s���ʊm�F      ::
::::::::::::::::::::::::::::::::::::::::::
IF ERRORLEVEL 1 (
  CALL :__ECHO__ AzureVM�N���������ɃG���[���������܂����B
  EXIT /B 1
)
CALL :__ECHO__ AzureVM�N���������������܂����B

:__QUIT__
EXIT /B 0

:__ECHO__
SET __TIME__=%TIME:~0,8%
ECHO [%DATE% %__TIME__: =0%] %*
ECHO [%DATE% %__TIME__: =0%] %* >>"%__LOGFILE__%"
EXIT /B 0
