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

function InstallCert
{
     param(
         [string]$CertFile,
         [string]$StoreLocation,
         [string]$StoreName
     )
     $certobj = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
     $certpath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($CertFile)
     $certobj.Import($certpath)
     $store = Get-Item "cert:\$StoreLocation\$StoreName"
	 $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]"ReadWrite")
     $store.Add($certobj)
     $store.Close()
} 

function RemoveCert
{
     param(
         [string]$CertFile,
         [string]$StoreLocation,
         [string]$StoreName
     )
$certobj = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
$certpath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($CertFile)
$certobj.Import($certpath)
$store = Get-Item "cert:\$StoreLocation\$StoreName"
$store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]"ReadWrite")
$store.Remove($certobj)
$store.Close()
}

############################ Script Main ##############################

#Start Transcript and Logging
$logDir = Get-LogDir
Start-Transcript "$logDir\CMGE_Registry_Upgrade.log"
$logCMD = "$logDir\CMGE_Registry_Upgrade_CMD.log"

#CSUI file name extension associations
#set-RegistryValue -Path "HKLM:\SOFTWARE\Classes\.csu" -Name "(Default)" -Value "csufile" -PropertyType "String"
#set-RegistryValue -Path "HKLM:\SOFTWARE\Classes\csufile\Shell\Open\Command" -Name "(Default)" -Value "%ProgramFiles%\CMITOfflineUpdateInstaller\csui.exe `"%1`"" -PropertyType "ExpandString"

#CMIT Activation Tool setup
#Set-RegistryValue -Path "HKLM:\SOFTWARE\CMIT\Active" -Name "ActivationServer" -Value "https://oag.cmgos.com:7892" -PropertyType "String"
#Set-RegistryValue -Path "HKLM:\SOFTWARE\CMIT\Active" -Name "ActiveMode" -Value "0" -PropertyType "DWord"
#Set-RegistryValue -Path "HKLM:\SOFTWARE\CMIT\Active" -Name "AndroidAppAddress" -Value "https://download.cmgos.com/api/download/tools/5/cmgeactivationapp.apk" -PropertyType "String"
Remove-ItemProperty "HKLM:\SOFTWARE\CMIT\Active" "ECLAFilePath" -Force
#Set-RegistryValue -Path "HKLM:\SOFTWARE\CMIT\Active" -Name "ExpirationDates" -Value "4999.0" -PropertyType "String"
#Set-RegistryValue -Path "HKLM:\SOFTWARE\CMIT\Active" -Name "IntranetActivationServer" -Value "http://vdi.cmge.local" -PropertyType "String"
#Set-RegistryValue -Path "HKLM:\SOFTWARE\CMIT\Active" -Name "IntranetSkuId" -Value "VDI" -PropertyType "String"
#Set-RegistryValue -Path "HKLM:\SOFTWARE\CMIT\Active" -Name "IosAppAddress" -Value "https://itunes.apple.com/cn/app/神州网信激活助手/id1435288167?mt=8" -PropertyType "String"
#Set-RegistryValue -Path "HKLM:\SOFTWARE\CMIT\Active" -Name "LastActiveTime" -Value "1970/1/1 11:11:11" -PropertyType "String"
#Set-RegistryValue -Path "HKLM:\SOFTWARE\CMIT\Active" -Name "OfflineEditionPkpn" -Value "171.X21-24728" -PropertyType "String"
#Set-RegistryValue -Path "HKLM:\SOFTWARE\CMIT\Active" -Name "OfflineGuid" -Value "a667c6a0-36b6-5017-f2ea-93902c53046b" -PropertyType "String"
#Set-RegistryValue -Path "HKLM:\SOFTWARE\CMIT\Active" -Name "OfflineSkuId" -Value "V0H0" -PropertyType "String"
#Set-RegistryValue -Path "HKLM:\SOFTWARE\CMIT\Active" -Name "OnlineEditionPkpn" -Value "171.X21-24728" -PropertyType "String"
#Set-RegistryValue -Path "HKLM:\SOFTWARE\CMIT\Active" -Name "OnlineGuid" -Value "a667c6a0-36b6-5017-f2ea-93902c53046b" -PropertyType "String"
#Set-RegistryValue -Path "HKLM:\SOFTWARE\CMIT\Active" -Name "OnlineSkuId" -Value "V0H" -PropertyType "String"

# For upgrade, enable OS reset by using the AllowUserToResetPhone registry key
Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\System" -Name "AllowUserToResetPhone" -Value 1 -PropertyType "DWord"
Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\System\AllowUserToResetPhone" -Name "value" -Value 1 -PropertyType "DWord"

# Disable "Let Apps Use My Advertising ID"
Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo" -Name "Enabled" -Value 0 -PropertyType "DWord"

#data emission abuout go.microsoft.com dmd.metaservices.microsoft.com dmd.metaservices.microsoft.com  dns.msftncsi.com
Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Device Metadata" -Name "PreventDeviceMetadataFromNetwork" -Value 1 -PropertyType "DWord"
Set-RegistryValue -Path "HKLM:\SYSTEM\ControlSet001\Services\NlaSvc\Parameters\Internet" -Name "EnableActiveProbing" -Value 0 -PropertyType "DWord"

# F1 redirect to CMIT website: http://support.cmgos.com/
Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\HelpAndSupport" -Name "OverrideUrl" -Value "http://support.cmgos.com/category/cmgehelp" -PropertyType "String"

#Data emission,displaycatalog.mp.microsoft.com
Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\InstallService\Configuration" -Name "AutoUpdateTasksEnabled" -value 0  -PropertyType "DWord"

