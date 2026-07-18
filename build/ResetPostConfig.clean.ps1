#     Microsoft Confidential     
#
#     Copyright Microsoft Corp.

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

<#
    .SYNOPSIS
        Enables access token privelege required for modifying registry permissions.

    .PARAMETER Privilege
        The privilege to adjust.

    .PARAMETER ProcessID
        The process on which to adjust the privilege.

    .PARAMETER AccountName
        Account given ownership of key during removal process.
#>

function Enable-Privilege 
{
    param
    (
        # The privilege to adjust. This set is taken from
        # http://msdn.microsoft.com/en-us/library/bb530716(VS.85).aspx
        [ValidateSet(
          "SeAssignPrimaryTokenPrivilege", "SeAuditPrivilege", "SeBackupPrivilege",
          "SeChangeNotifyPrivilege", "SeCreateGlobalPrivilege", "SeCreatePagefilePrivilege",
          "SeCreatePermanentPrivilege", "SeCreateSymbolicLinkPrivilege", "SeCreateTokenPrivilege",
          "SeDebugPrivilege", "SeEnableDelegationPrivilege", "SeImpersonatePrivilege", "SeIncreaseBasePriorityPrivilege",
          "SeIncreaseQuotaPrivilege", "SeIncreaseWorkingSetPrivilege", "SeLoadDriverPrivilege",
          "SeLockMemoryPrivilege", "SeMachineAccountPrivilege", "SeManageVolumePrivilege",
          "SeProfileSingleProcessPrivilege", "SeRelabelPrivilege", "SeRemoteShutdownPrivilege",
          "SeRestorePrivilege", "SeSecurityPrivilege", "SeShutdownPrivilege", "SeSyncAgentPrivilege",
          "SeSystemEnvironmentPrivilege", "SeSystemProfilePrivilege", "SeSystemtimePrivilege",
          "SeTakeOwnershipPrivilege", "SeTcbPrivilege", "SeTimeZonePrivilege", "SeTrustedCredManAccessPrivilege",
          "SeUndockPrivilege", "SeUnsolicitedInputPrivilege")]
        $Privilege,

        # The process on which to adjust the privilege. Defaults to the current process.
        $ProcessId = $pid,

        # Switch to disable the privilege, rather than enable it.
        [Switch] $Disable
    )

    # Taken from P/Invoke.NET with minor adjustments.
    $definition = @'
  using System;
  using System.Runtime.InteropServices;
   
  public class AdjPriv
  {
    [DllImport("advapi32.dll", ExactSpelling = true, SetLastError = true)]
    internal static extern bool AdjustTokenPrivileges(IntPtr htok, bool disall,
      ref TokPriv1Luid newst, int len, IntPtr prev, IntPtr relen);
   
    [DllImport("advapi32.dll", ExactSpelling = true, SetLastError = true)]
    internal static extern bool OpenProcessToken(IntPtr h, int acc, ref IntPtr phtok);
    [DllImport("advapi32.dll", SetLastError = true)]
    internal static extern bool LookupPrivilegeValue(string host, string name, ref long pluid);
    [StructLayout(LayoutKind.Sequential, Pack = 1)]
    internal struct TokPriv1Luid
    {
      public int Count;
      public long Luid;
      public int Attr;
    }
   
    internal const int SE_PRIVILEGE_ENABLED = 0x00000002;
    internal const int SE_PRIVILEGE_DISABLED = 0x00000000;
    internal const int TOKEN_QUERY = 0x00000008;
    internal const int TOKEN_ADJUST_PRIVILEGES = 0x00000020;
    public static bool EnablePrivilege(long processHandle, string privilege, bool disable)
    {
      bool retVal;
      TokPriv1Luid tp;
      IntPtr hproc = new IntPtr(processHandle);
      IntPtr htok = IntPtr.Zero;
      retVal = OpenProcessToken(hproc, TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, ref htok);
      tp.Count = 1;
      tp.Luid = 0;
      if(disable)
      {
        tp.Attr = SE_PRIVILEGE_DISABLED;
      }
      else
      {
        tp.Attr = SE_PRIVILEGE_ENABLED;
      }
      retVal = LookupPrivilegeValue(null, privilege, ref tp.Luid);
      retVal = AdjustTokenPrivileges(htok, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero);
      return retVal;
    }
  }
'@
    $type = Add-Type $definition -PassThru

    $processHandle = (Get-Process -id $ProcessId).Handle    

    $type[0]::EnablePrivilege($processHandle, $Privilege, $Disable)
}

