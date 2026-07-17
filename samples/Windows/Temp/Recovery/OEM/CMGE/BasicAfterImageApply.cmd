@ECHO OFF

set CMGEScriptFolder=%~dp0
set ScriptDrive=%~d0
for /f "skip=2 tokens=2,*" %%a in ('reg.exe query "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\RecoveryEnvironment" /v "TargetOS"') do set "TargetOS=%%b"
for %%A in (%TargetOS%) do set "TargetOSDrive=%%~dpA"
set LogFile=%TargetOSDrive%Windows\Panther\CMGEReset.log

ECHO %DATE% %TIME% Starting CMGE BasicAfterImageApply >> %LogFile%

echo Copying LayoutModifications.xml >> %LogFile%
copy "%CMGEScriptFolder%ResetSources\LayoutModification.xml" "%TargetOSDrive%Users\Default\AppData\Local\Microsoft\Windows\Shell\LayoutModification.xml" /y >> %LogFile%

echo Copying logo file >> %LogFile%
copy "%CMGEScriptFolder%ResetSources\logo.bmp" "%TargetOSDrive%Windows\System32\" /y >> %LogFile%

::echo Copying Activation Tool >> %LogFile%
::robocopy "%CMGEScriptFolder%ResetSources\CMITActivation\CMITActivation" "%TargetOSDrive%Program Files\CMITActivation" /e /Log+:%LogFile%
::robocopy "%CMGEScriptFolder%ResetSources\CMITActivation\KeyHolder" "%TargetOSDrive%ProgramData\Microsoft\Windows\ClipSVC\Install\KeyHolder" /e /Log+:%LogFile%

::echo Copying CMIT Update Agent >> %LogFile%
::robocopy "%CMGEScriptFolder%ResetSources\CmitUpdateAgent" "%TargetOSDrive%Program Files\CmitUpdateAgent" /e /Log+:%LogFile%
::copy "%CMGEScriptFolder%ResetSources\CmitUpdateAgent\cua.ini" "%TargetOSDrive%Windows\INF" /y >> %LogFile%

::echo Copying CMITTembin>> %LogFile%
::robocopy "%CMGEScriptFolder%ResetSources\CMITTembin" "%TargetOSDrive%Program Files\CMITTembin" /e /Log+:%LogFile%

::echo Copying LGPO >> %LogFile%
::robocopy "%CMGEScriptFolder%ResetSources\LGPO" "%TargetOSDrive%Windows\Temp\LGPO" /e /Log+:%LogFile%

::echo Copying Certificates >> %LogFile%
::robocopy "%CMGEScriptFolder%ResetSources\Certificates" "%TargetOSDrive%Windows\Temp\Certificates" /e /Log+:%LogFile%

::echo Copying SMxCNG >> %LogFile%
::robocopy "%CMGEScriptFolder%ResetSources\SMxCNG" "%TargetOSDrive%Windows\Temp\SMxCNG" /e /Log+:%LogFile%
::robocopy "%CMGEScriptFolder%ResetSources\SMxCNG\win64" "%TargetOSDrive%Windows\System32" *.dll /e /Log+:%LogFile%
::robocopy "%CMGEScriptFolder%ResetSources\SMxCNG\win32" "%TargetOSDrive%Windows\SysWOW64" *.dll /e /Log+:%LogFile%
::copy "%CMGEScriptFolder%ResetSources\SMxCNG\SysfileGenerator\wstcrypto.dll" "%TargetOSDrive%Windows\System32" /y >> %LogFile%
::copy "%CMGEScriptFolder%ResetSources\SMxCNG\SysfileGenerator\wstcrypto32.dll" "%TargetOSDrive%Windows\SysWOW64\wstcrypto.dll" /y >> %LogFile%
::copy "%CMGEScriptFolder%ResetSources\SMxCNG\SysfileGenerator\wstsysfile.dat" "%TargetOSDrive%ProgramData" /y >> %LogFile%

