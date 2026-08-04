<?php
/**
 * Applies one approved licensed ALSO content record to an existing WooCommerce draft.
 * Invoked through root-controlled msfixit-also-content with a temporary JSON file.
 */

declare(strict_types=1);

if (!defined('ABSPATH')) {
    exit(1);
}

if (!class_exists('WC_Product')) {
    WP_CLI::error('WooCommerce is not active.');
}

$payloadFile = getenv('MSFIXIT_ALSO_CONTENT_PAYLOAD_FILE') ?: '';
if ($payloadFile === '' || !is_readable($payloadFile)) {
    WP_CLI::error('ALSO content payload is unavailable.');
}

$payload = json_decode((string) file_get_contents($payloadFile), true, 512, JSON_THROW_ON_ERROR);
$productId = (int) ($payload['woocommerce_product_id'] ?? 0);
$product = $productId > 0 ? wc_get_product($productId) : false;
if (!$product instanceof WC_Product) {
    WP_CLI::error('WooCommerce draft was not found.');
}

if (($payload['media_mode'] ?? '') !== 'remote_only') {
    WP_CLI::error('Only remote-only ALSO media is supported.');
}

function msfixit_also_content_clean_text(mixed $value): string
{
    $value = is_scalar($value) ? (string) $value : '';
    $value = preg_replace('/\R{3,}/u', "\n\n", trim($value)) ?? trim($value);
    return wp_kses_post($value);
}

function msfixit_also_content_list_html(array $items, string $heading): string
{
    $clean = [];
    foreach ($items as $key => $value) {
        if (is_array($value)) {
            $value = implode(', ', array_map('strval', $value));
        }
        $text = trim(is_scalar($value) ? (string) $value : '');
        if ($text === '') {
            continue;
        }
        $clean[] = is_string($key) && !is_int($key)
            ? '<strong>' . esc_html($key) . ':</strong> ' . esc_html($text)
            : esc_html($text);
    }
    if ($clean === []) {
        return '';
    }
    return '<section class="msfixit-also-content-section"><h2>' . esc_html($heading) . '</h2><ul><li>'
        . implode('</li><li>', $clean) . '</li></ul></section>';
}

function msfixit_also_content_specs_html(array $specifications): string
{
    if ($specifications === []) {
        return '';
    }
    $rows = [];
    foreach ($specifications as $key => $value) {
        if (is_array($value)) {
            $value = implode(', ', array_map('strval', $value));
        }
        $label = trim(is_scalar($key) ? (string) $key : '');
        $text = trim(is_scalar($value) ? (string) $value : '');
        if ($label === '' || $text === '') {
            continue;
        }
        $rows[] = '<tr><th scope="row">' . esc_html($label) . '</th><td>' . esc_html($text) . '</td></tr>';
    }
    if ($rows === []) {
        return '';
    }
    return '<section class="msfixit-also-content-section"><h2>Technische Daten</h2>'
        . '<table class="shop_attributes shop_attributes_responsive"><tbody>'
        . implode('', $rows) . '</tbody></table></section>';
}

function msfixit_also_virtual_attachment(int $productId, string $url, int $position, string $role): int
{
    if (!filter_var($url, FILTER_VALIDATE_URL) || !str_starts_with(strtolower($url), 'https://')) {
        return 0;
    }
    $query = new WP_Query([
        'post_type' => 'attachment',
        'post_status' => 'inherit',
        'posts_per_page' => 1,
        'fields' => 'ids',
        'meta_query' => [[
            'key' => '_msfixit_remote_asset_url',
            'value' => $url,
        ]],
    ]);
    $attachmentId = (int) ($query->posts[0] ?? 0);
    if ($attachmentId < 1) {
        $path = (string) parse_url($url, PHP_URL_PATH);
        $extension = strtolower(pathinfo($path, PATHINFO_EXTENSION));
        $mime = match ($extension) {
            'png' => 'image/png',
            'webp' => 'image/webp',
            'gif' => 'image/gif',
            default => 'image/jpeg',
        };
        $attachmentId = wp_insert_attachment([
            'post_title' => $productId . ' – ALSO Produktbild ' . ($position + 1),
            'post_status' => 'inherit',
            'post_mime_type' => $mime,
            'guid' => $url,
            'post_parent' => $productId,
        ]);
        if (is_wp_error($attachmentId)) {
            return 0;
        }
    }
    update_post_meta($attachmentId, '_msfixit_remote_asset_url', esc_url_raw($url));
    update_post_meta($attachmentId, '_msfixit_remote_asset_source', 'also-1worldsync');
    update_post_meta($attachmentId, '_msfixit_remote_asset_role', sanitize_key($role));
    update_post_meta($attachmentId, '_msfixit_remote_asset_approved', 'yes');
    update_post_meta($attachmentId, '_wp_attachment_image_alt', $productId . ' – Produktansicht ' . ($position + 1));
    update_post_meta($attachmentId, '_wp_attachment_metadata', [
        'width' => 1600,
        'height' => 1600,
        'file' => '',
        'sizes' => [],
        'msfixit_remote' => true,
    ]);
    return (int) $attachmentId;
}

