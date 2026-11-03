# VOIMA Map Maker installer (Windows). Run it with install.bat (double-click).
# It copies the bridge to %LOCALAPPDATA%\VOIMA Map Maker, installs the Roblox Studio plugin,
# makes the bridge start with Windows (hidden), and starts it now. Nothing needs admin rights.
$ErrorActionPreference = 'Stop'
$repo    = Split-Path -Parent $PSScriptRoot
$target  = Join-Path $env:LOCALAPPDATA 'VOIMA Map Maker'
$plugins = Join-Path $env:LOCALAPPDATA 'Roblox\Plugins'
$startup = [Environment]::GetFolderPath('Startup')
$menu    = Join-Path ([Environment]::GetFolderPath('Programs')) 'VOIMA Map Maker'

function Say($text, $color = 'Gray') { Write-Host $text -ForegroundColor $color }
Say ''
Say '  VOIMA Map Maker - setup' 'Green'
Say '  Build maps in Roblox Studio, play them in VOIMA.' 'DarkGray'
Say ''

# 1. Python 3.10 or newer (the bridge uses only the standard library: no pip packages)
function Try-Python([string]$exe, [string[]]$pre) {
    try {
        $out = & $exe @pre -c "import sys; print(sys.executable if sys.version_info >= (3, 10) else '')" 2>$null
        if ($LASTEXITCODE -eq 0 -and $out -and (Test-Path "$out".Trim())) { return "$out".Trim() }
    } catch { }
    return $null
}
function Find-Python {
    $p = Try-Python 'py' @('-3'); if ($p) { return $p }
    $p = Try-Python 'python' @(); if ($p) { return $p }
    return (Try-Python 'python3' @())
}
$python = Find-Python
if (-not $python) {
    Say '  Python 3.10+ is needed and was not found.' 'Yellow'
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        $ans = Read-Host '  Install Python 3.12 now with winget? (Y/N)'
        if ($ans -match '^[Yy]') {
            winget install -e --id Python.Python.3.12 --scope user --accept-source-agreements
            $env:Path = [Environment]::GetEnvironmentVariable('Path', 'User') + ';' + [Environment]::GetEnvironmentVariable('Path', 'Machine')
            $python = Find-Python
        }
    }
    if (-not $python) {
        Say '  Please install Python from https://www.python.org/downloads/ (tick "Add python.exe to PATH"), then run install.bat again.' 'Red'
        Start-Process 'https://www.python.org/downloads/'
        Read-Host '  Press Enter to close'; exit 1
    }
}
$pythonw = Join-Path (Split-Path $python) 'pythonw.exe'
if (-not (Test-Path $pythonw)) { $pythonw = $python }
Say "  Python: $python" 'DarkGray'

# 2. VOIMA
$universes = Join-Path $env:APPDATA '.VOIMA\Universes'
if (-not (Test-Path $universes)) {
    Say '  VOIMA data was not found (%APPDATA%\.VOIMA). Start VOIMA once, then the bridge will find it.' 'Yellow'
} else {
    $found = Get-ChildItem $universes -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'Content') } | ForEach-Object Name
    Say "  VOIMA universes: $($found -join ', ')" 'DarkGray'
}

# 3. Stop an older bridge, copy the files
Get-CimInstance Win32_Process -Filter "Name='pythonw.exe' OR Name='python.exe'" |
    Where-Object { $_.CommandLine -like '*VOIMA Map Maker*bridge.py*' -or $_.CommandLine -like '*voima-map-maker*bridge.py*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Force $target | Out-Null
Copy-Item (Join-Path $repo 'bridge\*.py') $target -Force
Copy-Item (Join-Path $repo 'plugin\VOIMA Map Maker.lua') $target -Force
Copy-Item (Join-Path $repo 'docs\guide.md') (Join-Path $target 'Guide.md') -Force -ErrorAction SilentlyContinue
Say "  Installed to $target" 'DarkGray'

# 4. The Roblox Studio plugin (the bridge also keeps it up to date every time it starts)
New-Item -ItemType Directory -Force $plugins | Out-Null
Copy-Item (Join-Path $repo 'plugin\VOIMA Map Maker.lua') $plugins -Force
Say '  Roblox Studio plugin installed' 'DarkGray'

# 5. Shortcuts: start with Windows (hidden), plus Start menu entries
$shell = New-Object -ComObject WScript.Shell
function Shortcut($path, $exe, $arguments, $desc) {
    $s = $shell.CreateShortcut($path)
    $s.TargetPath = $exe; $s.Arguments = $arguments; $s.WorkingDirectory = $target; $s.Description = $desc
    $s.Save()
}
$bridgeArgs = '"' + (Join-Path $target 'bridge.py') + '"'
Shortcut (Join-Path $startup 'VOIMA Bridge.lnk') $pythonw $bridgeArgs 'VOIMA Bridge for the Roblox Studio Map Maker'
New-Item -ItemType Directory -Force $menu | Out-Null
Shortcut (Join-Path $menu 'Start VOIMA Bridge.lnk') $pythonw $bridgeArgs 'Start the VOIMA Bridge (runs hidden)'
Shortcut (Join-Path $menu 'VOIMA Bridge (with window).lnk') $python $bridgeArgs 'Run the VOIMA Bridge in a window to see what it does'
Shortcut (Join-Path $menu 'Uninstall VOIMA Map Maker.lnk') 'powershell.exe' ('-ExecutionPolicy Bypass -File "' + (Join-Path $target 'uninstall.ps1') + '"') 'Remove VOIMA Map Maker'
Copy-Item (Join-Path $PSScriptRoot 'uninstall.ps1') $target -Force
Say '  Starts with Windows; Start menu > VOIMA Map Maker' 'DarkGray'

# 6. Start it now and check it answers
Start-Process $pythonw -ArgumentList $bridgeArgs -WorkingDirectory $target
$ok = $false
for ($i = 0; $i -lt 60; $i++) {
    try { $ping = Invoke-RestMethod 'http://127.0.0.1:7878/ping' -TimeoutSec 2; $ok = $true; break } catch { Start-Sleep -Seconds 2 }
}
Say ''
if ($ok) {
    Say "  Done. The bridge is running (version $($ping.version), universe: $($ping.universe))." 'Green'
} else {
    Say '  Installed, but the bridge did not answer yet. Check %TEMP%\voima_work\bridge.log' 'Yellow'
}
Say ''
Say '  Next:' 'White'
Say '   1. Open (or restart) Roblox Studio.'
Say '   2. Plugins tab > Map Maker. Allow it to talk to 127.0.0.1 when Studio asks.'
Say '   3. Build, then press "Convert to VOIMA world". Restart VOIMA and open the world.'
Say ''
Read-Host '  Press Enter to close'
