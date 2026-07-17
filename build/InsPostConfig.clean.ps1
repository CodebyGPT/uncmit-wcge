#     Microsoft Confidential     
#
#     Copyright Microsoft Corp.

# Get-LogDir:  Return the location for logs and output files
function Get-LogDir 
{
    try
    {
        $ts = New-Object -ComObject Microsoft.SMS.TSEnvironment -ErrorAction Stop
        
        if ($ts.Value("LogPath") -ne "")
        {
            $logDir = $ts.Value("LogPath")
        }
        else
        {
            $logDir = $ts.Value("_SMSTSLogPath")
        }
    }
    catch
    {
        $logDir = $env:TEMP
    }
    
    return $logDir
}

#### Set REG values ####
function Set-RegistryValue {
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [String]$Path,
        [Parameter(Mandatory = $true)]
        [String]$Name,
        [Parameter(Mandatory = $true)]
        [String]$Value,
        [Parameter(Mandatory = $true)]
        [String]$PropertyType
    ) 

    process {
        if (-not (Test-Path $Path)) {
            New-Item -Path $Path -Force
        }

        if ((Get-Item -Path $Path).GetValue($Name, $null) -ne $null) {
            Set-ItemProperty -Path $Path -Name $Name -Value $Value -Force
        } else {
            New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $PropertyType -Force
        }
    }
}

#Start Transcript and Logging
$logDir = Get-LogDir
Start-Transcript "$logDir\CMGE_Registry_InsPostConfig.log"

# Install service for activation
# UNCMIT-DISABLED $ATExe="$env:windir\Microsoft.NET\Framework64\v4.0.30319\InstallUtil.exe"
# UNCMIT-DISABLED $ATCfg="`"$env:SystemDrive\Program Files\CMITActivation\CmitClientSVC.exe`""
# UNCMIT-DISABLED Start-Process -WindowStyle Hidden -FilePath "$ATExe" -ArgumentList "$ATCfg" -Verb runas -Wait
# Set CmitClientSVC service with Delayed Autostart, make the service starting after logon.
# UNCMIT-DISABLED Start-Sleep -Seconds 1
# UNCMIT-DISABLED Set-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\services\CmitClientSVC" -Name "DelayedAutostart" -Value 1 -PropertyType "DWord"

# Create Scheduled Task for CMIT Update Agent
# UNCMIT-DISABLED $Action = New-ScheduledTaskAction -Execute "$env:SystemDrive\Program Files\CmitUpdateAgent\CmitServiceMonitor.exe" -Id "10086"
# UNCMIT-DISABLED $Trigger0 = New-ScheduledTaskTrigger -Daily -At "3:00"
# UNCMIT-DISABLED $Trigger1 = New-ScheduledTaskTrigger -Daily -At "7:00"
# UNCMIT-DISABLED $Trigger2 = New-ScheduledTaskTrigger -Daily -At "11:00"
# UNCMIT-DISABLED $Trigger3 = New-ScheduledTaskTrigger -Daily -At "15:00"
# UNCMIT-DISABLED $Trigger4 = New-ScheduledTaskTrigger -Daily -At "19:00"
# UNCMIT-DISABLED $Trigger5 = New-ScheduledTaskTrigger -Daily -At "23:00"
# UNCMIT-DISABLED $Principal = New-ScheduledTaskPrincipal -GroupID "NT AUTHORITY\SYSTEM" -RunLevel Highest
# UNCMIT-DISABLED $Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Seconds 120)
# UNCMIT-DISABLED $SchTask = New-ScheduledTask -Action $Action -Principal $Principal -Trigger $Trigger0,$Trigger1,$Trigger2,$Trigger3,$Trigger4,$Trigger5 -Settings $Settings
# UNCMIT-DISABLED Register-ScheduledTask -TaskName "CmitUpdateAgent Daily Runner" -TaskPath "\CMIT\CmitUpdateAgent" -InputObject $SchTask

#Disable-ScheduledTask
Disable-ScheduledTask -TaskName "\Microsoft\Windows\InstallService\ScanForUpdates"
Disable-ScheduledTask -TaskName "\Microsoft\Windows\InstallService\ScanForUpdatesAsUser"

# Code Integrity policy
#Invoke-CimMethod -Namespace root\Microsoft\Windows\CI -ClassName PS_UpdateAndCompareCIPolicy -MethodName Update -Arguments @{FilePath = "C:\SiPolicy\SIPolicy.p7b"}

# Cleanup
#del "$env:windir\Temp\LGPO" -recurse
#del "$env:SystemDrive\SiPolicy" -recurse
#del $MyInvocation.MyCommand.Definition -Force
