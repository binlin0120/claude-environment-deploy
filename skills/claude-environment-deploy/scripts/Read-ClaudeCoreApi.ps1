#requires -Version 5.1
# Defines a read-only helper. Raw results and controller secrets stay in private memory.
function Get-ClaudeCoreField($Object,[string]$Name) {
    if($null -eq $Object){return $null}
    if($Object -is [Collections.IDictionary]){return $Object[$Name]}
    $property=$Object.PSObject.Properties[$Name]
    if($null -ne $property){return $property.Value}
    return $null
}
function Get-ClaudeCoreControllerOwner([Net.IPAddress]$Address,[int]$Port,[string]$CorePath) {
    $listeners=@(Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction Stop | Where-Object {
        $candidate=$null
        [Net.IPAddress]::TryParse([string]$_.LocalAddress,[ref]$candidate) -and
        ($candidate.Equals($Address) -or ($candidate.AddressFamily -eq $Address.AddressFamily -and ($candidate.Equals([Net.IPAddress]::Any) -or $candidate.Equals([Net.IPAddress]::IPv6Any))))
    })
    $owners=@($listeners | Select-Object -ExpandProperty OwningProcess -Unique)
    if($owners.Count -ne 1 -or [int]$owners[0] -le 0){throw 'controller_owner_unverified'}
    $owner=@(Get-Process -Id ([int]$owners[0]) -ErrorAction Stop)
    if($owner.Count -ne 1 -or -not $owner[0].Path -or -not [string]::Equals([IO.Path]::GetFullPath($owner[0].Path),[IO.Path]::GetFullPath($CorePath),[StringComparison]::OrdinalIgnoreCase)){throw 'controller_owner_unverified'}
    return [int]$owners[0]
}
function Get-ClaudeProbeProxyOwner([int]$Port) {
    $listeners = @(Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction Stop)
    $local = @($listeners | Where-Object LocalAddress -eq '127.0.0.1')
    if ($local.Count -ne 1 -or [int]$local[0].OwningProcess -le 0 -or
        @($listeners | Where-Object { $_.LocalAddress -notin @('127.0.0.1','::1') -or $_.OwningProcess -ne $local[0].OwningProcess }).Count) {
        throw 'probe_proxy_owner_unverified'
    }
    return [int]$local[0].OwningProcess
}
function New-ClaudeCoreHttpRequest([Uri]$Uri) { return [Net.HttpWebRequest]::Create($Uri) }
function Invoke-ClaudeCoreApiGet([Uri]$Uri,[string]$Secret) {
    $request=$null;$response=$null;$reader=$null
    try {
        $request=New-ClaudeCoreHttpRequest $Uri
        $request.Method='GET';$request.Proxy=$null;$request.AllowAutoRedirect=$false
        $request.UseDefaultCredentials=$false;$request.PreAuthenticate=$false
        $request.Timeout=3000;$request.ReadWriteTimeout=3000
        if($Secret){$request.Headers['Authorization']='Bearer '+$Secret}
        $response=$request.GetResponse()
        if([int]$response.StatusCode -ne 200){throw 'controller_response_unavailable'}
        $reader=New-Object IO.StreamReader($response.GetResponseStream())
        $buffer=New-Object char[] 8192;$body=New-Object Text.StringBuilder
        while(($count=$reader.Read($buffer,0,$buffer.Length)) -gt 0){
            if($body.Length+$count -gt 4194304){throw 'controller_response_unavailable'}
            [void]$body.Append($buffer,0,$count)
        }
        return ($body.ToString() | ConvertFrom-Json -ErrorAction Stop)
    }finally{
        if($reader){$reader.Dispose()}
        if($response){$response.Dispose()}
        if($request){$request.Abort()}
    }
}
function Get-ClaudeCoreApiSnapshot {
    [CmdletBinding()]
    param($Config,[string]$CorePath)
    $result=[ordered]@{state='unknown';reason='controller_not_configured';checked_at_utc=[DateTime]::UtcNow.ToString('o');controller_owner_verified=$false;configs=$null;proxies=$null;connections=$null}
    $controller=Get-ClaudeCoreField $Config 'external-controller'
    if($controller -isnot [string] -or -not $controller){return [pscustomobject]$result}
    if($CorePath -notmatch '^[A-Za-z]:[\\/]'){$result.reason='core_path_invalid';return [pscustomobject]$result}
    $match=[regex]::Match($controller,'^(?<host>127(?:\.\d{1,3}){3}|\[::1\]):(?<port>\d{1,5})$')
    $address=$null;$port=0
    if(-not $match.Success -or -not [Net.IPAddress]::TryParse($match.Groups['host'].Value.Trim('[',']'),[ref]$address) -or -not [Net.IPAddress]::IsLoopback($address) -or -not [int]::TryParse($match.Groups['port'].Value,[ref]$port) -or $port -lt 1 -or $port -gt 65535){$result.reason='controller_not_loopback_literal';return [pscustomobject]$result}
    $secret=Get-ClaudeCoreField $Config 'secret'
    if($null -ne $secret -and $secret -isnot [string]){$result.reason='controller_secret_invalid';return [pscustomobject]$result}
    if($secret -match '[\r\n]'){$result.reason='controller_secret_invalid';return [pscustomobject]$result}
    try {
        $owner=Get-ClaudeCoreControllerOwner $address $port $CorePath
        $result.controller_owner_verified=$true
    }catch{$result.reason='controller_owner_unverified';return [pscustomobject]$result}
    try {
        $private=@{}
        foreach($endpoint in @('configs','proxies','connections')){
            if((Get-ClaudeCoreControllerOwner $address $port $CorePath) -ne $owner){throw 'controller_owner_changed'}
            $uri=[Uri]('http://'+$controller+'/'+$endpoint)
            $private[$endpoint]=Invoke-ClaudeCoreApiGet $uri ([string]$secret)
            if($null -eq $private[$endpoint]){throw 'controller_response_unavailable'}
        }
        if((Get-ClaudeCoreControllerOwner $address $port $CorePath) -ne $owner){throw 'controller_owner_changed'}
        $result.state='read';$result.reason='read_only_snapshot'
        foreach($endpoint in @('configs','proxies','connections')){$result[$endpoint]=$private[$endpoint]}
    }catch{$result.reason='controller_read_failed'}finally{$secret=$null;$private=$null}
    return [pscustomobject]$result
}