# set hidden items in settings
Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name "SettingsPageVisibility" -value "hide:project;clipboard;remotedesktop;autoplay;mobile-devices;network-mobilehotspot;network-cellular;network-directaccess;nfctransactions;fonts;emailandaccounts;workplace;gaming-gamebar;gaming-gamedvr;gaming-gamemode;gaming-xboxnetworking;gaming-broadcasting;easeofaccess-speechrecognition;cortana-language;cortana-permissions;cortana-notifications;cortana-moredetails;privacy-phonecalls;privacy-speech;privacy-speechtyping;privacy-feedback;privacy-activityhistory;privacy-location;privacy-automaticfiledownloads;delivery-optimization;troubleshoot;findmydevice;windowsinsider;windowsanywhere;" -PropertyType "String"

# Set "feedback and diagnose" in settings closed. Set by CMGE Group Policy. Need to check in registry.
#Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Privacy" -Name "TailoredExperiencesWithDiagnosticDataEnabled" -Value 0 -PropertyType "DWord"

# Delete Windows Defender startup when system boot, in registry.
Remove-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" "SecurityHealth" -Force

# SpyNet Reporting Disabled (SR #38 - Item #12)
#Set-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Spynet" -Name "SpyNetReporting" -Value 0 -PropertyType "DWord"

# reset the version number
Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name "EditionSubManufacturer" -Value "神州网信技术有限公司" -PropertyType "String"
Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name "EditionSubstring" -Value "神州网信政府版" -PropertyType "String"
Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name "EditionSubVersion" -Value "V2022-L.1345.000" -PropertyType "String"
Set-RegistryValue -Path "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows NT\CurrentVersion" -Name "EditionSubManufacturer" -Value "神州网信技术有限公司" -PropertyType "String"
Set-RegistryValue -Path "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows NT\CurrentVersion" -Name "EditionSubstring" -Value "神州网信政府版" -PropertyType "String"
Set-RegistryValue -Path "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows NT\CurrentVersion" -Name "EditionSubVersion" -Value "V2022-L.1345.000" -PropertyType "String"

#Redirect active client
Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ClipSVC" -Name "AltActivationClient" -Value "%ProgramFiles%\CMITActivation\CmitClient.exe" -PropertyType "String"

#Fonts
Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts" -Name "Source Han Sans CN (TrueType)" -Value "SourceHanSansCN-Regular.otf" -PropertyType "String"

# Bug #896 - [GB30278]The port 139 is still in the netstat list
#Get-ChildItem -Path "HKLM:\SYSTEM\ControlSet001\services\NetBT\Parameters\Interfaces\" | foreach {
#    Set-RegistryValue -Path $_.PSPath -Name "NetbiosOptions" -Value 2 -PropertyType "DWord"
#}

# For upgrade, set Netlogon service start type to manual
Set-RegistryValue -Path "HKLM:\SYSTEM\ControlSet001\Services\Netlogon" -Name "Start" -Value "4" -PropertyType "DWord"

# Configure Registry Entry for VSO Bug 525 [data exhaust]
Set-RegistryValue -Path "HKLM:\SYSTEM\ControlSet001\Services\wlidsvc" -Name "Start" -Value "4" -PropertyType "DWord"

# Support from V0-G
# For upgrade, context menu "New" add BMP
# Set-RegistryValue -Path "HKLM:\SOFTWARE\Classes\.bmp" -Name "(default)" -Value "Paint.Picture" -PropertyType "String"

# For upgrade, delete Registry Settings for Setting Windows Photo Viewer as the Default Photo Viewer
# Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows Photo Viewer\Capabilities\FileAssociations" -Name ".bmp" -Force
# Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows Photo Viewer\Capabilities\FileAssociations" -Name ".dib" -Force
# Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows Photo Viewer\Capabilities\FileAssociations" -Name ".gif" -Force
# Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows Photo Viewer\Capabilities\FileAssociations" -Name ".jfif" -Force
# Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows Photo Viewer\Capabilities\FileAssociations" -Name ".jpe" -Force
# Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows Photo Viewer\Capabilities\FileAssociations" -Name ".jpeg" -Force
# Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows Photo Viewer\Capabilities\FileAssociations" -Name ".jpg" -Force
# Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows Photo Viewer\Capabilities\FileAssociations" -Name ".png" -Force
# Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows Photo Viewer\Capabilities\FileAssociations" -Name ".ico" -Force

# $Key = "HKLM\TK_NTUSER"
# $File = "$env:SystemDrive\Users\Default\NTUSER.DAT"
# Start-Process -FilePath "$env:WINDIR\system32\reg.exe" -ArgumentList "load $Key $File" -WindowStyle Hidden -Wait
# #Stretch wallpaper 
# Set-RegistryValue -Path "HKLM:\TK_NTUSER\Control Panel\Desktop" -Name "WallpaperStyle" -Value "2" -PropertyType "String"
# Set-RegistryValue -Path "HKLM:\TK_NTUSER\Software\Microsoft\Windows\CurrentVersion\Themes" -Name "WallpaperSetFromTheme" -Value 1 -PropertyType "DWord"
# Start-Sleep -Seconds 1
# #necessary call to be able to unload registry hive
# [gc]::Collect()
# Start-Process -FilePath "$env:WINDIR\system32\reg.exe" -ArgumentList "unload $Key" -WindowStyle Hidden -Wait
# Start-Sleep -Seconds 1

