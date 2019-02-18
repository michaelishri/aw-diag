#================================================================================
# Filename: aw-diag-v0.0x.ps1
# Author: Michael Ishri
# Date: 15th Feb 2019
# Description: Presents AirWatch releated diagnostic information
# To Do:
# - Check AW queues..done
# - Check Windows services..done
# - AW log files
# - Open ports
# - AWCM truststore
# - SSL certificate
# - JAVA_HOME..done
#================================================================================

Param (
    [Parameter(Mandatory=$false)][Switch]$DontPoll,
    [Parameter(Mandatory=$false)][int16]$PollIntervalSec=2
)

$Global:APP_TITLE = "AirWatch Diagnostics Tool"
$Host.UI.RawUI.WindowTitle = $Global:APP_TITLE


#================================================================================
# FUNCTION: Test-PSVersion
#================================================================================
# Description
#   Ensure the script is running on the correct version of PowerShell.
#
# Example
#   Test-PSVersion
#--------------------------------------------------------------------------------
Function Test-PS6Version() {
    If($PSVersionTable.PSVersion.Major -lt 6) {
        Write-Host "AW-DIAG: PowerShell v6 or newer required, please run script with PS6 (pwsh)." -ForegroundColor Red
        Exit
    }
}

#================================================================================
# FUNCTION: Write-Title -Title -Colour -Center
#================================================================================
# Description
#    Writes a bordered title to the terminal.
#
# Parameters
#  -Title: Specify the text to be shown, should be less than 80 characters long.
#  -Colour: Optionally specify the color of the text. Pleae use the standard
#            PowerShell Foreground colours. Default: White
#  -Center: Optionally specify if the title text should be centred.
#
# Example
#   Write-Title -Title "My Title" -Color Green -Centre
#--------------------------------------------------------------------------------
Function Write-Title() {
    param (
        [Parameter(Mandatory=$true,Position=1)][String]$Title,
        [Parameter(Mandatory=$false,Position=2)][String]$Colour="White",
        [Parameter(Mandatory=$false)][Switch]$Centre
    )

    If($Centre) {
        $LeftPadding = 40 + ([math]::Round($Title.Length / 2))
        $Title = $Title.PadLeft($LeftPadding)
    }

    Write-Host "==============================================================================="
    Write-Host " $($Title)" -ForegroundColor $Colour
    Write-Host "==============================================================================="
}

#================================================================================
# FUNCTION: Get-MsmqQueue -QueueType [Private|Public]
#================================================================================
# Description
#   Reads information about the Microsoft Message Queues.
#
# Example
#   Get-MsmqQueue -QueueType Private
#--------------------------------------------------------------------------------
Function Get-MsmqQueue() {
    param (
        [Parameter(Mandatory=$false)][ValidateSet("Private","Public")][String]$QueueType
    )

    If($QueueType -eq "Private") {
        $queues = Get-CimInstance Win32_PerfRawData_MSMQ_MSMQQueue -Filter "Name LIKE '%private$%'"
    } Else {
        $queues = Get-CimInstance Win32_PerfRawData_MSMQ_MSMQQueue
    }

    $collQueues = New-Object System.Collections.ArrayList

    ForEach($queue in $queues) {
        $objQueue = New-Object System.Object
        $objQueue | Add-Member -MemberType NoteProperty -Name "QueueName" -Value $queue.Name
        $objQueue | Add-Member -MemberType NoteProperty -Name "MessageCount" -Value $queue.MessagesinQueue

        $collQueues.Add($objQueue) | Out-Null
    }

    # Convert the list to a new object that matches the original fields if you want to polyfill.
    # https://docs.microsoft.com/en-us/powershell/module/msmq/get-msmqqueue?view=win10-ps

    return $collQueues
}