:: echo Copying SchdTaskCfgSvc.exe >> %LogFile%
:: robocopy "%CMGEScriptFolder%ResetSources\SchdTaskCfgSvc" "%TargetOSDrive%ProgramData\CMIT" SchdTaskCfgSvc.exe /Log+:%LogFile%

echo Copying ResetPreConfig.exe >> %LogFile%
copy "%CMGEScriptFolder%ResetSources\ResetPreConfig.exe" "%TargetOSDrive%Windows\Temp" /y >> %LogFile%

echo Copying ResetPreConfigPS.ps1 >> %LogFile%
copy "%CMGEScriptFolder%ResetSources\ResetPreConfigPS.ps1" "%TargetOSDrive%Windows\Temp" /y >> %LogFile%

echo Copying ResetPostConfig.exe >> %LogFile%
copy "%CMGEScriptFolder%ResetSources\ResetPostConfig.exe" "%TargetOSDrive%Windows\Temp" /y >> %LogFile%

echo Copying ResetPostConfigPS.ps1 >> %LogFile%
copy "%CMGEScriptFolder%ResetSources\ResetPostConfigPS.ps1" "%TargetOSDrive%Windows\Temp" /y >> %LogFile%

echo Copying CMIT Group Policy files >> %LogFile%
copy "%CMGEScriptFolder%ResetSources\GP_CMIT\CMITCustomPolicy.adml" "%TargetOSDrive%Windows\PolicyDefinitions\zh-CN" /y >> %LogFile%
copy "%CMGEScriptFolder%ResetSources\GP_CMIT\CMITCustomPolicy.admx" "%TargetOSDrive%Windows\PolicyDefinitions" /y >> %LogFile%

echo Copying Fonts >> %LogFile%
copy "%CMGEScriptFolder%ResetSources\Fonts\SourceHanSansCN-Regular.otf" "%TargetOSDrive%Windows\Fonts" /y >> %LogFile%
robocopy "%CMGEScriptFolder%ResetSources\Fonts\CMIT" "%TargetOSDrive%Windows\System32\zh-CN\Licenses\CMIT" /e /Log+:%LogFile%

::echo Copying CmitControlCenter >> %LogFile%
::robocopy "%CMGEScriptFolder%ResetSources\CMITControlCenter" "%TargetOSDrive%Program Files\CMITControlCenter" /e /Log+:%LogFile%

echo Copying EULA >> %LogFile%
robocopy "%CMGEScriptFolder%ResetSources\EULA\zh-CN\Licenses"  "%TargetOSDrive%Windows\System32\zh-CN\Licenses"  /e /Log+:%LogFile%
robocopy "%CMGEScriptFolder%ResetSources\EULA\zh-CN\Licenses"  "%TargetOSDrive%Windows\SysWOW64\zh-CN\Licenses"  /e /Log+:%LogFile%

echo Copying CMGEInstaller >> %LogFile%
md "%TargetOSDrive%Windows\Temp\cmit"  >> %LogFile%
copy "%TargetOSDrive%Windows.old\Windows\System32\config\SOFTWARE" "%TargetOSDrive%Windows\Temp\cmit"  /y >> %LogFile%
copy "%TargetOSDrive%Windows.old\Windows\INF\cua.ini" "%TargetOSDrive%Windows\Temp\cmit"  /y >> %LogFile%

::echo Copying CMITOfflineUpdateInstaller >> %LogFile%
::robocopy "%CMGEScriptFolder%ResetSources\CMITOfflineUpdateInstaller" "%TargetOSDrive%Program Files\CMITOfflineUpdateInstaller" /e /Log+:%LogFile%


::echo Copying SIPolicy >> %LogFile%
::robocopy "%CMGEScriptFolder%ResetSources\SIPolicy" "%TargetOSDrive%SIPolicy" /e /Log+:%LogFile%

exit /b 0