# if (Test-Path "$env:SystemDrive\Users\Default\AppData\Local\Microsoft\Windows\UsrClass.dat")
# {
	# $Key = "HKLM\TK_USERCLASS"
	# $File = "$env:SystemDrive\Users\Default\AppData\Local\Microsoft\Windows\UsrClass.dat"
	# Start-Process -FilePath "$env:WINDIR\system32\reg.exe" -ArgumentList "load $Key $File" -WindowStyle Hidden -Wait
	# Clear-ItemProperty -Path "HKLM:\TK_USERCLASS\.bmp" -Name "(default)"
	# Clear-ItemProperty -Path "HKLM:\TK_USERCLASS\.dib" -Name "(default)"
	# Clear-ItemProperty -Path "HKLM:\TK_USERCLASS\.gif" -Name "(default)"
	# Clear-ItemProperty -Path "HKLM:\TK_USERCLASS\.jfif" -Name "(default)"
	# Clear-ItemProperty -Path "HKLM:\TK_USERCLASS\.jpe" -Name "(default)"
	# Clear-ItemProperty -Path "HKLM:\TK_USERCLASS\.jpeg" -Name "(default)"
	# Clear-ItemProperty -Path "HKLM:\TK_USERCLASS\.jpg" -Name "(default)"
	# Clear-ItemProperty -Path "HKLM:\TK_USERCLASS\.png" -Name "(default)"
	# Clear-ItemProperty -Path "HKLM:\TK_USERCLASS\.ico" -Name "(default)"
	# Start-Sleep -Seconds 1
	# #necessary call to be able to unload registry hive
	# [gc]::Collect()
	# Start-Process -FilePath "$env:WINDIR\system32\reg.exe" -ArgumentList "unload $Key" -WindowStyle Hidden -Wait
# }

