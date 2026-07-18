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

############################ Script Main ##############################

#Start Transcript and Logging
$logDir = Get-LogDir
Start-Transcript "$logDir\CMGE_Registry_Reset_Pre.log"

## Remove Windows Media Player Functions
Disable-WindowsOptionalFeature -FeatureName WindowsMediaPlayer -Online -NoRestart -WarningAction silentlyContinue
Disable-WindowsOptionalFeature -FeatureName MediaPlayback -Online -NoRestart -WarningAction silentlyContinue

# ---HKEY_LOCAL_MACHINE--------------------------------------------------------------------
#CSUI file name extension associations
#set-RegistryValue -Path "HKLM:\SOFTWARE\Classes\.csu" -Name "(Default)" -Value "csufile" -PropertyType "String"
#set-RegistryValue -Path "HKLM:\SOFTWARE\Classes\csufile\Shell\Open\Command" -Name "(Default)" -Value "%ProgramFiles%\CMITOfflineUpdateInstaller\csui.exe `"%1`"" -PropertyType "ExpandString"

# Data exhaust detected Chshap.blob.core.windows.net
Remove-RestrictedRegKey -Path "HKLM:\SOFTWARE\Classes\CLSID\{AEB2BF55-0B96-456C-A57F-B742ACD4775B}" -AccountName "Administrators"

#CMIT Activation Tool setup
#Set-RegistryValue -Path "HKLM:\SOFTWARE\CMIT\Active" -Name "ActivationServer" -Value "https://oag.cmgos.com:7892" -PropertyType "String"
#Set-RegistryValue -Path "HKLM:\SOFTWARE\CMIT\Active" -Name "ActiveMode" -Value "0" -PropertyType "DWord"
#Set-RegistryValue -Path "HKLM:\SOFTWARE\CMIT\Active" -Name "AndroidAppAddress" -Value "https://download.cmgos.com/api/download/tools/5/cmgeactivationapp.apk" -PropertyType "String"
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

# Disable traffic to Setting-win.data.microsoft.com  VSO #566
Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Speech\" -Name "AllowSpeechModelUpdate" -Value "0" -PropertyType "DWord"

# Disable Wi-Fi Sesne (SR #29 - Item #6)
Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\WcmSvc\wifinetworkmanager\config" -Name "AutoConnectAllowedOEM" -Value "0" -PropertyType "DWord"

# Bug #943 - [data exhaust] Detected data traffic to cem.services.micorsoft.com when try to open Activation page in Settings
Set-RestrictedRegKeyValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModel\CloudExtensions" -Name "CloudErrorMessagesHostName" -PropertyType String -Value "https;//foo.bar" -AccountName "Administrators"

# Setup GSKU marker
Set-RestrictedRegKeyValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModel\CloudExtensions" -Name "excellence" -PropertyType String -Value "ae49ee92-e73d-4e07-8f1a-029ae58224cf" -AccountName "Administrators"

# Set Time Services (SR#62 - Item #3)
Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DateTime\Servers" -Name "(Default)" -Value "0" -PropertyType "String"
Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DateTime\Servers" -Name "0" -Value "cn.pool.ntp.org" -PropertyType "String"

#data emission abuout go.microsoft.com dmd.metaservices.microsoft.com dmd.metaservices.microsoft.com  dns.msftncsi.com
Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Device Metadata" -Name "PreventDeviceMetadataFromNetwork" -Value 1 -PropertyType "DWord"
Set-RegistryValue -Path "HKLM:\SYSTEM\ControlSet001\Services\NlaSvc\Parameters\Internet" -Name "EnableActiveProbing" -Value 0 -PropertyType "DWord"

# Removing 3D objects Section from Windows Explorer Navigation Pane
Remove-Item  "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace\{0DB7E03F-FC29-4DC6-9020-FF41B59E513A}" -recurse
Remove-Item  "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace\{0DB7E03F-FC29-4DC6-9020-FF41B59E513A}" -recurse

# F1 redirect to CMIT website: http://support.cmgos.com/
Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\HelpAndSupport" -Name "OverrideUrl" -Value "http://support.cmgos.com/category/cmgehelp" -PropertyType "String"

