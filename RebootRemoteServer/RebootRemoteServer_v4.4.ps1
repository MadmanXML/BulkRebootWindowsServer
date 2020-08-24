############################################
#Last Edit Author：xiamingliang
#E-mail：xiamingliang163@163.com
#Phone:15216839240
#Last Update Date:2019/04/02
############################################

$scriptStartTime = Get-Date
#######################################################
#Variable Zone
#######################################################
#reboot windows server who joined in domain on the list
$contents = import-csv c:\RebootRemoteServer\serverlist.csv
$serverlist = $contents.ServerIP
$servicelistpath = "C:\RebootRemoteServer\ServicesCheck"
$domainname = "TESTDOMAIN.COM"
$result_log = "c:\RebootRemoteServer\Logs\server_result.csv"
$reportfile = "C:\RebootRemoteServer\Reports\RebootRemoteServerReport_{0}.csv" -f $scriptStartTime.ToString("yyyyMMddhhmmss")
$logfile = "C:\RebootRemoteServer\Logs\RebootRemoteServerLog_{0}.log" -f $scriptStartTime.ToString("yyyyMMddhhmmss")

#if you need input username and password manual;
#if need to reboot server in domain;we use current logon user run all command
##$Credential_domainadmin = Get-Credential

#if you neeed input usernam and password auto;
#$User = "administrator"
#$PWord = ConvertTo-SecureString -String "P@ssw0rd" -AsPlainText -Force
#$Credential_admin = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $User, $PWord



#######################################################
#Function Zone
#######################################################
#for not in domain computer;we cannot user get-service cmdlet;so change to get-wmi
function checkkeyservicestatus($sl,$computername,$connectCredential){
    $result = $true
    $serviceDetail = @{}
    foreach($servicename in $sl){
        if($connectCredential -eq $Null){
            $ServiceStatus = $(Get-WmiObject Win32_Service -ComputerName $computername -Filter "Name='$($servicename.servicesname)'").State
            $sn = $servicename.servicesname
            $serviceDetail.$sn = $ServiceStatus
        }else{
            $ServiceStatus = $(Get-WmiObject Win32_Service -ComputerName $computername -Filter "Name='$($servicename.servicesname)'" -Credential $connectCredential).State
            $sn = $servicename.servicesname
            $serviceDetail.$sn = $ServiceStatus
        }
        if($ServiceStatus -eq $servicename.servicestatus){
            $result = $result -and $true
        }else{
            $result = $result -and $false
        }
    }
    if($result){
        $serviceDetail.allservicestatus = "Worked"
        return $serviceDetail
    }else{
        $serviceDetail.allservicestatus = "Failed"
        return $serviceDetail
    }
}



function writereport($reportfile,$ReportContent){
    foreach($i in $ReportContent.keys){
        $content = $ReportContent.$i | select @{ Label = 'ip'; Expression = { $_.ip} },@{ Label = 'bfrebootNetConnection'; Expression = { $_.bfrebootNetConnection} },@{ Label = 'bfrebootFQDN'; Expression = { $_.bfrebootFQDN} },@{ Label = 'bfrebootInDomain'; Expression = { $_.bfrebootInDomain} },@{ Label = 'bfrebootCredentialusername'; Expression = { $_.bfrebootCredentialusername} },@{ Label = 'CredentialStatus'; Expression = { $_.CredentialStatus} },@{ Label = 'bfrebootRunreboot'; Expression = { $_.bfrebootRunreboot} },@{ Label = 'waittime'; Expression = { $_.waittime} },@{ Label = 'afrebootNetConnection'; Expression = { $_.afrebootNetConnection} },@{ Label = 'afrebootlastBootuptime'; Expression = { $_.afrebootlastBootuptime} },@{ Label = 'afrebootallServiceStatus'; Expression = { $_.afrebootallServiceStatus} }
        $content | Export-Csv $reportfile -NoTypeInformation -Append -Encoding UTF8
    }
}



function writelog($logfile,$messagetime,$messagelevel,$serverip,$message){
    $logcontent = "{0} {1} {2} {3}" -f $messagetime,$messagelevel,$serverip,$message
    $logcontent | Out-File -FilePath $logfile -Append -Encoding utf8  
}




