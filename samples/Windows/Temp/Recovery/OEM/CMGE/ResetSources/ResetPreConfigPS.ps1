# Execute PreConfig.exe
$GpExe="$env:windir\Temp\ResetPreConfig.exe"
Start-Process -WindowStyle Hidden -FilePath "$GpExe" -Verb runas -Wait

# Cleanup
del "$env:windir\Temp\ResetPreConfig.exe"
del $MyInvocation.MyCommand.Definition -Force