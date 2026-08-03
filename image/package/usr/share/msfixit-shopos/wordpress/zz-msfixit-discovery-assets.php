<?php
/**
 * Plugin Name: Ms. FixIT ShopOS Discovery Assets
 * Description: Loads the lightweight cable search UI wherever the global storefront header is visible.
 * Version: 1.0.0
 */

declare(strict_types=1);

if (!defined('ABSPATH')) {
    exit;
}

add_action('wp_enqueue_scripts', static function (): void {
    if (!function_exists('msfixit_discovery_enabled') || !msfixit_discovery_enabled()) {
        return;
    }
    $version = '1.0.0';
    wp_enqueue_style('msfixit-discovery', plugins_url('assets/msfixit-discovery.css', __FILE__), [], $version);
    wp_enqueue_script('msfixit-discovery', plugins_url('assets/msfixit-discovery.js', __FILE__), [], $version, true);
    wp_localize_script('msfixit-discovery', 'MsFixITDiscovery', [
        'suggestionsUrl' => esc_url_raw(rest_url('msfixit/v1/cable-suggestions')),
        'minimumCharacters' => 2,
    ]);
}, 5);
