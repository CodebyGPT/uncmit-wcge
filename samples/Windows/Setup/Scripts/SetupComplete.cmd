if exist "%SystemDrive%\Windows.old" (
	if exist "%windir%\Temp\UpgradeConfig.exe" (
		start /wait "" "%windir%\Temp\UpgradeConfig.exe"
		del /q "%windir%\Temp\UpgradeConfig.exe"
	)
)

if exist "%SystemDrive%\Windows\SoftwareDistribution\CUACache" (
	rmdir /S /Q "%SystemDrive%\Windows\SoftwareDistribution\CUACache" 
)