#Data emission,displaycatalog.mp.microsoft.com
Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\InstallService\Configuration" -Name "AutoUpdateTasksEnabled" -value 0  -PropertyType "DWord"

# set hidden items in settings
Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name "SettingsPageVisibility" -value "hide:project;clipboard;remotedesktop;autoplay;mobile-devices;network-mobilehotspot;network-cellular;network-directaccess;nfctransactions;fonts;emailandaccounts;workplace;gaming-gamebar;gaming-gamedvr;gaming-gamemode;gaming-xboxnetworking;gaming-broadcasting;easeofaccess-speechrecognition;cortana-language;cortana-permissions;cortana-notifications;cortana-moredetails;privacy-phonecalls;privacy-speech;privacy-speechtyping;privacy-feedback;privacy-activityhistory;privacy-location;privacy-automaticfiledownloads;delivery-optimization;troubleshoot;findmydevice;windowsinsider;windowsanywhere;" -PropertyType "String"

# Set "feedback and diagnose" in settings closed
Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Privacy" -Name "TailoredExperiencesWithDiagnosticDataEnabled" -Value 0 -PropertyType "DWord"

# Delete Windows Defender startup when system boot, in registry.
Remove-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" "SecurityHealth" -Force

# Disable "Let Apps on my other devices..."
Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\SmartGlass" -Name "UserAuthPolicy" -Value 0 -PropertyType "DWord"

# Bug 1012 - Windows Defender
Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting" -Name "Disabled" -Value 1 -PropertyType "DWord"

# reset the version number
Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name "EditionSubManufacturer" -Value "神州网信技术有限公司" -PropertyType "String"
Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name "EditionSubstring" -Value "神州网信政府版" -PropertyType "String"
Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name "EditionSubVersion" -Value "V2022-L.1345.000" -PropertyType "String"
Set-RegistryValue -Path "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows NT\CurrentVersion" -Name "EditionSubManufacturer" -Value "神州网信技术有限公司" -PropertyType "String"
Set-RegistryValue -Path "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows NT\CurrentVersion" -Name "EditionSubstring" -Value "神州网信政府版" -PropertyType "String"
Set-RegistryValue -Path "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows NT\CurrentVersion" -Name "EditionSubVersion" -Value "V2022-L.1345.000" -PropertyType "String"

# Sets Register Owner Name
Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name "RegisteredOrganization" -Value "神州网信技术有限公司" -PropertyType "String"
#Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name "RegisteredOwner" -Value "政府版用户" -PropertyType "String"

#Redirect active client
Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ClipSVC" -Name "AltActivationClient" -Value "%ProgramFiles%\CMITActivation\CmitClient.exe" -PropertyType "String"

#Fonts
Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts" -Name "Source Han Sans CN (TrueType)" -Value "SourceHanSansCN-Regular.otf" -PropertyType "String"

#Configure KMS Host Server registry value
Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SoftwareProtectionPlatform" -Name "KeyManagementServiceName" -Value "KMS.cmgos.com" -PropertyType "String"

#settings-win.data.microsoft.com
Set-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name  "DisableOneSettingsDownloads" -Value 1 -PropertyType "DWord"
Set-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name  "EnableOneSettingsAuditing" -Value 1 -PropertyType "DWord"

# Disabling Malicious Software Removal Tool Update Offering through Windows Update Registry Keys
Set-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\MRT" -Name "DontOfferThroughWUAU" -Value 1 -PropertyType "DWord"

# Turn off Malicious Software Reporting Tool (SR #40 - Item #12)
Set-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\MRT" -Name "DontReportInfectionInformation" -Value 1 -PropertyType "DWord"

# Remove Store. Disabling Open With Look For Store Apps Registry Keys
Set-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer" -Name "NoUseStoreOpenWith" -Value 1 -PropertyType "DWord"

#DisableCleanPC
Set-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PushButtonReset" -Name "DisableCleanPC" -Value 1 -PropertyType "DWord"

