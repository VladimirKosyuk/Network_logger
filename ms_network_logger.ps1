#Created by https://github.com/VladimirKosyuk

#Collects array from all MS domain servers with network logged information from each one. Output view(*.txt files): Count – string repeat count, "Process ID (may be empty)";"Process name(may be empty)";local=ip:port remote=ip:port. Script progress output - CLI.
#
# Build date: 04.10.2020									   
 
#-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

#vars

#time in seconds to collect raw data from servers. 
$Timer_sec = 43200
#DCs ip address. Optional.
$DC_srv = ""
#DNS server for servers array. Need for execution step to collect connections from each server to all others.
$DNS_srv = ""
#Where to output preparsed data. Need to be created. Need to be accesible from $NetEventTrace_DST. Need to have embedded directory named result.
$result_hub = ""
#Output from servers as raw data files. Need to be created. Need to be smb share. Need to be accesible from all servers, that send raw data.
$NetEventTrace_DST = ""

Write-Output ((Get-Date -Format "dddd MM/dd/yyyy HH:mm K")+" "+"start script")

$List_SRV = Get-ADComputer -server $DC_srv  -Filter * -properties *|
Where-Object {$_.enabled -eq $true}|
Where-Object {$_.OperatingSystem -like "*Windows Server 2012 R2*"}|
where-object {$_.LastLogonDate -ge ((Get-Date).AddDays(-14))}| 
Select-Object -ExpandProperty "DNSHostName"

#start trace
    foreach ($pc in $List_SRV) 
        {
        $error.Clear()
        Write-Output (($pc)+" "+(Get-Date -Format "HH:mm K")+" "+"start trace")
        Invoke-Command -ComputerName $pc {
        $VerbosePreference='Continue'
        $myFQDN=(Get-WmiObject win32_computersystem).DNSHostName+"."+(Get-WmiObject win32_computersystem).Domain
        $NetEventTrace_SRC = "C:\"+$myFQDN+"_NetEventTrace.etl"
        New-NetEventSession -Name $myFQDN 
        Add-NetEventProvider -Name “Microsoft-Windows-TCPIP” -SessionName $myFQDN
        Set-NetEventSession -MaxFileSize 6000 -LocalFilePath $NetEventTrace_SRC
        Start-NetEventSession -Name $myFQDN
        Get-NetEventSession -Name $myFQDN
        }
    }

echo "Collecting raw data"
Get-Date
Start-Sleep -Seconds $Timer_sec

#stop trace and get proccess data
    foreach ($pc in $List_SRV) 
        {
        $error.Clear()
        Write-Output (($pc)+" "+(Get-Date -Format "HH:mm K")+" "+"stop trace and get proccess data")
        Invoke-Command -ComputerName $pc {
        $VerbosePreference='Continue'
        $myFQDN=(Get-WmiObject win32_computersystem).DNSHostName+"."+(Get-WmiObject win32_computersystem).Domain
        Stop-NetEventSession -Name $myFQDN
        Remove-NetEventSession -Name $myFQDN
        $ProcID = "C:\"+$myFQDN+"_ProcID.csv"
        #get process list remotely
        Get-Process -ErrorAction SilentlyContinue| Select-Object ID, ProcessName | Export-Csv -Path $ProcID -NoTypeInformation
        }

}
#move data
    foreach ($pc in $List_SRV) 
        {
        $error.Clear()
        Write-Output (($pc)+" "+(Get-Date -Format "HH:mm K")+" "+"move data")
        $NetEventTrace_SRC_SMB = "\\"+$pc+"\C$\"+$pc+"_NetEventTrace.etl"
        $ProcID_SMB = "\\"+$pc+"\C$\"+$pc+"_ProcID.csv"
        Move-Item $NetEventTrace_SRC_SMB, $ProcID_SMB -Destination $NetEventTrace_DST
}
#preparse data
    foreach ($pc in $List_SRV) 
        {
        $error.Clear()
        Write-Output (($pc)+" "+(Get-Date -Format "HH:mm K")+" "+"preparse data")
        #parse and agragate data
        $result = $result_hub+"\"+$pc+"_net_connections.txt"
        $Etl = $NetEventTrace_DST+"\"+$pc+"_NetEventTrace.etl"
        $CSV = $NetEventTrace_DST+"\"+$pc+"_ProcID.csv"
        get-winevent -filterhashtable @{path=$Etl;Id='1038'} -Oldest |
        where-object {$_.ProcessId -inotmatch "0"}|

        select @{Name = 'Process'; Expression = {(Select-String -Path $CSV -Pattern ('"'+$_.ProcessId+'"') | Select-Object -ExpandProperty line) -replace ",", ";"}},
        @{Name = 'Message'; Expression = {((($_.message) -replace "((TCP: connection\s..................).+[(])") -replace "([)]\s(close issued)).") -replace "(local=)+(.(::\d)+(.(:))).+(remote=)(.(::\d)+(.(:))).+"}} |
        Sort-Object -Property Process |
        select @{Name='Strings'; Expression ={($_.Process), ($_.Message) -join ';'}} | 
        Group-Object -Property Strings -NoElement |
        Format-Table -Property Count, Name -AutoSize |
        out-file $result -append
}
#collect connections from each server to all others
$Array = ((get-childitem $result_hub |Where-Object {-Not $_.PSIscontainer}).name) -replace "_net_connections.txt"
    foreach ($SRV in $Array){
        $IpAddr = (Resolve-DnsName $SRV -Server $DNS_srv).IPAddress
        $OutLog = $result_hub+"\result\"
        Write-Output ($SRV+" "+$IpAddr+" "+(Get-Date -Format "HH:mm K")+" "+"collect connections")
        get-content -path $result_hub"\*.txt"|
        Where-Object {-Not $_.PSIscontainer} | 
        select-string -Pattern "(((local=)+($IpAddr)+(:)|(remote=)+($IpAddr)+(:))|((local=)+(.)+($IpAddr)+(\D)+(:)|(remote=)+(.)+($IpAddr)+(\D)+(:)+(.)+(;)))"| 
        out-file $OutLog\$SRV".txt" -append
} 
#delete preparsed data files
Write-Output ($SRV+" "+$IpAddr+" "+(Get-Date -Format "HH:mm K")+" "+"clear preparsed data")
get-childitem $result_hub |Where-Object {-Not $_.PSIscontainer} | Select-Object -ExpandProperty FullName | Remove-Item

Write-Output ((Get-Date -Format "dddd MM/dd/yyyy HH:mm K")+" "+"end script")

Remove-Variable -Name * -Force -ErrorAction SilentlyContinue
