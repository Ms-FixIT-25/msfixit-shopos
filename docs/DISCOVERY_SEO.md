# Cable discovery, SEO and Google product feed

ShopOS 0.7 introduces a deliberately small discovery layer for the Austria-only cable pilot. It does not promise a ranking position. It makes the storefront technically understandable, crawlable, searchable and consistent so search engines and customers receive the same product facts.

## Search and filter experience

The managed page `/kabel-zubehoer/` contains:

- an accessible text search with keyboard-operable suggestions;
- synonyms for common cable language such as USB-C / Type-C, LAN / Ethernet / Patchkabel and DisplayPort / DP;
- ranking by title, Ms. FixIT article number, GTIN/EAN, manufacturer number, confirmed attributes and description;
- filters for cable type, connector A, connector B, length, standard, charging power, data rate, resolution/frame rate, brand, price and stock;
- mobile filter controls;
- server-rendered result links and pagination that still work without JavaScript.

The pilot catalogue is small enough to search locally. No customer query is sent to an external search service.

## Indexable structure

ShopOS provisions five durable product categories:

- `/produkt-kategorie/usb-kabel/`
- `/produkt-kategorie/hdmi-kabel/`
- `/produkt-kategorie/displayport-kabel/`
- `/produkt-kategorie/netzwerkkabel/`
- `/produkt-kategorie/usb-verlaengerungen/`

Each category has useful introductory text and is linked from the cable landing page. The landing page is linked from the primary navigation.

Product and category pages may be indexed after the shop is deliberately opened. Internal search results and faceted filter combinations receive `noindex,follow`; filter URLs are canonicalized to the clean cable landing page. This avoids creating thousands of near-duplicate index URLs from a catalogue with only a few products.

WordPress core provides `/wp-sitemap.xml`. The generated `robots.txt` references it and discourages crawling common filter parameters.

## Publication gate

A cable cannot remain published unless all required checks pass:

- Austria pilot approval;
- product compliance approval;
- discovery and SEO approval;
- verified main image;
- useful title;
- sufficiently detailed short and long descriptions;
- manual editorial confirmation instead of an unchecked supplier text;
- brand;
- GTIN/EAN or manufacturer part number;
- cable type;
- connector A and connector B;
- cable length;
- cable standard;
- positive sale price.

A failed audit returns the product to draft status. The same audit controls search suggestions, filter results, structured data and the Google feed, so incomplete products cannot leak through a second channel.

Run an audit:

```bash
sudo msfixit-discovery status
sudo msfixit-discovery audit
sudo msfixit-discovery audit 123
```

## ALSO draft suggestions

When an approved ALSO staging item creates a WooCommerce draft, ShopOS may suggest obvious values from the supplier title and description, for example:

- HDMI 2.1;
- 2 m;
- 4K at 120 Hz;
- USB-C to USB-C;
- Cat 6a / RJ45;
- 60 W charging.

Suggestions remain unapproved. They must be checked against the manufacturer data before the product receives discovery and compliance approval.

## Structured data

For approved cable products ShopOS enriches WooCommerce product structured data with:

- stable `MF-…` SKU;
- valid-length GTIN;
- manufacturer part number;
- brand;
- cable properties as `PropertyValue` entries;
- optional Austrian shipping details only after explicit approval.

ShopOS also publishes `WebSite` and `Organization` data. It deliberately does not add the obsolete Google sitelinks search-box markup.

Shipping and return structured data remain off until the values shown to customers and the real fulfilment process are identical.

## Search Console verification

Edit `/etc/msfixit-shopos/discovery.env`:

```ini
GOOGLE_SITE_VERIFICATION=verification-token-from-search-console
BING_SITE_VERIFICATION=verification-token-from-bing
```

These verification meta tags do not install analytics and do not set non-essential cookies.

After the public domain, HTTPS and legal pages are approved:

1. set WordPress search-engine visibility to public;
2. verify the domain in Google Search Console;
3. submit `/wp-sitemap.xml`;
4. inspect the cable landing page and one product URL;
5. monitor indexing, Core Web Vitals and product structured-data reports.

## Google Merchant feed

The built-in feed is intentionally disabled by default:

```ini
GOOGLE_MERCHANT_FEED_ENABLED=no
```

Before enabling it, configure and test at least:

```ini
GOOGLE_MERCHANT_FEED_ENABLED=yes
GOOGLE_TARGET_COUNTRY=AT
GOOGLE_CONTENT_LANGUAGE=de
GOOGLE_SHIPPING_SERVICE=Standardversand Österreich
GOOGLE_SHIPPING_COST_EUR=4.90
GOOGLE_DELIVERY_MIN_DAYS=1
GOOGLE_DELIVERY_MAX_DAYS=3
GOOGLE_RETURN_DAYS=14
```

The feed then appears at:

```text
https://SHOP-DOMAIN/google-products.xml
```

It includes only products that pass the complete publication audit. The feed uses the permanent Ms. FixIT SKU as its product ID and includes title, description, URL, image, availability, EUR price, brand, GTIN/MPN, product type, Austrian shipping cost and delivery window.

Do not enable the feed with placeholder shipping values. Merchant Center compares feed data, structured data and the landing page; inconsistent values can cause product disapproval.

## Product titles and descriptions

Use titles that describe the actual product instead of stuffing keywords:

```text
USB-C auf USB-C Kabel 2 m – 60 W, USB 2.0, Schwarz
HDMI-2.1-Kabel 2 m – 4K 120 Hz / 8K 60 Hz
Cat-6a-Patchkabel 3 m – RJ45, geschirmt, Schwarz
```

A useful description should explain:

- intended use;
- connector direction;
- length;
- supported standard;
- charging power or data rate where applicable;
- supported resolution/frame rate where applicable;
- important limitations;
- package contents;
- manufacturer and product identity.

Do not copy long supplier marketing text unchanged. It is often duplicated across many retailers and may include unsupported claims.

## Performance and privacy

The discovery JavaScript and CSS are small local assets. Product search runs on the Raspberry Pi and scans only approved pilot products. Images use WordPress/WooCommerce thumbnail sizes and browser lazy loading.

No analytics, advertising pixels or consent-dependent tracking are added by this component. Search Console ownership verification and the Merchant product feed work without them.
