param(
    [string]$SingBoxPath
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$templateDir = Join-Path $root 'references/templates'
$realPath = Join-Path $templateDir 'config-1.14.4-tun-realip.json'
$fakePath = Join-Path $templateDir 'config-1.14.4-tun-fakeip.json'
$defaultPath = Join-Path $root 'references/template.json'

function Assert-Valid($condition, [string]$message) {
    if (-not $condition) { throw $message }
}

$files = @(Get-ChildItem $templateDir -Filter '*.json')
Assert-Valid ($files.Count -eq 2) 'Expected exactly two versioned templates.'
Assert-Valid (Test-Path $realPath) 'Missing RealIP template.'
Assert-Valid (Test-Path $fakePath) 'Missing FakeIP template.'
Assert-Valid ((Get-FileHash $defaultPath).Hash -eq (Get-FileHash $realPath).Hash) 'Default template must be identical to RealIP.'

$paths = @($defaultPath, $realPath, $fakePath)
foreach ($path in $paths) {
    $raw = Get-Content -Raw $path
    $c = $raw | ConvertFrom-Json
    Assert-Valid ($c.route.final -eq 'direct' -and $c.dns.final -eq 'local-dns') "Russia selective defaults must fall back to direct traffic and local DNS in $path"
    Assert-Valid ($raw -notmatch 'alidns|223\.5\.5\.5|geosite-cn|geoip-cn|geolocation-!cn|jsdelivr') "Obsolete regional defaults in $path"
    $blockedRoute = @($c.route.rules | Where-Object { $_.rule_set -contains 'geosite-ru-blocked' })
    Assert-Valid ($blockedRoute.Count -eq 1 -and $blockedRoute[0].outbound -eq 'blocked-services') "Missing selective blocked-domain route in $path"
    $blockedSelector = @($c.outbounds | Where-Object tag -eq 'blocked-services')
    Assert-Valid ($blockedSelector.Count -eq 1 -and $blockedSelector[0].default -eq 'proxy') "Missing blocked-services selector in $path"
    $blockedDNS = @($c.dns.rules | Where-Object { $_.rule_set -contains 'geosite-ru-blocked' })
    Assert-Valid (@($blockedDNS | Where-Object server -eq 'remote-dns').Count -eq 1) "Blocked domains need remote real DNS in $path"
    $downloadClient = @($c.http_clients | Where-Object tag -eq $c.route.default_http_client)
    Assert-Valid ($downloadClient.Count -eq 1 -and $downloadClient[0].detour -eq 'proxy') "Rule-set downloads must use the proxy in $path"
    Assert-Valid ($c.route.default_domain_resolver -eq 'local-dns') "Proxy bootstrap must be independent of proxied DNS in $path"
    Assert-Valid ($raw -notmatch '"protocol"\s*:\s*"stun"|"port"\s*:\s*853') "Selective defaults must not globally block STUN or DoT in $path"
    Assert-Valid ($raw -notmatch '"(independent_cache|store_rdrc|rdrc_timeout|download_detour)"\s*:') "Deprecated field in $path"
    Assert-Valid ($c.dns.strategy -eq 'ipv4_only') "Expected IPv4-only lookup strategy in $path"
    Assert-Valid ($c.dns.optimistic -eq $true -and $c.experimental.cache_file.store_dns -eq $true) "Missing DNS caching in $path"
    $first = $c.dns.rules[0]
    Assert-Valid ($first.query_type -eq 'AAAA' -and $first.action -eq 'predefined' -and $first.rcode -eq 'NOERROR' -and -not $first.answer) "Missing empty AAAA response in $path"
    Assert-Valid ($c.dns.rules[1].preferred_by -eq 'hosts') "Missing hosts-aware matching in $path"
    $tun = @($c.inbounds | Where-Object type -eq 'tun')
    Assert-Valid ($tun.Count -eq 1 -and $tun[0].dns_mode -eq 'hijack' -and $tun[0].auto_route -eq $true) "Invalid TUN DNS mode in $path"
    Assert-Valid (@($tun[0].address | Where-Object { $_ -match ':' }).Count -eq 0) "Unexpected TUN IPv6 address in $path"
    Assert-Valid ($c.route.rules[0].action -eq 'sniff') "Sniff must be the first route rule in $path"
    $hijack = $c.route.rules[1]
    Assert-Valid ($hijack.action -eq 'hijack-dns' -and $hijack.mode -eq 'or' -and $hijack.rules[0].protocol -eq 'dns' -and $hijack.rules[1].port -eq 53) "Invalid DNS hijack rule in $path"
    Assert-Valid ($c.route.auto_detect_interface -eq $true) "Missing interface detection in $path"
    $outboundTags = @($c.outbounds.tag)
    $dnsTags = @($c.dns.servers.tag)
    $ruleSetTags = @($c.route.rule_set.tag)
    $httpTags = @($c.http_clients.tag)
    Assert-Valid (@($outboundTags | Select-Object -Unique).Count -eq $outboundTags.Count) "Duplicate outbound tags in $path"
    foreach ($outbound in $c.outbounds) {
        foreach ($member in @($outbound.outbounds)) {
            if ($member) { Assert-Valid ($member -in $outboundTags) "Unknown selector/URLTest member $member in $path" }
        }
        if ($outbound.default) { Assert-Valid ($outbound.default -in $outbound.outbounds) "Invalid selector default in $path" }
    }
    foreach ($rule in @($c.route.rules) + @($c.dns.rules)) {
        foreach ($tag in @($rule.rule_set)) {
            if ($tag) { Assert-Valid ($tag -in $ruleSetTags) "Unknown rule-set $tag in $path" }
        }
        if ($rule.outbound) { Assert-Valid ($rule.outbound -in $outboundTags) "Unknown route outbound in $path" }
        if ($rule.server) { Assert-Valid ($rule.server -in $dnsTags) "Unknown DNS server in $path" }
    }
    Assert-Valid ($c.route.final -in $outboundTags -and $c.dns.final -in $dnsTags) "Invalid final target in $path"
    Assert-Valid ($c.route.default_http_client -in $httpTags) "Missing explicit HTTP client in $path"
    Assert-Valid ($c.route.default_domain_resolver -in $dnsTags) "Unknown bootstrap resolver in $path"
    foreach ($client in $c.http_clients) {
        Assert-Valid ($client.detour -in $outboundTags) "Unknown HTTP client detour in $path"
    }
    $fakeServers = @($c.dns.servers | Where-Object type -eq 'fakeip')
    if ($path -eq $fakePath) {
        Assert-Valid ($fakeServers.Count -eq 1 -and $c.experimental.cache_file.store_fakeip -eq $true) 'FakeIP needs a server and persistent mappings.'
        $fakeRule = @($c.dns.rules | Where-Object server -eq 'fakeip-dns')
        Assert-Valid ($fakeRule.Count -eq 1 -and 'A' -in $fakeRule[0].query_type) 'Missing FakeIP address rule.'
        Assert-Valid ($fakeRule[0].rule_set -contains 'geosite-ru-blocked') 'FakeIP must only apply to selected blocked domains.'
        Assert-Valid ([array]::IndexOf($c.dns.rules, $fakeRule[0]) -lt [array]::IndexOf($c.dns.rules, ($blockedDNS | Where-Object server -eq 'remote-dns'))) 'Selective FakeIP must precede real DNS for blocked domains.'
    } else {
        Assert-Valid ($fakeServers.Count -eq 0 -and -not $c.experimental.cache_file.store_fakeip -and $c.dns.reverse_mapping -eq $true) 'RealIP variant has invalid mapping settings.'
    }
    Write-Output "PASS structure: $([IO.Path]::GetFileName($path))"
}

$documents = @(Get-Item (Join-Path $root 'SKILL.md')) + @(Get-ChildItem $root -Filter 'README*.md') + @(Get-ChildItem (Join-Path $root 'references') -Filter '*.md')
foreach ($document in $documents) {
    $text = Get-Content -Raw $document.FullName
    Assert-Valid ($text -notmatch '1\.13') "Obsolete version reference in $($document.Name)"
    foreach ($match in [regex]::Matches($text, 'config-[0-9.]+-tun(?:-realip|-fakeip)?\.json')) {
        Assert-Valid (Test-Path (Join-Path $templateDir $match.Value)) "Broken template reference $($match.Value)"
    }
}
Write-Output 'PASS documentation version and template references'

if (-not $SingBoxPath) {
    Write-Output 'Binary checks skipped; supply -SingBoxPath to validate with sing-box 1.14.4.'
    exit 0
}

$binary = (Get-Command $SingBoxPath -ErrorAction Stop).Source
$version = & $binary version
Assert-Valid ($LASTEXITCODE -eq 0 -and ($version -join "`n") -match '(?m)^sing-box version 1\.14\.4\s*$') 'Validation requires the sing-box 1.14.4 binary.'
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('sing-box-skill-check-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory $tempRoot
try {
    foreach ($path in $paths) {
        $c = Get-Content -Raw $path | ConvertFrom-Json
        # Keep VLESS/Reality and all routing fields; replace only invalid credential placeholders.
        $node = $c.outbounds | Where-Object tag -eq 'your-node-tag'
        $node.uuid = '00000000-0000-4000-8000-000000000001'
        $node.tls.reality.public_key = 'jNXHt1yRo0vDuchQlIP6Z0ZvjT3KtzVI-T4E7RoLJS0'
        $node.tls.reality.short_id = '0123456789abcdef'
        $tempFile = Join-Path $tempRoot ([IO.Path]::GetFileName($path))
        [IO.File]::WriteAllText($tempFile, ($c | ConvertTo-Json -Depth 100), (New-Object Text.UTF8Encoding $false))
        & $binary check -c $tempFile -D $tempRoot
        Assert-Valid ($LASTEXITCODE -eq 0) "sing-box check failed for $path"
        Write-Output "PASS sing-box 1.14.4 check: $([IO.Path]::GetFileName($path))"
    }
} finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force
}
