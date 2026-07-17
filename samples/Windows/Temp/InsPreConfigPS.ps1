# Execute PreConfig.exe
$GpExe="$env:windir\Temp\InsPreConfig.exe"
Start-Process -WindowStyle Hidden -FilePath "$GpExe" -Verb runas -Wait

# Cleanup
del "$env:windir\Temp\InsPreConfig.exe"
del $MyInvocation.MyCommand.Definition -Force