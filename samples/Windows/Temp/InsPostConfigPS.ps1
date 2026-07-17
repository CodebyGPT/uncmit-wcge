# Execute InsPostConfig.exe
$GpExe="$env:windir\Temp\InsPostConfig.exe"
Start-Process -WindowStyle Hidden -FilePath "$GpExe" -Verb runas -Wait

# Cleanup
del "$env:windir\Temp\InsPostConfig.exe"
del $MyInvocation.MyCommand.Definition -Force