# Disabling Windows SmartScreen Registry Keys
Set-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "EnableSmartScreen" -Value 0 -PropertyType "DWord"

# Data emission, News & Interests, api.msn.com & assets.msn.cn
Set-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feed" -Name "EnableFeeds" -Value 0 -PropertyType "DWord"

# Disabling Cortana and Hiding the Taskbar Search Icon Registry Keys
#Set-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Name "AllowCortana" -Value 0 -PropertyType "DWord"

# SpyNet Reporting Disabled (SR #38 - Item #12)
#Set-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Spynet" -Name "SpyNetReporting" -Value 0 -PropertyType "DWord"

# Bug 539 Windows contacts is listed in Set Default Programs
if ((Get-ItemProperty -Path HKLM:\SOFTWARE\RegisteredApplications).("Windows Address Book")) {
	Remove-ItemProperty -Path HKLM:\SOFTWARE\RegisteredApplications -Name "Windows Address Book"
}

# Bug #532 - Can start Windows Remote Assistance
Set-RegistryValue -Path "HKLM:\SYSTEM\ControlSet001\Control\Remote Assistance" -Name "fAllowToGetHelp" -Value 0 -PropertyType "DWord"
#Set-RegistryValue -Path "HKLM:\SYSTEM\ControlSet001\Control\Terminal Server" -Name "AllowRemoteRPC" -Value 0 -PropertyType "DWord"
#Set-RegistryValue -Path "HKLM:\SYSTEM\ControlSet001\Control\Terminal Server" -Name "fdenyTSConnections" -Value 1 -PropertyType "DWord"
#Set-RegistryValue -Path "HKLM:\SYSTEM\ControlSet001\Control\Terminal Server" -Name "TSUserEnabled" -Value 0 -PropertyType "DWord"
Set-RegistryValue -Path "HKLM:\SYSTEM\ControlSet001\services\UmRdpService" -Name "Start" -Value 4 -PropertyType "DWord"

# System variables
#Set-RegistryValue -Path "HKLM:\SYSTEM\ControlSet001\Control\Session Manager\Environment" -Name "Path" -value "%SystemRoot%\system32;%SystemRoot%;%SystemRoot%\System32\Wbem;%SYSTEMROOT%\System32\WindowsPowerShell\v1.0\;%SYSTEMROOT%\System32\OpenSSH\;%ProgramFiles%\CMITControlCenter\;" -PropertyType "ExpandString"

# GB30278 (#57, 58, 59, 60, 61, 62, 65, & 66)
Set-RegistryValue -Path "HKLM:\SYSTEM\ControlSet001\Services\AppMgmt" -Name "Start" -Value "4" -PropertyType "DWord"
#Set-RestrictedRegKeyValue -Path "HKLM:\SYSTEM\ControlSet001\Services\DPS" -Name "Start" -Value "4" -PropertyType "DWord" -AccountName "Administrators"
Set-RegistryValue -Path "HKLM:\SYSTEM\ControlSet001\Services\Netlogon" -Name "Start" -Value "4" -PropertyType "DWord"
Set-RegistryValue -Path "HKLM:\SYSTEM\ControlSet001\Services\pla" -Name "Start" -Value "4" -PropertyType "DWord"
#Set-RegistryValue -Path "HKLM:\SYSTEM\ControlSet001\Services\RemoteRegistry" -Name "Start" -Value "4" -PropertyType "DWord"
Set-RegistryValue -Path "HKLM:\SYSTEM\ControlSet001\Services\wercplsupport" -Name "Start" -Value "4" -PropertyType "DWord"
Set-RegistryValue -Path "HKLM:\SYSTEM\ControlSet001\Services\WerSvc" -Name "Start" -Value "4" -PropertyType "DWord"

# Disable Windows Firewall Service
Set-RegistryValue -Path "HKLM:\SYSTEM\ControlSet001\Services\DiagTrack" -Name "Start" -Value "4" -PropertyType "DWord"

# Disable Microsoft Telemetry Services
#Set-RegistryValue -Path "HKLM:\SYSTEM\ControlSet001\Services\dmwappushservice" -Name "Start" -Value "4" -PropertyType "DWord"