#================================================================================
# FUNCTION: Get-MessageQueueCount
#================================================================================
# Description
#   Returns the number of messages in the private queue.
#
# Example
#   Get-MessageQueueCount
#--------------------------------------------------------------------------------
Function Get-MessageQueueCount {
    $queueCount = (Get-MsmqQueue -QueueType Private | Measure-Object -Sum MessageCount).Sum

    If($null -eq $queueCount) {
        $queueCount = 0
    }

    return $queueCount
}

#================================================================================
# FUNCTION: Read-WindowsHostFile
#================================================================================
# Description
#   Reads the Windows DNS host file from disk and parses it into a PowerShell
#   collection.
#
# Example
#   Read-WindowsHostFile
#--------------------------------------------------------------------------------
Function Read-WindowsHostFile() {
    $hostFile = "C:\Windows\System32\drivers\etc\hosts"

    $hostEntries = New-Object System.Collections.ArrayList

    ForEach($line In Get-Content $hostFile) {
        If(-not $line.StartsWith("#")) {
            $hostLine = ($line -Replace "\s+"," ").Split("#")[0]
            If($hostLine -notmatch '^\s*$') {
                $hostLine = $hostLine.Split(" ", 2)

                $hostEntry = New-Object System.Object
                $hostEntry | Add-Member -MemberType NoteProperty -Name "ip" -Value $hostLine[0]
                $hostEntry | Add-Member -MemberType NoteProperty -Name "hosts" -Value $hostLine[1]
                $null = $hostEntries.Add($hostEntry)
            }
        }
    }

    Return $hostEntries
}

#================================================================================
# FUNCTION: Read-InstalledSoftware
#================================================================================
# Description
#   Reads all the installed software from WMI. This is inaccurate and will need
#   to be reworked but it pulls the information that is needed currently.
#
# Example
#   Read-InstalledSoftware
#--------------------------------------------------------------------------------
Function Read-InstalledSoftware() {
    $wmiObjects = Get-CimInstance Win32Reg_AddRemovePrograms | Sort-Object DisplayName
    Return $wmiObjects
}

#================================================================================
# FUNCTION: Read-AirwatchRegistryKeys
#================================================================================
# Description
#   Reads the specified AirWatch registry keys.
#
# Example
#   Read-AirwatchRegistryKeys
#--------------------------------------------------------------------------------
Function Read-AirwatchRegistryKeys() {
    $hive = "HKLM:\SOFTWARE\Wow6432Node\AirWatch"
    $keys = @("IS_SQLSERVER_SERVER", "Version", "ACMSERVERIP", "ACMSERVERPORT", "AWCMNODES", "AWSERVER", "AWSERVERDS", "AWVERSIONDIR")

    $awRegistry = New-Object System.Object

    ForEach($key in $keys) {
        $awValue = (Get-ItemProperty -Path $hive -Name $key).$key
        $awRegistry | Add-Member -MemberType NoteProperty -Name $key -Value $awValue
    }

    Return $awRegistry
}

#================================================================================
# FUNCTION: Read-AWCMConfig
#================================================================================
# Description
#   Reads the specified AirWatch Cloud Messaging configuration file keys.
#
# Example
#   Read-AWCMConfig
#--------------------------------------------------------------------------------
Function Read-AWCMConfig() {
    $awcmConfig = "$($AirWatch.Registry.AWVERSIONDIR)\AWCM\config\awcm.properties"
    $awcmKeys = @("AWCM_VERSION", "AWCM_CLUSTERING_MODE", "AWCM_DATABASE_PROVIDER", "AWCM_OFFLOAD_SSL", "AWCM_DISABLED_SSL_PROTOCOLS", "AWCM_SERVICE_HOST", "AWCM_SERVICE_PORT")

    $awcm = New-Object System.Object

    ForEach($line In Get-Content $awcmConfig) {
        ForEach($awcmKey In $awcmKeys) {
            If($line -match "$($awcmKey)=") {
                $awcmKvp = $line.Split("=")

                If($awcmKvp[1] -eq "Y") { $awcmKvp[1] = "Yes" }
                If($awcmKvp[1] -eq "N") { $awcmKvp[1] = "No" }

                $awcm | Add-Member -MemberType NoteProperty -Name $awcmKey -Value $awcmKvp[1]
            }
        }
    }

    Return $awcm
}