# Unregister dlls of SMx
$SMxExe="$env:SystemDrive\Recovery\OEM\CMGE\ResetSources\SMxCNG\win32\WstSM2ECESConfig.exe"
$SMxCfg="-unregister"
Start-Process -WindowStyle Hidden -FilePath "$SMxExe" -ArgumentList "$SMxCfg" -Verb runas -Wait
$SMxExe="$env:SystemDrive\Recovery\OEM\CMGE\ResetSources\SMxCNG\win32\WstSM2ECDSAConfig.exe"
$SMxCfg="-unregister"
Start-Process -WindowStyle Hidden -FilePath "$SMxExe" -ArgumentList "$SMxCfg" -Verb runas -Wait
$SMxExe="$env:SystemDrive\Recovery\OEM\CMGE\ResetSources\SMxCNG\win32\WstKSPConfig.exe"
$SMxCfg="-unregister"
Start-Process -WindowStyle Hidden -FilePath "$SMxExe" -ArgumentList "$SMxCfg" -Verb runas -Wait
$SMxExe="$env:SystemDrive\Recovery\OEM\CMGE\ResetSources\SMxCNG\win32\WstSM3Config.exe"
$SMxCfg="-unregister"
Start-Process -WindowStyle Hidden -FilePath "$SMxExe" -ArgumentList "$SMxCfg" -Verb runas -Wait
$SMxExe="$env:SystemDrive\Recovery\OEM\CMGE\ResetSources\SMxCNG\win32\WstSM4Config.exe"
$SMxCfg="-unregister"
Start-Process -WindowStyle Hidden -FilePath "$SMxExe" -ArgumentList "$SMxCfg" -Verb runas -Wait
$SMxExe="$env:SystemDrive\Recovery\OEM\CMGE\ResetSources\SMxCNG\win32\WstRngConfig.exe"
$SMxCfg="-unregister"
Start-Process -WindowStyle Hidden -FilePath "$SMxExe" -ArgumentList "$SMxCfg" -Verb runas -Wait
$SMxExe="cmd.exe"
$SMxCfg="/c `"$env:SystemDrive\Recovery\OEM\CMGE\ResetSources\SMxCNG\win32\WstKSPConfig.exe -enum`" >> $logCMD"
Start-Process -WindowStyle Hidden -FilePath "$SMxExe" -ArgumentList "$SMxCfg" -Verb runas -Wait

#Copy Recovery Folder
if (Test-Path "$env:SystemDrive\Recovery\OEM\ResetSources")
{
	del "$env:SystemDrive\Recovery\OEM\ResetSources" -recurse -Force
}
if (Test-Path "$env:SystemDrive\Recovery\OEM\LayoutModification.xml")
{
	del "$env:SystemDrive\Recovery\OEM\LayoutModification.xml" -Force
}
if (Test-Path "$env:SystemDrive\Recovery\OEM\ResetCustomizations.cmd")
{
	del "$env:SystemDrive\Recovery\OEM\ResetCustomizations.cmd" -Force
}
if (Test-Path "$env:SystemDrive\Recovery\OEM\unattend.xml")
{
	$CMGEStr = (Get-Content "$env:SystemDrive\Recovery\OEM\unattend.xml" -TotalCount 2)[-1].Substring(4,4)
	if ( -not ($CMGEStr -eq "CMGE"))
	{
		del "$env:SystemDrive\Recovery\OEM\unattend.xml" -Force
		Copy-Item "$env:windir\Temp\Recovery\OEM\unattend.xml" "$env:SystemDrive\Recovery\OEM" -Force
	}
}
else
{
	if ( -not (Test-Path "$env:SystemDrive\Recovery\OEM"))
	{
		New-Item "$env:SystemDrive\Recovery\OEM" -type Directory
	}
	Copy-Item "$env:windir\Temp\Recovery\OEM\unattend.xml" "$env:SystemDrive\Recovery\OEM" -Force
}
if (Test-Path "$env:SystemDrive\Recovery\OEM\ResetConfig.xml")
{
	$CMGEStr = (Get-Content "$env:SystemDrive\Recovery\OEM\ResetConfig.xml" -TotalCount 2)[-1].Substring(4,4)
	if ( -not ($CMGEStr -eq "CMGE"))
	{
		del "$env:SystemDrive\Recovery\OEM\ResetConfig.xml" -Force
		Copy-Item "$env:windir\Temp\Recovery\OEM\ResetConfig.xml" "$env:SystemDrive\Recovery\OEM" -Force
	}
}
else
{
	if ( -not (Test-Path "$env:SystemDrive\Recovery\OEM"))
	{
		New-Item "$env:SystemDrive\Recovery\OEM" -type Directory
	}
	Copy-Item "$env:windir\Temp\Recovery\OEM\ResetConfig.xml" "$env:SystemDrive\Recovery\OEM" -Force
}
if ( -not (Test-Path "$env:SystemDrive\Recovery\OEM\OEM"))
{
	New-Item "$env:SystemDrive\Recovery\OEM\OEM" -type Directory
}
if ( -not (Test-Path "$env:SystemDrive\Recovery\OEM\BasicPost.cmd"))
{
	if ( -not (Test-Path "$env:SystemDrive\Recovery\OEM"))
	{
		New-Item "$env:SystemDrive\Recovery\OEM" -type Directory
	}
	Copy-Item "$env:windir\Temp\Recovery\OEM\BasicPost.cmd" "$env:SystemDrive\Recovery\OEM" -Force
}
if ( -not (Test-Path "$env:SystemDrive\Recovery\OEM\BasicPre.cmd"))
{
	if ( -not (Test-Path "$env:SystemDrive\Recovery\OEM"))
	{
		New-Item "$env:SystemDrive\Recovery\OEM" -type Directory
	}
	Copy-Item "$env:windir\Temp\Recovery\OEM\BasicPre.cmd" "$env:SystemDrive\Recovery\OEM" -Force
}
if ( -not (Test-Path "$env:SystemDrive\Recovery\OEM\FactoryDiskFormat.cmd"))
{
	if ( -not (Test-Path "$env:SystemDrive\Recovery\OEM"))
	{
		New-Item "$env:SystemDrive\Recovery\OEM" -type Directory
	}
	Copy-Item "$env:windir\Temp\Recovery\OEM\FactoryDiskFormat.cmd" "$env:SystemDrive\Recovery\OEM" -Force
}
if ( -not (Test-Path "$env:SystemDrive\Recovery\OEM\FactoryPost.cmd"))
{
	if ( -not (Test-Path "$env:SystemDrive\Recovery\OEM"))
	{
		New-Item "$env:SystemDrive\Recovery\OEM" -type Directory
	}
	Copy-Item "$env:windir\Temp\Recovery\OEM\FactoryPost.cmd" "$env:SystemDrive\Recovery\OEM" -Force
}
if (Test-Path "$env:SystemDrive\Recovery\OEM\CMGE")
{
	#Delete CMGE Folder
	del "$env:SystemDrive\Recovery\OEM\CMGE" -recurse -Force
}
#Copy CMGE Folder
$CpyExe="$env:windir\System32\robocopy.exe"
$CpyCfg="$env:windir\Temp\Recovery\OEM\CMGE $env:SystemDrive\Recovery\OEM\CMGE /e"
Start-Process -WindowStyle Hidden -FilePath "$CpyExe" -ArgumentList "$CpyCfg" -Verb runas -Wait

# Implement Group Policy
$GpExe="$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\LGPO\LGPO.exe"
$GpCfg="/g $env:windir\Temp\Recovery\OEM\CMGE\ResetSources\LGPO"
Start-Process -WindowStyle Hidden -FilePath "$GpExe" -ArgumentList "$GpCfg" -Verb runas -Wait

# Remove Certificates
RemoveCert -CertFile "$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\Certificates\Beijing ROOT CA.cer" -StoreLocation LocalMachine -StoreName Root
RemoveCert -CertFile "$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\Certificates\Beijing GCA.cer" -StoreLocation LocalMachine -StoreName Root
RemoveCert -CertFile "$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\Certificates\BJCA.cer" -StoreLocation LocalMachine -StoreName Root
RemoveCert -CertFile "$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\Certificates\CEGN_RCA.cer" -StoreLocation LocalMachine -StoreName Root
RemoveCert -CertFile "$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\Certificates\CEGN_OCA.cer" -StoreLocation LocalMachine -StoreName Root
RemoveCert -CertFile "$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\Certificates\CMIT Root Authority.cer" -StoreLocation LocalMachine -StoreName Root
RemoveCert -CertFile "$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\Certificates\CMIT SubP.cer" -StoreLocation LocalMachine -StoreName CA  #####
RemoveCert -CertFile "$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\Certificates\CMIT signature.cer" -StoreLocation LocalMachine -StoreName TrustedPublisher
RemoveCert -CertFile "$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\Certificates\DigiCert Assured ID Root CA.cer" -StoreLocation LocalMachine -StoreName Root
RemoveCert -CertFile "$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\Certificates\DigiCert Global Root CA.cer" -StoreLocation LocalMachine -StoreName Root
RemoveCert -CertFile "$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\Certificates\DigiCert High Assurance EV Root CA.cer" -StoreLocation LocalMachine -StoreName Root
RemoveCert -CertFile "$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\Certificates\GDCA_ROOT_CA.cer" -StoreLocation LocalMachine -StoreName Root
RemoveCert -CertFile "$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\Certificates\GDCA_Guangdong_Certificate_Authority.cer" -StoreLocation LocalMachine -StoreName Root
RemoveCert -CertFile "$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\Certificates\ROOTCA.cer" -StoreLocation LocalMachine -StoreName Root
RemoveCert -CertFile "$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\Certificates\UCA Root.cer" -StoreLocation LocalMachine -StoreName Root
RemoveCert -CertFile "$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\Certificates\SHECA.cer" -StoreLocation LocalMachine -StoreName Root
# Install Certificates
Import-Certificate -FilePath "$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\Certificates\Beijing ROOT CA.cer" -CertStoreLocation Cert:\LocalMachine\Root
Import-Certificate -FilePath "$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\Certificates\Beijing GCA.cer" -CertStoreLocation Cert:\LocalMachine\CA
Import-Certificate -FilePath "$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\Certificates\BJCA.cer" -CertStoreLocation Cert:\LocalMachine\CA
Import-Certificate -FilePath "$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\Certificates\CEGN_RCA.cer" -CertStoreLocation Cert:\LocalMachine\Root
Import-Certificate -FilePath "$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\Certificates\CEGN_OCA.cer" -CertStoreLocation Cert:\LocalMachine\CA
Import-Certificate -FilePath "$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\Certificates\CMIT Root Authority.cer" -CertStoreLocation Cert:\LocalMachine\Root
Import-Certificate -FilePath "$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\Certificates\CMIT SubP.cer" -CertStoreLocation Cert:\LocalMachine\CA
InstallCert -CertFile "$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\Certificates\CMIT signature.cer" -StoreLocation LocalMachine -StoreName TrustedPublisher
Import-Certificate -FilePath "$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\Certificates\DigiCert Assured ID Root CA.cer" -CertStoreLocation Cert:\LocalMachine\Root
Import-Certificate -FilePath "$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\Certificates\DigiCert Global Root CA.cer" -CertStoreLocation Cert:\LocalMachine\Root
Import-Certificate -FilePath "$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\Certificates\DigiCert High Assurance EV Root CA.cer" -CertStoreLocation Cert:\LocalMachine\Root
Import-Certificate -FilePath "$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\Certificates\GDCA_ROOT_CA.cer" -CertStoreLocation Cert:\LocalMachine\Root
Import-Certificate -FilePath "$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\Certificates\GDCA_Guangdong_Certificate_Authority.cer" -CertStoreLocation Cert:\LocalMachine\CA
Import-Certificate -FilePath "$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\Certificates\ROOTCA.cer" -CertStoreLocation Cert:\LocalMachine\Root
Import-Certificate -FilePath "$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\Certificates\UCA Root.cer" -CertStoreLocation Cert:\LocalMachine\Root
Import-Certificate -FilePath "$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\Certificates\BeiJing ROOT CA New.cer" -CertStoreLocation Cert:\LocalMachine\Root
Import-Certificate -FilePath "$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\Certificates\Beijing GCA New.cer" -CertStoreLocation Cert:\LocalMachine\CA
Import-Certificate -FilePath "$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\Certificates\BJCA New.cer" -CertStoreLocation Cert:\LocalMachine\CA
#Import-Certificate -FilePath "$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\Certificates\PK.cer" -CertStoreLocation Cert:\LocalMachine\Root

#Copy activation tool files
$CpyExe="$env:windir\System32\robocopy.exe"
$CpyCfg="`"$env:Public\Desktop\系统激活.lnk`" `"$env:SystemDrive\Windows.old\Users\Public\Desktop\系统激活.lnk`"  /E /XC /XN /XO"
Start-Process -WindowStyle Hidden -FilePath "$CpyExe" -ArgumentList "$CpyCfg" -Verb runas -Wait
$CpyCfg="`"$env:Public\Desktop\系统激活.lnk`" `"$env:SystemDrive\Windows.old\Users\$env:USERNAME\Desktop\系统激活.lnk`"  /E /XC /XN /XO"
Start-Process -WindowStyle Hidden -FilePath "$CpyExe" -ArgumentList "$CpyCfg" -Verb runas -Wait
$CpyCfg="`"$env:SystemDrive\Program Files\CMIT3.0`" `"$env:SystemDrive\Windows.old\Program Files\CMIT3.0`"  /E /XC /XN /XO"
Start-Process -WindowStyle Hidden -FilePath "$CpyExe" -ArgumentList "$CpyCfg" -Verb runas -Wait
#$CpyCfg="`"$env:SystemDrive\Program Files\CMITActivation`" `"$env:SystemDrive\Windows.old\Program Files\CMITActivation`"  /E /XC /XN /XO"
#Start-Process -WindowStyle Hidden -FilePath "$CpyExe" -ArgumentList "$CpyCfg" -Verb runas -Wait