# Disable Fax
Set-RegistryValue -Path "HKLM:\SYSTEM\ControlSet001\Services\Fax" -Name "Start" -Value "4" -PropertyType "DWord"

# Disbale Font Providers (SR #48 - Item #3)
Set-RegistryValue -Path "HKLM:\SYSTEM\ControlSet001\Services\FontCache\Parameters" -Name "DisableFontProviders" -Value 1 -PropertyType "DWord"

# Disable Teredo (SR#66 - Item #3)
Set-RegistryValue -Path "HKLM:\SYSTEM\ControlSet001\Services\iphlpsvc\Teredo" -Name "Type" -Value "4" -PropertyType "DWord"

# Bug #898 - Remove C$, ADMIN$ and IPC$ administrative shares
Set-RegistryValue -Path "HKLM:\SYSTEM\ControlSet001\Services\LanmanServer\Parameters" -Name "AutoShareWks" -Value 0 -PropertyType "DWord"

# Disable data traffic licensing.mp.microsoft.com
Set-RegistryValue -Path "HKLM:\SYSTEM\ControlSet001\Services\LicenseManager" -Name "Start" -Value "4" -PropertyType "DWord"

# Disabling Windows Defender Security Center Service Registry Keys
Set-RegistryValue -Path "HKLM:\SYSTEM\ControlSet001\Services\SecurityHealthService" -Name "Start" -Value "4" -PropertyType "DWord"

# GB30278 (#87 & #88)
Set-RegistryValue -Path "HKLM:\SYSTEM\ControlSet001\Services\Tcpip\Parameters" -Name "SynAttackProtect" -Value "1" -PropertyType "DWord"
Set-RegistryValue -Path "HKLM:\SYSTEM\ControlSet001\Services\Tcpip\Parameters" -Name "TcpMaxConnectResponseRetransmissions" -Value "3" -PropertyType "DWord"

# Disbale IPv6 Teredo (SR #50 - Item #3) Bug #616 - Tcpip6 DisabledComonents setting
Set-RegistryValue -Path "HKLM:\SYSTEM\ControlSet001\Services\Tcpip6\Parameters" -Name "DisabledComponents" -Value 8 -PropertyType "DWord"

# Set new NTP Server (SR #49 - Item #3)
Set-RegistryValue -Path "HKLM:\SYSTEM\ControlSet001\Services\W32Time\Parameters" -Name "NtpServer" -Value "cn.pool.ntp.org,0x9" -PropertyType "String"

# Configure Registry Entry for VSO Bug 525 [data exhaust]
Set-RegistryValue -Path "HKLM:\SYSTEM\ControlSet001\Services\wlidsvc" -Name "Start" -Value "4" -PropertyType "DWord"


# ---Default user HKCU--------------------------------------------------
# Default user HKCU registry settings 
$Key = "HKLM\DU_HKCU"
$File = "$env:SystemDrive\Users\Default\NTUSER.DAT"
Start-Process -FilePath "$env:WINDIR\system32\reg.exe" -ArgumentList "load $Key $File" -WindowStyle Hidden -Wait
# Set delay lock interval for users after setting sleep(every time). Set by CMGE Group Policy. Need to check in registry.
# Set-RegistryValue -Path "HKLM:\DU_HKCU\Control Panel\Desktop" -Name "DelayLockInterval" -Value 0 -PropertyType "DWord"

# Stretch wallpaper 
Set-RegistryValue -Path "HKLM:\DU_HKCU\Control Panel\Desktop" -Name "WallpaperStyle" -Value "2" -PropertyType "String"
Set-RegistryValue -Path "HKLM:\DU_HKCU\Software\Microsoft\Windows\CurrentVersion\Themes" -Name "WallpaperSetFromTheme" -Value 1 -PropertyType "DWord"

# Let Websites provide locally relevant content by accessing language list (SR #9 - Item #3). Set by CMGE Group Policy. Need to check in registry.
# Set-RegistryValue -Path "HKLM:\DU_HKCU\Control Panel\International\User Profile" -Name "HttpAcceptLanguageOptOut" -Value 1 -PropertyType "DWord"

