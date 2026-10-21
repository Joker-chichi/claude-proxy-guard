# Windows proxy isolation lessons learned

These corrections come from repeated diagnosis of a real Claude Desktop MSIX and sing-box installation. Preserve them when adapting the scripts.

## Corrections that must not regress

1. **Do not start the versioned WindowsApps executable directly.** `Start-Process` can return Access Denied even when the package is healthy. Resolve the installed package, read the Application ID from `AppxManifest.xml`, and launch through `ApplicationActivationManager`. Do not depend on `Get-StartApps`; its `StartLayout` module may fail to load on otherwise healthy Windows installations.
2. **Do not bind firewall protection to versioned executable paths.** Claude updates change the package path and create an unprotected window. Bind outbound block rules to `PackageFamilyName`.
3. **Do not merely leave TCP port 20808 open.** That permits a connection to any external host using remote port 20808. Also block non-loopback IPv4 on port 20808 and all IPv6 on that port, leaving only `127.0.0.1:20808`.
4. **Block all UDP.** Otherwise Chromium/Electron can use QUIC and bypass an HTTP CONNECT proxy. Also pass `--disable-quic`.
5. **Do not use a TUN inbound for desktop-only isolation.** TUN with `auto_route` or `strict_route` can become the Windows default route and affect unrelated apps. Use a mixed inbound bound only to `127.0.0.1`.
6. **Do not put port 7890 in the Claude route.** The intended path is Claude directly to local port 20808, then sing-box to the purchased proxy.
7. **Validate before launch.** Refuse to open Claude unless the config passes `sing-box check`, contains no TUN, sing-box owns the listener using the expected config path, and package-family firewall rules pass validation. If sing-box stops, Claude must fail closed.
8. **Treat package repair as explicit recovery.** If the MSIX status is not `Ok`, report it first. Re-register its manifest only with an explicit repair switch; do not routinely change package permissions.
9. **Rotate logs.** A continuously running proxy log can grow past 100 MB. Rotate it at startup when it exceeds the configured limit and keep only one previous copy.
10. **Never copy live credentials into a reusable skill.** Parameterize server, port, username, and password; read the password through a secure prompt and restrict the config ACL.

## Required test order

1. Parse every PowerShell script with the PowerShell AST parser.
2. Generate a temporary sing-box config using dummy credentials and confirm there is no TUN inbound.
3. Run `start-singbox.ps1 -PlanOnly` and `install-singbox-task.ps1 -PlanOnly`.
4. Run `set-claude-package-firewall.ps1 -PlanOnly` before any elevated mutation.
5. Apply firewall rules, then run `-ValidateOnly`.
6. Start sing-box and confirm `127.0.0.1:20808` is owned by `sing-box`.
7. Check the exit IP through port 20808.
8. Run `launch-claude.ps1 -PlanOnly`, then launch normally.
9. Confirm every established Claude connection targets only `127.0.0.1:20808`.
10. Stop sing-box briefly and confirm Claude cannot connect; restart immediately.