#######################################################
#Phase 1:Reboot
#######################################################
$result1 = @{}
#get and reboot server
$message = "Start Phase 1."
writelog $logfile (Get-Date).ToString() "Info" Null $message
foreach ($content in $contents){
	$out = "start reboot {0}" -f $content.ServerIP
    Write-Host $out -BackgroundColor Green
    $r = @{}
    $r.ip = $content.ServerIP
    $message = "Handle {0}." -f $r.ip
    writelog $logfile (Get-Date).ToString() "Info" $r.ip $message
	$User = $content.AdminUserName
	$PWord = ConvertTo-SecureString -String $content.Password -AsPlainText -Force
	$Credential_admin = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $User, $PWord
    #judge net connect
    if($(Test-NetConnection -ComputerName $content.ServerIP).PingSucceeded){
        $r.bfrebootNetConnection = "YES"
        $message = "Test Network Connection;Result is {0}." -f $r.bfrebootNetConnection
        writelog $logfile (Get-Date).ToString() "Info" $r.ip $message
        #get Server FQDN name then decide which credential need
        $fqdn = ([System.Net.Dns]::GetHostByName((([system.net.dns]::GetHostByAddress($content.ServerIP)).hostname))).Hostname
        $r.bfrebootFQDN = $fqdn
        $message = "Get {0} FQDN;Result is {1}." -f $r.ip,$r.bfrebootFQDN
        writelog $logfile (Get-Date).ToString() "Info" $r.ip $message
		$r.Credential = $Credential_admin.UserName
        $r.bfrebootCredentialusername = $Credential_admin.UserName 
        if($fqdn.ToLower().Contains($domainname.ToLower())){
            #case in domain
            $r.bfrebootInDomain = "YES"
            $message = "Judge {0} whether in domain {1};Result is {2}." -f $r.ip,$domainname,$r.bfrebootInDomain
            writelog $logfile (Get-Date).ToString() "Info" $r.ip $message
            try{
                $j = get-wmiobject -class win32_OperatingSystem -namespace "root\cimv2" -computer $content.ServerIP -credential $Credential_admin
                $r.CredentialStatus = "Right"
				$message = "Judge administrator Credential;Credential is {0} and CredentialStatus is {1}." -f $r.bfrebootCredentialusername,$r.CredentialStatus
				writelog $logfile (Get-Date).ToString() "Info" $r.ip $message
				$j.reboot() | Out-Null
				$r.bfrebootRunreboot="YES"
				$message = "Reboot action has been done.Start Next..."
				writelog $logfile (Get-Date).ToString() "Info" $r.ip $message
            }catch{
                $r.CredentialStatus = "Wrong"
				$message = "Judge default local administrator Credential;Credential is {0} and CredentialStatus is {1}." -f $r.bfrebootCredentialusername,$r.CredentialStatus
                writelog $logfile (Get-Date).ToString() "Error" $r.ip $message
				$r.bfrebootRunreboot="NO"
				$message = "Reboot action doesn't finished.Start Next..."
				writelog $logfile (Get-Date).ToString() "Warning" $r.ip $message
            }
            #$r.Credential = $Credential_admin.UserName
            #$r.bfrebootCredentialusername = $Credential_admin.UserName 
            
            
        }else{
            #case not in domain
            $r.bfrebootInDomain = "NO"
            $message = "Judge {0} whether in domain {1};Result is {2}." -f $r.ip,$domainname,$r.bfrebootInDomain
            writelog $logfile (Get-Date).ToString() "Info" $r.ip $message
            try{
                $j = get-wmiobject -class win32_OperatingSystem -namespace "root\cimv2" -computer $content.ServerIP -Credential $Credential_admin
                $r.CredentialStatus = "Right"
                $message = "Judge default local administrator Credential;Credential is {0} and CredentialStatus is {1}." -f $r.bfrebootCredentialusername,$r.CredentialStatus
                writelog $logfile (Get-Date).ToString() "Info" $r.ip $message
                $j.reboot() | Out-Null
                $r.bfrebootRunreboot="YES"
                $message = "Reboot action has been done.Start Next..."
                writelog $logfile (Get-Date).ToString() "Info" $r.ip $message
            }catch{
                #Credential Wrong!!!
                $r.CredentialStatus = "Wrong"
                $message = "Judge default local administrator Credential;Credential is {0} and CredentialStatus is {1}." -f $r.bfrebootCredentialusername,$r.CredentialStatus
                writelog $logfile (Get-Date).ToString() "Error" $r.ip $message
				$r.bfrebootRunreboot="NO"
                $message = "Reboot action doesn't finished.Start Next..."
                writelog $logfile (Get-Date).ToString() "Warning" $r.ip $message
            }
			#$r.Credential = $Credential_admin
            #$r.bfrebootCredentialusername = $Credential_admin.UserName
        }
    }else{
        $r.bfrebootNetConnection = "NO"
        $r.bfrebootFQDN = "Unknow"
        $r.bfrebootInDomain = "Unknow"
        $r.Credential = "Null"
        $r.bfrebootCredentialusername = "Unknow"
        $r.bfrebootRunreboot="NO"
        $message = "Test Network Connection;Result is {0}.Start next..." -f $r.bfrebootNetConnection
        writelog $logfile (Get-Date).ToString() "Info" $r.ip $message
    }
    $result1.($content.ServerIP) = $r
}

 
#######################################################
#Phase 2:wait
#######################################################
#wait for reboot
$waittime = 90
$message = "wait for {0}s" -f $waittime
Write-Host $message -BackgroundColor Green
$message = "start wait for {0}s;Phase 2" -f $waittime
writelog $logfile (Get-Date).ToString() "Info" "Null" $message
Start-Sleep -s $waittime
$message = "finished wait for {0}s" -f $waittime
writelog $logfile (Get-Date).ToString() "Info" "Null" $message