#================================================================================
# FUNCTION: AWCMClusterConfig
#================================================================================
# Description
#   Reads the AWCM cluster configuration from the hazelcast.xml file.
#
# Example
#   AWCMClusterConfig
#--------------------------------------------------------------------------------
Function Read-AWCMClusterConfig() {
    $clusterConfig = "$($AirWatch.Registry.AWVERSIONDIR)\AWCM\config\hazelcast.xml"
    [xml]$awcmConfig = Get-Content $clusterConfig

    $awcm = New-Object System.Object
    $awcm | Add-Member -MemberType NoteProperty -Name "Members" -Value $awcmConfig.hazelcast.network.join.'tcp-ip'.member
    $awcm | Add-Member -MemberType NoteProperty -Name "MultiCast" -Value $awcmConfig.hazelcast.network.join.multicast.enabled

    Return $awcm
}

#================================================================================
# FUNCTION: Write-MessageQueueCountToScreen
#================================================================================
# Description
#   Returns the number of messages in the private queue.
#
# Example
#   Write-MessageQueueCountToScreen
#--------------------------------------------------------------------------------
Function Write-MessageQueueCountToScreen() {
    Write-Host " - AirWatch Message Queues: " -NoNewline

    $queueCount = $(Get-MessageQueueCount)

    if($queueCount -eq 0) {
        Write-Host "0"
    }
    elseif($queueCount -gt $AirWatch.LastQueueCount) {
        Write-Host "$($queueCount) (up)" -ForegroundColor Magenta
    } elseif($queueCount -lt $AirWatch.LastQueueCount) {
        Write-Host "$($queueCount) (down)" -ForegroundColor Yellow
    } else {
        Write-Host "$($queueCount) (steady)" -ForegroundColor Cyan
    }

    $AirWatch.LastQueueCount = $queueCount
}

#================================================================================
# FUNCTION: Write-DownServices
#================================================================================
# Description
#   Returns the number of messages in the private queue.
#
# Example
#   Write-MessageQueueCountToScreen
#--------------------------------------------------------------------------------
Function Write-DownServicesToScreen() {
    $services = Get-Service AirWatch*,W3SVC | Where-Object { $_.Status -ne "Running" }

    If($null -eq $services) {
        Write-Host " - Windows Services: " -NoNewline
        Write-Host "All Windows services are running" -ForegroundColor Green
    } Else {
        Write-Host " - Windows Services: "
        ForEach($service In $services) {
            Write-Host "   > $($service.DisplayName), is NOT running" -ForegroundColor Red
        }
    }
}

#================================================================================
# FUNCTION: Write-WindowsHostFileToScreen
#================================================================================
# Description
#   Writes all host file entries to the screen.
#
# Example
#   Write-MessageQueueCountToScreen
#--------------------------------------------------------------------------------
Function Write-WindowsHostFileToScreen() {

    Write-Host "`n Host File Entries"
    ForEach($Entry in $AirWatch.WindowsHostFile) {
        Write-Host " - $($Entry.ip): $($Entry.hosts)"
    }
}

#================================================================================
# FUNCTION: Write-AwGeneralDetailsToScreen
#================================================================================
# Description
#   Writes the General Environment Details section to the screen.
#
# Example
#   Write-AwGeneralDetailsToScreen
#--------------------------------------------------------------------------------
Function Write-AwGeneralDetailsToScreen() {

    Write-Host "`n General Environment Details"
    Write-Host " - AirWatch Version: $($AirWatch.Registry.version)"
    Write-Host " - SQL Server: $($AirWatch.Registry.IS_SQLSERVER_SERVER)"
    Write-Host " - Console Host: $($AirWatch.Registry.AWSERVER.ToLower())"
    Write-Host " - Device Services Host: $($AirWatch.Registry.AWSERVERDS.ToLower())"
    Write-Host " - Installation Path: $($AirWatch.Registry.AWVERSIONDIR)"
    Write-JavaHomeLocationToScreen
}

