# Run in a standalone PowerShell process. Hyper-V, inventory and HTTPS calls are mocked; no VM is created and no endpoint is contacted.
param([string]$SourceRoot=(Join-Path (Split-Path -Parent $PSScriptRoot) 'skills\claude-environment-deploy\scripts'))
$ErrorActionPreference='Stop'
Import-Module Microsoft.PowerShell.Utility,Microsoft.PowerShell.Management
$PSModuleAutoLoadingPreference='None'
$global:ReviewMock_mode='normal';$global:ReviewMock_events=New-Object 'System.Collections.Generic.List[string]';$global:ReviewMock_results=New-Object 'System.Collections.Generic.List[object]'
$global:ReviewMock_mockRoot=Join-Path $PSScriptRoot 'mock-vm';$global:ReviewMock_iso=Join-Path $PSScriptRoot 'fixture.iso';$global:ReviewMock_mockVm=Join-Path $global:ReviewMock_mockRoot 'ReviewTestVM'
function Get-Command { param([string]$Name,$ErrorAction); if($global:ReviewMock_mode -eq 'missing-command' -and $Name -eq 'New-VM'){return};[pscustomobject]@{Name=$Name} }
function Test-Path { param([string]$LiteralPath,$PathType);if($LiteralPath -eq $global:ReviewMock_iso){return ($global:ReviewMock_mode -ne 'missing-iso')};if($LiteralPath -eq $global:ReviewMock_mockVm){return ($global:ReviewMock_mode -eq 'existing-folder')};if($LiteralPath -eq $global:ReviewMock_mockRoot){return ($global:ReviewMock_mode -eq 'junction')};return $false }
function Get-Item { param([string]$LiteralPath);[pscustomobject]@{Length=2GB;Attributes=$(if($global:ReviewMock_mode -eq 'junction'){[IO.FileAttributes]::ReparsePoint}else{[IO.FileAttributes]::Normal})} }
function Get-VM { param($Name,$ErrorAction);if($global:ReviewMock_mode -eq 'existing-vm'){[pscustomobject]@{Name=$Name}} }
function Get-VMSwitch { param($Name,$ErrorAction);if($global:ReviewMock_mode -ne 'missing-switch'){[pscustomobject]@{Name='mock-switch';SwitchType='Internal'}} }
function Get-WindowsOptionalFeature {param($Online,$FeatureName);[pscustomobject]@{State='Enabled'}}
function Get-CimInstance { param($ClassName,$Filter);switch($ClassName){'Win32_OperatingSystem'{[pscustomobject]@{FreePhysicalMemory=32GB/1KB;Caption='Mock Windows';Version='10.0.00000';OSArchitecture='64-bit'}};'Win32_ComputerSystem'{[pscustomobject]@{NumberOfLogicalProcessors=16;TotalPhysicalMemory=64GB;HypervisorPresent=$true}};'Win32_LogicalDisk'{[pscustomobject]@{FreeSpace=500GB}};'Win32_Processor'{[pscustomobject]@{VirtualizationFirmwareEnabled=$true;SecondLevelAddressTranslationExtensions=$true;VMMonitorModeExtensions=$true}};default{throw 'Unexpected CIM class'}} }
function New-Item {param($ItemType,$Path,$ErrorAction);$global:ReviewMock_events.Add('CreateDirectory');[pscustomobject]@{FullName=$Path}}
function New-VM {param($Name,$Generation,$MemoryStartupBytes,$Path,$NewVHDPath,$NewVHDSizeBytes,$SwitchName);$global:ReviewMock_events.Add('New-VM')}
function Set-VMProcessor {param($VMName,$Count);$global:ReviewMock_events.Add('Set-VMProcessor');if($global:ReviewMock_mode -eq 'creation-failure'){throw 'Mock processor failure'}}
function Set-VMKeyProtector {param($VMName,[switch]$NewLocalKeyProtector);$global:ReviewMock_events.Add('Set-VMKeyProtector')}
function Enable-VMTPM {param($VMName);$global:ReviewMock_events.Add('Enable-VMTPM')}
function Add-VMDvdDrive {param($VMName,$Path,[switch]$Passthru);$global:ReviewMock_events.Add('Add-VMDvdDrive');[pscustomobject]@{MockDvd=$true}}
function Set-VMFirmware {param($VMName,$EnableSecureBoot,$SecureBootTemplate,$FirstBootDevice);$global:ReviewMock_events.Add('Set-VMFirmware')}
function Invoke-RestMethod { throw 'Legacy HTTP calls are blocked by this offline suite.' }
function Invoke-WebRequest {
 param($Uri,$Proxy,$Method,$TimeoutSec,$MaximumRedirection,[switch]$DisableKeepAlive,[switch]$UseBasicParsing,[switch]$SkipCertificateCheck,$Headers,$ErrorAction)
 if($PSVersionTable.PSVersion.Major -ge 6 -and (-not $PSBoundParameters.ContainsKey('SkipCertificateCheck') -or $SkipCertificateCheck)){$global:ReviewMock_requestPolicyFailed=$true;throw 'Certificate validation was not explicit.'}
 $global:ReviewMock_events.Add('MockNetwork')
 $global:ReviewMock_request++
 if($Uri -ne 'https://claude.ai/cdn-cgi/trace' -or $Proxy -ne 'http://127.0.0.1:17897/' -or $Method -ne 'Get' -or $TimeoutSec -ne 15 -or $MaximumRedirection -ne 0 -or -not $DisableKeepAlive -or -not $UseBasicParsing -or $Headers['Cache-Control'] -ne 'no-cache' -or $Headers['Pragma'] -ne 'no-cache' -or $Headers['Accept'] -ne 'text/plain' -or $null -ne [Net.ServicePointManager]::ServerCertificateValidationCallback){
  $global:ReviewMock_requestPolicyFailed=$true
  throw 'Request policy was not enforced.'
 }
 $middle=$global:ReviewMock_request -eq 2
 if($global:ReviewMock_mode -eq 'network-failure' -or ($middle -and $global:ReviewMock_mode -in @('single-request-failure','sensitive-error'))){throw 'Mock failure: ip=203.0.113.99; token=mock-private-token; expected=203.0.113.101'}
 if($middle -and $global:ReviewMock_mode -eq 'timeout'){throw [Net.WebException]::new('Mock sensitive timeout 203.0.113.99',$null,[Net.WebExceptionStatus]::Timeout,$null)}
 if($middle -and $global:ReviewMock_mode -eq 'tls-failure'){throw [Security.Authentication.AuthenticationException]::new('Mock sensitive certificate 203.0.113.99')}
 if($middle -and $global:ReviewMock_mode -eq 'canceled'){throw [OperationCanceledException]::new('Mock canceled 203.0.113.99')}
 $address='203.0.113.99';$country='US';$status=200;$contentType='text/plain; charset=UTF-8';$nl=[string][char]10
 if($middle){switch($global:ReviewMock_mode){'different-ip'{$address='203.0.113.100'};'country-mismatch'{$country='CA'};'invalid-ip'{$address='invalid-address'};'invalid-country'{$country='not-country'}}}
 if($global:ReviewMock_mode -eq 'ipv6-equivalent'){$address=if($middle){'2001:db8:0:0:0:0:0:99'}else{'2001:db8::99'}}
 $content='fl=mock'+$nl+'ip='+$address+$nl+'loc='+$country+$nl
 if($middle){switch($global:ReviewMock_mode){
  'missing-ip'{$content='fl=mock'+$nl+'loc=US'+$nl}
  'missing-country'{$content='fl=mock'+$nl+'ip=203.0.113.99'+$nl}
  'duplicate-ip'{$content+='ip=203.0.113.99'+$nl}
  'html'{$contentType='text/html';$content='<html>ip=203.0.113.99 loc=US token=mock-private-token</html>'}
  'html-as-text'{$content='<html>'+$nl+'ip=203.0.113.99'+$nl+'loc=US'+$nl+'</html>'}
  'empty-response'{$content=''}
  'non-string-response'{$content=[byte[]](1,2,3)}
  'http-403'{$status=403}
  'http-204'{$status=204}
  'redirect'{$status=302}
 }}
 [pscustomobject]@{StatusCode=$status;Headers=@{'Content-Type'=$contentType;'Location'='https://example.invalid/private'};Content=$content}
}
function Record([string]$Name,[bool]$Passed,[string]$Detail){$global:ReviewMock_results.Add([pscustomobject]@{test=$Name;passed=$Passed;detail=$Detail})}
$vmScript=Join-Path $SourceRoot 'New-ClaudeVM.ps1';$egressScript=Join-Path $SourceRoot 'Test-ClaudeEgress.ps1';$preScript=Join-Path $SourceRoot 'Test-ClaudePrerequisites.ps1'
$admin=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
foreach($case in @('normal','whatif','existing-vm','existing-folder','junction','missing-command','missing-iso','missing-switch','creation-failure','outside-root','normalized-outside','prefix-collision')){
 $global:ReviewMock_mode=$case;$global:ReviewMock_events.Clear();$caught=$null;$output=$null
 $a=@{VmName='ReviewTestVM';VmRoot=$global:ReviewMock_mockRoot;IsoPath=$global:ReviewMock_iso;SwitchName='mock-switch'}
 if($case -eq 'whatif'){$a.Apply=$true;$a.WhatIf=$true}elseif($case -notin @('normal','junction','outside-root','normalized-outside','prefix-collision')){$a.Apply=$true}
 if($case -eq 'outside-root'){$a.VmRoot='C:\ReviewForbidden'};if($case -eq 'normalized-outside'){$a.VmRoot='D:\Codex\..\ReviewForbidden'};if($case -eq 'prefix-collision'){$a.VmRoot='D:\CodexOther\ReviewForbidden'}
 try{$output=& $vmScript @a}catch{$caught=$_.Exception.Message}
 if($case -eq 'normal'){$obj=$output|ConvertFrom-Json;Record $case ($global:ReviewMock_events.Count-eq 0 -and $obj.mode-eq 'PlanOnly' -and -not $obj.installs_windows -and -not $obj.installs_claude) 'Default plan performs no mutation'}
 elseif($case -eq 'whatif'){$obj=$output|ConvertFrom-Json;Record $case ($global:ReviewMock_events.Count-eq 0 -and $obj.mode-eq 'WhatIf') 'WhatIf performs no mutation'}
 elseif($case -eq 'creation-failure' -and $admin){Record $case ($caught -match 'Set-VMProcessor' -and $global:ReviewMock_events.Count-eq 3) 'Partial creation reports exact failed step and does not delete assets'}
 elseif(-not $admin -and $a.Apply){Record $case ($caught-match 'Administrator' -and $global:ReviewMock_events.Count-eq 0) 'Unprivileged Apply stops before mutation; scenario-specific branch not reached'}
 else{Record $case ($null-ne $caught -and $global:ReviewMock_events.Count-eq 0) 'Unsafe/invalid input stops before mutation'}
}
if($admin){$global:ReviewMock_mode='normal';$global:ReviewMock_events.Clear();$obj=(& $vmScript -VmName 'ReviewTestVM' -VmRoot $global:ReviewMock_mockRoot -IsoPath $global:ReviewMock_iso -SwitchName 'mock-switch' -Apply)|ConvertFrom-Json;Record 'mock-apply' ($obj.mode-eq 'CreatedStopped' -and $global:ReviewMock_events.Count-eq 7 -and -not $obj.starts_vm -and -not $obj.installs_windows -and -not $obj.installs_claude) 'Successful mock Apply creates stopped VM only'}
function Get-NetTCPConnection {
    param($State,$LocalPort,$ErrorAction)
    if ($State -ne 'Listen' -or $LocalPort -ne 17897) { throw 'Unexpected proxy lookup' }
    $global:ReviewMock_ownerChecks++
    $owner = if ($global:ReviewMock_mode -eq 'owner-switch' -and $global:ReviewMock_ownerChecks -eq 2) { 43 } else { 42 }
    [pscustomobject]@{ LocalAddress = '127.0.0.1'; LocalPort = 17897; OwningProcess = $owner }
}
$fixtureRoot = Join-Path $PSScriptRoot ('egress-test-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($fixtureRoot)
try {
$mockAudit = @'
param([string]$EvidencePath,[int]$ProbeProxyPort)
if ($EvidencePath -ne 'D:\MockPrivate\evidence.json' -or $ProbeProxyPort -ne 17897) { throw 'Unexpected audit request' }
if ($global:ReviewMock_mode -eq 'audit-error') { throw 'Mock secret from audit, do not expose' }
$checks = foreach ($name in 'specified_core_process','effective_firewall_profiles','effective_allow_rule_filters','core_first_hop_rules','protected_application_rules','loopback_probe_proxy') {
    $status = if (($name -eq 'effective_firewall_profiles' -and $global:ReviewMock_mode -eq 'unguarded-outbound') -or
        ($name -eq 'loopback_probe_proxy' -and $global:ReviewMock_mode -eq 'unguarded-proxy')) { 'unknown' } else { 'pass' }
    @{check=$name; status=$status; details=@{owner_process_id=42}}
}
@{checks=@($checks)} | ConvertTo-Json -Depth 5
'@
[IO.File]::WriteAllText((Join-Path $fixtureRoot 'Test-ClaudeGuestNetwork.ps1'),$mockAudit)
Copy-Item -LiteralPath $egressScript,(Join-Path $SourceRoot 'Read-ClaudeCoreApi.ps1') -Destination $fixtureRoot
$egressScript = Join-Path $fixtureRoot 'Test-ClaudeEgress.ps1'
function Invoke-MockEgress {
    param([string]$ExpectedCountry,[string]$ExpectedExitIp='203.0.113.99',[int]$RequestCount=3,[string]$SampleLogPath)
    $global:ReviewMock_ownerChecks = 0
    $settings = @{ ExpectedExitIp=$ExpectedExitIp; EvidencePath='D:\MockPrivate\evidence.json'; ProxyPort=17897; RequestCount=$RequestCount }
    if ($ExpectedCountry) { $settings.ExpectedCountry = $ExpectedCountry }
    if ($SampleLogPath) { $settings.SampleLogPath = $SampleLogPath }
    & $egressScript @settings
}
foreach($case in @('normal','country-mismatch','network-failure','single-request-failure','invalid-country','missing-ip','missing-country','invalid-ip','different-ip','duplicate-ip','html','html-as-text','empty-response','non-string-response','http-403','http-204','redirect','sensitive-error','timeout','tls-failure','canceled')){
 $global:ReviewMock_mode=$case;$global:ReviewMock_events.Clear();$global:ReviewMock_request=0;$global:ReviewMock_requestPolicyFailed=$false
 $before=[Net.ServicePointManager]::SecurityProtocol;$callbackBefore=[Net.ServicePointManager]::ServerCertificateValidationCallback
 $json=Invoke-MockEgress -ExpectedCountry US;$obj=$json|ConvertFrom-Json
 $expected = $case -eq 'normal'
 $count = if ($case -in 'different-ip','country-mismatch') { 2 } else { 3 }
 $timings = @($obj.results | Where-Object { $null -ne $_.elapsed_ms -and $_.elapsed_ms -ge 0 -and
     $_.path -eq 'guest-loopback-proxy' -and $_.proxy_port -eq 17897 -and $_.started_at_utc -and $_.finished_at_utc }).Count -eq $count
 $safe=$json -notmatch '203\.0\.113\.(99|100|101)|mock-private-token|example\.invalid|Mock sensitive'
 $passed=($obj.country_consistent -eq $expected -and $obj.exit_ip_consistent -eq $expected -and $obj.egress_consistent -eq $expected -and $obj.overall_passed -eq $expected -and $obj.expected_exit_matches -eq $expected -and $global:ReviewMock_events.Count -eq $count -and $obj.results.Count -eq $count -and $obj.request_count -eq $count -and $obj.requested_count -eq 3 -and $timings -and $safe -and -not $global:ReviewMock_requestPolicyFailed -and [Net.ServicePointManager]::SecurityProtocol -eq $before -and [object]::ReferenceEquals([Net.ServicePointManager]::ServerCertificateValidationCallback,$callbackBefore))
 Record ('egress-'+$case) $passed 'Three fixed-endpoint requests; strict response checks; no address/message leakage; request policy and TLS state restored'
 if($case -in @('network-failure','single-request-failure','sensitive-error','canceled')){Record ('egress-stage-'+$case) (@($obj.results|Where-Object{-not $_.request_succeeded -and $_.error_stage -ne 'unknown'}).Count -eq 0) 'Uncertain request failures stay unknown'}
 if($case -eq 'timeout'){Record 'egress-stage-timeout' ($obj.results[1].error_stage -eq 'timeout') 'WebException Timeout supports timeout classification'}
 if($case -eq 'tls-failure'){Record 'egress-stage-tls' ($obj.results[1].error_stage -eq 'tls') 'AuthenticationException supports TLS classification'}
 if($case -in @('http-403','http-204','redirect')){Record ('egress-stage-'+$case) ($obj.results[1].error_stage -eq 'http-status') 'Rejected HTTP status is reported without the response body'}
}
foreach($case in @('expected-exit-match','expected-exit-mismatch')){
 $global:ReviewMock_mode='normal';$global:ReviewMock_events.Clear();$global:ReviewMock_request=0;$global:ReviewMock_requestPolicyFailed=$false
 $target=if($case -eq 'expected-exit-match'){'203.0.113.99'}else{'203.0.113.101'}
 $json=Invoke-MockEgress -ExpectedCountry US -ExpectedExitIp $target;$obj=$json|ConvertFrom-Json;$expected=$case -eq 'expected-exit-match'
 Record ('egress-'+$case) ($obj.egress_consistent -eq $expected -and $obj.expected_exit_matches -eq $expected -and $obj.overall_passed -eq $expected -and $json -notmatch '203\.0\.113\.(99|101)' -and -not $obj.public_ip_recorded -and $global:ReviewMock_events.Count -eq $(if($expected){3}else{1}) -and -not $global:ReviewMock_requestPolicyFailed) 'Expected address compared only in memory'
}
$global:ReviewMock_mode='normal';$global:ReviewMock_request=0;$json=Invoke-MockEgress;$obj=$json|ConvertFrom-Json
Record 'egress-optional-country' ($obj.overall_passed -and $null -eq $obj.expected_country_matches -and $obj.expected_exit_matches -and $json -notmatch '203\.0\.113\.99' -and $obj.scope -match 'same Claude HTTPS trace endpoint; one source only' -and $obj.not_tested -contains 'Independent geolocation sources') 'Expected exit is required; country may be omitted; report limits evidence to one source'
$global:ReviewMock_mode='normal';$global:ReviewMock_request=0;$json=Invoke-MockEgress -ExpectedCountry CA;$obj=$json|ConvertFrom-Json
Record 'egress-expected-country-mismatch' ($obj.request_count -eq 1 -and $obj.stop_reason -eq 'unexpected-egress' -and -not $obj.expected_country_matches -and -not $obj.overall_passed) 'Unexpected country ends the run after recording the sample'
$global:ReviewMock_mode='ipv6-equivalent';$global:ReviewMock_request=0;$json=Invoke-MockEgress -ExpectedExitIp '2001:db8::99';$obj=$json|ConvertFrom-Json
Record 'egress-ipv6-equivalent' ($obj.overall_passed -and $obj.exit_ip_consistent -and $obj.expected_exit_matches -and $json -notmatch '2001:db8') 'Equivalent IPv6 forms compare without reporting addresses'
foreach($invalid in @('invalid-address','2130706433','fe80::1%12')){
 $global:ReviewMock_mode='normal';$global:ReviewMock_events.Clear();$global:ReviewMock_request=0;$caught=$null
 try{Invoke-MockEgress -ExpectedExitIp $invalid|Out-Null}catch{$caught=$_.Exception.Message}
 Record 'egress-invalid-expected-ip' ($null -ne $caught -and $global:ReviewMock_events.Count -eq 0 -and $caught -notmatch [regex]::Escape($invalid)) 'Invalid expected address rejected before requests without repeating its value'
}
$protocolBefore=[Net.ServicePointManager]::SecurityProtocol;$originalCallback=[Net.ServicePointManager]::ServerCertificateValidationCallback
$sentinelCallback=[Net.Security.RemoteCertificateValidationCallback]{return $true}
try{
 [Net.ServicePointManager]::ServerCertificateValidationCallback=$sentinelCallback
 foreach($case in @('normal','network-failure')){
  $global:ReviewMock_mode=$case;$global:ReviewMock_request=0;$global:ReviewMock_requestPolicyFailed=$false
  $json=Invoke-MockEgress;$obj=$json|ConvertFrom-Json
  Record ('egress-certificate-validation-'+$case) (-not $global:ReviewMock_requestPolicyFailed -and [object]::ReferenceEquals([Net.ServicePointManager]::ServerCertificateValidationCallback,$sentinelCallback) -and [Net.ServicePointManager]::SecurityProtocol -eq $protocolBefore) 'Permissive callback is disabled while requests run and the exact prior callback is restored'
 }
}finally{[Net.ServicePointManager]::ServerCertificateValidationCallback=$originalCallback;[Net.ServicePointManager]::SecurityProtocol=$protocolBefore}
foreach ($case in 'missing-input','unguarded-outbound','unguarded-proxy','audit-error') {
    $global:ReviewMock_mode = $case
    $global:ReviewMock_events.Clear()
    $errorText = $null
    try {
        if ($case -eq 'missing-input') { & $egressScript | Out-Null }
        else { Invoke-MockEgress | Out-Null }
    } catch { $errorText = $_.Exception.Message }
    Record ('egress-'+$case) ($errorText -and $global:ReviewMock_events.Count -eq 0 -and $errorText -notmatch 'Mock secret') 'Unsafe or incomplete local evidence prevents all web requests.'
}
$global:ReviewMock_mode = 'owner-switch'
$global:ReviewMock_request = 0
$global:ReviewMock_events.Clear()
$obj = Invoke-MockEgress | ConvertFrom-Json
Record 'egress-owner-switch' ($obj.request_count -eq 3 -and $obj.started_request_count -eq 2 -and
    $obj.results[1].error_stage -eq 'proxy-unavailable' -and -not $obj.results[1].request_started -and
    $obj.results[2].request_succeeded -and $global:ReviewMock_events.Count -eq 2) 'Changed proxy owner fails that sample without making an unproxied request.'
$global:ReviewMock_mode = 'tls-failure'
$global:ReviewMock_request = 0
$global:ReviewMock_events.Clear()
$logPath = Join-Path $fixtureRoot 'samples.jsonl'
$obj = Invoke-MockEgress -RequestCount 4 -SampleLogPath $logPath | ConvertFrom-Json
$logRows = @(Get-Content -LiteralPath $logPath -Encoding UTF8 | ForEach-Object { ConvertFrom-Json -InputObject $_ })
Record 'egress-live-log' ($logRows.Count -eq 4 -and $logRows[1].error_stage -eq 'tls' -and
    $null -eq $logRows[1].http_status -and $logRows[2].http_status -eq 200 -and $logRows[2].expected_exit_matches -and
    $obj.started_request_count -eq 4 -and -not $obj.overall_passed -and
    ([IO.File]::ReadAllText($logPath) -notmatch '203\.0\.113\.|Mock sensitive')) 'TLS failure and later success are written separately without raw addresses.'
$global:ReviewMock_events.Clear()
$caught = $false
try { Invoke-MockEgress -SampleLogPath $logPath | Out-Null } catch { $caught = $true }
Record 'egress-log-no-overwrite' ($caught -and $global:ReviewMock_events.Count -eq 0 -and
    @([IO.File]::ReadAllLines($logPath)).Count -eq 4) 'Existing sample log is preserved and no probe is sent.'
$caught = $false
try { Invoke-MockEgress -SampleLogPath 'C:\ReviewForbidden\samples.jsonl' | Out-Null } catch { $caught = $true }
Record 'egress-log-outside-root' ($caught -and $global:ReviewMock_events.Count -eq 0) 'Reject file output outside D:\Codex before requesting the endpoint.'
} finally {
    foreach ($name in 'Test-ClaudeEgress.ps1','Test-ClaudeGuestNetwork.ps1','Read-ClaudeCoreApi.ps1','samples.jsonl') {
        [IO.File]::Delete((Join-Path $fixtureRoot $name))
    }
    [IO.Directory]::Delete($fixtureRoot)
}
$global:ReviewMock_mode='normal';$obj=(& $preScript)|ConvertFrom-Json;Record 'prereq-readonly' ($null-ne $obj.os -and $obj.notes.Count-ge 3 -and $null-ne $obj.hyper_v.feature_state) 'CIM/Hyper-V calls mocked; no report file requested'
[pscustomobject]@{powershell=$PSVersionTable.PSVersion.ToString();admin=$admin;total=$global:ReviewMock_results.Count;failed=@($global:ReviewMock_results|Where-Object{-not $_.passed}).Count;results=@($global:ReviewMock_results.ToArray())}|ConvertTo-Json -Depth 6

if(@($global:ReviewMock_results|Where-Object{-not $_.passed}).Count -gt 0){exit 1}
