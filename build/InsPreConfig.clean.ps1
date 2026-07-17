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

#Start Transcript and Logging
$logDir = Get-LogDir
Start-Transcript "$logDir\CMGE_Registry_InsPreConfig.log"

# Set Registry
Set-RegistryValue -Path "HKLM:\SYSTEM\ControlSet001\Services\Netlogon" -Name "Start" -Value "4" -PropertyType "DWord"

#Copy Recovery Folder
$CpyExe="$env:windir\System32\robocopy.exe"
$CpyCfg="$env:windir\Temp\Recovery $env:SystemDrive\Recovery /e"
Start-Process -WindowStyle Hidden -FilePath "$CpyExe" -ArgumentList "$CpyCfg" -Verb runas -Wait
Start-Sleep -Seconds 1
#Hide Recovery Folder
$HideExe="$env:windir\System32\attrib.exe"
$HideCfg=" +r +a +h +s $env:SystemDrive\Recovery /d"
Start-Process -WindowStyle Hidden -FilePath "$HideExe" -ArgumentList "$HideCfg" -Verb runas -Wait
Start-Sleep -Seconds 1

# CMIT Activation Tool setup
# Create a Shortcut for Activation Tool
#$TargetFile = "$env:SystemDrive\Program Files\CMIT3.0\CmitClient.exe"
#$ShortcutFile = "$env:Public\Desktop\系统激活.lnk"
#$WScriptShell = New-Object -ComObject WScript.Shell
#$Shortcut = $WScriptShell.CreateShortcut($ShortcutFile)
#$Shortcut.TargetPath = $TargetFile
#$Shortcut.Save()

# Install CMIT Update Agent
# Create a Shortcut for CMIT Update Agent
# UNCMIT-DISABLED New-Item "$env:SystemDrive\ProgramData\Microsoft\Windows\Start Menu\Programs\更新客户端" -type Directory
# UNCMIT-DISABLED $TargetFile = "$env:SystemDrive\Program Files\CmitUpdateAgent\CMOS-UA_ConfigurationTool.exe"
# UNCMIT-DISABLED $ShortcutFile = "$env:SystemDrive\ProgramData\Microsoft\Windows\Start Menu\Programs\更新客户端\更新客户端.lnk"
# UNCMIT-DISABLED $WorkingDir = "$env:SystemDrive\Program Files\CmitUpdateAgent"
# UNCMIT-DISABLED $WScriptShell = New-Object -ComObject WScript.Shell
# UNCMIT-DISABLED $Shortcut = $WScriptShell.CreateShortcut($ShortcutFile)
# UNCMIT-DISABLED $Shortcut.TargetPath = $TargetFile
# UNCMIT-DISABLED $Shortcut.WorkingDirectory = $WorkingDir
# UNCMIT-DISABLED $Shortcut.Save()

# Install service for CMIT Update Agent
# UNCMIT-DISABLED $CUAExe="$env:SystemDrive\Program Files\CmitUpdateAgent\CmitUpdateAgent.exe"
# UNCMIT-DISABLED $CUACfg="-install"
# UNCMIT-DISABLED Start-Process -WindowStyle Hidden -FilePath "$CUAExe" -ArgumentList "$CUACfg" -Verb runas -Wait

#Create two Shortcuts for CMITControlCenter
# UNCMIT-DISABLED New-Item "$env:SystemDrive\ProgramData\Microsoft\Windows\Start Menu\Programs\CMGE控制中心" -type Directory
# UNCMIT-DISABLED $TargetFile = "$env:SystemDrive\Program Files\CMITControlCenter\ControlCenter.exe"
# UNCMIT-DISABLED $ShortcutFile = "$env:SystemDrive\ProgramData\Microsoft\Windows\Start Menu\Programs\CMGE控制中心\控制中心.lnk"
# UNCMIT-DISABLED $WorkingDir = "$env:SystemDrive\Program Files\CMITControlCenter"
# UNCMIT-DISABLED $WScriptShell = New-Object -ComObject WScript.Shell
# UNCMIT-DISABLED $Shortcut = $WScriptShell.CreateShortcut($ShortcutFile)
# UNCMIT-DISABLED $Shortcut.TargetPath = $TargetFile
# UNCMIT-DISABLED $Shortcut.WorkingDirectory = $WorkingDir
# UNCMIT-DISABLED $Shortcut.Save()