# Configure Getting to Know You (Bug #618). Set by CMGE Group Policy. Need to check in registry.
# Set-RegistryValue -Path "HKLM:\DU_HKCU\SOFTWARE\Microsoft\InputPersonalization" -Name "RestrictImplicitInkCollection" -Value 1 -PropertyType "DWord"
# Set-RegistryValue -Path "HKLM:\DU_HKCU\SOFTWARE\Microsoft\InputPersonalization" -Name "RestrictImplicitTextCollection" -Value 1 -PropertyType "DWord"
# Set-RegistryValue -Path "HKLM:\DU_HKCU\SOFTWARE\Microsoft\InputPersonalization\TrainedDataStore" -Name "HarvestContacts" -Value 0 -PropertyType "DWord"
# Set-RegistryValue -Path "HKLM:\DU_HKCU\SOFTWARE\Microsoft\Personalization\Settings" -Name "AcceptedPrivacyPolicy" -Value 0 -PropertyType "DWord"

# Disable ActiveX Control (SR#56 - Item #3). Set by Windows Group Policy. Need to check in registry.
# Set-RegistryValue -Path "HKLM:\DU_HKCU\SOFTWARE\Microsoft\Internet Explorer\VersionManager" -Name "DownloadVersionList" -Value 0 -PropertyType "DWord"

# Feedback & Diagnostics Settings (SR #12, #13 - Item #3). Set by CMGE Group Policy. Need to check in registry.
# Set-RegistryValue -Path "HKLM:\DU_HKCU\SOFTWARE\Microsoft\Siuf\Rules" -Name "NumberOfSIUFInPeriod" -Value 0 -PropertyType "DWord"
# Set-RegistryValue -Path "HKLM:\DU_HKCU\SOFTWARE\Microsoft\Siuf\Rules" -Name "PeriodInNanoSeconds" -Value 0 -PropertyType "DWord"

# Disable "Let Apps Use My Advertising ID". Set by CMGE Group Policy. Need to check in registry.
# Set-RegistryValue -Path "HKLM:\DU_HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo" -Name "Enabled" -Value 0 -PropertyType "DWord"

# Disable "Turn on SmartScreenFilter". Set by CMGE Group Policy. Need to check in registry.
# Set-RegistryValue -Path "HKLM:\DU_HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\AppHost" -Name "EnableWebContentEvaluation" -Value 0 -PropertyType "DWord"

# Address issue of Personal Data Export page
Set-RegistryValue -Path "HKLM:\DU_HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\CloudExperienceHost\Intent\PersonalDataExport" -Name "PDEShown" -Value 1 -PropertyType "DWord"

# Hide Cortana Button in taskbar
Set-RegistryValue -Path "HKLM:\DU_HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowCortanaButton" -Value 0 -PropertyType "DWord"

# Hide People in taskbar
Set-RegistryValue -Path "HKLM:\DU_HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\People" -Name "PeopleBand" -Value 0 -PropertyType "DWord"

# Bug #887 - Configure Text for Screensaver
Set-RegistryValue -Path "HKLM:\DU_HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Screensavers\ssText3d" -Name "DisplayString" -Value "Windows 10 神州网信政府版" -PropertyType "String"

# Hide cortana search in current user
Set-RegistryValue -Path "HKLM:\DU_HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" -Name "SearchboxTaskbarMode"  -Value 1 -PropertyType "DWord"

Start-Sleep -Seconds 1
# necessary call to be able to unload registry hive
[gc]::Collect()
Start-Process -FilePath "$env:WINDIR\system32\reg.exe" -ArgumentList "unload $Key" -WindowStyle Hidden -Wait

# CMIT Activation Tool setup
# Create a Shortcut for Activation Tool
#$TargetFile = "$env:SystemDrive\Program Files\CMIT3.0\CmitClient.exe"
#$ShortcutFile = "$env:Public\Desktop\系统激活.lnk"
#$WScriptShell = New-Object -ComObject WScript.Shell
#$Shortcut = $WScriptShell.CreateShortcut($ShortcutFile)
#$Shortcut.TargetPath = $TargetFile
#$Shortcut.Save()