<#
    .SYNOPSIS
        Translates registry hive name.

    .PARAMETER Path
        The path to the registry key.
#>

function Get-Hive
{
    Param
    (
        [Parameter(Mandatory = $true)]
        [string]
        $Path
    )

    $hive = ([string]$Path).Split(':')[0]

    $rootKey = [Microsoft.Win32.Registry]::LocalMachine
    $keyPSPath = $Path

    switch($hive)
    {
        "HKLM" { }
        "HKCU" 
        { 
            $rootKey = [Microsoft.Win32.Registry]::CurrentUser   
        }
        "HKCR" 
        { 
            $rootKey = [Microsoft.Win32.Registry]::ClassesRoot 
            $keyPSPath = $Path -replace "HKCR:\\", "Microsoft.PowerShell.Core\Registry::HKEY_CLASSES_ROOT\" 
        }
        "HKU"  
        { 
            $rootKey = [Microsoft.Win32.Registry]::Users 
            $keyPSPath = $Path -replace "HKU:\\", "Microsoft.PowerShell.Core\Registry::HKEY_USERS\" 
        }
        default 
        { 
            Throw "Unable to determine registry hive"
            return 
        }
    }

    $result = @{
        RootKey = $rootKey
        keyPSPath = $keyPSPath
    }

    return $result
}

<#
    .SYNOPSIS
        Modifies permissions of a restricted registry key.

    .PARAMETER RootKey
        PS path to registry hive, result from Get-Hive function.

    .PARAMETER SubKeyPath
        Path to registry key below Rootkey hive.

    .PARAMETER AccountName
        Account given ownership of key during removal process.
#>

