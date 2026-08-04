# ShopOS customer authentication

ShopOS provides customer-facing authentication separately from the internal Google Workspace mail connection.

## Features

- Sign in with Google for WooCommerce customer accounts
- separate external Google OAuth web client
- authorization-code flow with one-time state and PKCE S256
- callback bound to the browser that started the login
- verified Google email and stable Google subject identifier
- optional automatic creation of new `customer` users
- deliberate linking of an existing account from the authenticated security page
- optional TOTP two-factor authentication for password login
- ten one-time recovery codes stored only as password hashes
- close all other WordPress sessions
- bounded account-security audit history
- payment-gated self-service account deletion with email confirmation
- WooCommerce `My account > Sicherheit` endpoint

## Security boundaries

The Google customer client is not the Workspace Gmail client. Use a separate external OAuth client with only:

```text
openid email profile
```

The customer flow receives no Gmail, Drive, Calendar, Contacts or Workspace administration permission.

The one-time OAuth state also contains a hash of a short-lived HttpOnly, SameSite browser cookie. A callback without the matching browser token is rejected. This prevents an authorization response started in another browser from being used as a customer login.

Existing local accounts are never linked solely because Google returns the same email address. The customer must first authenticate to the existing account and connect Google from `My account > Sicherheit`. A new account may be created only when customer registration is enabled and Google returns a verified email address.

An account created only through Google cannot remove its Google link until the customer has deliberately created a local password. This prevents accidental loss of the account's only usable sign-in method.

Administrator and shop-manager users cannot use the customer Google flow or the public self-deletion flow. Their access remains separate from public customer authentication.

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

## Self-service account deletion

Customers can request account deletion under `My account > Sicherheit`. The normal path is deliberately simple:

1. ShopOS checks WooCommerce orders and the independent Office payment allocation ledger.
2. If any amount is outstanding, the self-service button remains disabled and shows the blocking order or invoice.
3. If the balance is clear, the customer requests a confirmation email.
4. The email contains a random one-time link valid for 24 hours. Only a SHA-256 hash of that token is stored.
5. ShopOS repeats the payment check when the link is opened.
6. The customer login, profile, Google link, TOTP data, recovery codes and every active session are removed.

The check fails closed when WooCommerce or the Office ledger cannot be reached. A technical outage must never be interpreted as a paid balance.

When no transaction records exist, the WordPress customer user is deleted. When historical orders or finalized documents exist, ShopOS replaces the account with a non-login pseudonymous retention shell so that immutable order and document references remain valid. The shell has no role, usable email, profile data, Google link, password known to anyone or active session.

Finalized invoices, payment allocations and other legally retained accounting records are not altered by account deletion. They live in the separate Office core and follow the configured statutory and legal-claim retention rules. A blocked self-service deletion never prevents the customer from contacting `office@msfixit.at` with a broader privacy request; data not required for payment, legal claims or statutory retention must still be assessed separately.

## Data stored

Per active customer, ShopOS may store:

- Google `sub` identifier
- Google verified email used for the link
- whether the account originated from Google login
- whether a separate local password was deliberately established
- encrypted TOTP secret
- hashed recovery codes
- bounded security-event history containing time, event and method

During a pending deletion request, ShopOS additionally stores a hashed confirmation token and its expiry. After anonymization, only a deletion marker, deletion time and opaque retention reference remain on the customer shell.

The short-lived browser-binding token is kept only in an HttpOnly cookie and its keyed hash in a transient login record. No Google access token or refresh token is retained for customer login. The authorization access token is used only to obtain the verified identity during the callback.

## Operational checks

Before public launch:

- verify the exact public HTTPS redirect URI
- test first-time Google registration
- test deliberate linking of an existing account
- test rejection of a callback in a different browser
- test setting a local password before disconnecting a Google-only account
- test TOTP login, recovery-code use and clock tolerance
- test deletion with no orders
- test deletion with paid retained invoices
- test blocking on a WooCommerce payment and an Office balance
- test fail-closed behavior while the Office database is unavailable
- review privacy text for identity, security, deletion and retention metadata
- document the exact statutory retention schedule and later archive cleanup
- keep administrator authentication separate and protected with its own controls