#================================================================================
# FUNCTION: Write-AwcmDetailsToScreen
#================================================================================
# Description
#   Writes the AirWatch Cloud Messaging section to the screen.
#
# Example
#   Write-AwcmDetailsToScreen
#--------------------------------------------------------------------------------
Function Write-AwcmDetailsToScreen() {

    Write-Host "`n AirWatch Cloud Messaging"
    Write-Host " - Version: $($AirWatch.AWCM.AWCM_VERSION)"
    Write-Host " - Location: $($AirWatch.AWCM.AWCM_SERVICE_HOST):$($AirWatch.AWCM.AWCM_SERVICE_PORT)"
    Write-Host " - SSL Offloading: $($AirWatch.AWCM.AWCM_OFFLOAD_SSL)"
    Write-Host " - Disabled SSL Protocols: $($AirWatch.AWCM.AWCM_DISABLED_SSL_PROTOCOLS)"
    Write-Host " - Clustering Mode: $($AirWatch.AWCM.AWCM_CLUSTERING_MODE)"
    Write-Host " - Database Provider: $($AirWatch.AWCM.AWCM_DATABASE_PROVIDER)"

    Write-Host " - Cluster Nodes:"
    $ClusterNodes = ($AirWatch.AWCMCluster.Members).Split(",").Trim()
    ForEach($ClusterNode In $ClusterNodes) {
        If( $ClusterNode -like "$($env:COMPUTERNAME).$($env:USERDNSDOMAIN)*" ) {
            Write-Host "   > $($ClusterNode) (me)"
        } Else {
            Write-Host "   > $($ClusterNode)"
        }
    }
}

#================================================================================
# FUNCTION: Write-JavaHomeLocationToScreen
#================================================================================
# Description
#   Writes the location of the JAVA_HOME environment variable to screen.
#
# Example
#   Write-JavaHomeLocationToScreen
#--------------------------------------------------------------------------------
Function Write-JavaHomeLocationToScreen() {

    If($env:JAVA_HOME) {
        Write-Host " - JAVA_HOME Environment Variable: $($env:JAVA_HOME)"
    } Else {
        Write-Host " - JAVA_HOME Environment Variable:" -NoNewline
        Write-Host " Not configured" -ForegroundColor Red
    }
}

#================================================================================
# FUNCTION: Write-InstalledSoftwareToScreen
#================================================================================
# Description
#   Writes the specified list (not all) of installed software to the screen.
#
# Example
#   Write-InstalledSoftwareToScreen
#--------------------------------------------------------------------------------
Function Write-InstalledSoftwareToScreen() {

    Write-Host "`n Installed Software"

    Write-Host " - Oracle Java"
    $applications = $Airwatch.InstalledSoftware | Where-Object { $_.Publisher -like '*oracle*'}
    ForEach($application In $applications) {
        Write-Host "   > $($application.DisplayName) v$($application.Version)"
    }
}

#================================================================================
# FUNCTION: Test-Ping -IPAddress
#================================================================================
# Description
#   Performs a single ping test to the specified IP address
#
# Example
#   Test-Ping -IPAddress "192.168.0.1"
#--------------------------------------------------------------------------------
Function Test-Ping() {
    Param (
        [Parameter(Mandatory=$true,Position=1)][String]$IPAddress
    )

    Try {
        Return Test-Connection $IPAddress -Count 1 -Quiet -InformationAction Ignore
    } Catch {
        Return $false
    }
}

