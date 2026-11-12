#requires -Version 5.1
[CmdletBinding()]
param([string]$EvidencePath,[switch]$ReadCoreApi)
# Read-only: private JSON input; no probes, reloads, rules or policy changes.
$ErrorActionPreference='Stop'
function HP-Value($Object,[string]$Name) {
    if($null -eq $Object){return $null}
    if($Object -is [Collections.IDictionary]){return $Object[$Name]}
    $p=$Object.PSObject.Properties[$Name];if($null -ne $p){return $p.Value}
    return $null
}
function HP-LocalPath([string]$Path) {
    if($Path -notmatch '^[A-Za-z]:[\\/]'){throw 'Local path required'}
    return [IO.Path]::GetFullPath($Path)
}
function HP-ReadObject([string]$Path) {
    if(-not $Path){return $null}
    try {
        $raw=Get-Content -LiteralPath (HP-LocalPath $Path) -Raw -Encoding UTF8
        try {return ($raw | ConvertFrom-Json)}catch{}
        if(Get-Command ConvertFrom-Yaml -ErrorAction SilentlyContinue){return ($raw | ConvertFrom-Yaml)}
    }catch{}
    return $null
}
function HP-Address([string]$Value) {
    $ip=$null
    if($Value -match '[/,%*]' -or -not [Net.IPAddress]::TryParse($Value,[ref]$ip)){return $null}
    if($ip.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork -and $Value -notmatch '^\d{1,3}(?:\.\d{1,3}){3}$'){return $null}
    if($ip.Equals([Net.IPAddress]::Any) -or $ip.Equals([Net.IPAddress]::IPv6Any)){return $null}
    return $ip.ToString()
}
function HP-Time($Value) {
    if($Value -is [DateTimeOffset]){return $Value.ToUniversalTime()}
    if($Value -is [DateTime]){if($Value.Kind -eq [DateTimeKind]::Unspecified){return $null};return ([DateTimeOffset]$Value).ToUniversalTime()}
    $date=[DateTimeOffset]::MinValue
    if($Value -isnot [string] -or $Value -notmatch '(?:Z|[+-]\d{2}:\d{2})$' -or -not [DateTimeOffset]::TryParse($Value,[ref]$date)){return $null}
    return $date.ToUniversalTime()
}
$evidence=HP-ReadObject $EvidencePath
$now=[DateTimeOffset]::UtcNow
# Record the observation start before generating or observing the related guest traffic.
$collected=HP-Time (HP-Value $evidence 'guest_checked_at_utc')
$fresh=$null -ne $collected -and ($now-$collected).TotalMinutes -ge -1 -and ($now-$collected).TotalMinutes -le 10
$config=HP-ReadObject ([string](HP-Value $evidence 'host_active_config_path'))
$api=$null;$apiState='not_requested'
if($ReadCoreApi){
    try {
        . (Join-Path $PSScriptRoot 'Read-ClaudeCoreApi.ps1')
        $api=Get-ClaudeCoreApiSnapshot -Config $config -CorePath ([string](HP-Value $evidence 'host_core_path'))
        $apiState=$api.state
    }catch{$apiState='unknown'}
}
$logLines=New-Object 'System.Collections.Generic.List[object]'
$filesRead=0;$logReadIncomplete=$false
$logDirectory=[string](HP-Value $evidence 'host_log_directory')
if($logDirectory){
    try {
        $files=@(Get-ChildItem -LiteralPath (HP-LocalPath $logDirectory) -File -Filter '*.log' -ErrorAction Stop | Sort-Object LastWriteTime -Descending | Select-Object -First 5)
        foreach($file in $files){
            try {
                foreach($line in @(Get-Content -LiteralPath $file.FullName -Encoding UTF8 -Tail 4000 -ErrorAction Stop)){
                    if($line -notmatch 'time="(?<stamp>[^"]+)"'){continue}
                    $stamp=HP-Time $Matches.stamp
                    if($null -eq $stamp -or $stamp -gt $now.AddMinutes(1) -or $stamp -lt $now.AddMinutes(-10)){continue}
                    if($fresh -and $stamp -lt $collected){continue}
                    $logLines.Add([pscustomobject]@{at=$stamp;line=$line})
                }
                $filesRead++
            }catch{$logReadIncomplete=$true}
        }
    }catch{$logReadIncomplete=$true}
}
$results=New-Object 'System.Collections.Generic.List[object]'
$ordinal=0
foreach($hop in @(HP-Value $evidence 'guest_first_hops')){
    if($null -eq $hop){continue};$ordinal++
    $addresses=@();$inputValid=$true
    foreach($entry in @(HP-Value $hop 'addresses')){
        $normalized=HP-Address ([string]$entry)
        if($normalized){$addresses+=$normalized}else{$inputValid=$false}
    }
    $port=0;$portText=[string](HP-Value $hop 'port')
    if($portText -notmatch '^\d{1,5}$' -or -not [int]::TryParse($portText,[ref]$port) -or $port -lt 1 -or $port -gt 65535){$inputValid=$false}
    $expected=[string](HP-Value $hop 'expected_host_policy')
    if(-not $addresses.Count -or -not $expected -or $expected -match '[\r\n"]'){$inputValid=$false}
    $matchesExpected=0;$matchesOther=0;$errors=0;$apiMatching=0;$apiExpected=0;$apiOther=0
    if($inputValid){
        foreach($record in $logLines){
            $line=$record.line;$endpointMatched=$false
            foreach($address in $addresses){
                $server=if($address.Contains(':')){'['+$address+']'}else{$address}
                if($line -match ('--> '+[regex]::Escape($server)+':'+$port+'(?:\s|")')){$endpointMatched=$true;break}
            }
            if(-not $endpointMatched){continue}
            if($line -match 'level=(?:warning|error)|i/o timeout|deadline exceeded|connect failed'){$errors++}
            if($line -match ' using (?<policy>[^"\r\n]+)'){
                $actual=$Matches.policy.Trim()
                if($actual -ceq $expected -or $actual.StartsWith($expected+'[',[StringComparison]::Ordinal)){$matchesExpected++}else{$matchesOther++}
            }
        }
        if($apiState -eq 'read'){
            foreach($connection in @(HP-Value $api.connections 'connections')){
                $metadata=HP-Value $connection 'metadata'
                $destination=HP-Address ([string](HP-Value $metadata 'destinationIP'))
                if($destination -notin $addresses -or [string](HP-Value $metadata 'destinationPort') -ne [string]$port){continue}
                $apiMatching++
                $chain=@(HP-Value $connection 'chains')
                if($chain.Count -eq 0){continue}
                if($expected -ceq 'DIRECT'){
                    if(@($chain | Where-Object {$_ -cne 'DIRECT'}).Count -eq 0){$apiExpected++}else{$apiOther++}
                }elseif($expected -cin $chain){$apiExpected++}else{$apiOther++}
            }
        }
    }
    $status=if(-not $inputValid -or -not $fresh){'unknown'}elseif($matchesOther -or $apiOther -or $errors){'review_required'}elseif($matchesExpected -or $apiExpected){'snapshot_match'}else{'unknown'}
    $results.Add([pscustomobject]@{hop_index=$ordinal;status=$status;input_complete=$inputValid;guest_evidence_fresh=$fresh;log_expected_count=$matchesExpected;log_other_policy_count=$matchesOther;log_error_count=$errors;live_connection_count=$apiMatching;live_expected_count=$apiExpected;live_other_chain_count=$apiOther;unexpected_host_forwarding_observed=($matchesOther -gt 0 -or $apiOther -gt 0);source_attribution='endpoint_and_time_only';guest_identity_proven=$false})
}
[ordered]@{
    checked_at_utc=$now.ToString('o');mode='read_only';scope='Windows host; compare private guest first hops with recent host forwarding evidence'
    overall='review_required';guest_evidence_fresh=$fresh;core_api_state=$apiState;controller_owner_verified=($null -ne $api -and $api.controller_owner_verified -eq $true)
    log_files_read=$filesRead;log_read_incomplete=$logReadIncomplete;hops=@($results.ToArray())
    private_values_recorded=$false;network_changed=$false;public_requests_made=$false
    not_tested=@('Guest source identity after host NAT/TUN','End-to-end request success','Host rule persistence across subscription changes','Guest firewall protection','Browser leakage and Claude conversation')
} | ConvertTo-Json -Depth 7
