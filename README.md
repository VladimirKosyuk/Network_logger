# Network_logger_v2

Does:

For all prodution MS 2012 R2 servers and above simultaneously collects network established connections(every 10 secodns) and active connections(realtime) to csv files during 12 hours and moves them to SMB-share.

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

-One time error was when do\untill not stopped by conditions
