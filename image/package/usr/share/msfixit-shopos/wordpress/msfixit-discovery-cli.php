<?php
/**
 * WP-CLI entry point for ShopOS discovery audits.
 */

declare(strict_types=1);

if (!defined('ABSPATH')) {
    exit(1);
}

$command = getenv('MSFIXIT_DISCOVERY_COMMAND') ?: 'status';
$productId = (int) (getenv('MSFIXIT_DISCOVERY_PRODUCT_ID') ?: 0);

if (!function_exists('msfixit_discovery_product_audit')) {
    WP_CLI::error('The Ms. FixIT discovery MU plugin is not loaded.');
}

if ($command === 'status') {
    $settings = msfixit_discovery_settings();
    $products = wc_get_products(['status' => ['draft', 'publish'], 'limit' => -1, 'return' => 'objects']);
    $summary = [
        'discovery_enabled' => msfixit_discovery_enabled(),
        'landing_page' => home_url('/' . trim((string) $settings['DISCOVERY_LANDING_SLUG'], '/') . '/'),
        'merchant_feed_enabled' => msfixit_discovery_yes((string) $settings['GOOGLE_MERCHANT_FEED_ENABLED']),
        'merchant_feed_url' => home_url('/' . trim((string) $settings['GOOGLE_MERCHANT_FEED_PATH'], '/')),
        'published_cables' => 0,
        'draft_cables' => 0,
        'blocked_cables' => 0,
    ];
    foreach ($products as $product) {
        if (!$product instanceof WC_Product || !msfixit_discovery_is_cable($product)) {
            continue;
        }
        if ($product->get_status() === 'publish' && msfixit_discovery_product_audit($product) === []) {
            $summary['published_cables']++;
        } else {
            $summary['draft_cables']++;
            if (msfixit_discovery_product_audit($product) !== []) {
                $summary['blocked_cables']++;
            }
        }
    }
    echo wp_json_encode($summary, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . PHP_EOL;
    return;
}

if ($command === 'audit') {
    $products = $productId > 0
        ? [wc_get_product($productId)]
        : wc_get_products(['status' => ['draft', 'publish'], 'limit' => -1, 'return' => 'objects']);
    $rows = [];
    foreach ($products as $product) {
        if (!$product instanceof WC_Product || !msfixit_discovery_is_cable($product)) {
            continue;
        }
        $rows[] = [
            'product_id' => $product->get_id(),
            'sku' => $product->get_sku(),
            'name' => $product->get_name(),
            'status' => $product->get_status(),
            'errors' => msfixit_discovery_product_audit($product),
        ];
    }
    echo wp_json_encode($rows, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . PHP_EOL;
    return;
}

WP_CLI::error('Unknown discovery command.');
