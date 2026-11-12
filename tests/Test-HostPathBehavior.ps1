#requires -Version 5.1
# Offline mocks only. No host/guest settings or network requests.
param([string]$SourceRoot=(Join-Path (Split-Path -Parent $PSScriptRoot) 'skills\claude-environment-deploy\scripts'))
$ErrorActionPreference='Stop'
Import-Module Microsoft.PowerShell.Utility,Microsoft.PowerShell.Management
$PSModuleAutoLoadingPreference='None'
$global:HostMock_data=@{}
function Get-Content {
    param([string]$LiteralPath,[switch]$Raw,[string]$Encoding,[int]$Tail,$ErrorAction)
    if($Encoding -ne 'UTF8'){throw 'Encoding not specified'}
    if($LiteralPath -eq 'D:\PrivateHostCanary\evidence.json'){return ($global:HostMock_data.evidence | ConvertTo-Json -Depth 10)}
    if($LiteralPath -eq 'D:\PrivateHostCanary\active.json'){return '{"external-controller":"203.0.113.90:9090","secret":"PRIVATE-TOKEN-CANARY"}'}
    if($LiteralPath -eq 'D:\PrivateHostCanary\recent.log'){
        if($global:HostMock_data.mode -eq 'read-error'){throw 'PRIVATE-ERROR-CANARY'}
        return $global:HostMock_data.lines
    }
    throw 'Unexpected private path'
}
function Get-ChildItem {param($LiteralPath,[switch]$File,$Filter,$ErrorAction);[pscustomobject]@{FullName='D:\PrivateHostCanary\recent.log';LastWriteTime=[DateTime]::Now}}
function Get-Command {param($Name,$ErrorAction);return $null}
$cases=@('direct','other-policy','intentional-upstream','wrong-policy-prefix','stale-guest','future-guest','old-log','before-guest','missing-stamp','wrong-port','cidr-input','missing-port','error-log','read-error','ipv6','api-denied','no-evidence')
$results=New-Object 'System.Collections.Generic.List[object]'
foreach($case in $cases){
    $time=[DateTimeOffset]::UtcNow
    $hop=@{addresses=@('203.0.113.80');port=12345;expected_host_policy='DIRECT'}
    $evidence=@{guest_checked_at_utc=$time.AddSeconds(-5).ToString('o');host_log_directory='D:\PrivateHostCanary';host_active_config_path='D:\PrivateHostCanary\active.json';host_core_path='D:\PrivateHostCanary\core.exe';guest_first_hops=@($hop)}
    $stamp=$time.AddSeconds(-2).ToString('o');$destination='203.0.113.80:12345';$policy='DIRECT';$level='info';$suffix=''
    switch($case){
        'other-policy'{$policy='PRIVATE-UPSTREAM[PRIVATE-NODE]'}
        'intentional-upstream'{$hop.expected_host_policy='PRIVATE-UPSTREAM';$policy='PRIVATE-UPSTREAM[PRIVATE-NODE]'}
        'wrong-policy-prefix'{$policy='DIRECTLY[PRIVATE-NODE]'}
        'stale-guest'{$evidence.guest_checked_at_utc=$time.AddMinutes(-20).ToString('o')}
        'future-guest'{$evidence.guest_checked_at_utc=$time.AddMinutes(10).ToString('o')}
        'old-log'{$stamp=$time.AddMinutes(-20).ToString('o')}
        'before-guest'{$stamp=$time.AddSeconds(-10).ToString('o')}
        'wrong-port'{$destination='203.0.113.80:123456'}
        'cidr-input'{$hop.addresses=@('203.0.113.0/24')}
        'missing-port'{$hop.Remove('port')}
        'error-log'{$level='warning';$suffix=' i/o timeout'}
        'ipv6'{$hop.addresses=@('2001:db8::80');$destination='[2001:db8::80]:12345'}
    }
    $line='time="'+$stamp+'" level='+$level+' msg="[TCP] 198.18.0.1:50000 --> '+$destination+' match Match using '+$policy+$suffix+'"'
    if($case -eq 'missing-stamp'){$line='msg="[TCP] --> '+$destination+' match Match using DIRECT"'}
    $global:HostMock_data=@{evidence=$evidence;lines=@($line);mode=$case}
    $arguments=@{EvidencePath='D:\PrivateHostCanary\evidence.json'}
    if($case -eq 'api-denied'){$arguments.ReadCoreApi=$true}
    if($case -eq 'no-evidence'){$arguments=@{}}
    $json=& (Join-Path $SourceRoot 'Test-ClaudeHostPath.ps1') @arguments | Out-String
    $o=$json | ConvertFrom-Json;$h=@($o.hops)
    $expectedStatus=switch($case){'direct'{'snapshot_match'};'intentional-upstream'{'snapshot_match'};'ipv6'{'snapshot_match'};'api-denied'{'snapshot_match'};'other-policy'{'review_required'};'wrong-policy-prefix'{'review_required'};'error-log'{'review_required'};default{'unknown'}}
    $passed=if($case -eq 'no-evidence'){$h.Count -eq 0}else{$h.Count -eq 1 -and $h[0].status -eq $expectedStatus}
    if($case -eq 'other-policy' -or $case -eq 'wrong-policy-prefix'){$passed=$passed -and $h[0].unexpected_host_forwarding_observed}
    if($case -eq 'api-denied'){$passed=$passed -and $o.core_api_state -eq 'unknown' -and -not $o.controller_owner_verified}
    if($case -eq 'read-error'){$passed=$passed -and $o.log_read_incomplete}
    $privateOmitted=$json -notmatch '203\.0\.113\.|2001:db8|198\.18\.|PrivateHostCanary|PRIVATE-|12345'
    $limits=-not $o.network_changed -and -not $o.public_requests_made -and $o.overall -eq 'review_required' -and @($h | Where-Object guest_identity_proven).Count -eq 0
    $results.Add([pscustomobject]@{test=$case;passed=[bool]($passed -and $privateOmitted -and $limits)})
}
[pscustomobject]@{powershell=$PSVersionTable.PSVersion.ToString();total=$results.Count;failed=@($results | Where-Object {-not $_.passed}).Count;results=@($results.ToArray())} | ConvertTo-Json -Depth 5
