# A script to auto diagnose AirWatch issues.
# Check AW queues..done
# Check Windows services..done
# AW log files
# Open ports
# AWCM truststore
# SSL certificate

$global:Airwatch = New-Object System.Object
$Airwatch | Add-Member -MemberType NoteProperty -Name "LastQueueCount" -Value 0

# If($PSVersionTable.PSVersion.Major -gt 5) {
#     Write-Host "This script will only work on PowerShell version 5, exiting."
#     Exit
# }

#================================================================================
# FUNCTION: Write-Title -Title -Colour
#================================================================================
function Write-Title() {
    param (
        [Parameter(Mandatory=$true,Position=1)][String]$Title,
        [Parameter(Mandatory=$false,Position=2)][String]$Colour="White"
    )

    Write-Host "==============================================================================="
    Write-Host " $($Title)" -ForegroundColor $Colour
    Write-Host "==============================================================================="
}

#================================================================================
# FUNCTION: Get-MsmqQueue
#================================================================================
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
Function Get-MessageQueueCount {
    $queueCount = (Get-MsmqQueue -QueueType Private | Measure-Object -Sum MessageCount).Sum

    If($null -eq $queueCount) {
        $queueCount = 0
    }

    return $queueCount
}

#================================================================================
# FUNCTION: Get-MessageQueue
#================================================================================
Function Get-MessageQueue() {
    # Check the number of queued messages.
    $queueCount = $(Get-MessageQueueCount)

    Write-Host " - AirWatch Message Queues: " -NoNewline

    if($queueCount -eq 0) {
        Write-Host "0"
    }
    elseif($queueCount -gt $lastQueueCount) {
        Write-Host "$($queueCount) (Up)" -ForegroundColor Red 
    } elseif($queueCount -lt $lastQueueCount) {
        Write-Host "$($queueCount) (Down)" -ForegroundColor Green 
    } else {
        Write-Host "$($queueCount) (Steady)" -ForegroundColor Cyan 
    }
    $AirWatch.LastQueueCount = $queueCount
}

Function Get-DownServices() {
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
# FUNCTION: Test-HealthCheck -Uri -ExpectedStatusCode
#================================================================================
function Test-HealthCheck() {
    param (
        [Parameter(Mandatory=$true,Position=1)][String]$Uri,
        [Parameter(Mandatory=$true,Position=2)][String]$ExpectedStatusCode
    )

    try {
        $response = Invoke-WebRequest -Uri $Uri -SkipCertificateCheck
        If ($response.statusCode -eq $ExpectedStatusCode) {
            return $true
        } else {
            return $false
        }
    } catch {
        return $false
    }
}

Function Read-RegistryKeys() {
    $hive = "HKLM:\SOFTWARE\Wow6432Node\AirWatch"
    $keys = @("IS_SQLSERVER_SERVER", "Version", "ACMSERVERIP", "ACMSERVERPORT", "AWCMNODES", "AWSERVER", "AWSERVERDS", "AWVERSIONDIR")

    $awRegistry = New-Object System.Object

    ForEach($key in $keys) {
        $awValue = (Get-ItemProperty -Path $hive -Name $key).$key
        $awRegistry | Add-Member -MemberType NoteProperty -Name $key -Value $awValue
    }

    $AirWatch | Add-Member -MemberType NoteProperty -Name "Registry" -Value $awRegistry
}

Function Read-AWCMConfig() {
    $awcmConfig = "$($AirWatch.Registry.AWVERSIONDIR)\AWCM\config\awcm.properties"
    $awcmKeys = @("AWCM_VERSION", "AWCM_CLUSTERING_MODE", "AWCM_DATABASE_PROVIDER", "AWCM_OFFLOAD_SSL")

    $awcm = New-Object System.Object

    ForEach($line In Get-Content $awcmConfig) {
        ForEach($awcmKey In $awcmKeys) {
            If($line -match $awcmKey) {
                $awcmKvp = $line.Split("=")

                If($awcmKvp[1] -match "Y") { $awcmKvp[1] = "Yes" }
                If($awcmKvp[1] -match "N") { $awcmKvp[1] = "No" }
                $awcmKvp[1]

                $awcm | Add-Member -MemberType NoteProperty -Name $awcmKey -Value $awcmKvp[1]
            }
        }        
    }

    $AirWatch | Add-Member -MemberType NoteProperty -Name "AWCM" -Value $awcm
}

Function Write-AwDetails() {

    Write-Host "`n General Environment Details"
    Write-Host " - AirWatch Version: $($AirWatch.Registry.version)"
    Write-Host " - SQL Server: $($AirWatch.Registry.IS_SQLSERVER_SERVER)"
    Write-Host " - Console Host: $($AirWatch.Registry.AWSERVER.ToLower())"
    Write-Host " - Device Services Host: $($AirWatch.Registry.AWSERVERDS.ToLower())"

    Write-Host "`n AirWatch Cloud Messaging"
    Write-Host " - Version: $($AirWatch.AWCM.AWCM_VERSION)"
    Write-Host " - SSL Offloading: $($AirWatch.AWCM.AWCM_OFFLOAD_SSL)"
    Write-Host " - Cluster Nodes: $($AirWatch.Registry.AWCMNODES)"
    Write-Host " - Clustering Mode: $($AirWatch.AWCM.AWCM_CLUSTERING_MODE)"
    Write-Host " - Database Provider: $($AirWatch.AWCM.AWCM_DATABASE_PROVIDER)"
    Write-Host " - Location: $($AirWatch.Registry.ACMSERVERIP):$($AirWatch.Registry.ACMSERVERPORT)"
    
}

Read-RegistryKeys
Read-AWCMConfig
Exit

#$host.ui.RawUI.ReadKey("NoEcho,IncludeKeyUp").VirtualKeyCode -ne 27
While($true) {

    Clear-Host
    Write-Title -Title "                         AIRWATCH DIAGNOSTICS TOOL"
    
    Write-AwDetails

    Write-Host "`n Service Polls"
    Get-MessageQueue
    Get-DownServices

    Start-Sleep -s 2
}