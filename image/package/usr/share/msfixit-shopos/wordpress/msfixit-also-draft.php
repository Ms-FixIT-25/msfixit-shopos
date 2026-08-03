<?php
/**
 * Creates or updates one WooCommerce draft from an approved ALSO staging item.
 * Invoked only through root-controlled msfixit-also with a temporary JSON file.
 */

declare(strict_types=1);

if (!defined('ABSPATH')) {
    exit(1);
}

if (!class_exists('WC_Product_Simple')) {
    WP_CLI::error('WooCommerce is not active.');
}

require_once '/usr/share/msfixit-shopos/discovery/discovery-lib.php';

$payloadFile = getenv('MSFIXIT_ALSO_PAYLOAD_FILE') ?: '';
if ($payloadFile === '' || !is_readable($payloadFile)) {
    WP_CLI::error('ALSO payload file is unavailable.');
}

$payload = json_decode((string) file_get_contents($payloadFile), true, 512, JSON_THROW_ON_ERROR);
$article = strtoupper(trim((string) ($payload['article_number'] ?? '')));
if (!preg_match('/^MF-[0-9]{8}$/', $article)) {
    WP_CLI::error('Invalid Ms. FixIT article number.');
}

$existingId = wc_get_product_id_by_sku($article);
$product = $existingId > 0 ? wc_get_product($existingId) : new WC_Product_Simple();
if (!$product instanceof WC_Product_Simple) {
    WP_CLI::error('Existing SKU belongs to an incompatible WooCommerce product type.');
}

$name = sanitize_text_field((string) ($payload['name'] ?? 'Unbenannter Artikel'));
$description = wp_kses_post((string) ($payload['description'] ?? ''));
$shortDescription = wp_kses_post((string) ($payload['short_description'] ?? ''));
$attributeSuggestions = msfixit_discovery_infer_cable_attributes(
    $name . ' ' . wp_strip_all_tags($shortDescription) . ' ' . wp_strip_all_tags($description)
);

$product->set_name($name);
$product->set_sku($article);
$product->set_status('draft');
$product->set_catalog_visibility('hidden');
$product->set_regular_price(wc_format_decimal((string) ($payload['regular_price'] ?? '')));
$product->set_description($description);
$product->set_short_description($shortDescription);
$product->set_manage_stock(true);
$product->set_backorders('no');
$stock = $payload['stock_quantity'] ?? null;
if ($stock === null) {
    $product->set_stock_quantity(0);
    $product->set_stock_status('outofstock');
} else {
    $quantity = max(0, (int) $stock);
    $product->set_stock_quantity($quantity);
    $product->set_stock_status($quantity > 0 ? 'instock' : 'outofstock');
}

$productId = $product->save();
if ($productId < 1) {
    WP_CLI::error('Unable to save WooCommerce draft.');
}

$meta = [
    '_msfixit_pilot_mode' => 'at_popup',
    '_msfixit_pilot_status' => 'approved',
    '_msfixit_compliance_status' => 'pending',
    '_msfixit_discovery_review_status' => 'pending',
    '_msfixit_content_reviewed' => 'no',
    '_msfixit_discovery_cable' => $attributeSuggestions !== [] ? 'yes' : 'no',
    '_msfixit_attribute_suggestions' => wp_json_encode($attributeSuggestions, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES),
    '_msfixit_supplier_code' => sanitize_text_field((string) ($payload['supplier_code'] ?? 'also-at')),
    '_msfixit_supplier_sku' => sanitize_text_field((string) ($payload['supplier_sku'] ?? '')),
    '_msfixit_manufacturer_name' => sanitize_text_field((string) ($payload['manufacturer_name'] ?? '')),
    '_msfixit_manufacturer_sku' => sanitize_text_field((string) ($payload['manufacturer_sku'] ?? '')),
    '_msfixit_gtin' => sanitize_text_field((string) ($payload['gtin'] ?? '')),
    '_msfixit_supplier_image_url' => esc_url_raw((string) ($payload['image_url'] ?? '')),
    '_msfixit_supplier_datasheet_url' => esc_url_raw((string) ($payload['datasheet_url'] ?? '')),
    '_msfixit_content_license' => sanitize_key((string) ($payload['content_license'] ?? 'none')),
    '_msfixit_local_image_cache_allowed' => !empty($payload['allow_local_image_cache']) ? 'yes' : 'no',
    '_msfixit_supplier_last_sync' => current_time('mysql', true),
];
foreach ($meta as $key => $value) {
    update_post_meta($productId, $key, $value);
}

$attributeTaxonomies = [
    'cable_type' => 'pa_kabeltyp',
    'connector_a' => 'pa_anschluss-a',
    'connector_b' => 'pa_anschluss-b',
    'cable_length' => 'pa_kabellaenge',
    'cable_standard' => 'pa_kabelstandard',
    'max_power' => 'pa_max-leistung',
    'data_rate' => 'pa_datenrate',
    'resolution' => 'pa_aufloesung-bildrate',
];
foreach ($attributeTaxonomies as $suggestionKey => $taxonomy) {
    if (!empty($attributeSuggestions[$suggestionKey]) && taxonomy_exists($taxonomy)) {
        wp_set_object_terms($productId, (string) $attributeSuggestions[$suggestionKey], $taxonomy, false);
    }
}

$categoryMap = [
    'USB-Kabel' => 'usb-kabel',
    'HDMI-Kabel' => 'hdmi-kabel',
    'DisplayPort-Kabel' => 'displayport-kabel',
    'Netzwerkkabel' => 'netzwerkkabel',
    'USB-Verlängerung' => 'usb-verlaengerungen',
];
if (!empty($attributeSuggestions['cable_type']) && isset($categoryMap[$attributeSuggestions['cable_type']])) {
    $category = get_term_by('slug', $categoryMap[$attributeSuggestions['cable_type']], 'product_cat');
    if ($category instanceof WP_Term) {
        wp_set_object_terms($productId, [$category->term_id], 'product_cat', true);
    }
}

// Supplier images are deliberately not downloaded here. The approved content
// contract must explicitly permit local caching before a separate importer may
// sideload an image into the WordPress media library.

clean_post_cache($productId);
echo $productId . PHP_EOL;
