#requires -Version 5.1
[CmdletBinding()]
param([string]$EvidencePath,[switch]$ReadCoreApi,[ValidateRange(1,65535)][int]$ProbeProxyPort)
# Read-only. The optional evidence file remains private and is never echoed.
$ErrorActionPreference='Stop'
$checks=New-Object 'System.Collections.Generic.List[object]'
function Add-Check([string]$Name,[string]$Status,$Details) {
    $checks.Add([pscustomobject]@{check=$Name;status=$Status;details=$Details})
}
function Value($Object,[string]$Name) {
    if($null -eq $Object){return $null}
    if($Object -is [Collections.IDictionary]){return $Object[$Name]}
    $property=$Object.PSObject.Properties[$Name]
    if($null -ne $property){return $property.Value}
    return $null
}
function Names($Object) {
    if($Object -is [Collections.IDictionary]){return @($Object.Keys)}
    if($null -ne $Object){return @($Object.PSObject.Properties.Name)}
    return @()
}
function Strings($Object) { return @($Object | ForEach-Object {[string]$_} | Where-Object {$_}) }
function Local-Path([string]$Path) {
    if($Path -notmatch '^[A-Za-z]:[\\/]'){throw 'Local absolute path required'}
    return [IO.Path]::GetFullPath($Path)
}
function Read-Object([string]$Path) {
    if(-not $Path){return [pscustomobject]@{state='unknown';data=$null;format='none'}}
    try {
        $raw=Get-Content -LiteralPath (Local-Path $Path) -Raw -Encoding UTF8
        try {return [pscustomobject]@{state='read';data=($raw | ConvertFrom-Json);format='json'}}catch{}
        if(Get-Command ConvertFrom-Yaml -ErrorAction SilentlyContinue){
            return [pscustomobject]@{state='read';data=($raw | ConvertFrom-Yaml);format='existing_yaml_parser'}
        }
        return [pscustomobject]@{state='unknown';data=$null;format='yaml_parser_unavailable_or_invalid_json'}
    }catch{return [pscustomobject]@{state='unknown';data=$null;format='read_failed'}}
}
function Canonical($Object) {
    if($null -eq $Object){return 'null'}
    if($Object -is [string] -or $Object -is [ValueType]){return (ConvertTo-Json -InputObject $Object -Compress)}
    if($Object -is [Collections.IDictionary] -or $Object -is [pscustomobject]){
        $entries=@(Names $Object | Sort-Object | ForEach-Object {
            (ConvertTo-Json -InputObject ([string]$_) -Compress)+':'+(Canonical (Value $Object $_))
        })
        return '{'+($entries -join ',')+'}'
    }
    return '['+(@($Object | ForEach-Object {Canonical $_}) -join ',')+']'
}
function Same-Set($Left,$Right) {
    $a=@(Strings $Left | Sort-Object -Unique);$b=@(Strings $Right | Sort-Object -Unique)
    return ($a.Count -eq $b.Count -and ($a -join [char]0) -eq ($b -join [char]0))
}
function Is-Any($Object) {
    $a=@(Strings $Object)
    return ($a.Count -eq 0 -or @($a | Where-Object {$_ -notin @('Any','*','NotConfigured')}).Count -eq 0)
}
function Only-Loopback($Addresses) {
    $a=@(Strings $Addresses)
    if($a.Count -eq 0){return $false}
    foreach($entry in $a){
        $ip=$null
        if(-not [Net.IPAddress]::TryParse($entry,[ref]$ip) -or -not [Net.IPAddress]::IsLoopback($ip)){return $false}
    }
    return $true
}
function Valid-Port($Port) {
    $number=0
    return ([string]$Port -match '^\d{1,5}$' -and [int]::TryParse([string]$Port,[ref]$number) -and $number -ge 1 -and $number -le 65535)
}
function Concrete-Addresses($Addresses) {
    $entries=@(Strings $Addresses)
    if(-not $entries.Count){return $false}
    foreach($entry in $entries){
        $ip=$null
        if($entry -match '[/,%*]' -or -not [Net.IPAddress]::TryParse($entry,[ref]$ip)){return $false}
        if($ip.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork -and $entry -notmatch '^\d{1,3}(?:\.\d{1,3}){3}$'){return $false}
        if($ip.Equals([Net.IPAddress]::Any) -or $ip.Equals([Net.IPAddress]::IPv6Any)){return $false}
    }
    return $true
}
function Single-HostAddresses($Values) {
    $addresses = New-Object 'System.Collections.Generic.List[string]'
    foreach ($entry in @(Strings $Values)) {
        $parts = $entry.Split('/')
        if ($parts.Count -gt 2 -or -not (Concrete-Addresses @($parts[0]))) { return }
        $ip = [Net.IPAddress]::Parse($parts[0])
        $bits = if ($ip.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork) { '32' } else { '128' }
        if ($parts.Count -eq 2 -and $parts[1] -ne $bits) { return }
        $addresses.Add($ip.ToString())
    }
    return $addresses.ToArray()
}
function Complete-Node($Node) {
    $type=Value $Node 'type';$server=Value $Node 'server'
    if($type -isnot [string] -or $server -isnot [string] -or -not $server.Trim() -or -not (Valid-Port (Value $Node 'port'))){return $false}
    $required=switch($type){'vless'{@('uuid')};'vmess'{@('uuid')};'ss'{@('cipher','password')};'trojan'{@('password')};'socks5'{@()};'http'{@()};default{return $false}}
    foreach($key in $required){$v=Value $Node $key;if($v -isnot [string] -or -not $v.Trim()){return $false}}
    return $true
}
function Node-Differences($Left,$Right) {
    foreach($field in @((Names $Left)+(Names $Right) | Sort-Object -Unique | Where-Object {$_ -ne 'name'})){
        if(((Names $Left) -contains $field) -ne ((Names $Right) -contains $field) -or (Canonical (Value $Left $field)) -cne (Canonical (Value $Right $field))){$field}
    }
}
function Public-Fields($Fields) {
    @($Fields | ForEach-Object {
        if($_ -cin @('type','server','port','uuid','password','username','tls','udp','network','flow','servername','sni','client-fingerprint','reality-opts','ws-opts','grpc-opts','http-opts','h2-opts','dialer-proxy','skip-cert-verify','alpn','cipher','alterId','encryption','certificate','private-key','public-key','ip-version','tfo','mptcp','smux','obfs','obfs-password')){$_}else{'other_field'}
    } | Sort-Object -Unique)
}
$evidence=$null
if($EvidencePath){
    $loaded=Read-Object $EvidencePath
    if($loaded.state -eq 'read' -and $loaded.format -eq 'json'){$evidence=$loaded.data;Add-Check 'private_evidence' 'snapshot' @{read=$true}}
    else{Add-Check 'private_evidence' 'unknown' @{read=$false}}
}
$corePath=[string](Value $evidence 'core_path')
$tunAlias=[string](Value $evidence 'tun_interface_alias')
$protectedPaths=@(Strings (Value $evidence 'protected_program_paths'))
$protectedPackages=@(Strings (Value $evidence 'protected_package_sids'))
$coreLive=$false;$coreProcessId=$null;$tunLive=$false;$nativeProfiles=$null;$nativeRules=$null;$rulesComplete=$false
$blockRules=New-Object 'System.Collections.Generic.List[object]';$blocksComplete=$false
try {
    $processes=@(Get-Process -ErrorAction Stop | Where-Object {$_.ProcessName -match 'clash|mihomo'})
    if($corePath){
        $matches=@($processes | Where-Object {$_.Path -and $_.Path -eq $corePath})
        $coreLive=$matches.Count -eq 1
        if($coreLive -and [int]$matches[0].Id -gt 0){$coreProcessId=[int]$matches[0].Id}
        $status=if($coreLive){'pass'}else{'fail'}
        Add-Check 'specified_core_process' $status @{exact_path_running=$coreLive;matching_process_count=$matches.Count;candidate_count=$processes.Count}
    }else{Add-Check 'specified_core_process' 'unknown' @{candidate_count=$processes.Count;expected_path_supplied=$false}}
}catch{Add-Check 'specified_core_process' 'unknown' @{inventory_available=$false}}
if ($PSBoundParameters.ContainsKey('ProbeProxyPort')) {
    $owner = $null
    $status = 'unknown'
    if ($coreProcessId) {
        try {
            . (Join-Path $PSScriptRoot 'Read-ClaudeCoreApi.ps1')
            $owner = Get-ClaudeProbeProxyOwner $ProbeProxyPort
            $status = if ($owner -eq $coreProcessId) { 'pass' } else { 'fail' }
        } catch { $status = 'fail' }
    }
    Add-Check 'loopback_probe_proxy' $status @{ owner_process_id = $(if ($status -eq 'pass') { $owner } else { $null }) }
}
try {
    $adapters=@(Get-NetAdapter -ErrorAction Stop)
    if($tunAlias){
        $tunLive=@($adapters | Where-Object {$_.Name -eq $tunAlias -and $_.Status -eq 'Up'}).Count -eq 1
        $status=if($tunLive){'pass'}else{'fail'}
        Add-Check 'specified_tun_adapter' $status @{specified_adapter_up=$tunLive}
    }else{Add-Check 'specified_tun_adapter' 'unknown' @{expected_interface_supplied=$false;adapter_count=$adapters.Count}}
}catch{Add-Check 'specified_tun_adapter' 'unknown' @{inventory_available=$false}}
try {
    $nativeProfiles=@(Get-NetFirewallProfile -PolicyStore ActiveStore -ErrorAction Stop)
    $missing=0;$unsafe=0
    foreach($name in @('Domain','Private','Public')){
        $p=@($nativeProfiles | Where-Object {$_.Name -eq $name})
        if($p.Count -ne 1){$missing++}elseif([string]$p[0].Enabled -notin @('True','1') -or [string]$p[0].DefaultOutboundAction -ne 'Block'){$unsafe++}
    }
    $status=if($unsafe){'fail'}elseif($missing){'unknown'}else{'pass'}
    Add-Check 'effective_firewall_profiles' $status @{all_three_present=($missing -eq 0);all_three_enabled_default_block=($unsafe -eq 0 -and $missing -eq 0)}
}catch{Add-Check 'effective_firewall_profiles' 'unknown' @{inventory_available=$false}}
try {
    $active=@(Get-NetFirewallRule -PolicyStore ActiveStore -Direction Outbound -Enabled True -ErrorAction Stop | Where-Object {[string]$_.Action -eq 'Allow'})
    $nativeRules=New-Object 'System.Collections.Generic.List[object]';$rulesComplete=$true
    foreach($rule in $active){
        try {
            $app=@($rule | Get-NetFirewallApplicationFilter -ErrorAction Stop)
            $address=@($rule | Get-NetFirewallAddressFilter -ErrorAction Stop)
            $port=@($rule | Get-NetFirewallPortFilter -ErrorAction Stop)
            $iface=@($rule | Get-NetFirewallInterfaceFilter -ErrorAction Stop)
            $service=@($rule | Get-NetFirewallServiceFilter -ErrorAction Stop)
            $security=@($rule | Get-NetFirewallSecurityFilter -ErrorAction Stop)
            if($app.Count -ne 1 -or $address.Count -ne 1 -or $port.Count -ne 1 -or $iface.Count -ne 1 -or $service.Count -ne 1 -or $security.Count -ne 1){throw 'Incomplete filters'}
            foreach($pair in @(@($app[0],'Program'),@($app[0],'Package'),@($address[0],'RemoteAddress'),@($port[0],'RemotePort'),@($port[0],'Protocol'),@($iface[0],'InterfaceAlias'),@($service[0],'Service'),@($security[0],'LocalUser'))){if($null -eq (Value $pair[0] $pair[1])){throw 'Incomplete filter property'}}
            $nativeRules.Add([pscustomobject]@{program=$app[0].Program;package=$app[0].Package;local_user=$security[0].LocalUser;service=$service[0].Service;addresses=$address[0].RemoteAddress;ports=$port[0].RemotePort;protocol=$port[0].Protocol;interfaces=$iface[0].InterfaceAlias;profiles=$rule.Profile})
        }catch{$rulesComplete=$false}
    }
    Add-Check 'effective_allow_rule_filters' $(if($rulesComplete){'pass'}else{'unknown'}) @{rule_count=$active.Count;complete_filter_count=$nativeRules.Count;package_and_user_scope_checked=$true}
}catch{Add-Check 'effective_allow_rule_filters' 'unknown' @{inventory_available=$false}}
try {
    $blocks=@(Get-NetFirewallRule -PolicyStore ActiveStore -Direction Outbound -Enabled True -ErrorAction Stop | Where-Object {[string]$_.Action -eq 'Block'})
    $blocksComplete=$true
    foreach($rule in $blocks){
        try {
            $app=@($rule | Get-NetFirewallApplicationFilter -ErrorAction Stop);$addr=@($rule | Get-NetFirewallAddressFilter -ErrorAction Stop)
            $port=@($rule | Get-NetFirewallPortFilter -ErrorAction Stop);$iface=@($rule | Get-NetFirewallInterfaceFilter -ErrorAction Stop)
            $service=@($rule | Get-NetFirewallServiceFilter -ErrorAction Stop);$security=@($rule | Get-NetFirewallSecurityFilter -ErrorAction Stop)
            $ifaceType=@($rule | Get-NetFirewallInterfaceTypeFilter -ErrorAction Stop)
            if($app.Count -ne 1 -or $addr.Count -ne 1 -or $port.Count -ne 1 -or $iface.Count -ne 1 -or $service.Count -ne 1 -or $security.Count -ne 1 -or $ifaceType.Count -ne 1){throw 'Incomplete block filters'}
            $blockRules.Add([pscustomobject]@{program=$app[0].Program;package=$app[0].Package;local_user=$security[0].LocalUser;remote_user=$security[0].RemoteUser;remote_machine=$security[0].RemoteMachine;service=$service[0].Service;addresses=$addr[0].RemoteAddress;local_addresses=$addr[0].LocalAddress;ports=$port[0].RemotePort;local_ports=$port[0].LocalPort;protocol=$port[0].Protocol;interfaces=$iface[0].InterfaceAlias;interface_types=$ifaceType[0].InterfaceType;profiles=$rule.Profile})
        }catch{$blocksComplete=$false}
    }
}catch{$blocksComplete=$false}
$firstHop=Value $evidence 'first_hop'
$expectedAddresses=@(Strings (Value $firstHop 'addresses'))
$expectedPort=[string](Value $firstHop 'port');$expectedProtocol=[string](Value $firstHop 'protocol');$outbound=[string](Value $firstHop 'interface_alias')
$hasFirstHop=$corePath -and (Concrete-Addresses $expectedAddresses) -and (Valid-Port $expectedPort) -and $expectedProtocol -in @('TCP','UDP','6','17') -and -not (Is-Any $outbound) -and $outbound -ne $tunAlias
$approvedAddresses = @(Single-HostAddresses $expectedAddresses | Sort-Object -Unique)
$coveredAddresses = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$socketMatches=$null;$socketInventory=$false
if($coreProcessId -and $hasFirstHop -and $expectedProtocol -in @('TCP','6')){
    try {
        $sockets=@(Get-NetTCPConnection -OwningProcess $coreProcessId -State Established -ErrorAction Stop)
        $socketMatches=@($sockets | Where-Object {[int]$_.OwningProcess -eq $coreProcessId -and [string]$_.RemoteAddress -in $expectedAddresses -and [string]$_.RemotePort -eq $expectedPort}).Count
        $socketInventory=$true
    }catch{}
}
Add-Check 'observed_core_first_hop_sockets' $(if($socketMatches -gt 0){'snapshot_match'}else{'unknown'}) @{matching_socket_count=$socketMatches;socket_inventory_available=$socketInventory;only_established_tcp_checked=$true;outgoing_interface_not_verified=$true;no_new_connections_generated=$true;no_match_does_not_prove_failure=$true}
$coreBroad=0;$protectedBroad=0;$exactFirstHop=0;$unresolved=0;$packageRestricted=0
if($null -ne $nativeRules){
    foreach($rule in $nativeRules){
        $programAny=Is-Any $rule.program;$packageAny=Is-Any $rule.package;$userAny=Is-Any $rule.local_user;$serviceAny=Is-Any $rule.service
        if($programAny -and -not $packageAny){$packageRestricted++}
        $global=$programAny -and $packageAny -and $userAny -and $serviceAny
        $program = [Environment]::ExpandEnvironmentVariables([string]$rule.program)
        $coreApplies=$corePath -and ($program -eq $corePath -or $global)
        $protectedApplies=$global -or @($protectedPaths | Where-Object {$_ -eq $program}).Count -gt 0 -or @($protectedPackages | Where-Object {$_ -eq $rule.package}).Count -gt 0
        # Program=Any with a package/user/service constraint is not a global application allow.
        if($programAny -and $packageAny -and (-not $userAny -or -not $serviceAny)){$unresolved++}
        $viaTun=$tunAlias -and (Same-Set $rule.interfaces @($tunAlias))
        $local=Only-Loopback $rule.addresses
        $protocol=[string]$rule.protocol
        if($protocol -eq '6'){$protocol='TCP'}elseif($protocol -eq '17'){$protocol='UDP'}
        $wantedProtocol=$expectedProtocol
        if($wantedProtocol -eq '6'){$wantedProtocol='TCP'}elseif($wantedProtocol -eq '17'){$wantedProtocol='UDP'}
        $ruleAddresses = @(Single-HostAddresses $rule.addresses)
        $exact = $hasFirstHop -and $program -eq $corePath -and $packageAny -and $userAny -and $serviceAny -and
            $ruleAddresses.Count -gt 0 -and @($ruleAddresses | Where-Object { $_ -notin $approvedAddresses }).Count -eq 0 -and
            (Same-Set $rule.ports @($expectedPort)) -and $protocol -eq $wantedProtocol -and
            (Same-Set $rule.interfaces @($outbound)) -and (Same-Set $rule.profiles @('Any'))
        if ($exact) {
            $exactFirstHop++
            foreach ($address in $ruleAddresses) { [void]$coveredAddresses.Add($address) }
        }
        if($coreApplies -and -not $exact -and -not $local -and -not $viaTun){$coreBroad++}
        if($protectedApplies -and -not $local -and -not $viaTun){$protectedBroad++}
    }
}
$coreRuleStatus=if(-not $hasFirstHop){'unknown'}elseif($coreBroad){'fail'}elseif(-not $rulesComplete -or $unresolved){'unknown'}elseif($coveredAddresses.Count -ne $approvedAddresses.Count){'fail'}else{'pass'}
Add-Check 'core_first_hop_rules' $coreRuleStatus @{exact_first_hop_rule_count=$exactFirstHop;approved_address_count=$approvedAddresses.Count;covered_address_count=$coveredAddresses.Count;other_external_allow_count=$coreBroad;complete_expected_hop_supplied=[bool]$hasFirstHop;unresolved_service_or_user_rules=$unresolved}
$protectedStatus=if($protectedBroad){'fail'}elseif(-not $rulesComplete -or ($protectedPaths.Count+$protectedPackages.Count) -eq 0 -or -not $tunAlias -or $unresolved){'unknown'}else{'pass'}
Add-Check 'protected_application_rules' $protectedStatus @{unrestricted_external_allow_count=$protectedBroad;package_restricted_any_program_count=$packageRestricted;protected_object_count=($protectedPaths.Count+$protectedPackages.Count);unresolved_service_or_user_rules=$unresolved}
$confirmedBlocks=0;$uncertainBlocks=0
foreach($rule in $blockRules){
    if($corePath -and $rule.program -and -not (Is-Any $rule.program) -and $rule.program -ne $corePath){continue}
    $complete=$true
    foreach($field in @('program','package','local_user','remote_user','remote_machine','service','addresses','local_addresses','ports','local_ports','protocol','interfaces','interface_types','profiles')){if($null -eq (Value $rule $field)){$complete=$false}}
    $proto=[string]$rule.protocol;if($proto -eq '6'){$proto='TCP'}elseif($proto -eq '17'){$proto='UDP'}
    $want=$expectedProtocol;if($want -eq '6'){$want='TCP'}elseif($want -eq '17'){$want='UDP'}
    $scopeKnown=$complete -and $hasFirstHop -and (Is-Any $rule.package) -and (Is-Any $rule.local_user) -and (Is-Any $rule.remote_user) -and (Is-Any $rule.remote_machine) -and (Is-Any $rule.service) -and (Is-Any $rule.local_addresses) -and (Is-Any $rule.local_ports) -and (Is-Any $rule.interface_types) -and (Same-Set $rule.profiles @('Any'))
    $addressMatch=(Is-Any $rule.addresses) -or @($expectedAddresses | Where-Object {$_ -in @(Strings $rule.addresses)}).Count -gt 0
    $portMatch=(Is-Any $rule.ports) -or $expectedPort -in @(Strings $rule.ports)
    $interfaceMatch=(Is-Any $rule.interfaces) -or $outbound -in @(Strings $rule.interfaces)
    if($scopeKnown -and $addressMatch -and $portMatch -and $interfaceMatch -and ($proto -in @('Any','256') -or $proto -eq $want)){$confirmedBlocks++}else{$uncertainBlocks++}
}
Add-Check 'first_hop_explicit_block_conflicts' $(if($confirmedBlocks){'fail'}else{'unknown'}) @{confirmed_overlapping_rules=$confirmedBlocks;unresolved_rule_count=$uncertainBlocks;inventory_complete=$blocksComplete;all_windows_policy_exceptions_checked=$false;no_conflict_is_not_proven=$true}
$configs=@{}
foreach($kind in @('active','verge','profiles','subscription','persisted')){
    $configs[$kind]=Read-Object ([string](Value $evidence ($kind+'_config_path')))
    Add-Check ($kind+'_configuration_read') $(if($configs[$kind].state -eq 'read'){'snapshot'}else{'unknown'}) @{format=$configs[$kind].format;read=($configs[$kind].state -eq 'read')}
}
$config=$configs.active.data;$dns=Value $config 'dns';$tun=Value $config 'tun'
$dnsEnabled=Value $dns 'enable';$dnsIpv6=Value $dns 'ipv6';$topIpv6=Value $config 'ipv6'
if($dnsEnabled -isnot [bool]){$dnsEnabled=$null};if($dnsIpv6 -isnot [bool]){$dnsIpv6=$null};if($topIpv6 -isnot [bool]){$topIpv6=$null}
$tunEnabled=Value $tun 'enable';if($tunEnabled -isnot [bool]){$tunEnabled=$null}
$nameservers=@(Strings (Value $dns 'nameserver'));$hijack=@(Strings (Value $tun 'dns-hijack'))
$udp53=@($hijack | Where-Object {$_ -match '^(?:udp://)?(?:any|0\.0\.0\.0|\*):53$'}).Count -gt 0
$tcp53=@($hijack | Where-Object {$_ -match '^tcp://(?:any|0\.0\.0\.0|\*):53$'}).Count -gt 0
$dnsGroup=[string](Value $evidence 'dns_proxy_group')
$groupPinned=$null
if($dnsGroup -and $nameservers.Count){$groupPinned=@($nameservers | Where-Object {$_ -notmatch ('#'+[regex]::Escape($dnsGroup)+'(?:&|$)')}).Count -eq 0}
$override=Value $configs.verge.data 'enable_dns_override'
if($override -isnot [bool]){$override=$null}
Add-Check 'dns_override_display' $(if($null -ne $override){'snapshot'}else{'unknown'}) @{override_enabled=$override;override_is_not_dns_enable=$true}
$dnsStatus=if($dnsEnabled -eq $false -or $tunEnabled -eq $false -or ($null -ne $dnsEnabled -and $nameservers.Count -eq 0) -or $groupPinned -eq $false){'fail'}elseif($dnsEnabled -ne $true -or $tunEnabled -ne $true -or -not $tcp53 -or -not $udp53 -or $null -eq $groupPinned){'unknown'}else{'pass'}
Add-Check 'dns_configuration' $dnsStatus @{dns_enabled=$dnsEnabled;tun_enabled=$tunEnabled;nameserver_count=$nameservers.Count;all_nameservers_explicitly_pinned_to_expected_group=$groupPinned;udp53_hijack=$udp53;tcp53_hijack=$tcp53;dns_ipv6=$dnsIpv6;core_ipv6=$topIpv6;configuration_is_not_leak_test=$true}
$profileUid=[string](Value $evidence 'expected_profile_uid');$currentUid=[string](Value $configs.profiles.data 'current')
Add-Check 'active_profile_selection' $(if(-not $profileUid -or -not $currentUid){'unknown'}elseif($profileUid -eq $currentUid){'pass'}else{'fail'}) @{expected_profile_matches_saved_current=$(if($profileUid -and $currentUid){$profileUid -eq $currentUid}else{$null});saved_file_is_not_runtime=$true}
$coreApi=$null
if($ReadCoreApi){
    try {
        . (Join-Path $PSScriptRoot 'Read-ClaudeCoreApi.ps1')
        $coreApi=Get-ClaudeCoreApiSnapshot -Config $config -CorePath $corePath
    }catch{$coreApi=[pscustomobject]@{state='unknown';reason='helper_unavailable';controller_owner_verified=$false}}
}
$apiRead=$null -ne $coreApi -and $coreApi.state -eq 'read'
Add-Check 'runtime_current_configuration' $(if($apiRead){'snapshot'}else{'unknown'}) @{live_core_api_requested=[bool]$ReadCoreApi;live_core_api_queried=$apiRead;controller_owner_verified=($null -ne $coreApi -and $coreApi.controller_owner_verified);reason=$(if($coreApi){$coreApi.reason}else{'not_requested'});complete_runtime_node_parameters_available=$false;complete_runtime_dns_configuration_available=$false}
Add-Check 'runtime_connections_snapshot' $(if($apiRead -and $null -ne (Value $coreApi.connections 'connections')){'snapshot'}else{'unknown'}) @{connection_count=$(if($apiRead){@(Value $coreApi.connections 'connections').Count}else{$null});current_connections_only=$true;no_test_traffic_generated=$true;actual_success_not_proven=$true}
$effectiveCompared=0;$effectiveMissing=0;$effectiveConflict=0
foreach($field in @('mode','tun.enable')){
    $fileValue=$null;$apiValue=$null
    if($field -eq 'mode'){
        $fileValue=Value $config 'mode';if($apiRead){$apiValue=Value $coreApi.configs 'mode'}
        if($fileValue -isnot [string] -or $fileValue -notin @('rule','global','direct')){$fileValue=$null}
        if($apiValue -isnot [string] -or $apiValue -notin @('rule','global','direct')){$apiValue=$null}
    }else{
        $fileValue=Value (Value $config 'tun') 'enable';if($apiRead){$apiValue=Value (Value $coreApi.configs 'tun') 'enable'}
        if($fileValue -isnot [bool]){$fileValue=$null};if($apiValue -isnot [bool]){$apiValue=$null}
    }
    if($null -eq $fileValue -or $null -eq $apiValue){$effectiveMissing++}else{$effectiveCompared++;if($fileValue -ne $apiValue){$effectiveConflict++}}
}
Add-Check 'runtime_effective_settings' $(if($effectiveConflict){'fail'}elseif($effectiveMissing){'unknown'}else{'snapshot_match'}) @{fields_considered=@('mode','tun.enable');compared_field_count=$effectiveCompared;missing_field_count=$effectiveMissing;conflicting_field_count=$effectiveConflict;api_is_not_complete_dns_or_node_configuration=$true}
$expected=Value $evidence 'expected_group_selections';$saved=Value $evidence 'saved_group_selections';$runtime=Value $evidence 'runtime_group_selections'
if($ReadCoreApi){
    $runtime=$null
    if($apiRead){
        $runtime=@{};$apiProxies=Value $coreApi.proxies 'proxies'
        foreach($name in @(Names $apiProxies)){$now=Value (Value $apiProxies $name) 'now';if($null -ne $now){$runtime[$name]=$now}}
    }
}
if($null -eq $saved -and $currentUid){
    $saved=@{}
    $item=@((Value $configs.profiles.data 'items') | Where-Object {(Value $_ 'uid') -eq $currentUid})
    if($item.Count -eq 1){foreach($selection in @(Value $item[0] 'selected')){$n=[string](Value $selection 'name');if($n){$saved[$n]=Value $selection 'now'}}}
}
$selectionCount=@(Names $expected).Count;$missingSelection=0;$selectionConflicts=0
foreach($group in @(Names $expected)){
    $want=Value $expected $group;$persisted=Value $saved $group;$running=Value $runtime $group
    if($null -eq $persisted -or $null -eq $running){$missingSelection++}
    if(($null -ne $persisted -and $want -ne $persisted) -or ($null -ne $running -and $want -ne $running)){$selectionConflicts++}
}
Add-Check 'group_selection_snapshot_consistency' $(if($selectionConflicts){'fail'}elseif(-not $selectionCount -or $missingSelection){'unknown'}else{'snapshot_match'}) @{group_count=$selectionCount;missing_group_count=$missingSelection;conflicting_group_count=$selectionConflicts}
$checkedAt=[DateTimeOffset]::MinValue;$maxAge=24.0;$maxAgeInput=Value $evidence 'subscription_max_age_hours'
$maxAgeValid=$true
if($null -ne $maxAgeInput){$maxAgeValid=[double]::TryParse([string]$maxAgeInput,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$maxAge) -and $maxAge -gt 0 -and $maxAge -le 8760}
$checkedText=Value $evidence 'subscription_checked_at_utc'
$validTime=$false
if($checkedText -is [DateTimeOffset]){$checkedAt=$checkedText;$validTime=$checkedAt.Offset -eq [TimeSpan]::Zero}
elseif($checkedText -is [DateTime] -and $checkedText.Kind -ne [DateTimeKind]::Unspecified){$checkedAt=[DateTimeOffset]$checkedText;$validTime=$true}
elseif($checkedText -is [string]){$validTime=$checkedText -match '(?:Z|[+]00:00)$' -and [DateTimeOffset]::TryParse($checkedText,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::None,[ref]$checkedAt)}
$ageHours=if($validTime){([DateTimeOffset]::UtcNow-$checkedAt).TotalHours}else{$null}
$fresh=$maxAgeValid -and $validTime -and $ageHours -ge 0 -and $ageHours -le $maxAge
Add-Check 'subscription_snapshot_freshness' $(if($fresh){'snapshot'}else{'unknown'}) @{age_hours=$(if($validTime){[Math]::Round($ageHours,2)}else{$null});maximum_age_hours=$(if($maxAgeValid){$maxAge}else{$null});freshness_claim_is_agent_supplied=$true;subscription_downloaded_by_script=$false}
$pairs=@(Value $evidence 'node_pairs' | Where-Object {$null -ne $_})
if(-not $pairs.Count){$pairs=@([pscustomobject]@{local_node_name=(Value $evidence 'local_node_name');subscription_node_name=(Value $evidence 'subscription_node_name');persisted_node_name=(Value $evidence 'persisted_node_name');allowed_local_override_fields=(Value $evidence 'allowed_local_override_fields')})}
$pairResults=New-Object 'System.Collections.Generic.List[object]';$pairNumber=0
foreach($pair in $pairs){
    $pairNumber++;$localName=[string](Value $pair 'local_node_name');$remoteName=[string](Value $pair 'subscription_node_name')
    $persistedName=[string](Value $pair 'persisted_node_name');if(-not $persistedName){$persistedName=$localName}
    $localNode=@((Value $config 'proxies') | Where-Object {(Value $_ 'name') -eq $localName})
    $remoteNode=@((Value $configs.subscription.data 'proxies') | Where-Object {(Value $_ 'name') -eq $remoteName})
    $persistedNode=@((Value $configs.persisted.data 'proxies') | Where-Object {(Value $_ 'name') -eq $persistedName})
    $comparable=$localName -and $remoteName -and $localNode.Count -eq 1 -and $remoteNode.Count -eq 1
    if($comparable){$comparable=(Complete-Node $localNode[0]) -and (Complete-Node $remoteNode[0])}
    $allowed=@(Strings (Value $pair 'allowed_local_override_fields'));$invalidAllowed=@($allowed | Where-Object {$_ -cnotin @('dialer-proxy','udp','tfo','mptcp','smux','ip-version')})
    $changed=@();$approved=@();$unexpected=@()
    if($comparable){$changed=@(Node-Differences $localNode[0] $remoteNode[0]);$approved=@($changed | Where-Object {$_ -cin $allowed -and $_ -cin @('dialer-proxy','udp','tfo','mptcp','smux','ip-version')});$unexpected=@($changed | Where-Object {$_ -cnotin $approved})}
    $nodeStatus=if($unexpected.Count){'fail'}elseif(-not $comparable -or $invalidAllowed.Count -or -not $fresh){'unknown'}else{'pass'}
    $persistedComparable=$localName -and $persistedNode.Count -eq 1 -and $localNode.Count -eq 1
    if($persistedComparable){$persistedComparable=(Complete-Node $persistedNode[0]) -and (Complete-Node $localNode[0])}
    $persistedChanged=@();if($persistedComparable){$persistedChanged=@(Node-Differences $persistedNode[0] $localNode[0])}
    $persistedStatus=if(-not $persistedComparable){'unknown'}elseif($persistedChanged.Count){'fail'}else{'snapshot_match'}
    $pairResults.Add([pscustomobject]@{pair_index=$pairNumber;status=$nodeStatus;parameters_comparable=[bool]$comparable;all_parameters_equal=$(if($comparable){$changed.Count -eq 0}else{$null});changed_field_names=@(Public-Fields $unexpected);approved_local_override_fields=@(Public-Fields $approved);invalid_override_field_count=$invalidAllowed.Count;persisted_status=$persistedStatus;persisted_changed_field_names=@(Public-Fields $persistedChanged)})
}
$nodeStatus=if(@($pairResults | Where-Object status -eq 'fail').Count){'fail'}elseif(@($pairResults | Where-Object status -eq 'unknown').Count){'unknown'}else{'pass'}
Add-Check 'selected_node_parameters' $nodeStatus @{complete_node_parameters_match=$(if(@($pairResults | Where-Object {-not $_.parameters_comparable}).Count){$null}else{@($pairResults | Where-Object {-not $_.all_parameters_equal}).Count -eq 0});match_except_confirmed_local_overrides=($nodeStatus -eq 'pass');changed_field_names=@($pairResults | ForEach-Object {$_.changed_field_names} | Sort-Object -Unique);pair_count=$pairResults.Count;pairs=@($pairResults.ToArray());display_name_excluded=$true;subscription_source_is_local_snapshot=$true;runtime_complete_parameters_not_available=$true}
$persistedStatus=if(@($pairResults | Where-Object persisted_status -eq 'fail').Count){'fail'}elseif(@($pairResults | Where-Object persisted_status -eq 'unknown').Count){'unknown'}else{'snapshot_match'}
Add-Check 'persisted_generated_node_consistency' $persistedStatus @{pair_count=$pairResults.Count;persisted_input_must_be_actual_regeneration_source=$true;source_file_authority_not_automatically_proven=$true}
$failed=@($checks | Where-Object status -eq 'fail').Count
[ordered]@{
    checked_at_utc=[DateTime]::UtcNow.ToString('o');mode='read_only';overall=$(if($failed){'issues_found'}else{'review_required'})
    live_collection=@('local_processes','local_adapters','ActiveStore_firewall')+$(if($socketInventory){@('core_established_tcp_sockets')}else{@()})+$(if($apiRead){@('verified_loopback_core_api_get')}else{@()});checks=@($checks.ToArray())
    private_values_recorded=$false;network_changed=$false;public_requests_made=$false;proxy_core_stopped=$false
    not_tested=@('Complete live core node credentials and DNS configuration','Actual browser DNS/WebRTC/IPv6 leakage','Proxy-core shutdown and recovery','Guest reboot and application updates','Claude login and conversation','Subscription availability and authenticity of supplied freshness time','All Windows policy exceptions and complex explicit block scopes')
} | ConvertTo-Json -Depth 9
