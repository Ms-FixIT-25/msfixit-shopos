<?php
/**
 * Plugin Name: Ms. FixIT ShopOS Austrian Pilot
 * Description: Keeps the pop-up pilot Austria-only and blocks automatic supplier release.
 * Version: 1.0.0
 */

declare(strict_types=1);

if (!defined('ABSPATH')) {
    exit;
}

const MSFIXIT_PILOT_CONFIG = '/etc/msfixit-shopos/also.env';

function msfixit_pilot_settings(): array
{
    static $settings = null;
    if (is_array($settings)) {
        return $settings;
    }
    $settings = [];
    if (!is_readable(MSFIXIT_PILOT_CONFIG)) {
        return $settings;
    }
    foreach (file(MSFIXIT_PILOT_CONFIG, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) ?: [] as $line) {
        $line = trim($line);
        if ($line === '' || str_starts_with($line, '#') || !str_contains($line, '=')) {
            continue;
        }
        [$key, $value] = explode('=', $line, 2);
        $settings[trim($key)] = trim($value, " \t\n\r\0\x0B\"'");
    }
    return $settings;
}

function msfixit_pilot_enabled(): bool
{
    $settings = msfixit_pilot_settings();
    return in_array(strtolower((string) ($settings['AT_PILOT_ENABLED'] ?? 'yes')), ['1', 'yes', 'true', 'on'], true);
}

add_filter('woocommerce_countries_allowed_countries', static function (array $countries): array {
    return msfixit_pilot_enabled() && isset($countries['AT']) ? ['AT' => $countries['AT']] : $countries;
}, 1000);

add_filter('woocommerce_countries_shipping_countries', static function (array $countries): array {
    return msfixit_pilot_enabled() && isset($countries['AT']) ? ['AT' => $countries['AT']] : $countries;
}, 1000);

add_filter('pre_option_woocommerce_allowed_countries', static function (mixed $value): mixed {
    return msfixit_pilot_enabled() ? 'specific' : $value;
}, 1000);

add_filter('pre_option_woocommerce_specific_allowed_countries', static function (mixed $value): mixed {
    return msfixit_pilot_enabled() ? ['AT'] : $value;
}, 1000);

add_filter('pre_option_woocommerce_ship_to_countries', static function (mixed $value): mixed {
    return msfixit_pilot_enabled() ? 'specific' : $value;
}, 1000);

add_filter('pre_option_woocommerce_specific_ship_to_countries', static function (mixed $value): mixed {
    return msfixit_pilot_enabled() ? ['AT'] : $value;
}, 1000);

add_action('woocommerce_after_checkout_validation', static function (array $data, WP_Error $errors): void {
    if (!msfixit_pilot_enabled()) {
        return;
    }
    $billingCountry = strtoupper((string) ($data['billing_country'] ?? ''));
    $shippingCountry = strtoupper((string) ($data['shipping_country'] ?? $billingCountry));
    if ($billingCountry !== 'AT' || $shippingCountry !== 'AT') {
        $errors->add('msfixit_pilot_country', 'Der Ms.-FixIT-Pilotshop liefert derzeit ausschließlich innerhalb Österreichs.');
    }
    if (!WC()->cart) {
        return;
    }
    foreach (WC()->cart->get_cart() as $cartItem) {
        $product = $cartItem['data'] ?? null;
        if (!$product instanceof WC_Product) {
            continue;
        }
        $productId = $product->get_id();
        if (get_post_meta($productId, '_msfixit_pilot_mode', true) !== 'at_popup') {
            continue;
        }
        if (get_post_meta($productId, '_msfixit_pilot_status', true) !== 'approved') {
            $errors->add('msfixit_pilot_product', 'Mindestens ein Pilotartikel ist noch nicht zur Bestellung freigegeben.');
            break;
        }
    }
}, 1000, 2);

add_action('woocommerce_checkout_create_order', static function (WC_Order $order): void {
    if (!msfixit_pilot_enabled()) {
        return;
    }
    $order->update_meta_data('_msfixit_pilot_mode', 'at_popup');
    $order->update_meta_data('_msfixit_supplier_release_status', 'pending_manual_review');
    $order->update_meta_data('_msfixit_supplier_order_sent', 'no');
}, 1000);

add_action('woocommerce_checkout_order_created', static function (WC_Order $order): void {
    if (!msfixit_pilot_enabled()) {
        return;
    }
    $order->add_order_note('AT-Pilot: Einkaufspreis und ALSO-Bestand vor der Lieferantenbestellung manuell prüfen.');
}, 1000);

add_action('woocommerce_before_shop_loop', static function (): void {
    if (msfixit_pilot_enabled() && function_exists('wc_print_notice')) {
        wc_print_notice('Pilotbetrieb: Verkauf und Lieferung derzeit ausschließlich innerhalb Österreichs. Das Sortiment wird bewusst klein gehalten.', 'notice');
    }
}, 4);

add_action('wp_dashboard_setup', static function (): void {
    if (!msfixit_pilot_enabled()) {
        return;
    }
    wp_add_dashboard_widget('msfixit_at_pilot_status', 'Ms. FixIT – AT-Pilot & ALSO', static function (): void {
        $settings = msfixit_pilot_settings();
        echo '<p><strong>Markt:</strong> ausschließlich Österreich</p>';
        echo '<p><strong>Sortimentsgrenze:</strong> ' . esc_html((string) ($settings['AT_PILOT_MAX_APPROVED_PRODUCTS'] ?? '30')) . ' Artikel</p>';
        echo '<p><strong>Großhändler:</strong> ALSO Austria</p>';
        echo '<p><strong>Produktfreigabe:</strong> manuell</p>';
        echo '<p><strong>Lieferantenbestellung:</strong> manuell nach Preis- und Bestandsprüfung</p>';
        echo '<p>ALSO-Importe erzeugen nur Prüfeinträge und WooCommerce-Entwürfe. Eine automatische Veröffentlichung oder Bestellung ist gesperrt.</p>';
    });
});