#CMGEInstaller
Start-Process -FilePath "$env:SystemDrive\Recovery\OEM\CMGE\ResetSources\EPrivilege.exe" -ArgumentList " -U:S $env:SystemDrive\Recovery\OEM\CMGE\ResetSources\CMGEInstaller\CMGEInstaller.exe 01000000" -WindowStyle Hidden -Wait

# Install CMIT Update Agent
# Create a Shortcut for CMIT Update Agent
New-Item "$env:SystemDrive\ProgramData\Microsoft\Windows\Start Menu\Programs\更新客户端" -type Directory
$TargetFile = "$env:SystemDrive\Program Files\CmitUpdateAgent\\CMOS-UA_ConfigurationTool.exe"
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

# Implement Group Policy
$GpExe="$env:SystemDrive\Recovery\OEM\CMGE\ResetSources\LGPO\LGPO.exe"
$GpCfg="/g $env:SystemDrive\Recovery\OEM\CMGE\ResetSources\LGPO"
Start-Process -WindowStyle Hidden -FilePath "$GpExe" -ArgumentList "$GpCfg" -Verb runas -Wait


# Register dlls of SMx
$SMxExe="$env:SystemDrive\Recovery\OEM\CMGE\ResetSources\CMITSMx\win32\WstSM2ECESConfig.exe"
$SMxCfg="-register"
Start-Process -WindowStyle Hidden -FilePath "$SMxExe" -ArgumentList "$SMxCfg" -Verb runas -Wait
$SMxExe="$env:SystemDrive\Recovery\OEM\CMGE\ResetSources\CMITSMx\win32\WstSM2ECDSAConfig.exe"
$SMxCfg="-register"
Start-Process -WindowStyle Hidden -FilePath "$SMxExe" -ArgumentList "$SMxCfg" -Verb runas -Wait
$SMxExe="$env:SystemDrive\Recovery\OEM\CMGE\ResetSources\CMITSMx\win32\WstKSPConfig.exe"
$SMxCfg="-register"
Start-Process -WindowStyle Hidden -FilePath "$SMxExe" -ArgumentList "$SMxCfg" -Verb runas -Wait
$SMxExe="$env:SystemDrive\Recovery\OEM\CMGE\ResetSources\CMITSMx\win32\WstSM3Config.exe"
$SMxCfg="-register"
Start-Process -WindowStyle Hidden -FilePath "$SMxExe" -ArgumentList "$SMxCfg" -Verb runas -Wait
$SMxExe="$env:SystemDrive\Recovery\OEM\CMGE\ResetSources\CMITSMx\win32\WstSM4Config.exe"
$SMxCfg="-register"
Start-Process -WindowStyle Hidden -FilePath "$SMxExe" -ArgumentList "$SMxCfg" -Verb runas -Wait
$SMxExe="$env:SystemDrive\Recovery\OEM\CMGE\ResetSources\CMITSMx\win32\WstRngConfig.exe"
$SMxCfg="-register"
Start-Process -WindowStyle Hidden -FilePath "$SMxExe" -ArgumentList "$SMxCfg" -Verb runas -Wait
$SMxExe="$env:SystemDrive\Recovery\OEM\CMGE\ResetSources\CMITSMx\win32\WstKSPConfig.exe"
$SMxCfg="-enum"
Start-Process -WindowStyle Hidden -FilePath "$SMxExe" -ArgumentList "$SMxCfg" -Verb runas -Wait


