# Carrier integration and automatic labels

Research status: 2026-08-03. Contract conditions and API products can change. Before activating an adapter, verify the current documentation and credentials with the carrier's Austrian business-customer team.

## Common data model

ShopOS normalizes the information required by parcel carriers before translating it into a provider-specific request.

### Sender

- legal/business name;
- street, postcode, city and ISO country code;
- contact name;
- e-mail and telephone;
- carrier customer/account number;
- pickup or depot relationship where required.

### Recipient

- person or company name;
- street and house number;
- additional address line;
- postcode, city and ISO country code;
- e-mail and telephone for notifications;
- optional pickup-point or parcel-shop identifier.

### Package

- actual weight;
- length, width and height when required by the service;
- package count;
- contents description;
- value and currency;
- selected carrier product and additional services;
- shipping date and customer reference.

### Switzerland and other third countries

- clear goods description rather than generic wording;
- quantity and unit;
- value and currency;
- net and gross weight;
- country of origin;
- customs tariff/HS number;
- commercial or pro-forma invoice as applicable;
- sender EORI where required;
- incoterm and who bears duties/taxes;
- reason for export;
- recipient tax/import data where required by the chosen service.

ShopOS stores HS code and country of origin on the WooCommerce product and carries them into the order snapshot. Missing customs data must block automatic third-country label creation rather than being guessed.

## Austrian Post

### Access needed

- Austrian Post business-customer agreement;
- access to Post Labelcenter or the contract/API solution assigned by the Post sales contact;
- customer/account and product data provided by Austrian Post;
- approved label and advance-notification format.

### Relevant capabilities

The official Post Labelcenter creates parcel labels, shipment lists and electronic advance data. It can receive shipment data from an ERP system. Austrian Post also publishes XML data structures and API products for areas such as tracking, branches, pickup orders and return labels; access is coordinated through the carrier.

### ShopOS adapter plan

1. use the contract API when credentials and current specification are supplied;
2. otherwise export the accepted Labelcenter data format;
3. archive the returned PDF/ZPL label and tracking number;
4. queue the label for the configured CUPS printer;
5. create the required shipment list or manifest.

Recommended first carrier for Austrian-origin shipments because it matches the business location and avoids a foreign-origin contract.

## DPD Austria

### Access needed

- DPD business-customer contract and customer/depot details;
- myDPD Business access;
- API credentials and the current Austrian web-service specification supplied by DPD;
- agreed products and notification services.

DPD's business tools create digital parcel labels. DPD documents a SOAP shipping interface in its business environment, but the exact Austrian endpoint, authentication and product codes must be obtained from DPD Austria rather than copied from a German account.

### Typical request data

- DPD customer/depot relationship;
- sender and recipient;
- parcel weight and count;
- product/service code;
- reference numbers;
- e-mail/telephone for Predict or notifications;
- customs/commercial-invoice data for Switzerland.

### ShopOS adapter plan

- SOAP client isolated in `dpd_at` adapter;
- no German endpoint or product identifier hard-coded;
- returned parcel number, tracking and label archived;
- cancellation and reprint supported through the same shipment record.

## GLS Austria

### Access needed

- GLS business-customer number;
- YourGLS credentials for the portal workflow or ShipIT API credentials for direct integration;
- assigned depot/contact and enabled products;
- current label format and printer settings.

GLS positions YourGLS for smaller regular shipping volumes and ShipIT as the integration API. Package weight is a required value for API shipping. For Switzerland, commercial-invoice/customs information and tariff numbers are needed.

### ShopOS adapter plan

- `gls_at` ShipIT adapter for direct requests;
- YourGLS-compatible manual fallback during onboarding;
- mandatory positive package weight validation;
- customs completeness check for CH;
- PDF label by default, ZPL only for a tested thermal printer.

## UPS

### Access needed

- UPS.com profile;
- shipper account linked to the profile;
- application created in the UPS developer portal;
- OAuth client ID and client secret;
- API products enabled for the account, primarily Shipping and Tracking;
- billing/shipper account number and agreed services.

UPS APIs use OAuth. Credentials belong in a root-only carrier configuration file and must not be stored in WordPress or Git.

### Typical request data

- shipper and ship-from address;
- recipient and optional sold-to address;
- UPS service code;
- package weight and dimensions;
- payment/billing arrangement;
- references and notifications;
- customs lines, invoice and duties/tax arrangement for CH.

### ShopOS adapter plan

- OAuth token cache outside WordPress;
- Shipping API request from the background worker;
- tracking number and base64 label decoded and archived;
- Track API updates mapped to the shipment state;
- token refresh and retry with exponential backoff.

## DHL Paket Germany

DHL Paket's German business-customer API requires a DHL business contract, access to the Geschäftskundenportal, EKP/billing numbers and API authentication. The standard business-customer shipping API supports shipments whose origin is Germany.

Therefore `dhl_de` remains disabled for the initial Austrian-origin shop. It becomes appropriate only when Ms. FixIT uses:

- a German warehouse;
- a German fulfillment partner;
- or another valid German shipper origin under a DHL contract.

Do not route an Austrian sender through the German DHL adapter merely because the destination is Germany.

## Carrier activation states

Every carrier account begins with `enabled = 0`.

```text
post_at  disabled
DPD AT   disabled
GLS AT   disabled
UPS      disabled
DHL DE   disabled (German origin only)
```

Activation requires:

1. signed business-customer agreement;
2. production API credentials;
3. sandbox or test-label approval where offered;
4. validated sender and product codes;
5. tested cancellation and reprint;
6. tested A6 label on the real printer;
7. test shipment and tracking;
8. separate CH customs test before Swiss automatic shipping.

## Label formats and printers

Preferred order:

1. PDF A6 / 4×6 inch for broad compatibility;
2. PNG only as a fallback;
3. ZPL for a deliberately selected Zebra-compatible thermal printer.

The carrier response is archived before printing. A print failure therefore never requires buying a second label; the same archived label can be requeued.

ShopOS uses a named CUPS queue:

```text
PRINTER_A4=office-a4
PRINTER_LABEL=parcel-a6
```

The print worker records:

- requested file;
- printer queue;
- copy count;
- CUPS job ID;
- attempts;
- final success or failure.

## Implementation boundary in ShopOS 0.4

Included:

- neutral shipment and package database;
- per-carrier account/configuration records;
- carrier-request outbox event;
- customs fields on WooCommerce products;
- archived label and tracking storage;
- PDF/ZPL/PNG label import;
- automatic CUPS print queue;
- retry-safe event processing;
- explicit disabled state until credentials exist.

Not yet claimed as complete:

- production API calls to Austrian Post, DPD AT, GLS AT or UPS;
- automatic carrier selection based on live contract prices;
- automatic customs filing;
- DHL Germany shipping from an Austrian origin.

Those adapters require the actual contract-specific credentials, product codes and current provider specifications. They plug into the existing shipment record without changing orders, article numbers or documents.