#================================================================================
# FUNCTION: Test-OpenPort -IPAddress -Port
#================================================================================
# Description
#   Attempts to open a TCP connection over the specified port to the specified
#   remote host. This is similar to a telnet connection test.
#
# Example
#   Test-OpenPort -IPAddress "192.168.0.1" -Port "25"
#--------------------------------------------------------------------------------
Function Test-OpenPort() {
    Param (
        [Parameter(Mandatory=$true,Position=1)][String]$IPAddress,
        [Parameter(Mandatory=$true,Position=2)][String]$Port

    )

    Try {
        $Connection = New-Object System.Net.Sockets.TcpClient($IPAddress, $Port)
        Return $Connection.Connected
    } Catch {
        Return $false
    }

}

#================================================================================
# FUNCTION: Test-HealthCheck -Uri -ExpectedStatusCode
#================================================================================
# Description
#   Attempts to connect to a remote web server over HTTP and returns a success or
#   failure by comparing the ExpectedStatus code to the one returned by the
#   remote web server. This check will ignore any certificate errors.
#
# Example
#   Test-HealthCheck -Uri "https://google.com" -ExpectedStatusCode "200"
#--------------------------------------------------------------------------------
Function Test-HealthCheck() {
    Param (
        [Parameter(Mandatory=$true,Position=1)][String]$Uri,
        [Parameter(Mandatory=$true,Position=2)][String]$ExpectedStatusCode
    )

    Try {
        $response = Invoke-WebRequest -Uri $Uri -SkipCertificateCheck
        If ($response.statusCode -eq $ExpectedStatusCode) {
            Return $true
        } Else {
            Return $false
        }
    } Catch {
        Return $false
    }
}