$standard = msfixit_also_content_clean_text($payload['standard_description'] ?? '');
$marketing = msfixit_also_content_clean_text($payload['marketing_description'] ?? '');
$sellingPoints = is_array($payload['selling_points'] ?? null) ? $payload['selling_points'] : [];
$features = is_array($payload['features'] ?? null) ? $payload['features'] : [];
$specifications = is_array($payload['specifications'] ?? null) ? $payload['specifications'] : [];

if ($standard !== '') {
    $product->set_short_description(wpautop($standard));
}
$descriptionParts = [];
if ($marketing !== '') {
    $descriptionParts[] = '<section class="msfixit-also-content-section">' . wpautop($marketing) . '</section>';
}
$descriptionParts[] = msfixit_also_content_list_html($sellingPoints, 'Produktvorteile');
$descriptionParts[] = msfixit_also_content_list_html($features, 'Produktmerkmale');
$descriptionParts[] = msfixit_also_content_specs_html($specifications);
$description = implode("\n", array_filter($descriptionParts));
if ($description !== '') {
    $product->set_description($description);
}

// Applying licensed content never publishes a product.
if ($product->get_status() === 'publish') {
    $product->set_status('draft');
}
$product->set_catalog_visibility('hidden');
$productId = $product->save();

$images = [];
$documents = [];
foreach ((array) ($payload['assets'] ?? []) as $asset) {
    $url = esc_url_raw((string) ($asset['source_url'] ?? ''));
    if ($url === '') {
        continue;
    }
    if (($asset['asset_type'] ?? '') === 'image' && !empty($payload['allow_remote_images'])) {
        $images[] = [
            'url' => $url,
            'role' => sanitize_key((string) ($asset['asset_role'] ?? 'gallery')),
            'order' => (int) ($asset['display_order'] ?? count($images)),
        ];
    } elseif (!empty($payload['allow_remote_documents'])) {
        $documents[] = [
            'url' => $url,
            'role' => sanitize_key((string) ($asset['asset_role'] ?? 'manufacturer_document')),
            'language' => sanitize_text_field((string) ($asset['language_code'] ?? '')),
        ];
    }
}
usort($images, static fn(array $a, array $b): int => $a['order'] <=> $b['order']);

$attachmentIds = [];
foreach ($images as $position => $image) {
    $attachmentId = msfixit_also_virtual_attachment($productId, $image['url'], $position, $image['role']);
    if ($attachmentId > 0) {
        $attachmentIds[] = $attachmentId;
    }
}
if ($attachmentIds !== []) {
    set_post_thumbnail($productId, $attachmentIds[0]);
    update_post_meta($productId, '_product_image_gallery', implode(',', array_slice($attachmentIds, 1)));
}

$meta = [
    '_msfixit_content_source' => 'also-1worldsync',
    '_msfixit_content_package' => sanitize_key((string) ($payload['content_package'] ?? '')),
    '_msfixit_content_language' => sanitize_text_field((string) ($payload['language_code'] ?? 'de-AT')),
    '_msfixit_content_source_sha256' => sanitize_text_field((string) ($payload['source_sha256'] ?? '')),
    '_msfixit_content_license_verified' => 'yes',
    '_msfixit_content_reviewed' => 'yes',
    '_msfixit_remote_media_mode' => 'remote_only',
    '_msfixit_remote_media_approved' => $attachmentIds !== [] ? 'yes' : 'no',
    '_msfixit_remote_image_urls' => wp_json_encode(array_column($images, 'url'), JSON_UNESCAPED_SLASHES),
    '_msfixit_remote_document_links' => wp_json_encode($documents, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES),
    '_msfixit_content_relation_skus' => wp_json_encode((array) ($payload['relations'] ?? []), JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES),
    '_msfixit_content_applied_at' => current_time('mysql', true),
    '_msfixit_discovery_review_status' => 'pending',
];
foreach ($meta as $key => $value) {
    update_post_meta($productId, $key, $value);
}

$existingSuggestions = json_decode((string) get_post_meta($productId, '_msfixit_attribute_suggestions', true), true);
if (!is_array($existingSuggestions)) {
    $existingSuggestions = [];
}
$existingSuggestions['also_content_specifications'] = $specifications;
update_post_meta(
    $productId,
    '_msfixit_attribute_suggestions',
    wp_json_encode($existingSuggestions, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES)
);

clean_post_cache($productId);
echo $productId . PHP_EOL;
