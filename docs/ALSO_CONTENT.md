# Licensed ALSO content integration

## Scope

ShopOS treats ALSO Austria catalogue data as two separate streams:

1. commercial data such as article number, purchase price, stock and lead time;
2. licensed product content such as descriptions, sales arguments, technical characteristics, product-image links, manufacturer PDFs, data sheets and accessory relations.

The content stream is enabled only after the reseller account has the corresponding ALSO/1WorldSync contract and the actual feed format has been verified.

## Supported content packages

ShopOS models these contract levels:

- `none` – no supplier content may be displayed;
- `standard` – standard description, marketing description, selling points, product characteristics, manufacturer PDF links, image links and a standard data-sheet link;
- `extended` – standard content plus extended specifications and accessory SKU relations;
- `bmecat` – machine-readable segmented specifications according to the account-specific BMECAT feed.

The selected package is a safety setting. It does not create or replace an ALSO contract.

## Remote-only media rule

The Austrian content products provide links to images, PDFs and data sheets. ShopOS therefore stores and displays the approved URLs but does not download or persist the linked files locally by default.

```ini
ALSO_CONTENT_MEDIA_MODE=remote_only
ALSO_ALLOW_REMOTE_IMAGES=yes
ALSO_ALLOW_REMOTE_DOCUMENTS=yes
ALSO_ALLOW_LOCAL_IMAGE_CACHE=no
ALSO_ALLOW_LOCAL_DOCUMENT_CACHE=no
```

Local caching stays disabled unless an account-specific written agreement explicitly permits it. Permission is never inferred merely because a URL exists.

## Product texts

Licensed standard and marketing descriptions can be imported into a WooCommerce draft. Supplier content is marked with its source, package, language, import time and feed checksum.

Publication still requires review for factual accuracy, correct language, the actual product variant, safety information and unsupported claims. ShopOS recommends an additional short Ms. FixIT compatibility or buying note, but does not require the entire licensed description to be rewritten.

## Images

The feed can contain several high-resolution image URLs. ShopOS stores them in display order and can use approved remote images as the product main image and gallery without copying their bytes into WordPress.

If a remote image disappears from the feed or becomes unavailable, the product is flagged for review. The Google Merchant feed uses the same approved remote main-image URL as the storefront.

## Documents and data sheets

Approved remote documents are shown as product-page links, for example manufacturer product sheets, standard or extended technical data sheets and installation or compatibility documents.

Each link records its type, source URL, language, package and last-seen time. A linked file is not treated as a declaration of conformity or safety document unless its feed type and compliance review explicitly establish that status.

## Specifications and filters

Extended or BMECAT content can populate structured specifications. ShopOS maps reviewed values into cable attributes such as connector types, length, standard, data rate, charging power and supported resolution.

Supplier values remain suggestions until reviewed. A conflict with an already approved value creates a review item instead of silently overwriting it.

## Accessory relations

Extended content can supply SKU-to-SKU accessory relations. ShopOS maps them through ALSO supplier SKUs and exposes related WooCommerce products only when both articles have permanent `MF-…` numbers and are approved for the Austrian pilot.

## Audit trail

Every content import records the feed checksum, supplier SKU, package, language, received time, changed fields, review status, remote assets and the last time every URL appeared in the feed.