function Set-RegKeyPermission 
{
    param
    (
        [Parameter(Mandatory = $true)]
        [Microsoft.Win32.RegistryKey]
        $RootKey,

        [Parameter(Mandatory = $true)]
        [string]
        $SubKeyPath,

        [Parameter(Mandatory = $true)]
        [string]
        $AccountName
    )

    process 
    {
        # Take ownership of the registry key
        $enabled = Enable-Privilege -Privilege SeTakeOwnershipPrivilege

        # modify ACL
        $key = $RootKey.OpenSubKey($SubKeyPath, [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree, [System.Security.AccessControl.RegistryRights]::TakeOwnership)
        
        $acl = $key.GetAccessControl()
        $acl.SetOwner([System.Security.Principal.NTAccount]$AccountName)
        $key.SetAccessControl($acl)
        $key.Close();

        $rule = New-Object System.Security.AccessControl.RegistryAccessRule ($AccountName,"FullControl","Allow")

        #allow full control
        $key = $RootKey.OpenSubKey($SubKeyPath, [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree, [System.Security.AccessControl.RegistryRights]::ChangePermissions)
        $acl = $key.GetAccessControl()
        $acl.AddAccessRule($rule)
        $key.SetAccessControl($acl)
    }
}

<#
    .SYNOPSIS
        Configures a restricted registry value.

    .PARAMETER Path
        PSPath to registry key where value is stored.

    .PARAMETER Name
        Name of registry value to be configured.

    .PARAMETER Value
        Value to be configured.

    .PARAMETER PropertyType
        Type of registry value to be configured.

    .PARAMETER AccountName
        Account given ownership of key during removal process.
#>

function Set-RestrictedRegKeyValue 
{
    param
    (
        [Parameter(Mandatory = $true)]
        [string]
        $Path,

        [Parameter(Mandatory = $true)]
        [String]
        $Name,

        [Parameter(Mandatory = $true)]
        [String]
        $Value,

        [Parameter(Mandatory = $true)]
        [String]
        $PropertyType,

        [Parameter(Mandatory = $true)]
        [string]
        $AccountName
    )

    process 
    {
        $hive = Get-Hive -Path $path

        $rootKey = $hive.RootKey
        $keyPSPath = $hive.KeyPSPath

        $subKeyPath = ([string]$Path).Substring(([string]$Path).IndexOf('\') + 1)
        
        $key = $rootKey.OpenSubKey($subKeyPath, [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadSubTree, [System.Security.AccessControl.RegistryRights]::ReadPermissions)

        if (-not $key)
        {
            New-Item -Path $keyPSPath -Force
            $key = $rootKey.OpenSubKey($subKeyPath, [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadSubTree, [System.Security.AccessControl.RegistryRights]::ReadPermissions)
        }

        $aclBackup = $key.GetAccessControl().GetSecurityDescriptorBinaryForm()

        try 
        {
            Set-RegKeyPermission -RootKey $rootKey -SubKeyPath $subKeyPath -AccountName $AccountName
        }
        catch 
        {
            Write-Error $_
        }

        #Set CloudErrorMessagesHostName value
        if ((Get-ItemProperty -Path $keyPSPath).($Name)) 
        {
	        Remove-ItemProperty -Path $keyPSPath -Name $Name -Force
        }

        New-ItemProperty -Path $keyPSPath -Name $Name -PropertyType $PropertyType -Value $Value -Force

        #restore ACLs
        $enabled = Enable-Privilege SeRestorePrivilege
        $acl = New-Object System.Security.AccessControl.RegistrySecurity
        $acl.SetSecurityDescriptorBinaryForm($aclBackup, [System.Security.AccessControl.AccessControlSections]::All)
        $key = $rootKey.OpenSubKey($subKeyPath, [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree, [System.Security.AccessControl.RegistryRights]::TakeOwnership -bor [System.Security.AccessControl.RegistryRights]::ChangePermissions)
        $key.SetAccessControl($acl)
    }
}

<#
    .SYNOPSIS
        Removes restricted registry value.

    .PARAMETER Path
        PS path to registry key where value is stored.

    .PARAMETER Name
        Name of registry value to be removed.

    .PARAMETER AccountName
        Account given ownership of key during removal process.
#>

function Remove-RestrictedRegKeyValue 
{
    param
    (
        [Parameter(Mandatory = $true)]
        [string]
        $Path,

        [Parameter(Mandatory = $true)]
        [String]
        $Name,

        [Parameter(Mandatory = $true)]
        [string]
        $AccountName
    )

    process 
    {
        $hive = Get-Hive -Path $path

        $rootKey = $hive.RootKey
        $keyPSPath = $hive.KeyPSPath

        $subKeyPath = ([string]$Path).Substring(([string]$Path).IndexOf('\') + 1)
        
        $key = $rootKey.OpenSubKey($subKeyPath, [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadSubTree, [System.Security.AccessControl.RegistryRights]::ReadPermissions)

        if (-not $key)
        {
            Write-Error "$Path does not exists"
            return
        }

        $aclBackup = $key.GetAccessControl().GetSecurityDescriptorBinaryForm()

        try 
        {
            Set-RegKeyPermission -RootKey $rootKey -SubKeyPath $subKeyPath -AccountName $AccountName
        }
        catch 
        {
            Write-Error $_
        }

        #Set CloudErrorMessagesHostName value
        if ((Get-ItemProperty -Path $keyPSPath).($Name)) 
        {
	        Remove-ItemProperty -Path $keyPSPath -Name $Name -Force
        }

        #restore ACLs
        $enabled = Enable-Privilege SeRestorePrivilege
        $acl = New-Object System.Security.AccessControl.RegistrySecurity
        $acl.SetSecurityDescriptorBinaryForm($aclBackup, [System.Security.AccessControl.AccessControlSections]::All)
        $key = $rootKey.OpenSubKey($subKeyPath, [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree, [System.Security.AccessControl.RegistryRights]::TakeOwnership -bor [System.Security.AccessControl.RegistryRights]::ChangePermissions)
        $key.SetAccessControl($acl)
    }
}

<#
    .SYNOPSIS
        Removes restricted registry key.

    .PARAMETER Path
        PS path to registry key to be removed.

    .PARAMETER AccountName
        Account given ownership of key during removal process
#>
function Remove-RestrictedRegKey
{
    param
    (
        [Parameter(Mandatory = $true)]
        [string]
        $Path,

        [Parameter(Mandatory = $true)]
        [string]
        $AccountName
    )

    $hive = Get-Hive -Path $path
    $rootKey = $hive.RootKey

    $allKeys = @()
    $allKeys += Get-childitem $Path -Recurse
    $allKeys += Get-Item $Path

    foreach($key in $allKeys)
    {   
        $psPathRoot = $($key.PSDrive.Provider.ToString()) + "::" + $($key.PSDrive.Root.ToString()) + "\"
        $subKeyPath = $key.PSPath.Replace($psPathRoot, "")

        Set-RegKeyPermission -RootKey $rootKey -SubKeyPath $subKeyPath -AccountName $AccountName
    }

    Remove-Item -Path $Path -Force -Recurse
}

<#
    .SYNOPSIS
        Configures a registry value.

    .PARAMETER Path
        PSPath to registry key where value is stored.

    .PARAMETER Name
        Name of registry value to be configured.

    .PARAMETER Value
        Value to be configured.

    .PARAMETER PropertyType
        Type of registry value to be configured.
#>

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
#endregion

#Start Transcript and Logging
$logDir = Get-LogDir
Start-Transcript "$logDir\CMGE_Registry_Reset_Post.log"


# Set Registry
# Set "feedback and diagnose" in settings closed. Set by CMGE Group Policy. Need to check in registry.
#Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Privacy" -Name "TailoredExperiencesWithDiagnosticDataEnabled" -Value 0 -PropertyType "DWord"

Set-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon" -Name "Start" -Value "4" -PropertyType "DWord"

# Configure Registry Entry for VSO Bug 525 [data exhaust]
Set-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Services\wlidsvc" -Name "Start" -Value "4" -PropertyType "DWord"

# ---HKEY_CURRENT_USER--------------------------------------------------
# Set delay lock interval for users after setting sleep(every time). Set by CMGE Group Policy. Need to check in registry.
#Set-RegistryValue -Path "HKCU:\Control Panel\Desktop" -Name "DelayLockInterval" -Value 0 -PropertyType "DWord"

# Stretch wallpaper 
Set-RegistryValue -Path "HKCU:\Control Panel\Desktop" -Name "WallpaperStyle" -Value "2" -PropertyType "String"
Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes" -Name "WallpaperSetFromTheme" -Value 1 -PropertyType "DWord"

# Let Websites provide locally relevant content by accessing language list (SR #9 - Item #3). Set by CMGE Group Policy. Need to check in registry.
#Set-RegistryValue -Path "HKCU:\Control Panel\International\User Profile" -Name "HttpAcceptLanguageOptOut" -Value 1 -PropertyType "DWord"

# Configure "Getting to know you" for Inking & Typing Personalization (Bug #618). Set by CMGE Group Policy. Need to check in registry.
#Set-RegistryValue -Path "HKCU:\SOFTWARE\Microsoft\InputPersonalization" -Name "RestrictImplicitInkCollection" -Value 1 -PropertyType "DWord"
#Set-RegistryValue -Path "HKCU:\SOFTWARE\Microsoft\InputPersonalization" -Name "RestrictImplicitTextCollection" -Value 1 -PropertyType "DWord"
#Set-RegistryValue -Path "HKCU:\SOFTWARE\Microsoft\InputPersonalization\TrainedDataStore" -Name "HarvestContacts" -Value 0 -PropertyType "DWord"
#Set-RegistryValue -Path "HKCU:\SOFTWARE\Microsoft\Personalization\Settings" -Name "AcceptedPrivacyPolicy" -Value 0 -PropertyType "DWord"

# Disable ActiveX Control (SR#56 - Item #3). Set by Windows Group Policy. Need to check in registry.
#Set-RegistryValue -Path "HKCU:\SOFTWARE\Microsoft\Internet Explorer\VersionManager" -Name "DownloadVersionList" -Value 0 -PropertyType "DWord"

# Feedback & Diagnostics Settings (SR #12, #13 - Item #3). Set by CMGE Group Policy. Need to check in registry.
### Set the option "Windows should ask for my feedback" to "Never"
### Setting			PeriodInNanoSeconds			NumberOfSIUFInPeriod
### Automatically	Delete this QWORD			Delete this DWORD
### Always			100000000 (decimal)			Delete this DWORD
### Once a day		864000000000 (decimal)		1
### Once a week		6048000000000 (decimal)		1
### Never			0							0
#Set-RegistryValue -Path "HKCU:\SOFTWARE\Microsoft\Siuf\Rules" -Name "NumberOfSIUFInPeriod" -Value 0 -PropertyType "DWord"
#Set-RegistryValue -Path "HKCU:\SOFTWARE\Microsoft\Siuf\Rules" -Name "PeriodInNanoSeconds" -Value 0 -PropertyType "DWord"

# Disable "Let Apps Use My Advertising ID". Set by CMGE Group Policy. Need to check in registry.
#Set-RegistryValue -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo" -Name "Enabled" -Value 0 -PropertyType "DWord"

# Disable "Turn on SmartScreenFilter". Set by CMGE Group Policy. Need to check in registry.
#Set-RegistryValue -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppHost" -Name "EnableWebContentEvaluation" -Value 0 -PropertyType "DWord"

# Address issue of Personal Data Export page
Set-RegistryValue -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\CloudExperienceHost\Intent\PersonalDataExport" -Name "PDEShown" -Value 1 -PropertyType "DWord"

# Hide Cortana Button in taskbar
Set-RegistryValue -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowCortanaButton" -Value 0 -PropertyType "DWord"

# Hide People in taskbar
Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\People" -Name "PeopleBand" -Value 0 -PropertyType "DWord"

# Bug #887 - Configure Text for Screensaver
Set-RegistryValue -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Screensavers\ssText3d" -Name "DisplayString" -Value "Windows 10 神州网信政府版" -PropertyType "String"

# Hide cortana search in current user
Set-RegistryValue -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" -Name "SearchboxTaskbarMode"  -Value 1 -PropertyType "DWord"

# Disable "Let Apps Use My Advertising ID"
Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo" -Name "Enabled" -Value 0 -PropertyType "DWord"

# Make the changes of registry take effect immediately
# RUNDLL32.EXE user32.dll,UpdatePerUserSystemParameters
# $UpdateExe="$env:windir\System32\RUNDLL32.EXE"
# $UpdateCfg="user32.dll,UpdatePerUserSystemParameters"
# Start-Process -WindowStyle Hidden -FilePath "$UpdateExe" -ArgumentList "$UpdateCfg" -Verb runas -Wait

#CMGEInstaller
# UNCMIT-DISABLED Start-Process -FilePath "$env:SystemDrive\Recovery\OEM\CMGE\ResetSources\EPrivilege.exe" -ArgumentList " -U:S $env:SystemDrive\Recovery\OEM\CMGE\ResetSources\CMGEInstaller\CMGEInstaller.exe 02000000" -WindowStyle Hidden -Wait

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
#del "$env:SystemDrive\SiPolicy" -recurse
#del "$env:windir\Temp\ActivationTool" -recurse
del "$env:Public\Desktop\系统激活 (1).lnk"
#Start-Sleep -Seconds 1
#del $MyInvocation.MyCommand.Definition -Force
#Restart-Computer -Force