#######################################################
#Phase 3:judge
#######################################################
#get result
$message = "start Collect result:Phase 3"
writelog $logfile (Get-Date).ToString() "Info" "Null" $message
foreach ($content in $contents){
	$User = $content.AdminUserName
	$PWord = ConvertTo-SecureString -String $content.Password -AsPlainText -Force
	$Credential_admin = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $User, $PWord
    $result1.($content.ServerIP).waittime = $waittime
	$out = "get {0} reboot result and recode to log" -f $content.ServerIP
    Write-Host $out -BackgroundColor Green
    $message = "get {0} reboot result" -f $content.ServerIP
    writelog $logfile (Get-Date).ToString() "Info" $content.ServerIP $message
    #judge net connect
    if($(Test-NetConnection -ComputerName $content.ServerIP).PingSucceeded){
        $result1.($content.ServerIP).afrebootNetConnection = "YES"
        $message = "Test Network Connection;Result is {0}." -f $result1.($content.ServerIP).afrebootNetConnection
        writelog $logfile (Get-Date).ToString() "Info" $content.ServerIP $message
        #get Server FQDN name then decide which credential need
        $indomain = $result1.($content.ServerIP).bfrebootInDomain
        if($result1.($content.ServerIP).CredentialStatus -eq "Right"){
            $message = "The CredentialStatus Result is {0} before reboot." -f $result1.($content.ServerIP).CredentialStatus
            writelog $logfile (Get-Date).ToString() "Info" $content.ServerIP $message
            if($indomain -eq "YES"){
                #case in domain
                $message = "The Server {0} in domain {1}." -f $content.ServerIP,$domainname
                writelog $logfile (Get-Date).ToString() "Info" $content.ServerIP $message
                $starttime = $(Get-WmiObject Win32_OperatingSystem -ComputerName $content.ServerIP -Credential $Credential_admin).lastBootuptime
				#Converts a given DMTF datetime to DateTime. The returned DateTime will be in the current time zone of the system.
				$starttime = [Management.ManagementDateTimeConverter]::ToDateTime($starttime)
                $result1.($content.ServerIP).afrebootlastBootuptime = $starttime
                $message = "The Server {0} lastBootuptime is {1}." -f $content.ServerIP,$result1.($content.ServerIP).afrebootlastBootuptime
                writelog $logfile (Get-Date).ToString() "Info" $content.ServerIP $message
                $servicelistfile = $servicelistpath + $content.ServerIP + '.csv'
                #the servicelist file exist and not null
                if((Test-Path $servicelistfile) -and ((Get-Content $servicelistfile) -ne $Null)){
                    $message = "The Server {0} service file is {1} and not null." -f $content.ServerIP,$servicelistfile
                    writelog $logfile (Get-Date).ToString() "Info" $content.ServerIP $message
                    $servicelist = Import-Csv $servicelistfile
                    $sstatus = checkkeyservicestatus $servicelist $content.ServerIP
                    $result1.($content.ServerIP).afrebootallServiceStatus = $sstatus.allservicestatus
                    $result1.($content.ServerIP).afrebootServiceStatusdetail = $sstatus
                    $message = "The Server {0} after reboot allServiceStatus is {1}." -f $content.ServerIP,$result1.($content.ServerIP).afrebootallServiceStatus
                    writelog $logfile (Get-Date).ToString() "Info" $content.ServerIP $message
                    $message = "The Server {0} after reboot ServiceStatus detail is {1}." -f $content.ServerIP,$result1.($content.ServerIP).afrebootServiceStatusdetail
                    writelog $logfile (Get-Date).ToString() "Info" $content.ServerIP $message
                }else{
                    $result1.($content.ServerIP).afrebootallServiceStatus = "Null:default OK"
                    $message = "The Server {0} service file {1} not exist or is null." -f $content.ServerIP,$servicelistfile
                    writelog $logfile (Get-Date).ToString() "Info" $content.ServerIP $message
                }
            }else{
                #case not in domain
                $starttime = $(Get-WmiObject Win32_OperatingSystem -ComputerName $content.ServerIP -Credential $Credential_admin).lastBootuptime
                $result1.($content.ServerIP).afrebootlastBootuptime = $starttime
                $message = "The Server {0} lastBootuptime is {1}." -f $content.ServerIP,$result1.($content.ServerIP).afrebootlastBootuptime
                writelog $logfile (Get-Date).ToString() "Info" $content.ServerIP $message
                $servicelistfile = $servicelistpath + $content.ServerIP + '.csv'
                #the servicelist file exist and not null
                if((Test-Path $servicelistfile) -and ((Get-Content $servicelistfile) -ne $Null)){
                    $servicelist = Import-Csv $servicelistfile
                    $sstatus = checkkeyservicestatus $servicelist $content.ServerIP $Credential
                    $result1.($content.ServerIP).afrebootallServiceStatus = $sstatus.allservicestatus
                    $result1.($content.ServerIP).afrebootServiceStatusdetail = $sstatus
                    $message = "The Server {0} allServiceStatus is {1}." -f $content.ServerIP,$result1.($content.ServerIP).afrebootallServiceStatus
                    writelog $logfile (Get-Date).ToString() "Info" $content.ServerIP $message
                }else{
                    $result1.($content.ServerIP).afrebootallServiceStatus = "Null:default OK"
                    $message = "The Server {0} service file {1} not exist or is null." -f $content.ServerIP,$servicelistfile
                    writelog $logfile (Get-Date).ToString() "Info" $content.ServerIP $message
                }
            }
        }else{
            $result1.($content.ServerIP).afrebootlastBootuptime = "Unknow"
            $result1.($content.ServerIP).afrebootallServiceStatus = "Unknow"
            $result1.($content.ServerIP).afrebootServiceStatusdetail = "Unknow"
            $message = "The CredentialStatus Result is {0} before reboot;so not check after reboot status." -f $result1.($content.ServerIP).CredentialStatus
            writelog $logfile (Get-Date).ToString() "Info" $content.ServerIP $message
        }
    }else{
        #case net not connection
        $result1.($content.ServerIP).afrebootNetConnection = "NO"
        $result1.($content.ServerIP).afrebootlastBootuptime = "Unknow"
        $result1.($content.ServerIP).afrebootallServiceStatus = "Unknow"
        $result1.($content.ServerIP).afrebootServiceStatusdetail = @{}
        $message = "After reboot the server {0} network not connection;so not check after reboot status." -f $content.ServerIP
        writelog $logfile (Get-Date).ToString() "Info" $content.ServerIP $message
    }
}


#######################################################
#Phase 4:Ending
#######################################################
#write report
$message = "startwrite report:Phase 4"
writelog $logfile (Get-Date).ToString() "Info" "Null" $message
writereport $reportfile $result1
$scriptFinishedTime = Get-Date
$timeLapse = $scriptFinishedTime - $scriptStartTime
$message = "Total time spent: {0}Days {1}Hours {2}Minutes {3}Seconds！" -f $timeLapse.Days,$timeLapse.Hours,$timeLapse.Minutes,$timeLapse.Seconds
Write-Host $message -BackgroundColor Gray
writelog $logfile (Get-Date).ToString() "Info" "Null" $message
$message = "---------Finished!!!---------"
writelog $logfile (Get-Date).ToString() "Info" "Null" $message