# Uninstall previous activation tool
$PatGuid = ""
if (Test-Path "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\{61F90E65-243E-4FDB-9D44-E25D5C310F6F}")
{
	$PatGuid = "{61F90E65-243E-4FDB-9D44-E25D5C310F6F}"
}
if (Test-Path "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\{7D68C596-8427-4298-A288-7370D84C0F7A}")
{
	$PatGuid = "{7D68C596-8427-4298-A288-7370D84C0F7A}"
}
if (Test-Path "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\{17A2CCB1-99E3-42D2-8085-43E05816C681}")
{
	$PatGuid = "{17A2CCB1-99E3-42D2-8085-43E05816C681}"
}
if (Test-Path "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\{6E2FB2CF-C8B2-47FC-846B-033BE3B81901}")
{
	$PatGuid = "{6E2FB2CF-C8B2-47FC-846B-033BE3B81901}"
}
if ($PatGuid -ne "")
{
	$UatExe = "MsiExec.exe"
	$UatCfg = "/x $PatGuid /qn /quiet"
	Start-Process -WindowStyle Hidden -FilePath "$UatExe" -ArgumentList "$UatCfg" -Verb runas -Wait
}

$ScATExe = "cmd.exe"
$ScATCfg = "/c `"sc.exe stop CmitClientSVC`" >> $logCMD"
Start-Process -WindowStyle Hidden -FilePath "$ScATExe" -ArgumentList "$ScATCfg" -Verb runas -Wait
$ScATExe = "cmd.exe"
$ScATCfg = "/c `"sc.exe delete CmitClientSVC`" >> $logCMD"
Start-Process -WindowStyle Hidden -FilePath "$ScATExe" -ArgumentList "$ScATCfg" -Verb runas -Wait
Start-Sleep -Seconds 2

#Delete  activation tool files
del "$env:Public\Desktop\系统激活.lnk" -Force >> $logCMD
del "$env:USERPROFILE\Desktop\系统激活.lnk" -Force >> $logCMD

# CMIT Activation Tool setup
# Install CMIT Activation Tool
del "$env:SystemDrive\Program Files\CMIT3.0" -recurse -Force >> $logCMD
del "$env:SystemDrive\Program Files\CMITActivation" -recurse -Force >> $logCMD
#Copy-Item "$env:SystemDrive\Recovery\OEM\CMGE\ResetSources\CMITActivation\CMITActivation" "$env:SystemDrive\Program Files\CMITActivation\" -recurse >> $logCMD
#Copy KeyHolder file
#Copy-Item "$env:SystemDrive\Recovery\OEM\CMGE\ResetSources\CMITActivation\KeyHolder" "$env:SystemDrive\ProgramData\Microsoft\Windows\ClipSVC\Install\" -recurse


