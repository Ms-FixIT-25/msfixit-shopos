# Service requests and repair status

## Purpose

ShopOS provides a small customer-service intake instead of relying on unstructured first-contact e-mails. It is intended for repair requests, diagnosis, setup work, FRITZ!Box/WLAN support, data transfer, purchase advice and order questions.

The feature is deliberately conservative:

- it creates no chargeable order;
- it accepts no file uploads;
- it asks customers not to submit passwords, PINs or payment data;
- it stores requests as private WordPress records;
- it exposes status only through a reference plus a secret access key;
- it remains publicly disabled until a real privacy policy is published and an administrator explicitly enables it.

## Customer pages

Provisioning creates:

```text
/service-anfrage/
/service-status/
```

The request page appears in the primary navigation. The status page is linked from the request page and from the individual tracking URL.

## Fail-closed public enablement

The form is not publicly usable after first boot. Both conditions must be true:

1. the WordPress page with slug `datenschutz` is published;
2. the WordPress option `msfixit_service_public_enabled` equals `yes`.

After the reviewed privacy text has been published, enable the intake deliberately:

```bash
sudo -u www-data env HOME=/tmp /usr/local/bin/wp \
  --path=/srv/www/wordpress \
  option update msfixit_service_public_enabled yes
```

Disable it again without deleting existing requests:

```bash
sudo -u www-data env HOME=/tmp /usr/local/bin/wp \
  --path=/srv/www/wordpress \
  option update msfixit_service_public_enabled no
```

The dashboard widget shows whether public intake is currently enabled or blocked.

## Request security

Each successful request receives:

- a human-readable reference such as `MF-SVC-20260804-ABC123`;
- a random 32-character access key;
- a one-way password hash of that access key in WordPress;
- a private service-request post containing the submitted data;
- an initial `received` status event.

The plaintext access key is shown in the redirect URL and sent to the customer by e-mail. It is not stored in readable form. Losing the link therefore requires an administrator-assisted replacement workflow; ShopOS does not reveal the existing key.

The status page uses `noindex`, `nofollow`, `noarchive`, `Referrer-Policy: no-referrer` and private no-store cache headers. It never displays the customer's name, e-mail address, telephone number or full fault description.

## Submission controls

The form uses:

- WordPress nonces;
- a honeypot field;
- per-client submission rate limiting;
- strict allowlists for request, device and contact types;
- input length limits;
- WordPress text and e-mail sanitization;
- mandatory privacy consent;
- a separate public-enablement check in both form rendering and submission handling.

Status lookups are also rate limited and require both reference and secret key.

## Administration

Administrators and WooCommerce shop managers receive access to the private `Serviceanfragen` post type.

The backend provides:

- status, request type, device and contact columns;
- status filtering;
- full submitted contact and fault details;
- a public status note with a warning against entering sensitive internal data;
- a bounded status history;
- a dashboard count of open requests.

Supported states include received, reviewing, awaiting customer, appointment, device received, diagnosis, quote, approval, repair, waiting for parts, testing, ready, completed and cancelled.

## E-mail boundary

ShopOS calls the normal WordPress `wp_mail()` function for:

- an administrator notification without the full fault text;
- a customer receipt containing the reference and secret tracking URL.

Delivery still depends on a correctly configured and tested mail transport. A stored request remains valid even if mail delivery fails. SMTP credentials and provider-specific settings remain outside Git.

## Privacy and retention boundary

The feature records personal data, consent time, request details and operational status. A reviewed privacy text, lawful basis, retention period, deletion process and access controls are still operational responsibilities.

ShopOS does not automatically delete service requests because an unreviewed automatic retention policy could remove records that are still required for an active contract, warranty, dispute or statutory obligation. Retention and deletion automation should be added only after the real policy has been approved.
