# Removes VOIMA Map Maker: stops the bridge, deletes its shortcuts, the Studio plugin and the program folder.
# Your VOIMA worlds (including ones the Map Maker made) are left alone.
$target  = Join-Path $env:LOCALAPPDATA 'VOIMA Map Maker'
Get-CimInstance Win32_Process -Filter "Name='pythonw.exe' OR Name='python.exe'" |
    Where-Object { $_.CommandLine -like '*bridge.py*' -and ($_.CommandLine -like '*VOIMA Map Maker*' -or $_.CommandLine -like '*voima-map-maker*') } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Remove-Item (Join-Path ([Environment]::GetFolderPath('Startup')) 'VOIMA Bridge.lnk') -ErrorAction SilentlyContinue
Remove-Item (Join-Path ([Environment]::GetFolderPath('Programs')) 'VOIMA Map Maker') -Recurse -ErrorAction SilentlyContinue
Remove-Item (Join-Path $env:LOCALAPPDATA 'Roblox\Plugins\VOIMA Map Maker.lua') -ErrorAction SilentlyContinue
Set-Location $env:TEMP
Remove-Item $target -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ''
Write-Host '  VOIMA Map Maker removed. Your VOIMA worlds were not touched. Restart Roblox Studio to unload the plugin.' -ForegroundColor Green
Write-Host ''
Read-Host '  Press Enter to close'
