#Created by https://github.com/VladimirKosyuk

# For each Network_logger output files finds unique local ip, local port, remote ip, remote port, pid

# Build date: 11.11.2020

#data source, where active connections files placed
$source = ""
#data destanation - where to output parsing result
$hub = ""
#mark to find proper data files

$ext = "_Active_connections.csv"
#collects array
$matrix = get-childitem -path $source | where {$_.name -like "*$ext"} | select -ExpandProperty fullname

foreach ($m in $matrix){
#parse active connections route to remote_port local_port remote_ip local_ip
$data = import-csv -Path $m -Delimiter ';' -Encoding UTF8 |
#cut ipv6 localhost routes
where {$_.route -notmatch "^(local).+(::1).+(remote).+(::1).+$"} |
select @{Name = 'remote'; Expression = {(($_.Route) -replace '^.+(?=(remote))')}}, #^.+\s not working
@{Name = 'local'; Expression = {(($_.Route) -replace "(remote).+(:).+$")}},
* |
select @{Name = 'remote_port'; Expression = {(($_.remote) -replace '^.+(:)')}},
@{Name = 'local_port'; Expression = {(($_.local) -replace '^.+(:)')}},
@{Name = 'remote_ip'; Expression = {((($_.remote) -replace '(:).+$') -replace "remote=")}},
@{Name = 'local_ip'; Expression = {((($_.local) -replace '(:).+$') -replace "local=")}},
PID, TimeCreated
#get all custom properties, but not TimeCreated
$prop = $data |Get-Member |where {$_.MemberType -match "NoteProperty" -and $_.Name -notmatch "TimeCreated"} | select -ExpandProperty name
#set output file name
$file_out = ((($m) -replace [regex]::Escape($source)) -replace [regex]::Escape($ext))+"_Active_connections.txt"

foreach ($p in $prop) {
$p | out-file $hub"\"$file_out -Append
$data| select -ExpandProperty $p -Unique | out-file $hub"\"$file_out -Append
}

}
