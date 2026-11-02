# Network Modes and Platform Behavior

## Mode Selection

| Mode | Use case | Limitations |
|------|----------|------|
| TUN/VPN | Default. Captures all IP traffic; suitable for SFM/SFA/SFI and desktop-wide proxying | Creating TUN from the command line usually requires elevated privileges |
| system proxy | mixed inbound + `set_system_proxy`; suitable for lightweight command-line proxying | Captures only applications that honor the system proxy; application DNS is not controlled by sing-box |
| manual mixed/socks/http | Manually configure a proxy in a browser or individual application | Affects only applications explicitly configured to use the proxy |

System proxy and manual mixed/http modes do not use FakeIP as their core path because application DNS is not hijacked by TUN.

## Platform Notes

### macOS (SFM) / Android (SFA) / iOS (SFI)

- VPN is implemented through Network Extension / VPN APIs, without root access.
- Only a TUN inbound is needed by default; VPN mode captures browser HTTP/HTTPS traffic.
- `auto_detect_interface: true` prevents routing loops.
- `stack: "mixed"` provides the best compatibility.
- The same TUN configuration can be used across SFM/SFA/SFI.

SFM sets the system proxy only when the configuration contains `platform.http_proxy.enabled: true` and preferences allow it.

## `set_system_proxy` vs `platform.http_proxy`

| | `set_system_proxy` | `platform.http_proxy` |
|---|---|---|
| Configuration location | mixed/http inbound field | TUN inbound's `platform` block |
| Implementation | Calls the system proxy settings API | Sets the proxy through the VPN API |
| Use case | Command-line `sing-box run` | SFM/SFA/SFI GUI clients |
| TUN dependency | None | Requires a TUN inbound |
| Command-line support | Supported | Do not rely on it taking effect in the CLI; primarily consumed by GUI clients' PlatformInterface |

`platform.http_proxy` is not a proxy server; it only tells the system the proxy address. The actual proxy server is still provided by a mixed/http inbound. When using `platform.http_proxy`, also add a mixed/http inbound.

## Minimal System Proxy Structure

A system proxy configuration uses a mixed inbound, without a TUN inbound, DNS hijacking, or FakeIP:

```json
{
  "inbounds": [
    {
      "type": "mixed",
      "tag": "mixed-in",
      "listen": "127.0.0.1",
      "listen_port": 2080,
      "set_system_proxy": true
    }
  ],
  "route": {
    "auto_detect_interface": true,
    "default_domain_resolver": "alidns"
  }
}
```

v1.13 remote rule-sets can use `download_detour`. v1.14 system proxy configurations should use `http_clients` + `route.default_http_client` or per-rule-set `http_client`.

## Optional `platform.http_proxy`

Not needed by default. Add it only in these scenarios:

- A specific application honors only the system HTTP proxy and does not use TUN routing.
- You need `bypass_domain` / `match_domain` support provided by Apple GUI clients.

```json
"platform": {
  "http_proxy": {
    "enabled": true,
    "server": "127.0.0.1",
    "server_port": 2080,
    "bypass_domain": ["example.com"],
    "match_domain": ["specific-app.com"]
  }
}
```

Also add:

```json
{ "type": "mixed", "tag": "mixed-in", "listen": "127.0.0.1", "listen_port": 2080 }
```
