# ShopOS customer authentication

ShopOS provides customer-facing authentication separately from the internal Google Workspace mail connection.

## Features

- Sign in with Google for WooCommerce customer accounts
- separate external Google OAuth web client
- authorization-code flow with one-time state and PKCE S256
- verified Google email and stable Google subject identifier
- optional automatic creation of new `customer` users
- deliberate linking of an existing account from the authenticated security page
- optional TOTP two-factor authentication for password login
- ten one-time recovery codes stored only as password hashes
- close all other WordPress sessions
- bounded account-security audit history
- WooCommerce `My account > Sicherheit` endpoint

## Security boundaries

The Google customer client is not the Workspace Gmail client. Use a separate external OAuth client with only:

```text
openid email profile
```

The customer flow receives no Gmail, Drive, Calendar, Contacts or Workspace administration permission.

Existing local accounts are never linked solely because Google returns the same email address. The customer must first authenticate to the existing account and connect Google from `My account > Sicherheit`. A new account may be created only when customer registration is enabled and Google returns a verified email address.

Administrator and shop-manager users cannot use the customer Google flow. Their access remains separate from public customer authentication.

Google sign-in uses the security controls of the customer's Google account. ShopOS cannot claim that the customer has enabled Google's own two-step verification. ShopOS therefore also offers a separate local TOTP factor for password logins.

## Google Cloud setup

1. Create or select a Google Cloud project intended for public customer identity.
2. Configure the OAuth consent screen for external users.
3. Create an OAuth 2.0 Web application client.
4. In WordPress open `Settings > Kundenanmeldung`.
5. Copy the displayed redirect URI into the client's authorized redirect URIs.
6. Enter the customer Client ID and Client Secret in ShopOS.
7. Enable Google customer login and, if desired, automatic registration.
8. Test with a non-administrator Google account.

Do not reuse the internal Workspace mail OAuth client. Keeping identity and Gmail delivery separated reduces scope, consent and operational risk.

## TOTP enrollment

Customers open `My account > Sicherheit`, start two-factor setup and add the displayed secret to a standards-compatible authenticator app. ShopOS accepts six-digit, 30-second SHA-1 TOTP codes with a one-period clock tolerance.

The first valid code activates TOTP and produces ten recovery codes. Recovery codes are shown once, stored only as password hashes and removed after use. Disabling TOTP or regenerating codes requires both the current password and a valid TOTP or recovery code.

## Data stored

Per customer, ShopOS may store:

- Google `sub` identifier
- Google verified email used for the link
- encrypted TOTP secret
- hashed recovery codes
- bounded security-event history containing time, event and method

No Google access token or refresh token is retained for customer login. The authorization access token is used only to obtain the verified identity during the callback.

## Operational checks

Before public launch:

- verify the exact public HTTPS redirect URI
- test first-time Google registration
- test deliberate linking of an existing account
- test TOTP login, recovery-code use and clock tolerance
- review privacy text for the stored identity and security metadata
- confirm account deletion removes user metadata under the real retention policy
- keep administrator authentication separate and protected with its own controls
