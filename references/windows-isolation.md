# Windows Claude Desktop isolation

## Intended route

```text
Claude Desktop -> 127.0.0.1:20808 -> sing-box -> purchased ISP proxy -> Anthropic
```

Port `7890` and the Windows system proxy are not part of the route. Do not enable a sing-box TUN inbound for desktop-only isolation.

## Tested compatibility baseline

- Windows 11 with Windows PowerShell 5.1.
- sing-box 1.14.2. Always run `sing-box check` because future schemas may change.
- Claude Desktop MSIX 3.1623.0.0. Resolve package paths and Application ID dynamically rather than pinning this version.
- Microsoft Edge or Google Chrome with explicit command-line proxy support.

Treat these as tested baselines, not permanent version requirements. Re-run `scripts/test-skill.ps1` and all live validation after upgrades.

## Stable runtime

Install operational scripts and the credential-bearing configuration under `C:\ProgramData\ClaudeProxyGuard`; do not point a scheduled task at a Git checkout or a user's movable Skill directory. Keep browser and Claude profiles under `%LOCALAPPDATA%\ClaudeProxyGuard`.

## Launcher requirements

- Confirm the loopback listener exists before launch.
- Set `HTTP_PROXY`, `HTTPS_PROXY`, and `ALL_PROXY` to `http://127.0.0.1:20808`.
- Add `--proxy-server=http://127.0.0.1:20808` and `--disable-quic`.
- Use a dedicated Claude data directory if session separation is needed.
- If direct MSIX `Start-Process` returns Access Denied, resolve its AppUserModelId and use Windows `ApplicationActivationManager`; do not loosen package permissions.
- For auto-start, use a narrowly scoped scheduled task. Restrict the config ACL because it contains proxy credentials.
- If package repair temporarily stops `CoworkVMService`, restore its original running state in a `finally` block.

## Clean browser requirements

- Verify the listener belongs to sing-box and uses the expected configuration path.
- Detect an existing browser process using the dedicated profile. Refuse reuse if it lacks the required proxy and QUIC flags.
- Disable browser background mode and non-proxied WebRTC UDP.
- Keep the profile persistent for the user's own login, but never mix it with the default browser profile.

## Firewall design

Bind rules to the installed Claude package family, not a versioned executable path. Block TCP below and above the local proxy port, non-loopback IPv4 on that port, all IPv6 on that port, and all UDP. This leaves only IPv4 `127.0.0.1:20808`. Revalidate after package changes. Do not use "block all plus allow one" because a Windows Firewall allow rule does not override a matching block rule.

Update rules transactionally: create and validate temporary staging blocks before replacing invalid stable rules. Remove staging and legacy rules only after the complete final set passes validation. If final creation fails, leave staging blocks active so the failure remains closed.

## Recovery

- Back up an existing config before replacement and keep the backups under the stable runtime with the same restricted ACL.
- Write a candidate config to the same volume, validate it, and atomically replace the destination.
- Uninstall by removing only the named task, scoped firewall groups, and controlled shortcuts. Preserve profiles and configuration unless the user explicitly requests a recoverable runtime archive.
- Public scripts are unsigned. Prefer reviewing a pinned commit and running the included tests; production publishers may additionally sign scripts with Authenticode instead of relying on `ExecutionPolicy Bypass`.

## Verification

1. Confirm sing-box owns `127.0.0.1:20808`.
2. Confirm the config has no TUN inbound.
3. Launch Claude with the controlled launcher.
4. Confirm Claude connections target only `127.0.0.1:20808`, never port `7890` or external addresses.
5. Check exit country and IP through the local proxy.
6. Stop sing-box briefly and confirm Claude loses connectivity; restart it immediately.
7. Confirm unrelated applications still use normal routes.

## Official sources

- Supported countries: https://www.anthropic.com/supported-countries
- Pro signup: https://support.anthropic.com/en/articles/8325609-how-do-i-sign-up-for-claude-pro
- Desktop installation: https://support.anthropic.com/en/articles/10065433-installing-claude-for-desktop
- Pricing: https://www.anthropic.com/pricing?subjects=claude&type=product
