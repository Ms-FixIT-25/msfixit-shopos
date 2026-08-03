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

        // Refresh only the country assignment. Existing shipping methods and
        // their configured prices remain untouched on repeated provisioning.
        $zone->clear_locations();
        $zone->add_location($countryCode, 'country');
        $zone->save();
    }
}

WP_CLI::success('Sales restricted to AT, DE and CH with separate country shipping zones.');
