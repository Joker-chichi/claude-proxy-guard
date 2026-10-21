# Windows Claude Desktop isolation

## Intended route

```text
Claude Desktop -> 127.0.0.1:20808 -> sing-box -> purchased ISP proxy -> Anthropic
```

Port `7890` and the Windows system proxy are not part of the route. Do not enable a sing-box TUN inbound for desktop-only isolation.

## Launcher requirements

- Confirm the loopback listener exists before launch.
- Set `HTTP_PROXY`, `HTTPS_PROXY`, and `ALL_PROXY` to `http://127.0.0.1:20808`.
- Add `--proxy-server=http://127.0.0.1:20808` and `--disable-quic`.
- Use a dedicated Claude data directory if session separation is needed.
- If direct MSIX `Start-Process` returns Access Denied, resolve its AppUserModelId and use Windows `ApplicationActivationManager`; do not loosen package permissions.
- For auto-start, use a narrowly scoped scheduled task. Restrict the config ACL because it contains proxy credentials.

## Firewall design

Bind rules to the installed Claude package family, not a versioned executable path. Block TCP below and above the local proxy port, non-loopback IPv4 on that port, all IPv6 on that port, and all UDP. This leaves only IPv4 `127.0.0.1:20808`. Revalidate after package changes. Do not use "block all plus allow one" because a Windows Firewall allow rule does not override a matching block rule.

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
