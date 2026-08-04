# Google Workspace in ShopOS

ShopOS sends all WordPress, WooCommerce and service-request mail through the Google Workspace mailbox `office@msfixit.at`.

The integration uses OAuth 2.0 and the Gmail API. It does not store the Google account password, does not need a static public IP address and does not request inbox, contact, calendar or Drive access.

## What is included

- fixed sender: `Ms. FixIT <office@msfixit.at>`
- Google OAuth connection from WordPress administration
- Gmail API transport for the existing `wp_mail()` interface
- plain-text and HTML mail
- To, Cc, Bcc and Reply-To recipients
- readable local attachments
- encrypted client secret, refresh token and cached access token
- connection state, last success and last error in WordPress
- test-mail action
- Site Health check and dashboard status
- direct launch buttons for Gmail, Calendar, Drive and the Workspace Admin console

Calendar and Drive are launch links only. ShopOS currently requests no Calendar or Drive API scopes.

## Google Cloud preparation

Use a Google Cloud project owned by the Ms. FixIT Google Workspace organization.

1. Enable the Gmail API in the project.
2. Open Google Auth Platform.
3. Configure the app name, support address and contact address.
4. Set the audience to **Internal** when the project belongs to the Workspace organization and only Ms. FixIT users will connect it.
5. Add these data-access scopes:
   - `openid`
   - `email`
   - `https://www.googleapis.com/auth/gmail.send`
6. Create an OAuth client of type **Web application**.
7. Copy the exact authorized redirect URI shown in WordPress under **Settings > Google Workspace** into the OAuth client.

Do not add inbox-reading, Drive or Calendar scopes merely for mail delivery.

## Connect ShopOS

1. Open **WordPress > Settings > Google Workspace**.
2. Paste the OAuth client ID and client secret.
3. Save the credentials.
4. Select **Connect with Google Workspace**.
5. Sign in as `office@msfixit.at` and approve the requested send permission.
6. Return to ShopOS and send a test mail.

ShopOS rejects a different Google account during the callback.

## Secret handling

The OAuth client secret and refresh token are encrypted before being written to WordPress options. Sodium secret-box encryption is preferred; AES-256-GCM is the fallback. Access tokens are short-lived, encrypted and cached only until shortly before expiry.

The encryption key is derived from the WordPress authentication salt. Changing WordPress salts invalidates stored Workspace secrets and requires reconnecting the account.

## Sending behavior

The MU plugin intercepts `wp_mail()` before the normal local mail transport. It builds a MIME message with WordPress' bundled PHPMailer and submits the base64url-encoded message to the Gmail API `users.messages.send` endpoint.

When Workspace is not connected or Google rejects a request, ShopOS fails closed and reports the error instead of silently claiming that mail was sent.

## Operational checks

Before public launch:

- verify `office@msfixit.at` is a real Workspace mailbox and not only an unconfigured alias;
- verify SPF, DKIM and DMARC for `msfixit.at` in Google Workspace;
- send test messages to at least Gmail, Outlook and an Austrian provider;
- test WooCommerce order mail, password-reset mail and service-request confirmations;
- confirm attachments and HTML order templates arrive correctly;
- document who may revoke or renew the OAuth client;
- include Workspace configuration and recovery information in the encrypted external backup plan.

## Disconnect or recover

The WordPress settings page can remove the stored refresh token. Revoking ShopOS in the Google account or deleting the OAuth client also stops delivery. Reconnect after restoring a backup, changing WordPress salts or rotating the OAuth client secret.
