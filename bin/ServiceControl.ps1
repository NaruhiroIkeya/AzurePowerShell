<#::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
:: Copyright(c) 2015 NTT DATA Global Solutions CORPORATION. All rights reserved.
:: @auther:Naruhiro Ikeya
::
:: @name:ServiceControl.ps1
:: @summary:サービス起動・停止制御Function
::          管理者モードのコマンドプロンプトにて、PowerShell Set-ExecutionPolicy RemoteSignedを実行
:: @since:2015/06/03
:: @version:1.0
:: @see:
::
:: @param:server:サーバ名
:: @param:service:サービス名
:: @param:mode:start/stop
:: @return:0:Success 1:Error
::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::#>

function ServiceControl($server, $service, $mode) {

    $cntr = 0
    if (Test-Connection $server -quiet) {
        do {
            $result = Get-Service $service -ComputerName $server -ErrorVariable getServiceError -ErrorAction SilentlyContinue
            if ($getServiceError -and ($getServiceError | foreach {$_.FullyQualifiedErrorId -like "*NoServiceFoundForGivenName*"})) {
                $nowfmt = Get-Date -Format "yyyy/MM/dd HH:mm:ss.ff"
                Write-Host "[$nowfmt] $server $service サービスがありません。`r`n"
                return 9
            }
            if (($mode -match "START") -or ($mode -match "start")) {
                $status = "Running", "起動"
                if ($result.Status -eq "Stopped") {
                    $rc = (Get-WmiObject -computer $server Win32_Service -Filter "Name='$service'").InvokeMethod("StartService",$null)
                    if ($rc -ne 0) {
                        $message = $service + "サービスを" + $status[1] + "できませんでした。"
                        $message = $message + "RC=" + $rc
                        $nowfmt = Get-Date -Format "yyyy/MM/dd HH:mm:ss.ff"
                        Write-Host "[$nowfmt] $server $message`r`n"
                        return $rc
                    }
    　        　    Start-Sleep 5
                }
            } elseif (($mode -match "STOP") -or ($mode -match "stop")) {
                $status = "Stopped", "停止"
                if ($result.Status -eq "Running") {
                    $rc = (Get-WmiObject -computer $server Win32_Service -Filter "Name='$service'").InvokeMethod("StopService",$null)
                    if ($rc -ne 0) {
                        $message = $service + "サービスを" + $status[1] + "できませんでした。"
                        $message = $message + "RC=" + $rc
                        $nowfmt = Get-Date -Format "yyyy/MM/dd HH:mm:ss.ff"
                        Write-Host "[$nowfmt] $server $message`r`n"
                        return $rc
                    }
    　        　    Start-Sleep 5
                }
            } else {
                return 2
            }
            $result = Get-Service $service -ComputerName $server
            $cntr++
            if ($cntr -gt 3) { 
                $message = $service + "サービスを" + $status[1] + "できませんでした。"
                $nowfmt = Get-Date -Format "yyyy/MM/dd HH:mm:ss.ff"
                Write-Host "[$nowfmt] $server $message`r`n"
                return 3
            } else { 
                $message = $service + "サービスを" + $status[1] + "中です。"
                $nowfmt = Get-Date -Format "yyyy/MM/dd HH:mm:ss.ff"
                Write-Host "[$nowfmt] $server $message`r`n"
            }
        } while ($result.Status -ne $status[0])
    } else { return 1 } 
    $message = $service + "サービスを" + $status[1] + "しました。`r`n"
    $nowfmt = Get-Date -Format "yyyy/MM/dd HH:mm:ss.ff"
    Write-Host "[$nowfmt] $server $message"

    return 0
}