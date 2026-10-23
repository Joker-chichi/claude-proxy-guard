# Account and environment consistency

Use this guide during preflight, signup, verification, the optional observation period, and billing. It is a consistency and safety checklist, not a method for manufacturing eligibility or defeating platform controls.

## 1. Weight signals sensibly

Language and time zone are contextual signals, not proof that an account is safe or abusive. Chinese UI, Chinese input, or the user's normal local time zone should not be demonized. Keep the device clock accurate and leave language, locale, and time-zone settings natural for the user; do not spoof them to impersonate another location.

Eligibility still depends on Anthropic's current rules, including the user's real physical location and any current phone or paid-plan requirements. Re-check the official supported-country and Pro signup pages at execution time.

## 2. Prefer continuity over a “magic pool”

Use one dedicated, low-churn endpoint for one desktop when possible. A rotating or shared proxy pool can introduce unexplained country, ASN, DNS, and reputation changes. Disable automatic fresh-IP renewal unless a replacement is intentional.

“Clean IP,” “0 fraud score,” and similar labels are provider or third-party signals, not guarantees. Validate the observed exit, country, ASN, DNS, and WebRTC behavior, but do not promise that a score prevents review or suspension.

If an endpoint fails validation or becomes unstable:

1. Stop account, verification, and payment activity.
2. Replace the endpoint deliberately rather than hopping repeatedly.
3. Re-run the exit and leak checks.
4. Resume only after the dedicated browser and Claude Desktop show the same expected route.

Do not treat an anecdotal monthly price as a product requirement. Re-check the current term, traffic allowance, renewal behavior, taxes, refund window, and replacement policy before purchase.

## 3. Keep the browser and account user-controlled

Use the repository's persistent, extension-free browser profile with the explicit proxy and QUIC disabled. Do not mix the dedicated profile with the default browser profile, and do not reuse it through an ordinary Chrome or Edge shortcut.

Anthropic's official Pro signup guide currently documents email and Google as login choices. Strongly recommend a user-owned Google account with MFA and recovery configured as the first choice because it provides a well-established login and recovery chain. Project experience suggests this may reduce extra phone-verification prompts, but Anthropic has not published a probability or guarantee; present it as field experience, not as a way to bypass a required check. Never use a borrowed, purchased, shared, or mass-created Google or Claude account.

The user must type credentials and complete login, CAPTCHA, recovery, and checkout themselves. The assistant may inspect configuration and explain a page, but must not request, store, type, or transmit passwords, cookies, MFA codes, or recovery codes.

## 4. Handle phone verification truthfully

Anthropic's official Pro signup guidance says users must be physically located in a supported location and use a phone number from a supported location when a number is required. Use only a number legitimately controlled by the account owner and consistent with their truthful eligibility.

A disposable SMS platform, rented receiver, or relay service is an unsupported, high-risk path that some users independently try. Anthropic does not guarantee that such a number will be accepted. The number may already have been used, reassigned, monitored, or unavailable later, which can expose a verification code and cause failed recovery, account loss, or lost subscription payments. Its use may also conflict with current eligibility or platform rules.

Explain those losses before the user decides. The project must not select or endorse a provider, receive or relay a code, operate the service, or provide instructions intended to evade verification. If the user does not have a qualifying number, the supported path is to pause and contact official support.

## 5. Keep identity and face checks personal

If an official flow requests identity or biometric verification, the account owner must use their own identity document and their own face, with truthful details. As of October 2026, the project author has successfully completed Claude's Persona-powered passport and live-selfie flow using their own valid mainland Chinese passport. Anthropic's official guide separately states that original physical passports from most countries are accepted. Therefore, recommend the account owner's own physical Chinese passport when the flow requests a passport: select `China` and `Passport`, capture the original document, and complete the live selfie personally.

This is author-tested compatibility, not a guarantee for every account. Recent user reports indicate that Claude can present different verification templates, including flows that request more than one document. Passing identity verification also does not override supported-region rules or guarantee the account will remain enabled. Borrowing a passport, asking another person to verify, using prerecorded media, or handing remote control to a seller is identity misrepresentation and is not presented as a method in this project.

Complete the official flow on the user's own device. The mobile route is a critical preflight check: before scanning a QR code or moving from desktop to phone, first confirm that the user is physically in a currently supported Anthropic region. Then confirm that the mobile device clock is correct, the official verification page is reachable, and its route is secure, stable, and consistent with the user's real location and expected desktop session environment.

If the user is physically outside a supported region, stop and wait until they actually move to a supported region or Anthropic changes its policy. If the user is already in a supported region but the phone exit is wrong, leaking, or unstable, repair the network configuration and re-run the exit check before scanning. Avoid changing Wi-Fi, cellular service, country, or exit IP after the verification session begins. A material desktop-to-phone route mismatch can cause the session to fail. Changing only the phone IP does not create regional eligibility.

## 6. Use observation, not synthetic “account warming”

An optional 72-hour observation period can reveal a proxy that disconnects, rotates, leaks, or reports inconsistent geography. During that period, keep the same endpoint and use the account normally if needed.

This observation period is not “养号,” does not create eligibility, and does not guarantee account safety. Do not script visits, conversations, or other synthetic engagement to imitate a different person.

## 7. Prepare for billing before paying

Prefer Claude Settings > Billing, the official upgrade page, or an official mobile app store. Check the current regional price and terms at checkout rather than relying on a remembered price.

Before payment, confirm that the user can personally access email, MFA, recovery, a qualifying phone number, and any truthful identity or payment information an official review may require. Do not pay first and assume verification can be outsourced later.

If the user chooses a third-party recharge option after reviewing the disclosure and terms, the provider must never receive account credentials, verification codes, cookies, API keys, identity documents, biometrics, or remote-control access. Verify the resulting entitlement only inside official Claude settings.

## 8. Final continuity check

Before signup, verification, or payment, confirm all of the following:

- The user's real physical location and intended use meet current official rules.
- The dedicated browser and Claude Desktop resolve to the expected stable exit.
- DNS and WebRTC checks do not expose an unintended route.
- The user controls the login account, recovery channels, phone number, payment method, identity document, and biometrics involved.
- No language, locale, or time-zone spoofing is being used to impersonate a location.
- The user understands that stable routing reduces accidental inconsistency but does not guarantee approval or prevent suspension.

## Official sources

- Supported countries: https://www.anthropic.com/supported-countries
- Pro signup and current regional pricing: https://support.anthropic.com/en/articles/8325609-how-do-i-sign-up-for-claude-pro
- Claude identity verification and accepted ID categories: https://support.claude.com/en/articles/14328960-identity-verification-on-claude
- Persona document guidance: https://help.withpersona.com/articles/10ILwkQ6xh8qDoZmF4vLt8/