#Copy CMIT Update Agent files
$CpyExe="$env:windir\System32\robocopy.exe"
$CpyCfg="`"$env:SystemDrive\ProgramData\Microsoft\Windows\Start Menu\Programs\更新客户端`" `"$env:SystemDrive\Windows.old\ProgramData\Microsoft\Windows\Start Menu\Programs\更新客户端`"  /E /XC /XN /XO"
Start-Process -WindowStyle Hidden -FilePath "$CpyExe" -ArgumentList "$CpyCfg" -Verb runas -Wait
$CpyCfg="`"$env:SystemDrive\Program Files\CmitUpdateAgent`" `"$env:SystemDrive\Windows.old\Program Files\CmitUpdateAgent`"  /E /XC /XN /XO"
Start-Process -WindowStyle Hidden -FilePath "$CpyExe" -ArgumentList "$CpyCfg" -Verb runas -Wait

# Uninstall previous CMIT Update Agent
$subkeys = Get-ChildItem -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
foreach ($subkey in $subkeys)
{
    $fullPath = $subkey.ToString()
    $cuaName = (Get-ItemProperty -Path Registry::$fullPath).DisplayName
    $cuaGuid = [System.IO.Path]::GetFileNameWithoutExtension($fullPath)
    $strComp = "神州网信在线系统-更新客户端"
    
    if ($cuaName -eq $strComp)
    {
		$UcuaExe = "MsiExec.exe"
		$UcuaCfg = "/x $cuaGuid /qn /quiet"
		Start-Process -WindowStyle Hidden -FilePath "$UcuaExe" -ArgumentList "$UcuaCfg" -Verb runas -Wait
    }
}

$ScCUAExe = "cmd.exe"
$ScCUACfg = "/c `"sc.exe stop CmitUpdateAgent`" >> $logCMD"
Start-Process -WindowStyle Hidden -FilePath "$ScCUAExe" -ArgumentList "$ScCUACfg" -Verb runas -Wait
$ScCUAExe = "cmd.exe"
$ScCUACfg = "/c `"sc.exe delete CmitUpdateAgent`" >> $logCMD"
Start-Process -WindowStyle Hidden -FilePath "$ScCUAExe" -ArgumentList "$ScCUACfg" -Verb runas -Wait
Start-Sleep -Seconds 2

#Delete CMIT Update Agent files
del "$env:SystemDrive\ProgramData\Microsoft\Windows\Start Menu\Programs\更新客户端\更新客户端 - 配置.lnk" -Force >> $logCMD
del "$env:SystemDrive\ProgramData\Microsoft\Windows\Start Menu\Programs\更新客户端\更新客户端 - 下载状态.lnk" -Force >> $logCMD
del "$env:SystemDrive\ProgramData\Microsoft\Windows\Start Menu\Programs\更新客户端\更新客户端.lnk" -Force >> $logCMD

# Install CMIT Update Agent
del "$env:SystemDrive\Program Files\CmitUpdateAgent" -recurse -Force >> $logCMD
#Copy-Item "$env:SystemDrive\Recovery\OEM\CMGE\ResetSources\CmitUpdateAgent" "$env:SystemDrive\Program Files\CmitUpdateAgent\" -recurse >> $logCMD

#Copy  CMITOfflineUpdateInstaller
$CpyExe="$env:windir\System32\robocopy.exe"
$CpyCfg="`"$env:SystemDrive\Program Files\CMITOfflineUpdateInstaller`" `"$env:SystemDrive\Windows.old\Program Files\CMITOfflineUpdateInstaller`"  /E /XC /XN /XO"
Start-Process -WindowStyle Hidden -FilePath "$CpyExe" -ArgumentList "$CpyCfg" -Verb runas -Wait

# Uninstall previous CMITOfflineUpdateInstaller
$subkeys = Get-ChildItem -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
foreach ($subkey in $subkeys)
{
    $fullPath = $subkey.ToString()
    $cuaName = (Get-ItemProperty -Path Registry::$fullPath).DisplayName
    $cuaGuid = [System.IO.Path]::GetFileNameWithoutExtension($fullPath)
    $strComp = "CMGE 离线更新安装工具"
    
    if ($cuaName -eq $strComp)
    {
		$UcuaExe = "MsiExec.exe"
		$UcuaCfg = "/x $cuaGuid /qn /quiet"
		Start-Process -WindowStyle Hidden -FilePath "$UcuaExe" -ArgumentList "$UcuaCfg" -Verb runas -Wait
    }
}

del "$env:SystemDrive\Program Files\CMITOfflineUpdateInstaller" -recurse -Force >> $logCMD


#CMITCMGEInstaller
New-Item $env:windir\Temp\cmit -ItemType Directory -Force
Copy-Item "$env:SystemDrive\Windows.old\Windows\System32\config\SOFTWARE" "$env:windir\Temp\cmit\" -Force >> $logCMD
Copy-Item "$env:SystemDrive\Windows.old\Windows\INF\cua.ini" "$env:windir\Temp\cmit\" -Force >> $logCMD
Start-Process -FilePath "$env:SystemDrive\Recovery\OEM\CMGE\ResetSources\EPrivilege.exe" -ArgumentList " -U:S $env:SystemDrive\Recovery\OEM\CMGE\ResetSources\CMGEInstaller\CMGEInstaller.exe 00000200" -WindowStyle Hidden -Wait

