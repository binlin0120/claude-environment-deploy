#requires -Version 5.1
[CmdletBinding()]
param(
    [ValidatePattern('^[A-Za-z]{2}$')][string]$ExpectedCountry,
    [string]$ExpectedExitIp,
    [string]$EvidencePath,
    [ValidateRange(1,65535)][int]$ProxyPort,
    [ValidateRange(1,90)][int]$RequestCount = 3,
    [ValidateRange(0,30)][int]$IntervalSeconds = 0,
    [string]$SampleLogPath
)
$ErrorActionPreference = 'Stop'
function ConvertTo-NormalizedAddress([string]$Value) {
    $address = $null
    if ([string]::IsNullOrWhiteSpace($Value) -or $Value.Contains('%') -or -not [Net.IPAddress]::TryParse($Value, [ref]$address)) { return $null }
    if ($address.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork -and $Value -notmatch '^\d{1,3}(\.\d{1,3}){3}$') { return $null }
    if ($address.IsIPv4MappedToIPv6) { $address = $address.MapToIPv4() }
    return $address.ToString()
}
function Get-RequestErrorStage([Exception]$Exception) {
    for ($current = $Exception; $null -ne $current; $current = $current.InnerException) {
        if ($current -is [Net.WebException]) {
            switch ($current.Status.ToString()) {
                'Timeout' { return 'timeout' }
                'NameResolutionFailure' { return 'dns' }
                'ProxyNameResolutionFailure' { return 'dns' }
                'ConnectFailure' { return 'connect' }
                'TrustFailure' { return 'tls' }
                'SecureChannelFailure' { return 'tls' }
                'ProtocolError' { return 'http-status' }
            }
        }
        if ($null -ne $current.PSObject.Properties['Response'] -and $null -ne $current.Response -and $null -ne $current.Response.PSObject.Properties['StatusCode']) { return 'http-status' }
        if ($current -is [Security.Authentication.AuthenticationException]) { return 'tls' }
        if ($current -is [TimeoutException]) { return 'timeout' }
    }
    return 'unknown'
}
function Get-RequestHttpStatus([Exception]$Exception) {
    for ($current = $Exception; $null -ne $current; $current = $current.InnerException) {
        if ($current.PSObject.Properties['Response'] -and $current.Response -and $current.Response.PSObject.Properties['StatusCode']) {
            return [int]$current.Response.StatusCode
        }
    }
    return $null
}
function Open-SampleLog([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path)
    if (-not $full.StartsWith('D:\Codex\', [StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetExtension($full) -ne '.jsonl') {
        throw 'SampleLogPath must be a new .jsonl file inside D:\Codex.'
    }
    $dir = [IO.DirectoryInfo]::new([IO.Path]::GetDirectoryName($full))
    for ($parent = $dir; $parent; $parent = $parent.Parent) {
        if (-not $parent.Exists -or $parent.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw 'SampleLogPath requires an existing real directory without junctions or symbolic links.'
        }
    }
    $stream = [IO.File]::Open($full, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
    try {
        $writer = [IO.StreamWriter]::new($stream, [Text.UTF8Encoding]::new($false))
        $writer.AutoFlush = $true
        return $writer
    } catch {
        $stream.Dispose()
        throw
    }
}
$expectedAddress = ConvertTo-NormalizedAddress $ExpectedExitIp
if ($null -eq $expectedAddress -or [string]::IsNullOrWhiteSpace($EvidencePath) -or -not $ProxyPort) {
    throw 'Supply a valid ExpectedExitIp, EvidencePath and local ProxyPort before starting the egress check.'
}
try {
    $audit = & (Join-Path $PSScriptRoot 'Test-ClaudeGuestNetwork.ps1') -EvidencePath $EvidencePath -ProbeProxyPort $ProxyPort | ConvertFrom-Json
} catch {
    throw 'Local network guard could not be read. Egress check did not start.'
}
foreach ($name in 'specified_core_process','effective_firewall_profiles','effective_allow_rule_filters','core_first_hop_rules','protected_application_rules','loopback_probe_proxy') {
    $check = @($audit.checks | Where-Object check -eq $name)
    if ($check.Count -ne 1 -or $check[0].status -ne 'pass') {
        throw ('Local network guard did not pass ' + $name + '. Egress check did not start.')
    }
}
$proxyOwner = [int]($audit.checks | Where-Object check -eq 'loopback_probe_proxy').details.owner_process_id
if ($proxyOwner -le 0) { throw 'Local proxy owner is unverified. Egress check did not start.' }
. (Join-Path $PSScriptRoot 'Read-ClaudeCoreApi.ps1')
$proxyUri = [Uri]("http://127.0.0.1:$ProxyPort")
$endpoint = 'https://claude.ai/cdn-cgi/trace'
$results = @()
$addresses = @()
$oldProtocol = [Net.ServicePointManager]::SecurityProtocol
$oldCertificateCallback = [Net.ServicePointManager]::ServerCertificateValidationCallback
$writer = $null
$stopReason = $null
try {
    if ($SampleLogPath) { $writer = Open-SampleLog $SampleLogPath }
    [Net.ServicePointManager]::SecurityProtocol = $oldProtocol -bor [Net.SecurityProtocolType]::Tls12
    [Net.ServicePointManager]::ServerCertificateValidationCallback = $null
    foreach ($attempt in 1..$RequestCount) {
        $started = [DateTime]::UtcNow
        $clock = [Diagnostics.Stopwatch]::StartNew()
        $stage = 'proxy-unavailable'
        $startedRequest = $false
        $httpStatus = $null
        $country = $null
        $exitMatches = $null
        $countryMatches = $null
        $errorType = $null
        try {
            if ((Get-ClaudeProbeProxyOwner $ProxyPort) -ne $proxyOwner) { throw 'Local proxy owner changed.' }
            $stage = 'request'
            $started = [DateTime]::UtcNow
            $clock.Restart()
            $startedRequest = $true
            $requestOptions = @{}
            if ($PSVersionTable.PSVersion.Major -ge 6) { $requestOptions['SkipCertificateCheck'] = $false }
            $response = Invoke-WebRequest @requestOptions -Uri $endpoint -Proxy $proxyUri -Method Get -TimeoutSec 15 -MaximumRedirection 0 -DisableKeepAlive -UseBasicParsing -Headers @{ 'Cache-Control' = 'no-cache'; Pragma = 'no-cache'; Accept = 'text/plain' } -ErrorAction Stop
            $stage = 'http-status'
            $httpStatus = [int]$response.StatusCode
            if ($httpStatus -ne 200) { throw 'Unexpected HTTP status.' }
            $stage = 'response-validation'
            if ([string]$response.Headers['Content-Type'] -notmatch '^text/plain(?:\s*;|$)' -or $response.Content -isnot [string]) { throw 'Unexpected response format.' }
            $fields = @{}
            foreach ($line in ($response.Content -split '\r?\n')) {
                if ([string]::IsNullOrWhiteSpace($line)) { continue }
                if ($line -notmatch '^([A-Za-z0-9_-]+)=(.*)$' -or $fields.ContainsKey($Matches[1])) { throw 'Invalid trace response.' }
                $fields[$Matches[1]] = $Matches[2].Trim()
            }
            $address = ConvertTo-NormalizedAddress ([string]$fields['ip'])
            $country = [string]$fields['loc']
            if ($null -eq $address -or $country -notmatch '^[A-Za-z]{2}$') { throw 'Missing valid trace fields.' }
            $addresses += $address
            $country = $country.ToUpperInvariant()
            $exitMatches = ($address -eq $expectedAddress)
            if ($ExpectedCountry) { $countryMatches = ($country -eq $ExpectedCountry.ToUpperInvariant()) }
            $stage = $null
        } catch {
            if ($stage -eq 'request') {
                $stage = Get-RequestErrorStage $_.Exception
                $httpStatus = Get-RequestHttpStatus $_.Exception
            }
            $country = $null
            $errorType = $_.Exception.GetType().Name
        }
        $clock.Stop()
        $sample = [pscustomobject]@{
            attempt = $attempt; endpoint = $endpoint; path = 'guest-loopback-proxy'; proxy_port = $ProxyPort
            started_at_utc = $started.ToString('o'); finished_at_utc = [DateTime]::UtcNow.ToString('o')
            request_started = $startedRequest; request_succeeded = ($null -eq $stage); http_status = $httpStatus
            country = $country; elapsed_ms = $clock.ElapsedMilliseconds
            error_stage = $stage; error_type = $errorType
            expected_exit_matches = $exitMatches; expected_country_matches = $countryMatches
        }
        $results += $sample
        if ($writer) { $writer.WriteLine(($sample | ConvertTo-Json -Compress)) }
        if ($exitMatches -eq $false -or $countryMatches -eq $false) {
            $stopReason = 'unexpected-egress'
            break
        }
        if ($attempt -lt $RequestCount -and $IntervalSeconds) { Start-Sleep -Seconds $IntervalSeconds }
    }
} finally {
    [Net.ServicePointManager]::SecurityProtocol = $oldProtocol
    [Net.ServicePointManager]::ServerCertificateValidationCallback = $oldCertificateCallback
    if ($writer) { $writer.Dispose() }
}
$successes = @($results | Where-Object request_succeeded)
$countries = @($successes | Select-Object -ExpandProperty country -Unique)
$consistent = ($successes.Count -eq $RequestCount -and $countries.Count -eq 1)
$ipConsistent = ($successes.Count -eq $RequestCount -and @($addresses | Select-Object -Unique).Count -eq 1)
$egressConsistent = ($consistent -and $ipConsistent)
$expectedMatch = $null
if ($ExpectedCountry) { $expectedMatch = ($consistent -and $countries[0] -eq $ExpectedCountry.ToUpperInvariant()) }
$expectedExitMatch = $null
if ($null -ne $expectedAddress) { $expectedExitMatch = ($ipConsistent -and $addresses[0] -eq $expectedAddress) }
$overallPassed = ($egressConsistent -and ($null -eq $expectedMatch -or $expectedMatch) -and ($null -eq $expectedExitMatch -or $expectedExitMatch))
[ordered]@{
    checked_at_utc = [DateTime]::UtcNow.ToString('o')
    scope = 'Protected Windows guest; explicit local proxy; fresh HTTP requests to the same Claude HTTPS trace endpoint; one source only'
    requested_count = $RequestCount; request_count = $results.Count
    started_request_count = @($results | Where-Object request_started).Count; stop_reason = $stopReason
    results = $results; country_consistent = $consistent; expected_country = $ExpectedCountry; expected_country_matches = $expectedMatch
    exit_ip_consistent = $ipConsistent; egress_consistent = $egressConsistent; expected_exit_matches = $expectedExitMatch; overall_passed = $overallPassed
    public_ip_recorded = $false
    not_tested = @('Independent geolocation sources', 'Browser DNS/WebRTC/IPv6', 'Claude login and conversation', 'Proxy failure protection', 'Restart and update behavior', 'Physical location or service eligibility', 'Residential IP classification')
} | ConvertTo-Json -Depth 5