# UNCMIT-DISABLED $TargetFile = "$env:SystemDrive\Program Files\CMITControlCenter\ControlCenter.exe"
# UNCMIT-DISABLED $ShortcutFile = "$env:Public\Desktop\控制中心.lnk"
# UNCMIT-DISABLED $WorkingDir = "$env:SystemDrive\Program Files\CMITControlCenter"
# UNCMIT-DISABLED $WScriptShell = New-Object -ComObject WScript.Shell
# UNCMIT-DISABLED $Shortcut = $WScriptShell.CreateShortcut($ShortcutFile)
# UNCMIT-DISABLED $Shortcut.TargetPath = $TargetFile
# UNCMIT-DISABLED $Shortcut.WorkingDirectory = $WorkingDir
# UNCMIT-DISABLED $Shortcut.Save()


# Implement Group Policy
$GpExe="$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\LGPO\LGPO.exe"
$GpCfg="/g $env:windir\Temp\Recovery\OEM\CMGE\ResetSources\LGPO"
Start-Process -WindowStyle Hidden -FilePath "$GpExe" -ArgumentList "$GpCfg" -Verb runas -Wait

# Register dlls of SMx
# UNCMIT-DISABLED $SMxExe="$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\CMITSMx\win32\WstSM2ECESConfig.exe"
# UNCMIT-DISABLED $SMxCfg="-register"
# UNCMIT-DISABLED Start-Process -WindowStyle Hidden -FilePath "$SMxExe" -ArgumentList "$SMxCfg" -Verb runas -Wait
# UNCMIT-DISABLED $SMxExe="$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\CMITSMx\win32\WstSM2ECDSAConfig.exe"
# UNCMIT-DISABLED $SMxCfg="-register"
# UNCMIT-DISABLED Start-Process -WindowStyle Hidden -FilePath "$SMxExe" -ArgumentList "$SMxCfg" -Verb runas -Wait
# UNCMIT-DISABLED $SMxExe="$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\CMITSMx\win32\WstKSPConfig.exe"
# UNCMIT-DISABLED $SMxCfg="-register"
# UNCMIT-DISABLED Start-Process -WindowStyle Hidden -FilePath "$SMxExe" -ArgumentList "$SMxCfg" -Verb runas -Wait
# UNCMIT-DISABLED $SMxExe="$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\CMITSMx\win32\WstSM3Config.exe"
# UNCMIT-DISABLED $SMxCfg="-register"
# UNCMIT-DISABLED Start-Process -WindowStyle Hidden -FilePath "$SMxExe" -ArgumentList "$SMxCfg" -Verb runas -Wait
# UNCMIT-DISABLED $SMxExe="$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\CMITSMx\win32\WstSM4Config.exe"
# UNCMIT-DISABLED $SMxCfg="-register"
# UNCMIT-DISABLED Start-Process -WindowStyle Hidden -FilePath "$SMxExe" -ArgumentList "$SMxCfg" -Verb runas -Wait
# UNCMIT-DISABLED $SMxExe="$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\CMITSMx\win32\WstRngConfig.exe"
# UNCMIT-DISABLED $SMxCfg="-register"
# UNCMIT-DISABLED Start-Process -WindowStyle Hidden -FilePath "$SMxExe" -ArgumentList "$SMxCfg" -Verb runas -Wait
# UNCMIT-DISABLED $SMxExe="$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\CMITSMx\win32\WstKSPConfig.exe"
# UNCMIT-DISABLED $SMxCfg="-enum"
# UNCMIT-DISABLED Start-Process -WindowStyle Hidden -FilePath "$SMxExe" -ArgumentList "$SMxCfg" -Verb runas -Wait

