
. .\LogController.ps1

[LogController]::new($true, $myInvocation.MyCommand.name).info("hoge1 information")
[LogController]::new($true, $myInvocation.MyCommand.name).warn("hoge2 warning")
[LogController]::new($true, $myInvocation.MyCommand.name).error("hoge3 error")
[LogController]::new().warn("mogaaa  aasefq )() 99e")
[LogController]::new().error("toge")

$Logfile = Split-Path $myInvocation.MyCommand.Path -Parent | Split-Path -Parent | Join-Path -ChildPath log | Join-Path -ChildPath $myInvocation.MyCommand.Name
$Logfile
[LogController]::new($Logfile, $true).RotateLog(9)


$log = New-Object LogController($logfile,$true)
$log.getLogInfo()
$log.info("ログローテーション処理を開始します。")
$log.RotateLog(9)
$log.info("ログローテーション処理が完了しました。")

