# Help center and verified partner programmes

## Purpose

ShopOS provides a customer-facing help center that is useful before and after a purchase. It is not a collection of supplier advertising pages. The managed pages use original Ms. FixIT wording, normal crawlable HTML links and a restricted internal help search.

Managed pages:

```text
/hilfe/
/hilfe/kabelberater/
/hilfe/fritzbox-wlan/
/hilfe/reparaturwissen/
/hilfe/bestellung-versand-rueckgabe/
```

The main menu links to `/hilfe/`. The help landing page links to every topic page with normal `<a href>` links so customers and search engines can discover the content without submitting the search form.

## Help search

The search form on `/hilfe/` searches only the managed help pages. It does not mix products, legal drafts, account pages or ordinary WordPress content into the help results.

A help-search result URL receives `noindex, follow`. The underlying topic pages remain indexable after the normal ShopOS go-live and indexing approval.

## Cable adviser

The cable adviser asks for:

- source connector;
- destination connector;
- intended use;
- preferred length.

It provides warnings about common technical misunderstandings and links to the filtered cable catalogue. It does not claim compatibility solely from the connector shape. Final publication still depends on the normal product-data and compliance checks.

## FRITZ!Box and WLAN information

The FRITZ!Box help page covers original Ms. FixIT service descriptions such as:

- initial setup;
- WLAN and mesh planning;
- repeaters and wired access points;
- DECT and telephony;
- guest network and user rights;
- VPN and remote access;
- migration to another FRITZ!Box.

FRITZ! and FRITZ!Box are third-party trademarks. The page can exist without displaying any partner claim. A public programme claim appears only when the corresponding profile has current evidence and is deliberately enabled.

## iFixit Pro and repair knowledge

The repair page describes Ms. FixIT's own process, preparation, data protection and repair decision criteria.

Public iFixit guides may be linked. ShopOS does not copy iFixit guide text, photographs or logos into the commercial site by default. The public iFixit content licence contains a non-commercial condition, and the iFixit logo requires separate permission.

An iFixit Pro membership is not presented as an independent certification. The default public wording is only `iFixit Pro Mitglied`, and it remains hidden until verified.

## Evidence-based partner profiles

Partner records are stored in `shopos_catalog.partner_profiles`.

Seeded profiles:

```text
fritz-business-at
iFixit-pro
```

The actual iFixit code is lowercase:

```text
ifixit-pro
```

Every public profile requires:

- exact programme name;
- verified membership status;
- evidence file below `/data/partners/evidence`;
- SHA-256 checksum of that evidence;
- reviewer name and time;
- reviewed public wording;
- non-expired validity, when the programme is time-limited;
- deliberate public enablement.

A membership is never automatically described as `certified`, `authorised`, `premium` or another higher status unless the evidence supports the exact wording.

## Logos and marketing assets

Membership evidence and logo rights are separate.

A logo is shown only when all of the following are present:

- separately reviewed usage rights;
- evidence file and SHA-256 checksum;
- reviewer and review time;
- HTTPS asset URL;
- public partner profile still enabled and valid.

This supports a logo or marketing asset supplied through a partner portal without treating general programme membership as permission to use every brand asset.

## Administration

List profiles:

```bash
sudo msfixit-partners list
```

Inspect a profile:

```bash
sudo msfixit-partners show fritz-business-at
sudo msfixit-partners show ifixit-pro
```

Place evidence below the protected directory:

```text
/data/partners/evidence/
```

Verify the exact FRITZ! programme and public wording:

```bash
sudo msfixit-partners verify \
  fritz-business-at \
  "FRITZ! Business-Partnerprogramm Österreich" \
  2026-12-31 \
  /data/partners/evidence/fritz-status.pdf \
  shopadmin \
  "Teilnahme am FRITZ! Business-Partnerprogramm Österreich"
```

Verify iFixit Pro without claiming a certification:

```bash
sudo msfixit-partners verify \
  ifixit-pro \
  "iFixit Pro" \
  none \
  /data/partners/evidence/ifixit-pro.pdf \
  shopadmin \
  "iFixit Pro Mitglied"
```

Record separately approved logo rights:

```bash
sudo msfixit-partners logo \
  fritz-business-at \
  https://SHOP-DOMAIN/PATH/APPROVED-FRITZ-ASSET.svg \
  /data/partners/evidence/fritz-logo-rights.pdf \
  shopadmin
```

Enable public display only after reviewing the stored record:

```bash
sudo msfixit-partners enable fritz-business-at shopadmin
sudo msfixit-partners enable ifixit-pro shopadmin
```

Disable a claim immediately:

```bash
sudo msfixit-partners disable fritz-business-at shopadmin "status not renewed"
```

## Expiry and tampering protection

ShopOS refuses to enable an expired profile. The WordPress display also filters expired profiles at query time.

Before enablement, the CLI recalculates the membership-evidence SHA-256 value. A modified or missing evidence file blocks publication.

Partner identity, deletion, public enablement and logo use are additionally protected by MariaDB triggers. All changes are recorded in `partner_profile_audit`.

## Backup

The database profile and audit history are part of the normal `shopos_catalog` backup. The evidence directory must also be included in the ShopOS data backup because the file and database checksum together form the proof chain.

## Deliberate boundary

ShopOS can prevent unsupported public claims, expired status and unverified logo use. It cannot interpret a private partner agreement by itself. The exact programme name, validity and asset rights still require a human review of the current account documents or portal terms.
