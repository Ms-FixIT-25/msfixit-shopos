# ShopOS Office & Fulfillment

## Purpose

ShopOS Office is the independent commercial document and fulfillment core for Ms. FixIT. WooCommerce remains the order channel, while Office owns immutable invoices, credit notes, delivery notes, payments, reminders, ProSaldo handoffs, shipments, labels and print jobs.

```text
WooCommerce order
      |
      v
Office event outbox
      |
      +--> invoice / credit note / delivery note
      +--> payment allocation and open item
      +--> reminder workflow
      +--> ProSaldo handoff
      +--> shipment and carrier adapter
      +--> CUPS print queue
```

WordPress does not render PDFs or contact carriers during checkout. It inserts small events into MariaDB. Systemd timers process those events asynchronously, so a mail, PDF, printer or carrier failure cannot block a customer checkout.

## Safe defaults

The appliance deliberately starts in review mode:

- business configuration is not approved;
- country tax profiles are `review_required`;
- invoice and delivery-note drafts may be created;
- final invoice numbering is blocked until business and tax data are approved;
- automatic e-mail dispatch is off;
- automatic printing is off;
- reminder fees and interest are zero;
- friendly reminders may be prepared automatically;
- formal reminder levels require manual approval;
- every carrier account is disabled.

The settings live in `/etc/msfixit-shopos/business.env`. Secrets must never be committed to Git.

## Document lifecycle

Supported document types:

- invoice;
- credit note;
- delivery note;
- commercial invoice;
- pro-forma invoice.

Each document starts as a draft. Finalization performs the following steps:

1. verify that the approved business configuration exists;
2. verify that the tax profile is not `review_required`;
3. allocate the next protected document number;
4. render the PDF with TCPDF;
5. calculate and store the PDF SHA-256 hash;
6. mark the database snapshot final;
7. create optional e-mail and print jobs.

Final document numbers use independent yearly sequences, for example:

```text
RE-2026-000001   invoice
GU-2026-000001   credit note
LS-2026-000001   delivery note
MA-2026-000001   reminder
VS-2026-000001   shipment
```

A database trigger blocks changes to the commercial content of a final document. Final documents and their lines cannot be deleted. A correction therefore becomes a new credit note or correction document instead of rewriting history.

## WooCommerce events

The WordPress MU plugin queues these events:

- payment completed;
- order moved to processing;
- order completed;
- refund created.

The stored order snapshot includes:

- source order ID and order number;
- billing and shipping address;
- consumer or business classification;
- currency and totals;
- payment method, transaction reference and payment time;
- every line including the permanent `MF-…` article number;
- item net, tax and gross amounts;
- product weight and dimensions;
- customs tariff number and country of origin when maintained.

Repeated WooCommerce hooks cannot create duplicate invoices because source system, source document ID and document type are unique.

## Payments and open items

Payments are stored separately and allocated to invoices. The system supports:

- payment-provider transaction IDs;
- manual bank-payment entry;
- partial payments;
- overpayments without silently changing the invoice;
- remaining open balance calculation;
- payment-source audit data.

Example:

```bash
sudo msfixit-office payment-record \
  RE-2026-000001 \
  bank \
  BANK-2026-08-04-4711 \
  129.90 \
  EUR \
  "2026-08-04 10:30:00" \
  RE-2026-000001
```

A future bank or payment-provider adapter writes into the same payment model. The invoice model does not change.

## Dunning workflow

A daily systemd timer checks final overdue invoices with a remaining balance.

Default levels are created separately for consumer and business customers in AT, DE and CH:

| Level | Default time | Default action |
|---|---:|---|
| 0 | 3 days after due date | friendly payment reminder |
| 1 | 10 days after due date | approval required |
| 2 | 17 days after due date | approval required |

All default fees and interest rates are zero. Legal and contractual settings must be reviewed before enabling amounts.

A document can be placed on a dunning hold, for example during a complaint or payment investigation:

```bash
sudo msfixit-office hold RE-2026-000001 on "Reklamation in Bearbeitung"
sudo msfixit-office hold RE-2026-000001 off
```

Preview the next run:

```bash
sudo msfixit-office dunning-run --dry-run
```

Approve and render a formal reminder:

```bash
sudo msfixit-office reminder-approve REMINDER_UUID
```

## ProSaldo handoff

ProSaldo currently provides no direct shop API and no invoice-data CSV import. ShopOS therefore does not pretend that a fully automatic booking interface exists.

Instead it creates a controlled ZIP handoff containing:

```text
pdf/
  RE-2026-000001.pdf
  GU-2026-000001.pdf
documents.csv
contacts.csv
products.csv
manifest.json
README.txt
```

`documents.csv` is the booking and control list. `contacts.csv` and `products.csv` provide importable master-data help. Every PDF and control file is included in the hash manifest.

Create a monthly handoff:

```bash
sudo msfixit-office prosaldo-export 2026-08-01 2026-08-31
```

After PDFs have been uploaded, reviewed and booked in ProSaldo, mark the ShopOS handoff complete:

```bash
sudo msfixit-office prosaldo-list
sudo msfixit-office prosaldo-mark-imported EXPORT_UUID
```

When ProSaldo adds a supported API, an adapter can replace the manual upload step without changing invoice numbers or the document database.

## Delivery notes

A delivery-note draft is created from the order snapshot when the order enters processing. It includes:

- delivery-note number;
- order reference;
- recipient and delivery address;
- `MF-…` article numbers;
- descriptions and quantities;
- no sales prices.

Automatic finalization and A4 printing remain off until the workflow and printer are tested.

## Shipments and packages

Shipments are separate from orders because one order may later require several shipments or packages.

Each package stores:

- actual weight;
- length, width and height;
- contents description;
- declared value and currency;
- optional carrier metadata.

A shipment stores:

- selected carrier and service;
- sender and recipient;
- planned shipping date;
- customs data;
- carrier shipment ID;
- tracking number;
- label format and archived label;
- raw carrier response.

Create a shipment draft from JSON:

```bash
sudo msfixit-office shipment-create shipment.json
```

Until a live carrier adapter is activated, a label downloaded from the carrier portal can already be archived and printed through the same pipeline:

```bash
sudo msfixit-office label-import \
  VS-2026-000001 \
  /tmp/carrier-label.pdf \
  TRACKING123
```

## Printing

ShopOS uses the normal CUPS client command `lp`. The image does not run an unnecessary local printer daemon by default.

Recommended production arrangement:

- A4 printer queue for invoices, reminders and delivery notes;
- A6/4×6-inch label queue for parcel labels;
- a network printer or an existing CUPS print server;
- PDF as the preferred carrier-label format for broad printer compatibility;
- ZPL only when a compatible thermal label printer is deliberately selected.

For a USB-only printer connected directly to the Raspberry Pi, the optional CUPS server and the correct printer driver must be installed and tested separately.

Process queued jobs manually:

```bash
sudo msfixit-office print-run
```

The normal timer retries failed jobs and stops after repeated failures instead of creating an endless print loop.

## Administration

```bash
sudo msfixit-office status
sudo msfixit-office document-create invoice order.json
sudo msfixit-office document-finalize DOCUMENT_UUID
sudo msfixit-office document-send RE-2026-000001
sudo msfixit-office dunning-run --dry-run
sudo msfixit-office carrier-list
sudo msfixit-office print-run
sudo msfixit-office worker-run
```

## Backups

The normal ShopOS backup includes:

- WordPress database and uploads;
- article master;
- Office database;
- invoice, credit-note, delivery-note and reminder PDFs;
- labels, shipment manifests and ProSaldo handoffs;
- protected ShopOS configuration and carrier credentials.

A backup stored only on the Raspberry Pi is not sufficient. An external encrypted destination and restore test remain mandatory before production operation.