# Install Certificates
Import-Certificate -FilePath "$env:SystemDrive\Recovery\OEM\CMGE\ResetSources\Certificates\Beijing ROOT CA.cer" -CertStoreLocation Cert:\LocalMachine\Root
Import-Certificate -FilePath "$env:SystemDrive\Recovery\OEM\CMGE\ResetSources\Certificates\Beijing GCA.cer" -CertStoreLocation Cert:\LocalMachine\CA
Import-Certificate -FilePath "$env:SystemDrive\Recovery\OEM\CMGE\ResetSources\Certificates\BJCA.cer" -CertStoreLocation Cert:\LocalMachine\CA
Import-Certificate -FilePath "$env:SystemDrive\Recovery\OEM\CMGE\ResetSources\Certificates\CEGN_RCA.cer" -CertStoreLocation Cert:\LocalMachine\Root
Import-Certificate -FilePath "$env:SystemDrive\Recovery\OEM\CMGE\ResetSources\Certificates\CEGN_OCA.cer" -CertStoreLocation Cert:\LocalMachine\CA
Import-Certificate -FilePath "$env:SystemDrive\Recovery\OEM\CMGE\ResetSources\Certificates\CMIT Root Authority.cer" -CertStoreLocation Cert:\LocalMachine\Root
Import-Certificate -FilePath "$env:SystemDrive\Recovery\OEM\CMGE\ResetSources\Certificates\CMIT SubP.cer" -CertStoreLocation Cert:\LocalMachine\CA
InstallCert -CertFile "$env:SystemDrive\Recovery\OEM\CMGE\ResetSources\Certificates\CMIT signature.cer" -StoreLocation LocalMachine -StoreName TrustedPublisher
Import-Certificate -FilePath "$env:SystemDrive\Recovery\OEM\CMGE\ResetSources\Certificates\DigiCert Assured ID Root CA.cer" -CertStoreLocation Cert:\LocalMachine\Root
Import-Certificate -FilePath "$env:SystemDrive\Recovery\OEM\CMGE\ResetSources\Certificates\DigiCert Global Root CA.cer" -CertStoreLocation Cert:\LocalMachine\Root
Import-Certificate -FilePath "$env:SystemDrive\Recovery\OEM\CMGE\ResetSources\Certificates\DigiCert High Assurance EV Root CA.cer" -CertStoreLocation Cert:\LocalMachine\Root
Import-Certificate -FilePath "$env:SystemDrive\Recovery\OEM\CMGE\ResetSources\Certificates\GDCA_ROOT_CA.cer" -CertStoreLocation Cert:\LocalMachine\Root
Import-Certificate -FilePath "$env:SystemDrive\Recovery\OEM\CMGE\ResetSources\Certificates\GDCA_Guangdong_Certificate_Authority.cer" -CertStoreLocation Cert:\LocalMachine\CA
Import-Certificate -FilePath "$env:SystemDrive\Recovery\OEM\CMGE\ResetSources\Certificates\ROOTCA.cer" -CertStoreLocation Cert:\LocalMachine\Root
Import-Certificate -FilePath "$env:SystemDrive\Recovery\OEM\CMGE\ResetSources\Certificates\UCA Root.cer" -CertStoreLocation Cert:\LocalMachine\Root
Import-Certificate -FilePath "$env:SystemDrive\Recovery\OEM\CMGE\ResetSources\Certificates\BeiJing ROOT CA New.cer" -CertStoreLocation Cert:\LocalMachine\Root
Import-Certificate -FilePath "$env:SystemDrive\Recovery\OEM\CMGE\ResetSources\Certificates\Beijing GCA New.cer" -CertStoreLocation Cert:\LocalMachine\CA
Import-Certificate -FilePath "$env:SystemDrive\Recovery\OEM\CMGE\ResetSources\Certificates\BJCA New.cer" -CertStoreLocation Cert:\LocalMachine\CA
#Import-Certificate -FilePath "$env:SystemDrive\Recovery\OEM\CMGE\ResetSources\Certificates\PK.cer" -CertStoreLocation Cert:\LocalMachine\Root


# Cleanup
#del "$env:windir\Temp\LGPO" -recurse
#del "$env:windir\Temp\Certificates" -recurse
#del "$env:windir\Temp\SMxCNG" -recurse
del "$env:SystemDrive\ProgramData\Microsoft\Windows\Start Menu\Programs\Administrative Tools\Windows Defender Firewall with Advanced Security.lnk"
#del $MyInvocation.MyCommand.Definition -Force