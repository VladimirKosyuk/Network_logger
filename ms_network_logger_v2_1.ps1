#Created by https://github.com/VladimirKosyuk

# For all prodution MS 2012 R2 servers and above simultaneously collects TCP established connections(every 10 secodns) and active connections(realtime) to csv files during 12 hours and moves them to SMB-share. Outputs progress to CLI.

# Build date: 11.11.2020

#About (Russian):

<# 
Описание:
-Проверяет, создана ли папка для сбора результатов, если нет - скрипт создаст. Внимание - для *.etl файлов шара не создается автоматически!
-Cобирает список прод серверов MS 2012 R2 домена
-На всех из списка через invoke-command запускает логирование по провайдеру Microsoft-Windows-TCPIP, вывод в FQDN_Active_connections.csv.etl в корень С:
-На всех из списка через get-NetTCPConnection забирает listening соединения, шаг - 10 секунд, вывод в FQDN_established_connections.csv в корень С;
-Шаги 3 и 4 работают в течении таймера(продолжительность указать в $Timer_sec или если место на диске не станет меньше 1 ГБ;
-На каждом из списка через SMB перемещает данные логирования в шары .
-Парсинг *.etl файлов по событию 1033, приведение к виду: Route = local=ip:port remote=ip:port , PID = number, TimeCreated = date, вывод в CSV
-Очистка шары с *.etl файлами
Требования к внедрению:
-Запуск от АДМ у\з на всех собираемых серверах
-Active Directory module 
-Execution policy unrestricted (или надо подписать скрипт)
-Сервера из списка не ниже 2012 R2(для серверов ниже нет NetEventSession)
-Invoke-command с сервера источника на сервера назначения выполняется успешно
-SMB шара для raw data с серверов должна быть доступна для серверов из списка
-На каждом из серверов на диске С: должно быть не менее 10 ГБ свободного места - *.etl файлы имеют ограничение на рост до 6 ГБ, *.csv ограничений не имеют
-Я не умею передавать в invoke переменные извне, потому для изменения таймера надо менять 96 строку
Баги:
-invoke-command для текущего списка из 64 серверов не выполняет одновременно на всех, примерно для половины, после окончания цикла сбора данных - переходит на вторую половину.
-Очистка шары с *.etl файлами не всегда удаляет все файлы
-Set-NetEventSession -MaxFileSize - увеличение параметра более 6ГБ вызывает ошибку
-Однократно было замечено, что скрипт не может остановить do\untill цикл, в таком случае - 
    1. Собрать $List_SRV, для него найти, сколько сессий зависло - foreach ($pc in $List_SRV) {Get-PSSession -ComputerName $pc #| Remove-PSSession}
    2. Для найденных серверов сделать (gwmi win32_process -ComputerName "найденный_сервер") | WHERE-OBJECT { $_.Name -imatch "wsmprovhost.exe" } |% { $_.Name; $_.Terminate() }
#>									   
 
#About (English):

 <#
 Description:
-Check if folder to output parsed data is created, if not – creates it. For smb-share with collected *.etl files – it will not be created via script!
-Collects array with DNS names production MS 2012 R2 doman servers 
-For each one simultaneously via invoke-command starts Microsoft-Windows-TCPIP logging with output to C:\FQDN_Active_connections.csv.etl
-For each one simultaneously via get-NetTCPConnection collects listening connections with output to C:\FQDN_established_connections.csv
-Steps 3 and 4 proceed until $Timer_sec is over or C: space is running below 1 GB
-For each one of files moves to shares via smb
-Parse each one of collected *.etl files via 1033 event and to output as following: Route = local=ip:port remote=ip:port , PID = number, TimeCreated = date
-Removes *.etl files from share
Bugs:
-Invoke-command for all 64 elements of my array cannot do simultaneously, but half – first step, do\untill ends, then – second half
-Remove *.etl files from share not do for all files. Couple of files holded via system
-For Set-NetEventSession setting -MaxFileSize > 6 GB causes error
-One time error was when do\untill not stopped by conditions. If so, need to do for each of $List_SRV Get-PSSession -ComputerName $pc | Remove-PSSession. If not helping - (gwmi win32_process -ComputerName "$your_problem_server") | WHERE-OBJECT { $_.Name -imatch "wsmprovhost.exe" } |% { $_.Name; $_.Terminate() }
 #>

#-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

#DCs ip address. 
$DC_srv = ""
#Where to output preparsed data. Need to be accesible from $NetEventTrace_DST. 
$result_hub = ""
#Output from servers as raw data files. Need to be created. Need to be smb share. Need to be accesible from all servers, that send raw data.
$NetEventTrace_DST = ""


#check if $result_hub exists, if not - create
if (test-path $result_hub) {
    Write-Output ((Get-Date -Format "HH:mm")+" "+$result_hub+" "+"folder exists")
    
}
    else{
        try{
            Write-Output ((Get-Date -Format "HH:mm")+" "+$result_hub+" "+"folder not exists, trying to create")
            New-Item -Path $result_hub  -ItemType "directory" | out-null
            Write-Output ((Get-Date -Format "HH:mm")+" "+$result_hub+" "+"folder created")
            }
        catch{
            Write-Output ((Get-Date -Format "HH:mm")+($Error[0].Exception.Message ))
            Break
            }
}

Write-Output ((Get-Date -Format "dddd MM/dd/yyyy HH:mm")+" "+"start script") 

#collect servers array
$List_SRV = Get-ADComputer -server $DC_srv  -Filter * -properties *|
Where-Object {$_.enabled -eq $true}|
Where-Object {$_.OperatingSystem -like "*Windows Server 2012 R2*"}|
Where-Object {(($_.distinguishedname -like "*Servers*") -and ($_.distinguishedname -notlike "*Test*")) -and ($_.LastLogonDate -ge ((Get-Date).AddDays(-14)))}| 
Select-Object -ExpandProperty "DNSHostName"


#foreach of collected do simultaneously
Invoke-Command -ComputerName $List_SRV -ScriptBlock {
#Timer to rpoceed logging. Reccomendded time is 43200 seconds(12h). 
$Timer_sec = 43200  
$Date_now= get-date
$myFQDN=(Get-WmiObject win32_computersystem).DNSHostName+"."+(Get-WmiObject win32_computersystem).Domain
$NetEventTrace_SRC = "C:\"+$myFQDN+"_NetEventTrace.etl" 
$Established_connections = "C:\"+$myFQDN+"_Established_connections.csv"

Write-Output (($myFQDN)+" "+(Get-Date -Format "HH:mm")+" "+"start network logging")
#start realtime network logging
$NetEventTrace_SRC = "C:\"+$myFQDN+"_NetEventTrace.etl"
    New-NetEventSession -Name $myFQDN | out-null
    Add-NetEventProvider -Name “Microsoft-Windows-TCPIP” -SessionName $myFQDN | out-null
    #Add-NetEventPacketCaptureProvider -IpProtocols $bytes -SessionName $myFQDN | out-null
    Set-NetEventSession -MaxFileSize 6000 -LocalFilePath $NetEventTrace_SRC | out-null
    Start-NetEventSession -Name $myFQDN | out-null
    Get-NetEventSession -Name $myFQDN
#start 10 sec step network logging for listening connections. Finish when timer is over or disk free space less 1 GB
    do {
            
            $disk = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='C:'" | Select-Object @{label='FreeSpaceGB';expression={$_.FreeSpace/1gb -as [int]}}
            get-NetTCPConnection -State Listen|Select-Object -Property CreationTime, LocalAddress, LocalPort, RemoteAddress, RemotePort, OwningProcess, @{name='Process';expression={(Get-Process -Id $_.OwningProcess).path}} | Sort-Object -Property Process, RemoteAddress, RemotePort, LocalPort | Export-Csv -Append -Delimiter ';' -Path $Established_connections -Encoding UTF8
            start-sleep -s 10
       
    }
    until (((Get-Date) -ge ($Date_now).AddSeconds($Timer_sec)) -or ($disk.FreeSpaceGB -le "1"))

Write-Output (($myFQDN)+" "+(Get-Date -Format "HH:mm")+" "+"stop network logging")

Stop-NetEventSession -Name $myFQDN
Remove-NetEventSession -Name $myFQDN

}


#move data
    foreach ($pc in $List_SRV) 
        {
        $error.Clear()
        Write-Output (($pc)+" "+(Get-Date -Format "HH:mm")+" "+"move data")
        $NetEventTrace_SRC_SMB = "\\"+$pc+"\C$\"+$pc+"_NetEventTrace.etl"
        $ProcID_SMB = "\\"+$pc+"\C$\"+$pc+"_dictionary.csv"
        $Established_connections_SMB = "\\"+$pc+"\C$\"+$pc+"_Established_connections.csv"
        Move-Item $NetEventTrace_SRC_SMB -Destination $NetEventTrace_DST -force
        Move-Item $Established_connections_SMB -Destination $result_hub -force
}
#parse data
    foreach ($pc in $List_SRV) 
        {
        $error.Clear()
        Write-Output (($pc)+" "+(Get-Date -Format "HH:mm K")+" "+"parse data")
        $result = $result_hub+"\"+$pc+"_Active_connections.csv"
        $Etl = $NetEventTrace_DST+"\"+$pc+"_NetEventTrace.etl"
        get-winevent -filterhashtable @{path=$Etl;Id='1033','1169'} -Oldest |
        where-object {$_.ProcessId -inotmatch "0"}|
        select @{Name = 'Route'; Expression = {(($_.message) -replace "^.+([(])|([)])|(connect|sending).+$") }}, @{Name = 'PID'; Expression = {($_.message) -replace "(TCP|UDP).+(PID = )|[.]"}},TimeCreated|
        Sort-Object -Property PID, TimeCreated |
        Export-Csv -Append -Delimiter ';' -Path $result -Encoding UTF8

}


Write-Output ((Get-Date -Format "dddd MM/dd/yyyy HH:mm")+" "+"clearing temp files")
get-childitem -path $NetEventTrace_DST | where {$_.name -like "*_NetEventTrace.etl"} | remove-item -Force
Write-Output ((Get-Date -Format "dddd MM/dd/yyyy HH:mm")+" "+"end script")

Remove-Variable -Name * -Force -ErrorAction SilentlyContinue