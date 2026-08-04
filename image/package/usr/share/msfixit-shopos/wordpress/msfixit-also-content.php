<?php
/**
 * Plugin Name: Ms. FixIT ShopOS Licensed ALSO Content
 * Description: Renders approved remote-only ALSO/1WorldSync media and product documents without local file caching.
 * Version: 1.0.0
 */

declare(strict_types=1);

if (!defined('ABSPATH')) {
    exit;
}

function msfixit_also_remote_attachment_url(int $attachmentId): string
{
    if (get_post_meta($attachmentId, '_msfixit_remote_asset_approved', true) !== 'yes') {
        return '';
    }
    $url = esc_url_raw((string) get_post_meta($attachmentId, '_msfixit_remote_asset_url', true));
    return str_starts_with(strtolower($url), 'https://') ? $url : '';
}

add_filter('image_downsize', static function (mixed $downsize, int $attachmentId, string|array $size): mixed {
    $url = msfixit_also_remote_attachment_url($attachmentId);
    if ($url === '') {
        return $downsize;
    }
    $width = 1600;
    $height = 1600;
    if (is_array($size) && isset($size[0], $size[1])) {
        $width = max(1, (int) $size[0]);
        $height = max(1, (int) $size[1]);
    } elseif (is_string($size)) {
        $registered = wp_get_registered_image_subsizes();
        if (isset($registered[$size])) {
            $width = max(1, (int) ($registered[$size]['width'] ?? 1600));
            $height = max(1, (int) ($registered[$size]['height'] ?? 1600));
        }
    }
    return [$url, $width, $height, false];
}, 10, 3);

add_filter('wp_get_attachment_url', static function (string|false $url, int $attachmentId): string|false {
    $remote = msfixit_also_remote_attachment_url($attachmentId);
    return $remote !== '' ? $remote : $url;
}, 10, 2);

add_filter('wp_calculate_image_srcset', static function (array|false $sources, array $sizeArray, string $imageSrc, array $imageMeta, int $attachmentId): array|false {
    return msfixit_also_remote_attachment_url($attachmentId) !== '' ? false : $sources;
}, 10, 5);

add_filter('wp_get_attachment_metadata', static function (array|false $metadata, int $attachmentId): array|false {
    if (msfixit_also_remote_attachment_url($attachmentId) === '') {
        return $metadata;
    }
    return [
        'width' => 1600,
        'height' => 1600,
        'file' => '',
        'sizes' => [],
        'msfixit_remote' => true,
    ];
}, 10, 2);

add_filter('get_attached_file', static function (string|false $file, int $attachmentId): string|false {
    return msfixit_also_remote_attachment_url($attachmentId) !== '' ? false : $file;
}, 10, 2);

function msfixit_also_product_documents(int $productId): array
{
    $decoded = json_decode((string) get_post_meta($productId, '_msfixit_remote_document_links', true), true);
    if (!is_array($decoded)) {
        return [];
    }
    $documents = [];
    foreach ($decoded as $document) {
        $url = esc_url_raw((string) ($document['url'] ?? ''));
        if ($url === '' || !str_starts_with(strtolower($url), 'https://')) {
            continue;
        }
        $documents[] = [
            'url' => $url,
            'role' => sanitize_key((string) ($document['role'] ?? 'manufacturer_document')),
            'language' => sanitize_text_field((string) ($document['language'] ?? '')),
        ];
    }
    return $documents;
}

add_action('woocommerce_product_meta_end', static function (): void {
    global $product;
    if (!$product instanceof WC_Product || get_post_meta($product->get_id(), '_msfixit_content_license_verified', true) !== 'yes') {
        return;
    }
    $documents = msfixit_also_product_documents($product->get_id());
    if ($documents === []) {
        return;
    }
    $labels = [
        'datasheet' => 'Technisches Datenblatt',
        'manufacturer_document' => 'Herstellerdokument',
        'manual' => 'Anleitung',
        'compatibility' => 'Kompatibilitätsinformation',
    ];
    echo '<section class="msfixit-product-documents"><h2>Produktunterlagen</h2><ul>';
    foreach ($documents as $index => $document) {
        $label = $labels[$document['role']] ?? ('Produktunterlage ' . ($index + 1));
        if ($document['language'] !== '') {
            $label .= ' (' . $document['language'] . ')';
        }
        echo '<li><a href="' . esc_url($document['url']) . '" target="_blank" rel="noopener nofollow">'
            . esc_html($label) . '</a></li>';
    }
    echo '</ul><p class="msfixit-content-source">Produktinformationen und verlinkte Medien: lizenzierter ALSO/1WorldSync-Content.</p></section>';
});

add_filter('woocommerce_structured_data_product', static function (array $markup, WC_Product $product): array {
    if (get_post_meta($product->get_id(), '_msfixit_remote_media_approved', true) !== 'yes') {
        return $markup;
    }
    $images = json_decode((string) get_post_meta($product->get_id(), '_msfixit_remote_image_urls', true), true);
    if (is_array($images)) {
        $images = array_values(array_filter(array_map(static function (mixed $value): string {
            $url = esc_url_raw(is_scalar($value) ? (string) $value : '');
            return str_starts_with(strtolower($url), 'https://') ? $url : '';
        }, $images)));
        if ($images !== []) {
            $markup['image'] = $images;
        }
    }
    return $markup;
}, 40, 2);

add_filter('rest_post_dispatch', static function (WP_HTTP_Response $response, WP_REST_Server $server, WP_REST_Request $request): WP_HTTP_Response {
    if ($request->get_route() !== '/msfixit/v1/cable-suggestions' || !function_exists('wc_get_product_id_by_sku')) {
        return $response;
    }
    $data = $response->get_data();
    if (!is_array($data)) {
        return $response;
    }
    foreach ($data as &$entry) {
        if (!is_array($entry) || empty($entry['sku'])) {
            continue;
        }
        $productId = wc_get_product_id_by_sku((string) $entry['sku']);
        if ($productId < 1 || get_post_meta($productId, '_msfixit_remote_media_approved', true) !== 'yes') {
            continue;
        }
        $images = json_decode((string) get_post_meta($productId, '_msfixit_remote_image_urls', true), true);
        $url = is_array($images) ? esc_url_raw((string) ($images[0] ?? '')) : '';
        if ($url !== '' && str_starts_with(strtolower($url), 'https://')) {
            $entry['image'] = $url;
        }
    }
    unset($entry);
    $response->set_data($data);
    return $response;
}, 10, 3);

add_action('wp_head', static function (): void {
    if (!function_exists('is_product') || !is_product()) {
        return;
    }
    echo '<style>.msfixit-product-documents{margin-top:1.5rem;padding:1rem;border:1px solid #d8e1ea;border-radius:.5rem}.msfixit-product-documents h2{font-size:1.1rem;margin:0 0 .5rem}.msfixit-product-documents ul{margin:.5rem 0}.msfixit-content-source{font-size:.85rem;opacity:.75}</style>';
});
