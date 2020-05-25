<#::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
:: Copyright(c) 2015 NTT DATA Global Solutions CORPORATION. All rights reserved.
:: @auther:Naruhiro Ikeya
::
:: @name:StopInstance.ps1
:: @summary:SAPシステム停止
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

$nowfmt = Get-Date -Format "yyyy/MM/dd HH:mm:ss.ff"
Write-Host "[$nowfmt] SAP インスタンスを停止します。`r`n"

# サービス順序を逆順に並び替え
$ReverseInstance = $SAPConfig.Configuration.SAP.SID
[array]::Reverse($ReverseInstance)
foreach($Instance in $ReverseInstance) {
    $ReverseHost = $Instance.host
    [array]::Reverse($ReverseHost)
    foreach($saphost in $ReverseHost) {
        $nowfmt = Get-Date -Format "yyyy/MM/dd HH:mm:ss.ff"
        Write-Host "[$nowfmt]" $Instance.name $saphost.name $saphost.nr "インスタンスを停止します。`r`n"
        $sapctrlparam = "-prot PIPE -host " + $saphost.name + " -nr " + $saphost.nr + " -function StopWait " + $saphost.timeout + " " + $saphost.delay
        $result = Start-Process -FilePath "sapcontrol.exe" -ArgumentList $sapctrlparam -PassThru -Wait
        if ($result.ExitCode -ne 0) {
            Write-Host $Hostname $Instance.name "が停止できませんでした。`r`n"
            exit 1
        }
    }
    Start-Sleep 5
}
$nowfmt = Get-Date -Format "yyyy/MM/dd HH:mm:ss.ff"
Write-Host "[$nowfmt] すべてのインスタンスが停止しました。`r`n"

$Hostname = $SAPConfig.Configuration.Services.Host.Name
# サービス順序を逆順に並び替え
$ReverseService = $SAPConfig.Configuration.Services.Host.service
[array]::Reverse($ReverseService)

foreach($Service in $ReverseService) {
    $nowfmt = Get-Date -Format "yyyy/MM/dd HH:mm:ss.ff"
    Write-Host "[$nowfmt]" $Service.name "を停止します。`r`n"
    $rc = (ServiceControl $Hostname $Service.name "STOP")
    if ($rc -ne 0) {
        $nowfmt = Get-Date -Format "yyyy/MM/dd HH:mm:ss.ff"
        Write-Host "[$nowfmt]" $Hostname $Service.name "が停止できませんでした。`r`n"
        exit 1
    }
    Start-Sleep $Service.delay
}

Exit 0

