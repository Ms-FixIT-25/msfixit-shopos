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

update_option('woocommerce_allowed_countries', 'specific');
update_option('woocommerce_specific_allowed_countries', $allowedCountries);
update_option('woocommerce_ship_to_countries', 'specific');
update_option('woocommerce_specific_ship_to_countries', $allowedCountries);
update_option('woocommerce_default_customer_address', 'base');
update_option('msfixit_shopos_sales_region', 'DACH');
update_option('msfixit_shopos_sales_countries', $allowedCountries);

if (class_exists('WC_Shipping_Zones') && class_exists('WC_Shipping_Zone')) {
    $zoneName = 'DACH – Österreich, Deutschland, Schweiz';
    $zoneId = 0;

    foreach (WC_Shipping_Zones::get_zones() as $zoneData) {
        if (($zoneData['zone_name'] ?? '') === $zoneName) {
            $zoneId = (int) ($zoneData['zone_id'] ?? 0);
            break;
        }
    }

    $zone = $zoneId > 0 ? new WC_Shipping_Zone($zoneId) : new WC_Shipping_Zone();
    $zone->set_zone_name($zoneName);
    $zone->set_zone_order(0);
    $zone->save();

    // Refresh only locations. Existing shipping methods and their prices stay intact.
    $zone->clear_locations();
    foreach ($allowedCountries as $countryCode) {
        $zone->add_location($countryCode, 'country');
    }
    $zone->save();
}

WP_CLI::success('DACH sales and shipping countries restricted to AT, DE and CH.');
