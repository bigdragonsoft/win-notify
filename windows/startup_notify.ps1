# Windows Startup Notify Script
# Usage: .\startup_notify.ps1 -EventType <startup|login|shutdown|test|login_failed>

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("startup", "login", "shutdown", "test", "login_failed")]
    [string]$EventType
)

# Load config
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$scriptPath\config.ps1"

# === State file for deduplication ===
$stateDir = "$env:ProgramData\StartupNotify"
$stateFile = "$stateDir\last_event.json"

# Ensure state dir exists
if (-not (Test-Path $stateDir)) {
    New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
}

# === Deduplication: prevent sending same event type within 30 seconds ===
$now = Get-Date
$dedupeWindow = 30 # seconds

if (Test-Path $stateFile) {
    try {
        $lastEvent = Get-Content $stateFile | ConvertFrom-Json
        if ($lastEvent.type -eq $EventType) {
            $lastTime = [DateTime]::Parse($lastEvent.time)
            $elapsed = ($now - $lastTime).TotalSeconds
            if ($elapsed -lt $dedupeWindow) {
                # Duplicate event, skip
                exit 0
            }
        }
    } catch { }
}

# Save current event
@{type=$EventType; time=$now.ToString("o")} | ConvertTo-Json | Out-File $stateFile -Force

# === Smart Connectivity Check ===
# Wait for network (max 30 seconds for startup, 5 seconds for others)
$maxRetries = if ($EventType -eq "startup") { 6 } else { 1 }
$retryCount = 0
# Extract hostname from NOTIFY_URL for connection test
$vpsHost = ([System.Uri]$NOTIFY_URL).Host

while ($retryCount -lt $maxRetries) {
    # Try to resolve or ping VPS
    try {
        $result = Test-Connection -ComputerName $vpsHost -Count 1 -Quiet
        if ($result) { break }
    } catch { }
    
    Start-Sleep -Seconds 5
    $retryCount++
}
# ================================

# Get computer name
$computerName = $env:COMPUTERNAME

# Get current time
$currentTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

# Get IP address (exclude VMware virtual adapters and APIPA)
function Get-LocalIP {
    try {
        # Get all network adapters, exclude VMware and disconnected
        $adapters = Get-NetAdapter | Where-Object { 
            $_.Status -eq "Up" -and 
            $_.Name -notlike "*VMware*" -and 
            $_.Name -notlike "*Virtual*" -and
            $_.Name -notlike "*VPN*"
        }
        
        foreach ($adapter in $adapters) {
            $ip = (Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | 
                   Where-Object { $_.IPAddress -notlike "169.254.*" -and $_.IPAddress -ne "127.0.0.1" } | 
                   Select-Object -First 1).IPAddress
            if ($ip) { return $ip }
        }
    } catch { }
    
    # Fallback: any non-virtual IP
    try {
        $ip = (Get-NetIPAddress -AddressFamily IPv4 | 
               Where-Object { 
                   $_.IPAddress -ne "127.0.0.1" -and 
                   $_.IPAddress -notlike "169.254.*" -and
                   $_.IPAddress -notlike "192.168.213.*" -and
                   $_.IPAddress -notlike "192.168.22.*"
               } | Select-Object -First 1).IPAddress
        if ($ip) { return $ip }
    } catch { }
    
    return "Unknown"
}

$ipAddress = Get-LocalIP

# URL encode function
function UrlEncode($str) {
    return [System.Uri]::EscapeDataString($str)
}

# Get last shutdown time for startup event
$lastShutdown = ""
if ($EventType -eq "startup") {
    try {
        # Event ID 1074: User initiated shutdown/restart
        $shutdownEvent = Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='User32'; Id=1074} -MaxEvents 1 -ErrorAction SilentlyContinue
        if ($shutdownEvent) {
            $lastShutdown = $shutdownEvent.TimeCreated.ToString("yyyy-MM-dd HH:mm:ss")
        }
    } catch { }
}

# Build request URL
$requestUrl = "{0}?event={1}&computer={2}&ip={3}&time={4}&key={5}&desc={6}" -f $NOTIFY_URL, (UrlEncode $EventType), (UrlEncode $computerName), (UrlEncode $ipAddress), (UrlEncode $currentTime), (UrlEncode $SECRET_KEY), (UrlEncode $MACHINE_DESCRIPTION)

# Add last shutdown time if available
if ($lastShutdown) {
    $requestUrl += "&last_shutdown=" + (UrlEncode $lastShutdown)
}

# Send request (with retry for startup)
$maxSendRetries = if ($EventType -eq "startup") { 3 } else { 1 }
for ($i = 0; $i -lt $maxSendRetries; $i++) {
    try {
        $response = Invoke-WebRequest -Uri $requestUrl -Method GET -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
        if ($response.StatusCode -eq 200) { break }
    } catch {
        if ($i -lt $maxSendRetries - 1) {
            Start-Sleep -Seconds 2
        }
    }
}
