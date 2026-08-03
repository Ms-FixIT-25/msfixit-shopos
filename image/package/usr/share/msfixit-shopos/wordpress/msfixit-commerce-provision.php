<?php
/**
 * Idempotent commercial-region provisioning for the initial DACH launch.
 * Payment, shipping rates, taxes and legal content remain explicit go-live tasks.
 */

declare(strict_types=1);

if (!defined('ABSPATH')) {
    exit(1);
}

$allowedCountries = ['AT', 'DE', 'CH'];
$countryZones = [
    'AT' => ['name' => 'DACH – Österreich', 'order' => 10],
    'DE' => ['name' => 'DACH – Deutschland', 'order' => 20],
    'CH' => ['name' => 'DACH – Schweiz', 'order' => 30],
];

update_option('woocommerce_allowed_countries', 'specific');
update_option('woocommerce_specific_allowed_countries', $allowedCountries);
update_option('woocommerce_ship_to_countries', 'specific');
update_option('woocommerce_specific_ship_to_countries', $allowedCountries);
update_option('woocommerce_default_customer_address', 'base');
update_option('msfixit_shopos_sales_region', 'DACH');
update_option('msfixit_shopos_sales_countries', $allowedCountries);

if (class_exists('WC_Shipping_Zones') && class_exists('WC_Shipping_Zone')) {
    $existingZones = WC_Shipping_Zones::get_zones();

    foreach ($countryZones as $countryCode => $definition) {
        $zoneId = 0;
        foreach ($existingZones as $zoneData) {
            if (($zoneData['zone_name'] ?? '') === $definition['name']) {
                $zoneId = (int) ($zoneData['zone_id'] ?? 0);
                break;
            }
        }

        $zone = $zoneId > 0 ? new WC_Shipping_Zone($zoneId) : new WC_Shipping_Zone();
        $zone->set_zone_name($definition['name']);
        $zone->set_zone_order($definition['order']);
        $zone->save();
        $zone->clear_locations();
        $zone->add_location($countryCode, 'country');
        $zone->save();
    }
}

// The page contains only the technical two-step withdrawal function. The
// country-specific withdrawal information itself remains a separately versioned
// and approved legal document in the compliance database.
$withdrawalPage = get_page_by_path('vertrag-widerrufen', OBJECT, 'page');
if (!$withdrawalPage instanceof WP_Post) {
    $withdrawalPageId = wp_insert_post([
        'post_type' => 'page',
        'post_status' => 'publish',
        'post_title' => 'Vertrag widerrufen',
        'post_name' => 'vertrag-widerrufen',
        'post_content' => '[msfixit_withdrawal]',
        'comment_status' => 'closed',
    ], true);
    if (is_wp_error($withdrawalPageId)) {
        WP_CLI::warning('Withdrawal function page could not be created: ' . $withdrawalPageId->get_error_message());
    } else {
        update_post_meta((int) $withdrawalPageId, '_msfixit_shopos_managed', '1');
    }
} elseif (get_post_meta($withdrawalPage->ID, '_msfixit_shopos_managed', true) === '1') {
    wp_update_post([
        'ID' => $withdrawalPage->ID,
        'post_status' => 'publish',
        'post_title' => 'Vertrag widerrufen',
        'post_content' => '[msfixit_withdrawal]',
    ]);
}

WP_CLI::success('Sales restricted to AT, DE and CH with separate zones and electronic withdrawal function page.');
