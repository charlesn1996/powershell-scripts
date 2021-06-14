param( [string]$VMFilePath)

# Function to check Windows Registry entries
Function validateRegistry  {
    param ([string]$path, [string]$property, [string]$value, [string]$computerName)
    $RemoteRegistryStatus = Get-Service -ComputerName $computerName -Name RemoteRegistry 

    #Start Remote Registry Service if stopped
    if ($RemoteRegistryStatus.Status -ne "Running") {
    Get-Service -ComputerName $computerName -Name RemoteRegistry | Start-Service
    }
    # Connect to Windows Registry Service and examine entries
    $Reg = [Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey('LocalMachine', $computerName)
    if ($?) {
        $RegKey= $Reg.OpenSubKey($path)
        $Rvalue = $RegKey.GetValue($property)
       
        if ($Rvalue -eq $null) {
            Write-Output ("Windows registry property does not exist") | Out-File $LogFile -append
        } else {

            if ($Rvalue -eq $value) {
                Write-Output ("The registry property matches the value expected") | Out-File $LogFile -append
            } else {
                Write-Output ("The registry property does not match the value expected") | Out-File $LogFile -append
            }

            Write-Output($property + " = " + $Rvalue) | Out-File $LogFile -append
        }
    } else {
        Write-Output("Could not connect to Windows Registry Service") | Out-File $LogFile -append
        Write-Output("Could not connect to Windows Registry Service for " + $computerName) | Out-File $FailuresLogFile -append
    }
    
}

$LogFile = "C:\temp\LogFile.txt"
$FailuresLogFile = "C:\temp\FailuresLogFile.txt"
 # Clear log files
Clear-Content $LogFile
Clear-Content $FailuresLogFile
Get-Content $VMFilePath | Foreach-Object {
$computerName = $_
Write-Output ($computerName) | Out-File $LogFile -append # Start of auditing process for each VM

if ( Test-Path "\\$computerName\c$\AutoWindowsUpdater" ) {

    # CHECK IF XML FILE EXISTS
    if (Test-Path "\\$computerName\c$\AutoWindowsUpdater\SupportFiles\AutoWindowsUpdate_afterRestart.xml") { # Check if XML file exists
        Write-Output ("XML file check passed") | Out-File $LogFile -append

    } else {
        Write-Output ("XML file check failed") | Out-File $LogFile -append
        Write-Output ("XML file check failed for " + $computerName) | Out-File $FailuresLogFile -append
    }
    # Attempt connection to remote computer
    $sch = New-Object -ComObject("Schedule.Service")
    $sch.connect($computerName)
    if (-Not $?) { # if connection fails
        Write-Output ("Could not connect to remote computer") | Out-File $LogFile -append 
        Write-Output ("Could not connect to " + $computerName) | Out-File $FailuresLogFile -append
       
    } else {
        # Get root scheduled tasks
        $root = $sch.GetFolder("\") 
        $scheduledTasks = $root.GetTasks(0)
        
        # CHECK FOR AUTOWINDOWSUPDATE_AFTERRESTART
        $task1 = "AutoWindowsUpdate_afterRestart"
        $taskExists1 = $scheduledTasks | Where-Object {$_.Name -eq $task1} 
        if ($taskExists1) {
            Write-Output ("AutoWindowsUpdate_afterRestart scheduled task exists") | Out-File $LogFile -append
        } else {
            Write-Output ("AutoWindowsUpdate_afterRestart scheduled task does not exist") | Out-File $LogFile -append
            Write-Output ("AutoWindowsUpdate_afterRestart scheduled task does not exist in " + $computerName) | Out-File $FailuresLogFile -append
        }

        # CHECK FOR AUTOWINDOWSUPDATE_ONSCHEDULE
        $task2 = "AutoWindowsUpdate_onSchedule"
        $taskExists2 = $scheduledTasks | Where-Object {$_.Name -eq $task2} 
        if ($taskExists2) {
            Write-Output ("AutoWindowsUpdate_onSchedule scheduled task exists") | Out-File $LogFile -append
        } else {
            Write-Output ("AutoWindowsUpdate_onSchedule scheduled task does not exist") | Out-File $LogFile -append
            Write-Output ("AutoWindowsUpdate_onSchedule scheduled task does not exist in " + $computerName) | Out-File $FailuresLogFile -append
        }

        # CHECK REGISTRY ENTRIES USING FUNCTION
        validateRegistry "SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" "AutoAdminLogon" "1" $computerName

        # CHECK MCAFEE EXCLUSIONS
        $RemoteRegistryStatus = Get-Service -ComputerName $computerName -Name RemoteRegistry 

        if ($RemoteRegistryStatus.Status -ne "Running") {
        Get-Service -ComputerName $computerName -Name RemoteRegistry | Start-Service
        }
  
        $Reg = [Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey('LocalMachine', $computerName)
        if ($?) {
            $RegKey= $Reg.OpenSubKey("SOFTWARE\Wow6432Node\McAfee\SystemCore\VSCore\On Access Scanner\McShield\Configuration\Default")  
                   
            #Get excluded Items          
            $Exclusion1 = $RegKey.GetValue("ExcludedItem_0")
            $Exclusion2 = $RegKey.GetValue("ExcludedItem_1")
            $Exclusion3 = $RegKey.GetValue("ExcludedItem_2")
            #Write-Output($Exclusion1 + "   " + $Exclusion2 + "   " + $Exclusion3)

            #Store excluded items in array and iterate to find desired folders
            $arr = $Exclusion1, $Exclusion2
            $boolean1 = $false
            $boolean2 = $false

            for ($i = 0; $i -lt $arr.Length; $i++) {
                if ($arr[$i] -match "C:\\Program Files\\Kinaxis\\") {
                    $boolean1 = $true
                } elseif ($arr[$i] -match "C:\\RapidResponse\\") {
                    $boolean2 = $true
                }
            }

            if ($boolean1 -and $boolean2) {
                Write-Output ("McAfee Exclusions check passed") | Out-File $LogFile -append
            } else {
                Write-Output ("McAfee Exclusions check failed") | Out-File $LogFile -append
                Write-Output ("McAfee Exclusions check failed for " + $computerName) | Out-File $FailuresLogFile -append
            }
            
        } else {
            Write-Output ("Could not connect to Windows Registry service for " + $computerName)
        }

        # CHECK WINDOWS UPDATES 
        $LastUpdates = @{}
        $Errors      = @{}

        [System.Reflection.Assembly]::LoadWithPartialName('Microsoft.Update.Session')
        $Session = [activator]::CreateInstance([type]::GetTypeFromProgID("Microsoft.Update.Session", $computerName))
        
        $UpdateSearcher   = $Session.CreateUpdateSearcher()
        $NumUpdates       = $UpdateSearcher.GetTotalHistoryCount()
        $InstalledUpdates = $UpdateSearcher.QueryHistory(1, $NumUpdates)
            
        if ($?) {
            $LastInstalledUpdate   = $InstalledUpdates | Select-Object Title, Date | Sort-Object -Property Date -Descending | Select-Object -first 1
            Write-Output ("Windows Updates were last installed: " + $LastInstalledUpdate.Date) | Out-File $LogFile -append

        }  else {
            Write-Output ( "Error. Windows Update search query failed") | Out-File $LogFile -append 
            Write-Output ( "Error. Windows Update search query failed for " + $computerName) | Out-File $LogFile -append 
        }

     }


Write-Output("------------------------------------------------------------------") | Out-File $LogFile -append
Write-Output("-------------------------------------------------------------------------------------------------------------------------") | Out-File $FailuresLogFile -append

}
}
