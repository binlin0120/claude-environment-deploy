#requires -Version 5.1
[CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='Medium')]
param(
    [ValidatePattern('^[\p{L}\p{N}_-]{1,64}$')][string]$VmName = 'Claude-Workspace',
    [string]$VmRoot = 'D:\Codex\虚拟机\Claude公开方案',
    [Parameter(Mandatory=$true)][string]$IsoPath,
    [Parameter(Mandatory=$true)][string]$SwitchName,
    [ValidateRange(4,64)][int]$MemoryGB = 8,
    [ValidateRange(64,1024)][int]$DiskGB = 80,
    [ValidateRange(2,32)][int]$ProcessorCount = 4,
    [switch]$Apply
)
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($VmRoot).TrimEnd('\')
$iso = [IO.Path]::GetFullPath($IsoPath)
foreach ($path in @($root,$iso)) {
    if (-not $path.StartsWith('D:\Codex\', [StringComparison]::OrdinalIgnoreCase)) { throw 'VmRoot and IsoPath must be inside D:\Codex.' }
    for ($item=$path; $item; $item=Split-Path -Parent $item) {
        if ((Test-Path -LiteralPath $item) -and ((Get-Item -LiteralPath $item).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'A path contains a junction or symbolic link. Use real D: paths.' }
    }
}
$vmPath = Join-Path $root $VmName
$vhdPath = Join-Path $vmPath ($VmName + '.vhdx')
$plan = [ordered]@{
    mode = 'PlanOnly'; vm_name=$VmName; vm_path=$vmPath; vhd_path=$vhdPath
    iso_path=$iso; iso_exists=[bool](Test-Path -LiteralPath $iso -PathType Leaf)
    switch_name=$SwitchName; generation=2; memory_gb=$MemoryGB; disk_max_gb=$DiskGB
    processors=$ProcessorCount; secure_boot=$true; virtual_tpm=$true
    starts_vm=$false; installs_windows=$false; installs_claude=$false
    note='Creates only a stopped VM when -Apply is supplied. Windows installation, licensing, login, network setup and Claude acceptance are later stages.'
}
if (-not $Apply) { $plan | ConvertTo-Json -Depth 4; return }
if (-not $PSCmdlet.ShouldProcess($vmPath, 'Create a stopped generation-2 VM with a new virtual disk')) {
    $plan.mode='WhatIf'; $plan | ConvertTo-Json -Depth 4; return
}
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Administrator permissions are required for VM creation.' }
foreach ($command in @('Get-VM','Get-VMSwitch','New-VM','Set-VMProcessor','Set-VMKeyProtector','Enable-VMTPM','Add-VMDvdDrive','Set-VMFirmware')) {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) { throw ('Missing Hyper-V command: ' + $command) }
}
if (Get-VM -Name $VmName -ErrorAction SilentlyContinue) { throw 'A VM with this name already exists. No existing VM was changed; inspect it before choosing reuse or a different name.' }
if (Test-Path -LiteralPath $vmPath) { throw 'The target VM folder already exists. No files were overwritten.' }
if (-not (Test-Path -LiteralPath $iso -PathType Leaf)) { throw 'ISO file not found. Obtain an authorized Windows ISO and verify it first.' }
if ([IO.Path]::GetExtension($iso) -ne '.iso') { throw 'IsoPath must refer to an ISO file.' }
if ((Get-Item -LiteralPath $iso).Length -lt 1GB) { throw 'ISO is too small to be the expected Windows installation media. Verify its origin and hash.' }
if (-not (Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue)) { throw 'The selected virtual switch does not exist. No switch was created or changed.' }
$os=Get-CimInstance Win32_OperatingSystem
$computer=Get-CimInstance Win32_ComputerSystem
$disk=Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='D:'"
if ($ProcessorCount -gt $computer.NumberOfLogicalProcessors) { throw 'Requested processor count exceeds available logical processors.' }
if (($os.FreePhysicalMemory / 1MB) -lt ($MemoryGB + 2)) { throw 'Insufficient free memory for requested startup RAM plus 2 GB host headroom.' }
if (-not $disk -or ($disk.FreeSpace / 1GB) -lt ($DiskGB + 10)) { throw 'Insufficient D: free space for maximum virtual disk plus 10 GB headroom.' }
$step='CreateDirectory'
try {
    New-Item -ItemType Directory -Path $vmPath -ErrorAction Stop | Out-Null
    $step='New-VM'
    New-VM -Name $VmName -Generation 2 -MemoryStartupBytes ($MemoryGB * 1GB) -Path $vmPath -NewVHDPath $vhdPath -NewVHDSizeBytes ($DiskGB * 1GB) -SwitchName $SwitchName | Out-Null
    $step='Set-VMProcessor'
    Set-VMProcessor -VMName $VmName -Count $ProcessorCount
    $step='Set-VMKeyProtector'
    Set-VMKeyProtector -VMName $VmName -NewLocalKeyProtector
    $step='Enable-VMTPM'
    Enable-VMTPM -VMName $VmName
    $step='Add-VMDvdDrive'
    $dvd = Add-VMDvdDrive -VMName $VmName -Path $iso -Passthru
    $step='Set-VMFirmware'
    Set-VMFirmware -VMName $VmName -EnableSecureBoot On -SecureBootTemplate MicrosoftWindows -FirstBootDevice $dvd
    $plan.mode='CreatedStopped'; $plan | ConvertTo-Json -Depth 4
} catch {
    throw ('Creation did not complete at step ' + $step + '. Partial files or a stopped VM may remain at ' + $vmPath + '. Nothing was automatically deleted. Error type: ' + $_.Exception.GetType().Name)
}
