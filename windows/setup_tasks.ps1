# WinNotify - Task Scheduler Setup
# Run as Administrator

# Check admin privileges
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Error: Please run as Administrator!" -ForegroundColor Red
    pause
    exit 1
}

# Script path (Source)
$sourcePath = Split-Path -Parent $MyInvocation.MyCommand.Path
$installDir = "C:\ProgramData\StartupNotify"

# Create install directory
if (-not (Test-Path $installDir)) {
    New-Item -ItemType Directory -Force -Path $installDir | Out-Null
    Write-Host "Created install dir: $installDir" -ForegroundColor Cyan
}

# Copy files
try {
    Copy-Item -Path "$sourcePath\startup_notify.ps1" -Destination "$installDir\startup_notify.ps1" -Force
    Copy-Item -Path "$sourcePath\config.ps1" -Destination "$installDir\config.ps1" -Force
    Write-Host "Copied scripts to $installDir" -ForegroundColor Green
} catch {
    Write-Host "Error copying files: $_" -ForegroundColor Red
    pause
    exit 1
}

# Use the installed script for tasks
$notifyScript = "$installDir\startup_notify.ps1"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  WinNotify - Setup" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$powershellPath = "powershell.exe"
$taskSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

# Pre-create CIM trigger class for event-based tasks
$CIMTriggerClass = Get-CimClass -ClassName MSFT_TaskEventTrigger -Namespace Root/Microsoft/Windows/TaskScheduler

# ============ Task 1: System Startup ============
$taskName1 = "StartupNotify_Boot"
Write-Host "[1/3] Creating system startup task..." -ForegroundColor Yellow

Unregister-ScheduledTask -TaskName $taskName1 -Confirm:$false -ErrorAction SilentlyContinue

$trigger1 = New-ScheduledTaskTrigger -AtStartup
$trigger1.Delay = "PT10S"

$action1 = New-ScheduledTaskAction -Execute $powershellPath -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$notifyScript`" -EventType startup"

$principal1 = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

Register-ScheduledTask -TaskName $taskName1 -Trigger $trigger1 -Action $action1 -Principal $principal1 -Settings $taskSettings -Description "Send notification on system startup" | Out-Null
Write-Host "  [OK] System startup task created" -ForegroundColor Green

# ============ Task 2: User Login (Event-based) ============
$taskName2 = "StartupNotify_Login"
Write-Host "[2/3] Creating user login task (event-based)..." -ForegroundColor Yellow

Unregister-ScheduledTask -TaskName $taskName2 -Confirm:$false -ErrorAction SilentlyContinue

$action2 = New-ScheduledTaskAction -Execute $powershellPath -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$notifyScript`" -EventType login"

# Use SYSTEM account to read Security log
$principal2 = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

# Event ID 4624: Successful logon
# LogonType: 2=Interactive, 7=Unlock, 10=RemoteInteractive, 11=CachedInteractive (Microsoft Account)
$subscriptionXml2 = @"
<QueryList>
  <Query Id="0" Path="Security">
    <Select Path="Security">
      *[System[EventID=4624] and EventData[(Data[@Name='LogonType']='2' or Data[@Name='LogonType']='7' or Data[@Name='LogonType']='10' or Data[@Name='LogonType']='11')]]
    </Select>
  </Query>
</QueryList>
"@

$trigger2 = New-CimInstance -CimClass $CIMTriggerClass -ClientOnly
$trigger2.Subscription = $subscriptionXml2
$trigger2.Enabled = $true

Register-ScheduledTask -TaskName $taskName2 -Action $action2 -Principal $principal2 -Settings $taskSettings -Description "Send notification on successful user login" | Out-Null

$task2 = Get-ScheduledTask -TaskName $taskName2
$task2.Triggers = @($trigger2)
Set-ScheduledTask -InputObject $task2 | Out-Null

Write-Host "  [OK] User login task created (Event ID 4624)" -ForegroundColor Green

# ============ Task 3: Login Failed ============
$taskName3 = "StartupNotify_LoginFailed"
Write-Host "[3/3] Creating login failed task..." -ForegroundColor Yellow

Unregister-ScheduledTask -TaskName $taskName3 -Confirm:$false -ErrorAction SilentlyContinue
# Also remove old task name if exists
Unregister-ScheduledTask -TaskName "StartupNotify_Shutdown" -Confirm:$false -ErrorAction SilentlyContinue

$action3 = New-ScheduledTaskAction -Execute $powershellPath -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$notifyScript`" -EventType login_failed"

# Event 4625: An account failed to log on (interactive logon types only)
# Exclude system accounts and security software triggered events
$subscriptionXml3 = @"
<QueryList>
  <Query Id="0" Path="Security">
    <Select Path="Security">
      *[System[EventID=4625] and EventData[(Data[@Name='LogonType']='2' or Data[@Name='LogonType']='7' or Data[@Name='LogonType']='10' or Data[@Name='LogonType']='11')]]
    </Select>
    <Suppress Path="Security">
      *[EventData[Data[@Name='TargetUserName']='WDAGUtilityAccount' or Data[@Name='TargetUserName']='Guest' or Data[@Name='TargetUserName']='DefaultAccount' or Data[@Name='TargetUserName']='SYSTEM' or Data[@Name='TargetUserName']='Administrator']]
    </Suppress>
  </Query>
</QueryList>
"@

$trigger3 = New-CimInstance -CimClass $CIMTriggerClass -ClientOnly
$trigger3.Subscription = $subscriptionXml3
$trigger3.Enabled = $true

Register-ScheduledTask -TaskName $taskName3 -Action $action3 -Principal $principal1 -Settings $taskSettings -Description "Send notification on login failed" | Out-Null

$task3 = Get-ScheduledTask -TaskName $taskName3
$task3.Triggers = @($trigger3)
Set-ScheduledTask -InputObject $task3 | Out-Null

Write-Host "  [OK] Login failed task created" -ForegroundColor Green

# ============ Done ============
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  All tasks created successfully!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Created tasks:" -ForegroundColor White
Write-Host "  * $taskName1 - Triggers on system startup (with last shutdown time)"
Write-Host "  * $taskName2 - Triggers on user login (Event ID 4624)"
Write-Host "  * $taskName3 - Triggers on login failed"
Write-Host ""
Write-Host "Note: Shutdown time is included in the startup notification." -ForegroundColor Gray
Write-Host ""
Write-Host "Tip: View tasks in Task Scheduler" -ForegroundColor Gray
Write-Host ""

$test = Read-Host "Send test notification now? (Y/N)"
if ($test -eq "Y" -or $test -eq "y") {
    Write-Host "Sending test notification..." -ForegroundColor Yellow
    & $notifyScript -EventType test
    Write-Host "Test notification sent. Check your Telegram." -ForegroundColor Green
}

Write-Host ""
pause
