
. .\LogController.ps1

[LogController]::new($true, $myInvocation.MyCommand.name).info("hoge1 information")
[LogController]::new($true, $myInvocation.MyCommand.name).warn("hoge2 warning")
[LogController]::new($true, $myInvocation.MyCommand.name).error("hoge3 error")
[LogController]::new().warn("mogaaa  aasefq )() 99e")
[LogController]::new().error("toge")

$Logfile = "C:\Users\naruhiro.ikeya\Documents\GitHub\AzurePowerShell\log\sample2.log"

$log = New-Object LogController
$log.info("para none")

$log = New-Object LogController($logfile,$true)
$log.RotateLog(9)

$log = New-Object LogController($logfile,$false)
$log.DeleteLog(3)

. .\AzureLogonFunction.ps1
$connect = New-Object AzureLogonFunction("C:\Users\naruhiro.ikeya\Documents\GitHub\AzurePowerShell\etc\AzureCredential.xml")
$connect.Initialize($log)
if($connect.logon()) {
 "OK"
}



