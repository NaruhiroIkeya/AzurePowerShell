::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
:: Copyright(c) 2019 BeeX Inc. All rights reserved.
:: @auther:Naruhiro Ikeya
::
:: @name:AzureBackup.bat
:: @summary:ExecAzureBackupJob.ps1 Wrapper
::
:: @since:2019/01/17
:: @version:1.0
:: @see:
:: @parameter
::  1:AzureVM��
::  2:Recovery Service�R���e�i�[��
::  3:Azure Backup�W���u���s�҂��^�C���A�E�g�l
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

IF %__ARGC__% neq 3 (
  SET __TIME__=%TIME:~0,8%
  SET __TIME__=!__TIME__: =0!
  ECHO [%DATE% !__TIME__!] Usage:%~n0 AzureVM�� RecoveryService�R���e�i�[�� �^�C���A�E�g�l
  EXIT /B 1
) 

SET __VMNAME__=%1
SET __R_S_CONTAINER__=%2
SET /A __JOB_TIMEOUT__=%3

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
IF NOT EXIST %~dpn0.ps1 (
  SET __TIME__=%TIME:~0,8%
  ECHO [%DATE% %__TIME__: =0%] Azure Backup���s�X�N���v�g�����݂��܂���B
  EXIT /B 1
)

::::::::::::::::::::::::::::::::::
::      �X�N���v�g�{�̎��s      ::
::::::::::::::::::::::::::::::::::
CALL :__ECHO__ Azure Backup���s�����i%~n0.ps1�j���J�n���܂��B
powershell -NoProfile -inputformat none -command "%~dpn0.ps1 %__VMNAME__% %__R_S_CONTAINER__% %__JOB_TIMEOUT__%;exit $LASTEXITCODE" >>"%__LOGFILE__%"

::::::::::::::::::::::::::::::::::::::::::
::      �X�N���v�g�{�̎��s���ʊm�F      ::
::::::::::::::::::::::::::::::::::::::::::
IF ERRORLEVEL 1 (
  CALL :__ECHO__ Azure Backup���s�������ɃG���[���������܂����B
  EXIT /B 1
)
CALL :__ECHO__ Azure Backup���s�������������܂����B

:__QUIT__
EXIT /B 0

:__ECHO__
SET __TIME__=%TIME:~0,8%
ECHO [%DATE% %__TIME__: =0%] %*
ECHO [%DATE% %__TIME__: =0%] %* >>"%__LOGFILE__%"
EXIT /B 0
