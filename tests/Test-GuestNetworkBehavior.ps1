#requires -Version 5.1
# Standalone offline behavior tests; no actual network, credentials or policy mutation.
param([string]$SourceRoot=(Join-Path (Split-Path -Parent $PSScriptRoot) 'skills\claude-environment-deploy\scripts'))
$ErrorActionPreference='Stop'
Import-Module Microsoft.PowerShell.Utility,Microsoft.PowerShell.Management
$PSModuleAutoLoadingPreference='None'
$global:GuestMock_cases=New-Object 'System.Collections.Generic.List[object]'
$global:GuestMock_files=@{};$global:GuestMock_rules=@();$global:GuestMock_mode='normal'
function Get-Content {param([string]$LiteralPath,[switch]$Raw,[string]$Encoding);if($Encoding -ne 'UTF8'){$global:GuestMock_utf8=$false};if(-not $global:GuestMock_files.ContainsKey($LiteralPath)){throw 'Missing mock file'};return $global:GuestMock_files[$LiteralPath]}
function Get-Command {param([string]$Name,$ErrorAction);if($Name -eq 'ConvertFrom-Yaml'){return};throw 'Unexpected command lookup'}
function Get-Process {param($Id,$ErrorAction);if($global:GuestMock_mode -eq 'core-missing'){return};[pscustomobject]@{Id=42;ProcessName='mihomo';Path=$(if($global:GuestMock_mode -eq 'api-owner-wrong'){'D:\MockPrivate\wrong.exe'}else{'D:\MockPrivate\core.exe'})}}
function Get-NetTCPConnection {
    param($State,$LocalPort,$OwningProcess,$ErrorAction)
    if($State -eq 'Established'){
        if($global:GuestMock_mode -eq 'socket-none'){return}
        [pscustomobject]@{LocalAddress='192.0.2.10';LocalPort=50000;RemoteAddress=$(if($global:GuestMock_mode -eq 'socket-other'){'203.0.113.28'}else{'203.0.113.27'});RemotePort=24443;OwningProcess=$OwningProcess};return
    }
    if($global:GuestMock_mode -eq 'probe-listener-unavailable'){throw 'Offline socket inventory unavailable'}
    if($global:GuestMock_mode -eq 'probe-listener-wrong-owner'){[pscustomobject]@{LocalAddress='127.0.0.1';LocalPort=$LocalPort;OwningProcess=43};return}
    if($global:GuestMock_mode -eq 'probe-listener-wildcard'){[pscustomobject]@{LocalAddress='0.0.0.0';LocalPort=$LocalPort;OwningProcess=42};return}
    [pscustomobject]@{LocalAddress=$(if($global:GuestMock_mode -eq 'api-ipv6'){'::1'}else{'127.0.0.1'});LocalPort=$LocalPort;OwningProcess=42}
}
function Get-NetAdapter {param($ErrorAction);[pscustomobject]@{Name='MockTUN';Status=$(if($global:GuestMock_mode -eq 'tun-down'){'Down'}else{'Up'})}}
function Get-NetFirewallProfile {param($PolicyStore,$ErrorAction);foreach($n in @('Domain','Private','Public')){[pscustomobject]@{Name=$n;Enabled=$true;DefaultOutboundAction=$(if($global:GuestMock_mode -eq 'profile-allow' -and $n -eq 'Public'){'Allow'}else{'Block'})}}}
function Get-NetFirewallRule {param($PolicyStore,$Direction,$Enabled,$ErrorAction);if($global:GuestMock_mode -eq 'firewall-unreadable'){throw 'Mock inaccessible'};return $global:GuestMock_rules}
function Get-NetFirewallApplicationFilter {[CmdletBinding()]param([Parameter(ValueFromPipeline)]$InputObject)process{if($global:GuestMock_mode -eq 'incomplete-filter'){[pscustomobject]@{Program=$InputObject.Program}}else{[pscustomobject]@{Program=$InputObject.Program;Package=$InputObject.Package}}}}
function Get-NetFirewallAddressFilter {[CmdletBinding()]param([Parameter(ValueFromPipeline)]$InputObject)process{[pscustomobject]@{RemoteAddress=$InputObject.Addresses;LocalAddress='Any'}}}
function Get-NetFirewallPortFilter {[CmdletBinding()]param([Parameter(ValueFromPipeline)]$InputObject)process{[pscustomobject]@{RemotePort=$InputObject.Ports;LocalPort='Any';Protocol=$InputObject.Protocol}}}
function Get-NetFirewallInterfaceFilter {[CmdletBinding()]param([Parameter(ValueFromPipeline)]$InputObject)process{[pscustomobject]@{InterfaceAlias=$InputObject.Interfaces}}}
function Get-NetFirewallInterfaceTypeFilter {[CmdletBinding()]param([Parameter(ValueFromPipeline)]$InputObject)process{[pscustomobject]@{InterfaceType='Any'}}}
function Get-NetFirewallServiceFilter {[CmdletBinding()]param([Parameter(ValueFromPipeline)]$InputObject)process{[pscustomobject]@{Service=$InputObject.Service}}}
function Get-NetFirewallSecurityFilter {[CmdletBinding()]param([Parameter(ValueFromPipeline)]$InputObject)process{[pscustomobject]@{LocalUser=$InputObject.LocalUser;RemoteUser='Any';RemoteMachine='Any'}}}
function Invoke-RestMethod {throw 'No network permitted'}
function New-NetFirewallRule {throw 'No mutation permitted'}
function Set-NetFirewallProfile {throw 'No mutation permitted'}
function Stop-Process {throw 'No mutation permitted'}
function Rule($Program,$Package,$Addresses,$Ports,$Interfaces,$Service='Any',$LocalUser='Any') {
    [pscustomobject]@{Program=$Program;Package=$Package;Addresses=$Addresses;Ports=$Ports;Interfaces=$Interfaces;Service=$Service;LocalUser=$LocalUser;Action='Allow';Profile='Any';Protocol='TCP'}
}
function Fixture {
    $global:GuestMock_rules=@((Rule 'D:\MockPrivate\core.exe' 'Any' @('203.0.113.27') @('24443') @('MockEthernet')),(Rule 'D:\MockPrivate\browser.exe' 'Any' @('Any') @('Any') @('MockTUN')))
    $node=[ordered]@{name='private-local-name';type='vless';server='203.0.113.27';port=24443;uuid='PRIVATE-UUID-CANARY';tls=$true;'reality-opts'=@{'public-key'='PRIVATE-KEY-CANARY';'short-id'='PRIVATE-SHORT-CANARY'}}
    $remote=[ordered]@{name='private-subscription-name';type='vless';server='203.0.113.27';port=24443;uuid='PRIVATE-UUID-CANARY';tls=$true;'reality-opts'=@{'short-id'='PRIVATE-SHORT-CANARY';'public-key'='PRIVATE-KEY-CANARY'}}
    $global:GuestMock_active=[ordered]@{proxies=@($node);ipv6=$false;dns=@{enable=$true;ipv6=$false;nameserver=@('https://private-dns.example/dns-query#PrivateGroup')};tun=@{enable=$true;'dns-hijack'=@('any:53','tcp://any:53')}}
    $global:GuestMock_subscription=@{proxies=@($remote)}
    $global:GuestMock_evidence=[ordered]@{core_path='D:\MockPrivate\core.exe';tun_interface_alias='MockTUN';protected_program_paths=@('D:\MockPrivate\browser.exe');protected_package_sids=@('S-1-15-2-123456789');active_config_path='D:\MockPrivate\active.yaml';verge_config_path='D:\MockPrivate\verge.yaml';profiles_config_path='D:\MockPrivate\profiles.yaml';subscription_config_path='D:\MockPrivate\subscription.yaml';expected_profile_uid='private-profile-uid';dns_proxy_group='PrivateGroup';expected_group_selections=@{PrivateGroup='private-local-name'};runtime_group_selections=@{PrivateGroup='private-local-name'};local_node_name='private-local-name';subscription_node_name='private-subscription-name';first_hop=@{addresses=@('203.0.113.27');port=24443;protocol='TCP';interface_alias='MockEthernet'}}
    $global:GuestMock_evidence.subscription_checked_at_utc=[DateTime]::UtcNow.ToString('o')
    $global:GuestMock_evidence.persisted_config_path='D:\MockPrivate\persisted.yaml'
    $global:GuestMock_persisted=$global:GuestMock_active|ConvertTo-Json -Depth 10|ConvertFrom-Json
    $global:GuestMock_files=@{'D:\MockPrivate\verge.yaml'='{"enable_dns_override":false}';'D:\MockPrivate\profiles.yaml'='{"current":"private-profile-uid","items":[{"uid":"private-profile-uid","selected":[{"name":"PrivateGroup","now":"private-local-name"}]}]}'}
}
function Save-Fixture {
    $global:GuestMock_files['D:\MockPrivate\active.yaml']=$global:GuestMock_active|ConvertTo-Json -Depth 10
    $global:GuestMock_files['D:\MockPrivate\subscription.yaml']=$global:GuestMock_subscription|ConvertTo-Json -Depth 10
    $global:GuestMock_files['D:\MockPrivate\persisted.yaml']=$global:GuestMock_persisted|ConvertTo-Json -Depth 10
    $global:GuestMock_files['D:\MockPrivate\evidence.json']=$global:GuestMock_evidence|ConvertTo-Json -Depth 10
}
function Check($Object,[string]$Name) {return @($Object.checks|Where-Object check -eq $Name)[0]}
function Record([string]$Name,[bool]$Passed,[string]$Detail){$global:GuestMock_cases.Add([pscustomobject]@{test=$Name;passed=$Passed;detail=$Detail})}
$script=Join-Path $SourceRoot 'Test-ClaudeGuestNetwork.ps1'
foreach($case in @('normal','default-no-evidence','core-missing','tun-down','profile-allow','firewall-unreadable','incomplete-filter','core-wide','wrong-hop','browser-wide','other-package','protected-package','service-restricted','user-restricted','selection-conflict','node-nested-change','node-order','yaml-no-parser','dns-disabled','dns-unpinned','invalid-sensitive-bool','no-runtime','hop-any','hop-cidr','hop-range','hop-port-zero','hop-port-high','tun-disabled','tun-missing','node-name-only','node-uuid-missing','node-unsupported','node-null-field','unicode-names','selection-missing-with-conflict','freshness-missing','freshness-stale','freshness-future','freshness-invalid-max','batch-node-change','batch-node-missing','approved-chain-override','forbidden-auth-override','persisted-drift','block-first-hop','block-restricted','api-not-configured','socket-match','socket-none','socket-other')){
    $global:GuestMock_mode=$case;$global:GuestMock_utf8=$true;Fixture
    switch($case){
        'core-wide'{$global:GuestMock_rules+=Rule 'D:\MockPrivate\core.exe' 'Any' @('Any') @('Any') @('Any')}
        'wrong-hop'{$global:GuestMock_evidence.first_hop.port=24444}
        'browser-wide'{$global:GuestMock_rules+=Rule 'D:\MockPrivate\browser.exe' 'Any' @('Any') @('Any') @('Any')}
        'other-package'{$global:GuestMock_rules+=Rule 'Any' 'S-1-15-2-987654321' @('Any') @('Any') @('Any')}
        'protected-package'{$global:GuestMock_rules+=Rule 'Any' 'S-1-15-2-123456789' @('Any') @('Any') @('Any')}
        'service-restricted'{$global:GuestMock_rules+=Rule 'Any' 'Any' @('Any') @('Any') @('Any') 'MockService'}
        'user-restricted'{$global:GuestMock_rules+=Rule 'Any' 'Any' @('Any') @('Any') @('Any') 'Any' 'D:(A;;CC;;;S-1-5-21-123)'}
        'selection-conflict'{$global:GuestMock_evidence.runtime_group_selections.PrivateGroup='wrong-private-node'}
        'selection-missing-with-conflict'{$global:GuestMock_evidence.Remove('runtime_group_selections');$global:GuestMock_evidence.saved_group_selections=@{PrivateGroup='wrong-private-node'}}
        'freshness-missing'{$global:GuestMock_evidence.Remove('subscription_checked_at_utc')}
        'freshness-stale'{$global:GuestMock_evidence.subscription_checked_at_utc=[DateTime]::UtcNow.AddDays(-2).ToString('o')}
        'freshness-future'{$global:GuestMock_evidence.subscription_checked_at_utc=[DateTime]::UtcNow.AddHours(1).ToString('o')}
        'freshness-invalid-max'{$global:GuestMock_evidence.subscription_max_age_hours='PRIVATE-BAD-MAX'}
        'batch-node-change'{
            $global:GuestMock_evidence.node_pairs=@(@{local_node_name='private-local-name';subscription_node_name='private-subscription-name'},@{local_node_name='private-local-name';subscription_node_name='private-subscription-two'})
            $global:GuestMock_subscription.proxies+=@{name='private-subscription-two';type='vless';server='203.0.113.28';port=24443;uuid='PRIVATE-UUID-CANARY'}
        }
        'batch-node-missing'{$global:GuestMock_evidence.node_pairs=@(@{local_node_name='private-local-name';subscription_node_name='private-subscription-name'},@{local_node_name='missing-private-name';subscription_node_name='missing-private-remote'})}
        'approved-chain-override'{$global:GuestMock_active.proxies[0]['dialer-proxy']='PRIVATE-TRANSIT';$global:GuestMock_persisted.proxies[0]|Add-Member NoteProperty 'dialer-proxy' 'PRIVATE-TRANSIT';$global:GuestMock_evidence.allowed_local_override_fields=@('dialer-proxy')}
        'forbidden-auth-override'{$global:GuestMock_active.proxies[0].uuid='CHANGED-PRIVATE-UUID';$global:GuestMock_evidence.allowed_local_override_fields=@('uuid')}
        'persisted-drift'{$global:GuestMock_persisted.proxies[0].port=24444}
        'block-first-hop'{$b=Rule 'D:\MockPrivate\core.exe' 'Any' @('203.0.113.27') @('24443') @('MockEthernet');$b.Action='Block';$global:GuestMock_rules+=$b}
        'block-restricted'{$b=Rule 'D:\MockPrivate\core.exe' 'Any' @('203.0.113.27') @('24443') @('MockEthernet') 'PrivateService';$b.Action='Block';$global:GuestMock_rules+=$b}
        'node-nested-change'{$global:GuestMock_subscription.proxies[0]['reality-opts']['public-key']='CHANGED-PRIVATE-CANARY'}
        'node-order'{$global:GuestMock_active.proxies[0]['reality-opts']=@{'short-id'='PRIVATE-SHORT-CANARY';'public-key'='PRIVATE-KEY-CANARY'}}
        'dns-disabled'{$global:GuestMock_active.dns.enable=$false}
        'dns-unpinned'{$global:GuestMock_active.dns.nameserver=@('https://private-dns.example/dns-query')}
        'invalid-sensitive-bool'{$global:GuestMock_active.dns.enable='PRIVATE-BOOLEAN-CANARY';$global:GuestMock_files['D:\MockPrivate\verge.yaml']='{"enable_dns_override":"PRIVATE-OVERRIDE-CANARY"}'}
        'no-runtime'{$global:GuestMock_evidence.Remove('runtime_group_selections')}
        'hop-any'{$global:GuestMock_evidence.first_hop.addresses=@('Any');$global:GuestMock_rules[0].Addresses=@('Any')}
        'hop-cidr'{$global:GuestMock_evidence.first_hop.addresses=@('203.0.113.0/24')}
        'hop-range'{$global:GuestMock_evidence.first_hop.addresses=@('203.0.113.1-203.0.113.9')}
        'hop-port-zero'{$global:GuestMock_evidence.first_hop.port=0}
        'hop-port-high'{$global:GuestMock_evidence.first_hop.port=65536}
        'tun-disabled'{$global:GuestMock_active.tun.enable=$false}
        'tun-missing'{$global:GuestMock_active.tun.Remove('enable')}
        'node-name-only'{$global:GuestMock_active.proxies=@(@{name='private-local-name'});$global:GuestMock_subscription.proxies=@(@{name='private-subscription-name'})}
        'node-uuid-missing'{$global:GuestMock_active.proxies[0].Remove('uuid');$global:GuestMock_subscription.proxies[0].Remove('uuid')}
        'node-unsupported'{$global:GuestMock_active.proxies[0].type='custom';$global:GuestMock_subscription.proxies[0].type='custom'}
        'node-null-field'{$global:GuestMock_active.proxies[0]['sni']=$null}
        'unicode-names'{
            $cnGroup=([string][char]0x4ee3)+([string][char]0x7406)+([string][char]0x7ec4)
            $cnNode=([string][char]0x8282)+([string][char]0x70b9)
            $global:GuestMock_active.proxies[0].name=$cnNode;$global:GuestMock_evidence.local_node_name=$cnNode
            $global:GuestMock_evidence.dns_proxy_group=$cnGroup;$global:GuestMock_active.dns.nameserver=@('https://private-dns.example/dns-query#'+$cnGroup)
            $global:GuestMock_evidence.expected_group_selections=@{};$global:GuestMock_evidence.expected_group_selections[$cnGroup]=$cnNode
            $global:GuestMock_evidence.runtime_group_selections=@{};$global:GuestMock_evidence.runtime_group_selections[$cnGroup]=$cnNode
            $global:GuestMock_files['D:\MockPrivate\profiles.yaml']=@{current='private-profile-uid';items=@(@{uid='private-profile-uid';selected=@(@{name=$cnGroup;now=$cnNode})})}|ConvertTo-Json -Depth 8
        }
    }
    Save-Fixture
    if($case -eq 'yaml-no-parser'){$global:GuestMock_files['D:\MockPrivate\active.yaml']='dns: {enable: true}'}
    $args=@{};if($case -ne 'default-no-evidence'){$args.EvidencePath='D:\MockPrivate\evidence.json'}
    if($case -eq 'api-not-configured'){$args.ReadCoreApi=$true}
    $json=& $script @args;$o=$json|ConvertFrom-Json
    $passed=switch($case){
        'normal'{$o.overall -eq 'review_required' -and (Check $o 'selected_node_parameters').status -eq 'pass' -and (Check $o 'dns_configuration').status -eq 'pass' -and (Check $o 'core_first_hop_rules').status -eq 'pass' -and (Check $o 'group_selection_snapshot_consistency').status -eq 'snapshot_match' -and (Check $o 'dns_override_display').details.override_enabled -eq $false}
        'default-no-evidence'{$o.overall -eq 'review_required' -and (Check $o 'specified_core_process').status -eq 'unknown'}
        'core-missing'{(Check $o 'specified_core_process').status -eq 'fail'}
        'tun-down'{(Check $o 'specified_tun_adapter').status -eq 'fail'}
        'profile-allow'{(Check $o 'effective_firewall_profiles').status -eq 'fail'}
        'firewall-unreadable'{(Check $o 'core_first_hop_rules').status -eq 'unknown'}
        'incomplete-filter'{(Check $o 'effective_allow_rule_filters').status -eq 'unknown'}
        'core-wide'{(Check $o 'core_first_hop_rules').status -eq 'fail'}
        'wrong-hop'{(Check $o 'core_first_hop_rules').status -eq 'fail'}
        'browser-wide'{(Check $o 'protected_application_rules').status -eq 'fail'}
        'other-package'{(Check $o 'protected_application_rules').status -eq 'pass' -and (Check $o 'core_first_hop_rules').status -eq 'pass'}
        'protected-package'{(Check $o 'protected_application_rules').status -eq 'fail'}
        'service-restricted'{(Check $o 'protected_application_rules').status -eq 'unknown'}
        'user-restricted'{(Check $o 'protected_application_rules').status -eq 'unknown'}
        'selection-conflict'{(Check $o 'group_selection_snapshot_consistency').status -eq 'fail'}
        'selection-missing-with-conflict'{(Check $o 'group_selection_snapshot_consistency').status -eq 'fail' -and (Check $o 'group_selection_snapshot_consistency').details.missing_group_count -eq 1}
        'freshness-missing'{(Check $o 'subscription_snapshot_freshness').status -eq 'unknown' -and (Check $o 'selected_node_parameters').status -eq 'unknown'}
        'freshness-stale'{(Check $o 'subscription_snapshot_freshness').status -eq 'unknown' -and (Check $o 'selected_node_parameters').status -eq 'unknown'}
        'freshness-future'{(Check $o 'subscription_snapshot_freshness').status -eq 'unknown' -and (Check $o 'selected_node_parameters').status -eq 'unknown'}
        'freshness-invalid-max'{(Check $o 'subscription_snapshot_freshness').status -eq 'unknown' -and $json -notmatch 'PRIVATE-BAD-MAX'}
        'batch-node-change'{(Check $o 'selected_node_parameters').status -eq 'fail' -and (Check $o 'selected_node_parameters').details.pair_count -eq 2}
        'batch-node-missing'{(Check $o 'selected_node_parameters').status -eq 'unknown' -and (Check $o 'selected_node_parameters').details.pair_count -eq 2}
        'approved-chain-override'{(Check $o 'selected_node_parameters').status -eq 'pass' -and (Check $o 'selected_node_parameters').details.pairs[0].approved_local_override_fields -contains 'dialer-proxy' -and (Check $o 'persisted_generated_node_consistency').status -eq 'snapshot_match'}
        'forbidden-auth-override'{(Check $o 'selected_node_parameters').status -eq 'fail' -and (Check $o 'selected_node_parameters').details.pairs[0].invalid_override_field_count -eq 1}
        'persisted-drift'{(Check $o 'persisted_generated_node_consistency').status -eq 'fail'}
        'block-first-hop'{(Check $o 'first_hop_explicit_block_conflicts').status -eq 'fail'}
        'block-restricted'{(Check $o 'first_hop_explicit_block_conflicts').status -eq 'unknown' -and (Check $o 'first_hop_explicit_block_conflicts').details.unresolved_rule_count -eq 1}
        'api-not-configured'{(Check $o 'runtime_current_configuration').status -eq 'unknown' -and (Check $o 'runtime_current_configuration').details.reason -eq 'controller_not_configured' -and (Check $o 'group_selection_snapshot_consistency').status -eq 'unknown'}
        'socket-match'{(Check $o 'observed_core_first_hop_sockets').status -eq 'snapshot_match' -and (Check $o 'observed_core_first_hop_sockets').details.matching_socket_count -eq 1}
        'socket-none'{(Check $o 'observed_core_first_hop_sockets').status -eq 'unknown' -and (Check $o 'observed_core_first_hop_sockets').details.matching_socket_count -eq 0}
        'socket-other'{(Check $o 'observed_core_first_hop_sockets').status -eq 'unknown' -and (Check $o 'observed_core_first_hop_sockets').details.matching_socket_count -eq 0}
        'node-nested-change'{(Check $o 'selected_node_parameters').status -eq 'fail' -and (Check $o 'selected_node_parameters').details.changed_field_names -contains 'reality-opts'}
        'node-order'{(Check $o 'selected_node_parameters').status -eq 'pass'}
        'yaml-no-parser'{(Check $o 'active_configuration_read').status -eq 'unknown' -and (Check $o 'dns_configuration').status -eq 'unknown'}
        'dns-disabled'{(Check $o 'dns_configuration').status -eq 'fail'}
        'dns-unpinned'{(Check $o 'dns_configuration').status -eq 'fail'}
        'invalid-sensitive-bool'{(Check $o 'dns_configuration').status -eq 'unknown' -and (Check $o 'dns_override_display').status -eq 'unknown'}
        'no-runtime'{(Check $o 'group_selection_snapshot_consistency').status -eq 'unknown'}
        'hop-any'{(Check $o 'core_first_hop_rules').status -eq 'unknown'}
        'hop-cidr'{(Check $o 'core_first_hop_rules').status -eq 'unknown'}
        'hop-range'{(Check $o 'core_first_hop_rules').status -eq 'unknown'}
        'hop-port-zero'{(Check $o 'core_first_hop_rules').status -eq 'unknown'}
        'hop-port-high'{(Check $o 'core_first_hop_rules').status -eq 'unknown'}
        'tun-disabled'{(Check $o 'dns_configuration').status -eq 'fail'}
        'tun-missing'{(Check $o 'dns_configuration').status -eq 'unknown'}
        'node-name-only'{(Check $o 'selected_node_parameters').status -eq 'unknown'}
        'node-uuid-missing'{(Check $o 'selected_node_parameters').status -eq 'unknown'}
        'node-unsupported'{(Check $o 'selected_node_parameters').status -eq 'unknown'}
        'node-null-field'{(Check $o 'selected_node_parameters').status -eq 'fail'}
        'unicode-names'{(Check $o 'selected_node_parameters').status -eq 'pass' -and (Check $o 'dns_configuration').status -eq 'pass' -and (Check $o 'group_selection_snapshot_consistency').status -eq 'snapshot_match' -and $json -notmatch [regex]::Escape($cnGroup) -and $json -notmatch [regex]::Escape($cnNode)}
    }
    $privateOmitted=$json -notmatch '203\.0\.113\.27|MockPrivate|PRIVATE-|private-local-name|private-profile-uid|private-dns|PrivateGroup|987654321|123456789|MockService'
    $limitsCorrect=(Check $o 'runtime_current_configuration').status -eq 'unknown' -and -not $o.network_changed -and -not $o.public_requests_made -and -not $o.proxy_core_stopped -and $o.overall -ne 'pass'
    Record $case ([bool]$passed -and $privateOmitted -and $limitsCorrect -and $global:GuestMock_utf8) 'Offline mocks; status, UTF8 reading, private-value omission and live-acceptance limits checked'
}
. (Join-Path $SourceRoot 'Read-ClaudeCoreApi.ps1')
# Replace the transport factory in this test scope; no socket is opened.
function New-ClaudeCoreHttpRequest([Uri]$Uri) {
    $global:GuestMock_requests.Add([pscustomobject]@{path=$Uri.AbsolutePath;host=$Uri.Host})
    $request=[pscustomobject]@{Method='';Proxy='not-cleared';AllowAutoRedirect=$true;UseDefaultCredentials=$true;PreAuthenticate=$true;Timeout=0;ReadWriteTimeout=0;Headers=@{};MockUri=$Uri}
    $request|Add-Member ScriptMethod Abort {}
    $request|Add-Member ScriptMethod GetResponse {
        if($this.Method -ne 'GET' -or $null -ne $this.Proxy -or $this.AllowAutoRedirect -or $this.UseDefaultCredentials -or $this.PreAuthenticate -or $this.Timeout -ne 3000 -or $this.ReadWriteTimeout -ne 3000 -or $this.Headers.Authorization -ne 'Bearer PRIVATE-CONTROLLER-SECRET'){throw 'PRIVATE-TRANSPORT-DETAIL'}
        if($global:GuestMock_mode -in @('api-request-failure','runtime-api-failed')){throw 'PRIVATE-RAW-ERROR-WITH-SECRET'}
        $body=switch($this.MockUri.AbsolutePath){
            '/configs'{'{"mode":"rule","ipv6":false,"tun":{"enable":true}}'}
            '/proxies'{'{"proxies":{"PrivateGroup":{"now":"private-local-name"}}}'}
            '/connections'{'{"connections":[{"metadata":{"host":"PRIVATE-HOST"},"chains":["private-local-name"]}]}'}
            default {throw 'Unexpected endpoint'}
        }
        if($global:GuestMock_mode -eq 'api-invalid-json'){$body='PRIVATE-INVALID-JSON'}
        if($this.MockUri.AbsolutePath -eq '/configs'){
            if($global:GuestMock_mode -eq 'runtime-api-mode-conflict'){$body='{"mode":"global","tun":{"enable":true}}'}
            if($global:GuestMock_mode -eq 'runtime-api-tun-conflict'){$body='{"mode":"rule","tun":{"enable":false}}'}
            if($global:GuestMock_mode -eq 'runtime-api-missing-settings'){$body='{"mode":"rule"}'}
        }
        if($this.MockUri.AbsolutePath -eq '/proxies' -and $global:GuestMock_mode -eq 'runtime-api-groups-conflict'){$body='{"proxies":{"PrivateGroup":{"now":"PRIVATE-WRONG-NODE"}}}'}
        if($global:GuestMock_mode -eq 'api-oversized'){$body='x'*4194305}
        $response=[pscustomobject]@{StatusCode=$(if($global:GuestMock_mode -eq 'api-redirect'){302}else{200});MockBody=$body}
        $response|Add-Member ScriptMethod GetResponseStream {return New-Object IO.MemoryStream(,[Text.Encoding]::UTF8.GetBytes($this.MockBody))}
        $response|Add-Member ScriptMethod Dispose {}
        return $response
    }
    return $request
}
foreach($case in @('api-read','api-ipv6','api-nonloopback','api-hostname','api-owner-wrong','api-invalid-port','api-invalid-secret','api-redirect','api-request-failure','api-invalid-json','api-oversized')){
    $global:GuestMock_mode=$case;$global:GuestMock_requests=New-Object 'System.Collections.Generic.List[object]'
    $controller='127.0.0.1:9090';if($case -eq 'api-ipv6'){$controller='[::1]:9090'}
    if($case -eq 'api-nonloopback'){$controller='203.0.113.27:9090'}
    if($case -eq 'api-hostname'){$controller='private-host.example:9090'}
    if($case -eq 'api-invalid-port'){$controller='127.0.0.1:65536'}
    $apiConfig=@{'external-controller'=$controller;secret='PRIVATE-CONTROLLER-SECRET'}
    if($case -eq 'api-invalid-secret'){$apiConfig.secret=('PRIVATE-SECRET'+[Environment]::NewLine+'INJECTED')}
    $snapshot=Get-ClaudeCoreApiSnapshot -Config $apiConfig -CorePath 'D:\MockPrivate\core.exe'
    $ok=switch($case){
        'api-read'{$snapshot.state -eq 'read' -and $snapshot.controller_owner_verified -and $global:GuestMock_requests.Count -eq 3 -and ($global:GuestMock_requests.path -join ',') -eq '/configs,/proxies,/connections' -and $snapshot.proxies.proxies.PrivateGroup.now -eq 'private-local-name'}
        'api-ipv6'{$snapshot.state -eq 'read' -and $global:GuestMock_requests.Count -eq 3}
        'api-nonloopback'{$snapshot.state -eq 'unknown' -and $global:GuestMock_requests.Count -eq 0}
        'api-hostname'{$snapshot.state -eq 'unknown' -and $global:GuestMock_requests.Count -eq 0}
        'api-owner-wrong'{$snapshot.state -eq 'unknown' -and $snapshot.reason -eq 'controller_owner_unverified' -and $global:GuestMock_requests.Count -eq 0}
        'api-invalid-port'{$snapshot.state -eq 'unknown' -and $global:GuestMock_requests.Count -eq 0}
        'api-invalid-secret'{$snapshot.state -eq 'unknown' -and $global:GuestMock_requests.Count -eq 0}
        default {$snapshot.state -eq 'unknown' -and $snapshot.reason -eq 'controller_read_failed' -and $null -eq $snapshot.configs -and $null -eq $snapshot.proxies -and $null -eq $snapshot.connections}
    }
    $safeSummary=[pscustomobject]@{state=$snapshot.state;reason=$snapshot.reason;verified=$snapshot.controller_owner_verified}|ConvertTo-Json -Compress
    Record $case ([bool]$ok -and $safeSummary -notmatch 'PRIVATE-|private-local|PrivateGroup|203\.0\.113') 'Offline API transport: fixed GETs, verified owner, loopback, no proxy, no redirects, bounded response and redacted failures'
}
# Load the production guest body in memory with the already-loaded helper. Only the
# redundant helper dot-source is skipped, so the fake request factory stays in scope.
$guestBody=Microsoft.PowerShell.Management\Get-Content -LiteralPath $script -Raw -Encoding UTF8
$guestBody=$guestBody.Replace(". (Join-Path $"+'PSScriptRoot'+" 'Read-ClaudeCoreApi.ps1')",'# helper loaded by offline harness')
$guestBlock=[scriptblock]::Create($guestBody)
foreach($case in @('runtime-api-match','runtime-api-mode-conflict','runtime-api-tun-conflict','runtime-api-missing-settings','runtime-api-groups-conflict','runtime-api-failed')){
    $global:GuestMock_mode=$case;Fixture
    $global:GuestMock_requests=New-Object 'System.Collections.Generic.List[object]'
    $global:GuestMock_active['mode']='rule';$global:GuestMock_active['external-controller']='127.0.0.1:9090';$global:GuestMock_active['secret']='PRIVATE-CONTROLLER-SECRET'
    Save-Fixture
    $json=& $guestBlock -EvidencePath 'D:\MockPrivate\evidence.json' -ReadCoreApi
    $o=$json|ConvertFrom-Json
    $ok=switch($case){
        'runtime-api-match'{(Check $o 'runtime_effective_settings').status -eq 'snapshot_match' -and (Check $o 'group_selection_snapshot_consistency').status -eq 'snapshot_match' -and (Check $o 'runtime_current_configuration').details.live_core_api_queried -and (Check $o 'observed_core_first_hop_sockets').details.matching_socket_count -eq 1}
        'runtime-api-mode-conflict'{(Check $o 'runtime_effective_settings').status -eq 'fail'}
        'runtime-api-tun-conflict'{(Check $o 'runtime_effective_settings').status -eq 'fail'}
        'runtime-api-missing-settings'{(Check $o 'runtime_effective_settings').status -eq 'unknown' -and (Check $o 'runtime_effective_settings').details.missing_field_count -eq 1}
        'runtime-api-groups-conflict'{(Check $o 'group_selection_snapshot_consistency').status -eq 'fail'}
        'runtime-api-failed'{(Check $o 'runtime_current_configuration').status -eq 'unknown' -and (Check $o 'runtime_effective_settings').status -eq 'unknown' -and (Check $o 'group_selection_snapshot_consistency').status -eq 'unknown'}
    }
    $safe=$json -notmatch 'PRIVATE-|MockPrivate|private-local-name|PrivateGroup|203\.0\.113\.27'
    Record $case ([bool]$ok -and $safe -and -not $o.network_changed -and -not $o.public_requests_made) 'Offline integration: live-group precedence, mode/TUN consistency, established TCP matching and private output'
}
foreach ($case in 'split-first-hop','missing-approved-hop','extra-address','broad-prefix','proxy-pass','probe-listener-unavailable','probe-listener-wrong-owner','probe-listener-wildcard') {
    $global:GuestMock_mode = $case
    Fixture
    if ($case -in 'split-first-hop','missing-approved-hop','extra-address','broad-prefix') {
        $global:GuestMock_evidence.first_hop.addresses = @('203.0.113.27','203.0.113.28','2001:db8::27')
        $backup = switch ($case) {
            'split-first-hop' { '203.0.113.28/32','2001:0db8:0:0:0:0:0:27/128' }
            'missing-approved-hop' { '203.0.113.28/32' }
            'extra-address' { '203.0.113.28','2001:db8::27','203.0.113.29' }
            'broad-prefix' { '203.0.113.28/24','2001:db8::27' }
        }
        $global:GuestMock_rules += Rule 'D:\MockPrivate\core.exe' 'Any' @($backup) @('24443') @('MockEthernet')
    }
    Save-Fixture
    $json = & $script -EvidencePath 'D:\MockPrivate\evidence.json' -ProbeProxyPort 17897
    $report = $json | ConvertFrom-Json
    $hop = Check $report 'core_first_hop_rules'
    $proxy = Check $report 'loopback_probe_proxy'
    $ok = switch ($case) {
        'split-first-hop' { $hop.status -eq 'pass' -and $hop.details.exact_first_hop_rule_count -eq 2 -and $hop.details.covered_address_count -eq 3 }
        'missing-approved-hop' { $hop.status -eq 'fail' -and $hop.details.covered_address_count -eq 2 -and $hop.details.other_external_allow_count -eq 0 }
        'extra-address' { $hop.status -eq 'fail' -and $hop.details.other_external_allow_count -eq 1 }
        'broad-prefix' { $hop.status -eq 'fail' -and $hop.details.other_external_allow_count -eq 1 }
        'proxy-pass' { $proxy.status -eq 'pass' -and $proxy.details.owner_process_id -eq 42 }
        default { $proxy.status -eq 'fail' -and $null -eq $proxy.details.owner_process_id }
    }
    Record $case ([bool]$ok -and $json -notmatch '203\.0\.113\.|2001:db8|MockPrivate') 'Exact approved addresses may be split across rules; proxy must belong to the expected core and listen locally.'
}
[pscustomobject]@{powershell=$PSVersionTable.PSVersion.ToString();total=$global:GuestMock_cases.Count;failed=@($global:GuestMock_cases|Where-Object {-not $_.passed}).Count;results=@($global:GuestMock_cases.ToArray())}|ConvertTo-Json -Depth 6
