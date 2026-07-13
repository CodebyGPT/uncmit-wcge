##################################################################################################
#
#     Apply Registry Modifications - Microsoft Confidential                                      #
#                    
#                 
##################################################################################################

#region functions
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

function Set-RegistryValue 
{
    param
    (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [String]
        $Path,

        [Parameter(Mandatory = $true)]
        [String]
        $Name,

        [Parameter(Mandatory = $true)]
        [String]
        $Value,

        [Parameter(Mandatory = $true)]
        [String]
        $PropertyType
    ) 

    process 
    {
        if (-not (Test-Path $Path)) 
        {
            New-Item -Path $Path -Force
        }

        if ((Get-Item -Path $Path).GetValue($Name, $null) -ne $null) 
        {
            Set-ItemProperty -Path $Path -Name $Name -Value $Value -Force
        } 
        else 
        {
            New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $PropertyType -Force
        }
    }
}

############################ Script Main ##############################

#Start Transcript and Logging
$logDir = Get-LogDir
Start-Transcript "$logDir\CMGE_Registry_UpgradeSchdTask.log"

# Update the VC files of SMx
Copy-Item "$env:SystemDrive\Recovery\OEM\CMGE\ResetSources\CMITSMx\win64\msvcr110.dll" "$env:windir\System32\" -Force
Copy-Item "$env:SystemDrive\Recovery\OEM\CMGE\ResetSources\CMITSMx\win64\msvcr110d.dll" "$env:windir\System32\" -Force
Copy-Item "$env:SystemDrive\Recovery\OEM\CMGE\ResetSources\CMITSMx\win32\msvcr110.dll" "$env:windir\SysWOW64\" -Force
Copy-Item "$env:SystemDrive\Recovery\OEM\CMGE\ResetSources\CMITSMx\win32\msvcr110d.dll" "$env:windir\SysWOW64\" -Force

#CMITCMGEInstaller
Start-Process -FilePath "$env:SystemDrive\Recovery\OEM\CMGE\ResetSources\EPrivilege.exe" -ArgumentList " -U:S $env:SystemDrive\Recovery\OEM\CMGE\ResetSources\CMGEInstaller\CMGEInstaller.exe 00000400" -WindowStyle Hidden -Wait

# Set "feedback and diagnose" in settings closed. Set by CMGE Group Policy. Need to check in registry.
#Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Privacy" -Name "TailoredExperiencesWithDiagnosticDataEnabled" -Value 0 -PropertyType "DWord"

# Support from V0-H
# Delete image file format association
# $testKey ='HKCU:\SOFTWARE\Classes'
# if (Test-Path $testKey) 
# {
	# Clear-ItemProperty -Path "HKCU:\SOFTWARE\Classes\.bmp" -Name "(default)"
	# Clear-ItemProperty -Path "HKCU:\SOFTWARE\Classes\.dib" -Name "(default)"
	# Clear-ItemProperty -Path "HKCU:\SOFTWARE\Classes\.gif" -Name "(default)"
	# Clear-ItemProperty -Path "HKCU:\SOFTWARE\Classes\.jfif" -Name "(default)"
	# Clear-ItemProperty -Path "HKCU:\SOFTWARE\Classes\.jpe" -Name "(default)"
	# Clear-ItemProperty -Path "HKCU:\SOFTWARE\Classes\.jpeg" -Name "(default)"
	# Clear-ItemProperty -Path "HKCU:\SOFTWARE\Classes\.jpg" -Name "(default)"
	# Clear-ItemProperty -Path "HKCU:\SOFTWARE\Classes\.png" -Name "(default)"
	# Clear-ItemProperty -Path "HKCU:\SOFTWARE\Classes\.ico" -Name "(default)"
# }

# Install service for activation
$ATExe="$env:windir\Microsoft.NET\Framework64\v4.0.30319\InstallUtil.exe"
$ATCfg="`"$env:SystemDrive\Program Files\CMITActivation\CmitClientSVC.exe`""
Start-Process -WindowStyle Hidden -FilePath "$ATExe" -ArgumentList "$ATCfg" -Verb runas -Wait
# Set CmitClientSVC service with Delayed Autostart, make the service starting after logon.
Start-Sleep -Seconds 1
Set-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\services\CmitClientSVC" -Name "DelayedAutostart" -Value 1 -PropertyType "DWord"

Unregister-ScheduledTask -TaskName "UpgradeSchdTask" -Confirm:$false

$DelCfg = "-Command del $env:windir\Temp\UpgradeSchdTask.exe"
Start-Process -FilePath "$env:windir\system32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList "$DelCfg" -WindowStyle Hidden