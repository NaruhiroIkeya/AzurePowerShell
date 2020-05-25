<#::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
:: Copyright(c) 2015 NTT DATA Global Solutions CORPORATION. All rights reserved.
:: @auther:Naruhiro Ikeya
::
:: @name:ServiceControl.ps1
:: @summary:�T�[�r�X�N���E��~����Function
::          �Ǘ��҃��[�h�̃R�}���h�v�����v�g�ɂāAPowerShell Set-ExecutionPolicy RemoteSigned�����s
:: @since:2015/06/03
:: @version:1.0
:: @see:
::
:: @param:server:�T�[�o��
:: @param:service:�T�[�r�X��
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
                Write-Host "[$nowfmt] $server $service �T�[�r�X������܂���B`r`n"
                return 9
            }
            if (($mode -match "START") -or ($mode -match "start")) {
                $status = "Running", "�N��"
                if ($result.Status -eq "Stopped") {
                    $rc = (Get-WmiObject -computer $server Win32_Service -Filter "Name='$service'").InvokeMethod("StartService",$null)
                    if ($rc -ne 0) {
                        $message = $service + "�T�[�r�X��" + $status[1] + "�ł��܂���ł����B"
                        $message = $message + "RC=" + $rc
                        $nowfmt = Get-Date -Format "yyyy/MM/dd HH:mm:ss.ff"
                        Write-Host "[$nowfmt] $server $message`r`n"
                        return $rc
                    }
    �@        �@    Start-Sleep 5
                }
            } elseif (($mode -match "STOP") -or ($mode -match "stop")) {
                $status = "Stopped", "��~"
                if ($result.Status -eq "Running") {
                    $rc = (Get-WmiObject -computer $server Win32_Service -Filter "Name='$service'").InvokeMethod("StopService",$null)
                    if ($rc -ne 0) {
                        $message = $service + "�T�[�r�X��" + $status[1] + "�ł��܂���ł����B"
                        $message = $message + "RC=" + $rc
                        $nowfmt = Get-Date -Format "yyyy/MM/dd HH:mm:ss.ff"
                        Write-Host "[$nowfmt] $server $message`r`n"
                        return $rc
                    }
    �@        �@    Start-Sleep 5
                }
            } else {
                return 2
            }
            $result = Get-Service $service -ComputerName $server
            $cntr++
            if ($cntr -gt 3) { 
                $message = $service + "�T�[�r�X��" + $status[1] + "�ł��܂���ł����B"
                $nowfmt = Get-Date -Format "yyyy/MM/dd HH:mm:ss.ff"
                Write-Host "[$nowfmt] $server $message`r`n"
                return 3
            } else { 
                $message = $service + "�T�[�r�X��" + $status[1] + "���ł��B"
                $nowfmt = Get-Date -Format "yyyy/MM/dd HH:mm:ss.ff"
                Write-Host "[$nowfmt] $server $message`r`n"
            }
        } while ($result.Status -ne $status[0])
    } else { return 1 } 
    $message = $service + "�T�[�r�X��" + $status[1] + "���܂����B`r`n"
    $nowfmt = Get-Date -Format "yyyy/MM/dd HH:mm:ss.ff"
    Write-Host "[$nowfmt] $server $message"

    return 0
}