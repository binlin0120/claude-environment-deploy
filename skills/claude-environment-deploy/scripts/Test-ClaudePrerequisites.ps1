#requires -Version 5.1
[CmdletBinding()]
param([string]$OutputPath)
$ErrorActionPreference = 'Stop'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$os = Get-CimInstance Win32_OperatingSystem
$computer = Get-CimInstance Win32_ComputerSystem
$cpus = @(Get-CimInstance Win32_Processor)
$drive = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='D:'"
$feature = 'Unknown'
$switches = @()
$notes = New-Object 'System.Collections.Generic.List[string]'
if ($isAdmin -and (Get-Command Get-WindowsOptionalFeature -ErrorAction SilentlyContinue)) {
    try { $feature = [string](Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All).State }
    catch { $notes.Add('Hyper-V feature state could not be read; do not treat this as Enabled.') }
}
if ($isAdmin -and (Get-Command Get-VMSwitch -ErrorAction SilentlyContinue)) {
    try { $switches = @(Get-VMSwitch | Select-Object Name, SwitchType) }
    catch { $notes.Add('Virtual switch listing failed; verify Hyper-V service and permissions.') }
}
$commands = [ordered]@{}
foreach ($command in @('claude','git','ssh','scp','pwsh','New-VM')) {
    $commands[$command] = [bool](Get-Command $command -ErrorAction SilentlyContinue)
}
$notes.Add('This is a host prerequisite report, not a Claude login or deployment acceptance report.')
$notes.Add('Home editions do not officially include Hyper-V. Native Claude use is a separate route.')
$notes.Add('Task files stay under D:\Codex. Windows feature changes may write system files to C: and require prior permission.')
if (-not $drive) { $notes.Add('D: is missing. This package requires D:\Codex; stop deployment. Do not repartition or redirect files to C:.') }
if (-not $isAdmin) { $notes.Add('Not elevated. Some Hyper-V checks are unknown; no attempt was made to elevate.') }
$report = [ordered]@{
    checked_at_utc = [DateTime]::UtcNow.ToString('o')
    is_administrator = $isAdmin
    os = [ordered]@{ name=$os.Caption; version=$os.Version; architecture=$os.OSArchitecture }
    hardware = [ordered]@{
        total_memory_gb = [math]::Round($computer.TotalPhysicalMemory / 1GB, 1)
        free_memory_gb = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
        logical_processors = $computer.NumberOfLogicalProcessors
        hypervisor_present = $computer.HypervisorPresent
        cpu_virtualization = @($cpus | Select-Object VirtualizationFirmwareEnabled, SecondLevelAddressTranslationExtensions, VMMonitorModeExtensions)
    }
    data_drive = [ordered]@{ present=[bool]$drive; free_gb=$(if($drive){[math]::Round($drive.FreeSpace / 1GB,1)}else{$null}) }
    hyper_v = [ordered]@{ feature_state=$feature; switches=$switches }
    command_available = $commands
    notes = @($notes.ToArray())
}
$json = $report | ConvertTo-Json -Depth 7
if ($OutputPath) {
    $full = [IO.Path]::GetFullPath($OutputPath)
    if (-not $full.StartsWith('D:\Codex\', [StringComparison]::OrdinalIgnoreCase)) { throw 'OutputPath must be inside D:\Codex.' }
    $parent = Split-Path -Parent $full
    for ($item = $parent; $item; $item = Split-Path -Parent $item) {
        if ((Test-Path -LiteralPath $item) -and ((Get-Item -LiteralPath $item).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Output path contains a junction or symbolic link; choose a real D: directory.' }
    }
    if (Test-Path -LiteralPath $full) { throw 'Output file already exists; choose a new report name.' }
    [IO.Directory]::CreateDirectory($parent) | Out-Null
    [IO.File]::WriteAllText($full, $json, (New-Object Text.UTF8Encoding($false)))
}
$json
