<?php
/**
 * Plugin Name: Ms. FixIT ShopOS Discovery Compliance Sync
 * Description: Mirrors the current protected AT product approval into the WooCommerce discovery gate.
 * Version: 1.0.0
 */

declare(strict_types=1);

if (!defined('ABSPATH')) {
    exit;
}

function msfixit_discovery_sync_compliance(int $productId): void
{
    if (!function_exists('msfixit_compliance_product_check') || !function_exists('wc_get_product')) {
        return;
    }
    $product = wc_get_product($productId);
    if (!$product instanceof WC_Product) {
        return;
    }
    $sku = trim((string) $product->get_sku());
    if ($sku === '') {
        update_post_meta($productId, '_msfixit_compliance_status', 'pending');
        return;
    }

    try {
        $check = msfixit_compliance_product_check($sku, 'AT');
        update_post_meta($productId, '_msfixit_compliance_status', !empty($check['approved']) ? 'approved' : 'pending');
        update_post_meta(
            $productId,
            '_msfixit_compliance_missing',
            wp_json_encode(array_values((array) ($check['missing'] ?? [])), JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES)
        );
        update_post_meta($productId, '_msfixit_compliance_checked_at', current_time('mysql', true));
    } catch (Throwable $exception) {
        update_post_meta($productId, '_msfixit_compliance_status', 'pending');
        error_log('[Ms. FixIT discovery] Compliance synchronization failed: ' . $exception->getMessage());
    }
}

add_action('save_post_product', static function (int $productId): void {
    if (!wp_is_post_revision($productId)) {
        msfixit_discovery_sync_compliance($productId);
    }
}, 90);

add_action('admin_init', static function (): void {
    $productId = isset($_GET['post']) ? (int) $_GET['post'] : 0;
    if ($productId > 0 && get_post_type($productId) === 'product' && current_user_can('edit_post', $productId)) {
        msfixit_discovery_sync_compliance($productId);
    }
});
