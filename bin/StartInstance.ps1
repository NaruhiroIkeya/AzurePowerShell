<#::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
:: Copyright(c) 2015 NTT DATA Global Solutions CORPORATION. All rights reserved.
:: @auther:Naruhiro Ikeya
::
:: @name:StartInstance.ps1
:: @summary:SAP�V�X�e���N��
::
:: @since:2015/06/05
:: @version:1.0
:: @see:
::
:: @return:0:Success 1:Error
::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::#>
$scriptPath = [System.IO.Path]::GetDirectoryName($myInvocation.MyCommand.Definition)
$SAPConfig = [xml](Get-Content "$scriptPath\SAPInstanceConfig.xml")
. "$scriptPath\ServiceControl.ps1"

$Hostname = $SAPConfig.Configuration.Services.Host.Name
foreach($Service in $SAPConfig.Configuration.Services.Host.service) {
    $nowfmt = Get-Date -Format "yyyy/MM/dd HH:mm:ss.ff"
    Write-Host "[$nowfmt]" $Service.name "���N�����܂��B`r`n"
    $rc = (ServiceControl $Hostname $Service.name "START")
    if ($rc -ne 0) {
        $nowfmt = Get-Date -Format "yyyy/MM/dd HH:mm:ss.ff"
        Write-Host "[$nowfmt]" $Hostname $Service.name "���N���ł��܂���ł����B`r`n"
        exit 1
    }
    Start-Sleep $Service.delay
}
$nowfmt = Get-Date -Format "yyyy/MM/dd HH:mm:ss.ff"
Write-Host "[$nowfmt] ���ׂẴT�[�r�X���N�����܂����B`r`n"

$nowfmt = Get-Date -Format "yyyy/MM/dd HH:mm:ss.ff"
Write-Host "[$nowfmt] SAP �C���X�^���X���N�����܂��B`r`n"
foreach($Instance in $SAPConfig.Configuration.SAP.SID) {
    foreach($saphost in $Instance.host) {
        $nowfmt = Get-Date -Format "yyyy/MM/dd HH:mm:ss.ff"
        Write-Host "[$nowfmt]" $Instance.name $saphost.name $saphost.nr "�C���X�^���X���N�����܂��B`r`n"
        $sapctrlparam = "-prot PIPE -host " + $saphost.name + " -nr " + $saphost.nr + " -function StartWait " + $saphost.timeout + " " + $saphost.delay
        $result = Start-Process -FilePath "sapcontrol.exe" -ArgumentList $sapctrlparam -PassThru -Wait
        if ($result.ExitCode -ne 0) {
            Write-Host $Hostname $Instance.name "���N���ł��܂���ł����B`r`n"
            exit 1
        }
    }
    Start-Sleep 5
}
$nowfmt = Get-Date -Format "yyyy/MM/dd HH:mm:ss.ff"
Write-Host "[$nowfmt] ���ׂẴC���X�^���X���N�����܂����B`r`n"

Exit 0