# Install Certificates
# UNCMIT-DISABLED Import-Certificate -FilePath "$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\Certificates\Beijing ROOT CA.cer" -CertStoreLocation Cert:\LocalMachine\Root
# UNCMIT-DISABLED Import-Certificate -FilePath "$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\Certificates\Beijing GCA.cer" -CertStoreLocation Cert:\LocalMachine\CA
# UNCMIT-DISABLED Import-Certificate -FilePath "$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\Certificates\BJCA.cer" -CertStoreLocation Cert:\LocalMachine\CA
# UNCMIT-DISABLED Import-Certificate -FilePath "$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\Certificates\CEGN_RCA.cer" -CertStoreLocation Cert:\LocalMachine\Root
# UNCMIT-DISABLED Import-Certificate -FilePath "$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\Certificates\CEGN_OCA.cer" -CertStoreLocation Cert:\LocalMachine\CA
# UNCMIT-DISABLED Import-Certificate -FilePath "$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\Certificates\CMIT Root Authority.cer" -CertStoreLocation Cert:\LocalMachine\Root
# UNCMIT-DISABLED Import-Certificate -FilePath "$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\Certificates\CMIT SubP.cer" -CertStoreLocation Cert:\LocalMachine\CA
# UNCMIT-DISABLED InstallCert -CertFile "$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\Certificates\CMIT signature.cer" -StoreLocation LocalMachine -StoreName TrustedPublisher
Import-Certificate -FilePath "$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\Certificates\DigiCert Assured ID Root CA.cer" -CertStoreLocation Cert:\LocalMachine\Root
Import-Certificate -FilePath "$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\Certificates\DigiCert Global Root CA.cer" -CertStoreLocation Cert:\LocalMachine\Root
Import-Certificate -FilePath "$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\Certificates\DigiCert High Assurance EV Root CA.cer" -CertStoreLocation Cert:\LocalMachine\Root
# UNCMIT-DISABLED Import-Certificate -FilePath "$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\Certificates\GDCA_ROOT_CA.cer" -CertStoreLocation Cert:\LocalMachine\Root
# UNCMIT-DISABLED Import-Certificate -FilePath "$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\Certificates\GDCA_Guangdong_Certificate_Authority.cer" -CertStoreLocation Cert:\LocalMachine\CA
# UNCMIT-DISABLED Import-Certificate -FilePath "$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\Certificates\ROOTCA.cer" -CertStoreLocation Cert:\LocalMachine\Root
# UNCMIT-DISABLED Import-Certificate -FilePath "$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\Certificates\UCA Root.cer" -CertStoreLocation Cert:\LocalMachine\Root
# UNCMIT-DISABLED Import-Certificate -FilePath "$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\Certificates\BeiJing ROOT CA New.cer" -CertStoreLocation Cert:\LocalMachine\Root
# UNCMIT-DISABLED Import-Certificate -FilePath "$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\Certificates\Beijing GCA New.cer" -CertStoreLocation Cert:\LocalMachine\CA
# UNCMIT-DISABLED Import-Certificate -FilePath "$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\Certificates\BJCA New.cer" -CertStoreLocation Cert:\LocalMachine\CA
#Import-Certificate -FilePath "$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\Certificates\PK.cer" -CertStoreLocation Cert:\LocalMachine\Root


# Cleanup
#del "$env:windir\Temp\LGPO" -recurse
#del "$env:windir\Temp\Certificates" -recurse
del "$env:windir\Setup\Scripts" -recurse
del "$env:windir\Temp\Recovery" -recurse -Force
del "$env:windir\Temp\UpgradeConfig.exe"
del "$env:windir\Temp\UpgradeSchdTask.exe"
#del $MyInvocation.MyCommand.Definition -Force
