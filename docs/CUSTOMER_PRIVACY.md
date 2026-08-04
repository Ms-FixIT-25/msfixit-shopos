# ShopOS customer privacy and personal-data access

ShopOS provides a customer-facing privacy center under `My account > Datenschutz`.

## Customer-facing transparency

The privacy center shows:

- the customer profile currently linked to the account
- whether Google sign-in and local TOTP are enabled
- counts for WooCommerce orders, service requests, Office documents and allocated payments
- the categories of personal data processed
- purposes and intended legal bases
- sources of the data
- recipient or recipient categories
- general retention rules
- contact and complaint routes
- a statement that ShopOS does not make solely automated decisions with legal or similarly significant effect on the customer account

Customers can use the existing WooCommerce account pages to correct profile and address data.

## Self-service data copy

A logged-in customer can request a data copy with one button. ShopOS sends a confirmation link to the account email address. The link:

- contains a random 256-bit token
- is valid for 24 hours
- can be used only once
- is stored only as a SHA-256 hash
- returns a no-store, noindex JSON download

The JSON payload contains:

- controller and contact information
- processing categories, purposes, legal bases, sources, recipients and retention information
- customer profile data
- Google-link and account-security status
- bounded security-event history
- WooCommerce orders, addresses, line items, payment method and transaction reference
- service requests, contact data, device information, fault description, consent time and status history
- matching Office orders, finalized documents and allocated payments

The export fails closed when WooCommerce or the independent Office database cannot be read completely. The confirmation token remains valid so the customer can retry.

## Security exclusions

The export deliberately does not disclose credentials or system secrets, including:

- password hashes
- encrypted TOTP secrets
- recovery-code hashes
- OAuth client secrets or tokens
- service-request access secrets or their hashes
- database credentials
- internal filesystem paths
- raw payment-provider payloads

Instead, the export states that the relevant security material exists and why it is excluded.

## WordPress privacy integration

ShopOS also registers a `wp_privacy_personal_data_exporters` callback. Administrators using WordPress `Tools > Export Personal Data` receive the custom ShopOS customer-security, service-request and Office datasets in addition to exporters registered by WordPress and WooCommerce.

## Processing inventory

The built-in catalog covers:

1. customer account and master data
2. orders, delivery and service performance
3. invoices, payments and accounting
4. service and repair requests
5. authentication and account security
6. transactional and service email
7. technical security and log data

The catalog is an operational implementation aid, not a substitute for a reviewed privacy notice, processor inventory, records of processing activities, retention schedule or data-processing agreements.

## Legal and operational review before launch

Before production, review at least:

- controller identity and contact details
- the exact legal basis for each real processing activity
- actual processors and recipients, including hosting, Google Workspace, payment, shipping and suppliers
- international-transfer safeguards where applicable
- exact log, email, service, warranty and accounting retention periods
- the public privacy notice under Articles 13 and 14 GDPR
- response handling for access, rectification, restriction, objection, portability and complaints
- identity verification for requests outside an authenticated account
- manual handling when data exists in systems not connected to the automated export

Under Austrian accounting and tax rules, accounting records may generally require seven-year retention and longer retention when proceedings are pending. Final legal wording and the real retention schedule require professional review.