# Update the files of SMx
## Copy-Item "$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\SMxCNG\win64\msvcr110.dll" "$env:SystemDrive\Windows.old\Windows\System32\" -Force >> $logCMD
## Copy-Item "$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\SMxCNG\win64\msvcr110d.dll" "$env:SystemDrive\Windows.old\Windows\System32\" -Force >> $logCMD
## Copy-Item "$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\SMxCNG\win32\msvcr110.dll" "$env:SystemDrive\Windows.old\Windows\SysWOW64\" -Force >> $logCMD
##Copy-Item "$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\SMxCNG\win32\msvcr110d.dll" "$env:SystemDrive\Windows.old\Windows\SysWOW64\" -Force >> $logCMD
#Copy-Item "$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\CMITSMx\SysfileGenerator\wstcrypto.dll" "$env:windir\System32\" -Force >> $logCMD
#Copy-Item "$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\CMITSMx\SysfileGenerator\wstcrypto32.dll" "$env:windir\SysWOW64\wstcrypto.dll" -Force >> $logCMD
#Copy-Item "$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\CMITSMx\SysfileGenerator\wstsysfile.dat" "$env:SystemDrive\ProgramData\" -Force >> $logCMD
#$CpyExe="$env:windir\System32\robocopy.exe"
#$CpyCfg="$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\CMITSMx\win64\ $env:windir\System32\ *.dll /e"
#Start-Process -WindowStyle Hidden -FilePath "$CpyExe" -ArgumentList "$CpyCfg" -Verb runas -Wait
#$CpyExe="$env:windir\System32\robocopy.exe"
#$CpyCfg="$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\CMITSMx\win32\ $env:windir\SysWOW64\ *.dll /e"
#Start-Process -WindowStyle Hidden -FilePath "$CpyExe" -ArgumentList "$CpyCfg" -Verb runas -Wait
# $ScATExe = "cmd.exe"
# $ScATCfg = "/c `"robocopy.exe $env:windir\Temp\Recovery\OEM\CMGE\ResetSources\SMxCNG\win64\ $env:windir\System32\ *.dll /e`" >> $logCMD"
# Start-Process -WindowStyle Hidden -FilePath "$ScATExe" -ArgumentList "$ScATCfg" -Verb runas -Wait
# $ScATExe = "cmd.exe"
# $ScATCfg = "/c `"robocopy.exe $env:windir\Temp\Recovery\OEM\CMGE\ResetSources\SMxCNG\win32\ $env:windir\SysWOW64\ *.dll /e`" >> $logCMD"
# Start-Process -WindowStyle Hidden -FilePath "$ScATExe" -ArgumentList "$ScATCfg" -Verb runas -Wait

# Register dlls of SMx
$SMxExe="$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\CMITSMx\win32\WstSM2ECESConfig.exe"
$SMxCfg="-register"
Start-Process -WindowStyle Hidden -FilePath "$SMxExe" -ArgumentList "$SMxCfg" -Verb runas -Wait
$SMxExe="$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\CMITSMx\win32\WstSM2ECDSAConfig.exe"
$SMxCfg="-register"
Start-Process -WindowStyle Hidden -FilePath "$SMxExe" -ArgumentList "$SMxCfg" -Verb runas -Wait
$SMxExe="$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\CMITSMx\win32\WstKSPConfig.exe"
$SMxCfg="-register"
Start-Process -WindowStyle Hidden -FilePath "$SMxExe" -ArgumentList "$SMxCfg" -Verb runas -Wait
$SMxExe="$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\CMITSMx\win32\WstSM3Config.exe"
$SMxCfg="-register"
Start-Process -WindowStyle Hidden -FilePath "$SMxExe" -ArgumentList "$SMxCfg" -Verb runas -Wait
$SMxExe="$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\CMITSMx\win32\WstSM4Config.exe"
$SMxCfg="-register"
Start-Process -WindowStyle Hidden -FilePath "$SMxExe" -ArgumentList "$SMxCfg" -Verb runas -Wait
$SMxExe="$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\CMITSMx\win32\WstRngConfig.exe"
$SMxCfg="-register"
Start-Process -WindowStyle Hidden -FilePath "$SMxExe" -ArgumentList "$SMxCfg" -Verb runas -Wait
$SMxExe="cmd.exe"
$SMxCfg="/c `"$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\CMITSMx\win32\WstKSPConfig.exe -enum`" >> $logCMD"
Start-Process -WindowStyle Hidden -FilePath "$SMxExe" -ArgumentList "$SMxCfg" -Verb runas -Wait



# Copy unattend file to Panther folder
Copy-Item "$env:SystemDrive\Recovery\OEM\unattend.xml" "$env:windir\Panther" -Force

# Delete Scheduled Task
Unregister-ScheduledTask -TaskName "GSKU User Settings" -Confirm:$false
del "$env:Public\GSKU_HKCU" -recurse -Force

# Create Scheduled Task
$Action = New-ScheduledTaskAction -Execute "$env:windir\Temp\UpgradeSchdTask.exe"
$Trigger = New-ScheduledTaskTrigger -AtLogon
$Principal = New-ScheduledTaskPrincipal -GroupID "Builtin\Users" -RunLevel Highest
$Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Seconds 60) -Compatibility Win8
$SchTask = New-ScheduledTask -Action $Action -Principal $Principal -Trigger $Trigger -Settings $Settings
Register-ScheduledTask "UpgradeSchdTask" -InputObject $SchTask


# Create a Shortcut for CMIT Update Agent
New-Item "$env:SystemDrive\ProgramData\Microsoft\Windows\Start Menu\Programs\更新客户端" -type Directory
$TargetFile = "$env:SystemDrive\Program Files\CmitUpdateAgent\CMOS-UA_ConfigurationTool.exe"
$ShortcutFile = "$env:SystemDrive\ProgramData\Microsoft\Windows\Start Menu\Programs\更新客户端\更新客户端.lnk"
$WorkingDir = "$env:SystemDrive\Program Files\CmitUpdateAgent"
$WScriptShell = New-Object -ComObject WScript.Shell
$Shortcut = $WScriptShell.CreateShortcut($ShortcutFile)
$Shortcut.TargetPath = $TargetFile
$Shortcut.WorkingDirectory = $WorkingDir
$Shortcut.Save()

# Install service for CMIT Update Agent
$CUAExe="$env:SystemDrive\Program Files\CmitUpdateAgent\CmitUpdateAgent.exe"
$CUACfg="-install"
Start-Process -WindowStyle Hidden -FilePath "$CUAExe" -ArgumentList "$CUACfg" -Verb runas -Wait
# Start service for CMIT Update Agent
$CUAExe = "cmd.exe"
$CUACfg = "/c `"sc.exe start CmitUpdateAgent`" >> $logCMD"
Start-Process -WindowStyle Hidden -FilePath "$CUAExe" -ArgumentList "$CUACfg" -Verb runas -Wait
Start-Sleep -Seconds 2

