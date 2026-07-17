# Execute UserConfig.exe
$GpExe="$env:windir\Temp\ResetPostConfig.exe"
Start-Process -WindowStyle Hidden -FilePath "$GpExe" -Verb runas -Wait

# Cleanup
del "$env:windir\Temp\ResetPostConfig.exe"
Start-Sleep -Seconds 1
del $MyInvocation.MyCommand.Definition -Force