#================================================================================
# FUNCTION: Start-BackgroundJobs
#================================================================================
# Description
#   Starts all the network connectivity tests as a background job. This also
#   creates objects to store the job information which is used to keep track of
#   the state of each job and retrieve the results.
#
# Example
#   Start-BackgroundJobs
#--------------------------------------------------------------------------------
Function Start-BackgroundJobs() {
    $Vendors = @("gateway.push.apple.com:2195", "feedback.push.apple.com:2196", "discovery.awmdm.com:443", "play.google.com:80:443")

    $passFunctions = [scriptblock]::Create(@"
        Function Test-Ping { ${function:Test-Ping} }
        Function Test-OpenPort { ${function:Test-OpenPort} }
"@)

    $Connections = New-Object System.Collections.ArrayList

    ForEach($Vendor in $Vendors) {

        $hostInfo = $Vendor.Split(':')
        $Connectivity = New-Object System.Object
        $ping = @{
            "job" = Start-Job -InitializationScript $passFunctions -ScriptBlock { Test-Ping $args[0] } -ArgumentList $hostInfo[0];
            "result" = $null
        }

        $Connectivity | Add-Member -MemberType NoteProperty -Name "host" -Value $hostInfo[0]
        $Connectivity | Add-Member -MemberType NoteProperty -Name "ping" -Value $ping
        $Ports = New-Object System.Collections.ArrayList

        For($i=1; $i -lt $hostInfo.Count; $i++) {
            $Port = @{
                "port" = $hostInfo[$i];
                "job" = Start-Job -InitializationScript $passFunctions -ScriptBlock { Test-OpenPort $args[0] $args[1] } -ArgumentList $hostInfo[0], $hostInfo[$i];
                "result" = $null
            }
            $Ports.Add($Port) | Out-Null
        }

        $Connectivity | Add-Member -MemberType NoteProperty -Name "ports" -Value $Ports
        $Connections.Add($Connectivity) | Out-Null
    }

    Return $Connections
}

#================================================================================
# FUNCTION: Update-BackgroundJobs
#================================================================================
# Description
#   Polls each of the known background jobs for changes. When the job is finished
#   the result is collected and stored which is later used to display on screen.
#
# Example
#   Update-BackgroundJobs
#--------------------------------------------------------------------------------
Function Update-BackgroundJobs() {

    ForEach($RemoteHost In $AirWatch.ConnectivityTests) {

        If($null -eq $RemoteHost.ping.result -and ($RemoteHost.ping.job).state -eq "Completed") {
            $RemoteHost.ping.result = Receive-Job $RemoteHost.ping.job
            $RemoteHost.ping.job | Remove-Job
        }

        ForEach($Port In $RemoteHost.ports) {
            If($null -eq $Port.result -and ($Port.job).state -eq "Completed") {
                $Port.result = Receive-Job $Port.job
                $Port.job | Remove-Job
            }
        }
    }
}

#================================================================================
# FUNCTION: Write-ConnectivityTestsToScreen
#================================================================================
# Description
#   Displays the status of each network connectivity test (Ping & Open Port).
#
# Example
#   Write-ConnectivityTestsToScreen
#--------------------------------------------------------------------------------
Function Write-ConnectivityTestsToScreen() {

    Write-Host "`n Network Connectivity (no proxy)"

    ForEach($RemoteHost In $AirWatch.ConnectivityTests) {

        Write-Host " - $($RemoteHost.host):" -NoNewline

        If($null -eq $RemoteHost.ping.result) {
            Write-Host " PING" -ForegroundColor Cyan -NoNewline
        } ElseIf($RemoteHost.ping.result -eq $true) {
            Write-Host " PING" -ForegroundColor Green -NoNewline
        } Else {
            Write-Host " PING" -ForegroundColor Red -NoNewline
        }

        ForEach($Port In $RemoteHost.ports) {
            If($null -eq $Port.result) {
                Write-Host " TCP_$($Port.port)" -ForegroundColor Cyan -NoNewline
            } ElseIf($Port.result -eq $true) {
                Write-Host " TCP_$($Port.port)" -ForegroundColor Green -NoNewline
            } Else {
                Write-Host " TCP_$($Port.port)" -ForegroundColor Red -NoNewline
            }
        }

        Write-Host ""
    }
}


#================================================================================
# SCRIPT MAIN
#================================================================================
Test-PS6Version

Clear-Host
Write-Title -Title "$($Global:APP_TITLE)" -Centre
Write-Host "`n Gathering system information, I'll be done in a jiffy..."

# Build the Global AirWatch object by collecting information from the system.
$global:AirWatch = New-Object System.Object
$AirWatch | Add-Member -MemberType NoteProperty -Name "LastQueueCount" -Value 0
$AirWatch | Add-Member -MemberType NoteProperty -Name "Registry" -Value $(Read-AirwatchRegistryKeys)
$AirWatch | Add-Member -MemberType NoteProperty -Name "AWCM" -Value $(Read-AWCMConfig)
$AirWatch | Add-Member -MemberType NoteProperty -Name "AWCMCluster" -Value $(Read-AWCMClusterConfig)
$AirWatch | Add-Member -MemberType NoteProperty -Name "WindowsHostFile" -Value $(Read-WindowsHostFile)
$AirWatch | Add-Member -MemberType NoteProperty -Name "InstalledSoftware" -Value $(Read-InstalledSoftware)
$AirWatch | Add-Member -MemberType NoteProperty -Name "ConnectivityTests" -Value $(Start-BackgroundJobs)
# Exit

While($true) {
    Clear-Host

    Write-Title -Title "$($Global:APP_TITLE)" -Centre

    Write-AwGeneralDetailsToScreen
    Write-AwcmDetailsToScreen
    Write-WindowsHostFileToScreen
    Write-InstalledSoftwareToScreen
    Write-ConnectivityTestsToScreen

    Write-Host "`n Automatic Polling (every $($PollIntervalSec) seconds)"
    Write-DownServicesToScreen
    Write-MessageQueueCountToScreen

    Update-BackgroundJobs

    Write-Host ""
    If($DontPoll) { Exit }
    Start-Sleep -s $PollIntervalSec
}