# Delete Scheduled Taskfor CMIT Update Agent
Unregister-ScheduledTask -TaskName "CmitUpdateAgent Daily Runner" -Confirm:$false 

# Create Scheduled Task for CMIT Update Agent
$Action = New-ScheduledTaskAction -Execute "$env:SystemDrive\Program Files\CmitUpdateAgent\CmitServiceMonitor.exe" -Id "10086"
$Trigger0 = New-ScheduledTaskTrigger -Daily -At "3:00"
$Trigger1 = New-ScheduledTaskTrigger -Daily -At "7:00"
$Trigger2 = New-ScheduledTaskTrigger -Daily -At "11:00"
$Trigger3 = New-ScheduledTaskTrigger -Daily -At "15:00"
$Trigger4 = New-ScheduledTaskTrigger -Daily -At "19:00"
$Trigger5 = New-ScheduledTaskTrigger -Daily -At "23:00"
$Principal = New-ScheduledTaskPrincipal -GroupID "NT AUTHORITY\SYSTEM" -RunLevel Highest
$Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Seconds 120)
$SchTask = New-ScheduledTask -Action $Action -Principal $Principal -Trigger $Trigger0,$Trigger1,$Trigger2,$Trigger3,$Trigger4,$Trigger5 -Settings $Settings
Register-ScheduledTask -TaskName "CmitUpdateAgent Daily Runner" -TaskPath "\CMIT\CmitUpdateAgent" -InputObject $SchTask

#Disable-ScheduledTask
Disable-ScheduledTask -TaskName "\Microsoft\Windows\InstallService\ScanForUpdates"
Disable-ScheduledTask -TaskName "\Microsoft\Windows\InstallService\ScanForUpdatesAsUser"


#Create two Shortcuts for CMITControlCenter
New-Item "$env:SystemDrive\ProgramData\Microsoft\Windows\Start Menu\Programs\CMGE控制中心" -type Directory
$TargetFile = "$env:SystemDrive\Program Files\CMITControlCenter\ControlCenter.exe"
$ShortcutFile = "$env:SystemDrive\ProgramData\Microsoft\Windows\Start Menu\Programs\CMGE控制中心\控制中心.lnk"
$WorkingDir = "$env:SystemDrive\Program Files\CMITControlCenter"
$WScriptShell = New-Object -ComObject WScript.Shell
$Shortcut = $WScriptShell.CreateShortcut($ShortcutFile)
$Shortcut.TargetPath = $TargetFile
$Shortcut.WorkingDirectory = $WorkingDir
$Shortcut.Save()

$TargetFile = "$env:SystemDrive\Program Files\CMITControlCenter\ControlCenter.exe"
$ShortcutFile = "$env:Public\Desktop\控制中心.lnk"
$WorkingDir = "$env:SystemDrive\Program Files\CMITControlCenter"
$WScriptShell = New-Object -ComObject WScript.Shell
$Shortcut = $WScriptShell.CreateShortcut($ShortcutFile)
$Shortcut.TargetPath = $TargetFile
$Shortcut.WorkingDirectory = $WorkingDir
$Shortcut.Save()

$ScATExe = "cmd.exe"
$ScATCfg = "/c `"sc.exe stop wlidsvc`" >> $logCMD"
Start-Process -WindowStyle Hidden -FilePath "$ScATExe" -ArgumentList "$ScATCfg" -Verb runas -Wait
$ScATExe = "cmd.exe"
$ScATCfg = "/c `"sc.exe config wlidsvc start= disabled`" >> $logCMD"
Start-Process -WindowStyle Hidden -FilePath "$ScATExe" -ArgumentList "$ScATCfg" -Verb runas -Wait
Start-Sleep -Seconds 2

$ScATExe = "cmd.exe"
$ScATCfg = "/c `"sc.exe stop netlogon`" >> $logCMD"
Start-Process -WindowStyle Hidden -FilePath "$ScATExe" -ArgumentList "$ScATCfg" -Verb runas -Wait
$ScATExe = "cmd.exe"
$ScATCfg = "/c `"sc.exe config netlogon start= disabled`" >> $logCMD"
Start-Process -WindowStyle Hidden -FilePath "$ScATExe" -ArgumentList "$ScATCfg" -Verb runas -Wait
Start-Sleep -Seconds 2

# Code Integrity policy
#Invoke-CimMethod -Namespace root\Microsoft\Windows\CI -ClassName PS_UpdateAndCompareCIPolicy -MethodName Update -Arguments @{FilePath = "C:\SiPolicy\SIPolicy.p7b"}

# Cleanup
#del "$env:windir\Temp\LGPO" -recurse
#del "$env:windir\Temp\Certificates" -recurse
del "$env:windir\Temp\Recovery" -recurse -Force
#del "$env:SystemDrive\SiPolicy" -recurse
#del "$env:windir\Temp\ActivationTool" -recurse
del "$env:windir\Temp\InsPreConfig.exe"
del "$env:windir\Temp\InsPreConfigPS.ps1"
del "$env:windir\Temp\InsPostConfig.exe"
del "$env:windir\Temp\InsPostConfigPS.ps1"
del "$env:SystemDrive\ProgramData\Microsoft\Windows\Start Menu\Programs\Administrative Tools\Windows Defender Firewall with Advanced Security.lnk"
#del $MyInvocation.MyCommand.Definition -Force