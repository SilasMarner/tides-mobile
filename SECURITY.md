# Security Policy

## Supported versions

Only the latest release is actively maintained.

| Version | Supported |
|---------|-----------|
| 2.x (latest) | Yes |
| 1.x (Python/Kivy) | No — archived in `legacy/` |

## Reporting a vulnerability

Please **do not** open a public GitHub issue for security vulnerabilities.

Send a description to: **tides-mobile.human695@passmail.com**

Include:
- A description of the vulnerability and potential impact
- Steps to reproduce
- Any suggested fix if you have one

You can expect an acknowledgement within a few days. If the issue is confirmed, a fix will be prioritized for the next release.

## Scope

This app:
- Makes only outbound HTTPS requests to NOAA CO-OPS (`api.tidesandcurrents.noaa.gov`) and NWS (`api.weather.gov`) — both public APIs, no authentication
- Stores only station favorites and notification preferences locally via `shared_preferences`
- Requests location permission (used only for nearest-station search, not stored or transmitted)
- Contains no user accounts, no backend, and no analytics

Areas of interest:
- Insecure data storage
- Improper handling of API responses that could cause unexpected behavior
- Permission misuse
