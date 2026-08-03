<?php
/**
 * Plugin Name: Ms. FixIT ShopOS DACH Region
 * Description: Displays the initial DACH delivery region and keeps commercial go-live tasks visible.
 * Version: 1.0.0
 */

declare(strict_types=1);

if (!defined('ABSPATH')) {
    exit;
}

function msfixit_shopos_dach_notice(): void
{
    if (!function_exists('wc_print_notice')) {
        return;
    }

    wc_print_notice(
        'Lieferung derzeit ausschließlich nach Österreich, Deutschland und in die Schweiz.',
        'notice'
    );
}

add_action('woocommerce_before_shop_loop', 'msfixit_shopos_dach_notice', 5);
add_action('woocommerce_before_cart', 'msfixit_shopos_dach_notice', 5);
add_action('woocommerce_before_checkout_form', 'msfixit_shopos_dach_notice', 5);

add_action('wp_dashboard_setup', static function (): void {
    wp_add_dashboard_widget(
        'msfixit_shopos_commerce_status',
        'Ms. FixIT – Verkaufsregion & Artikelstamm',
        static function (): void {
            $countries = (array) get_option('msfixit_shopos_sales_countries', ['AT', 'DE', 'CH']);
            echo '<p><strong>Aktive Lieferländer:</strong> ' . esc_html(implode(', ', $countries)) . '</p>';
            echo '<p><strong>Eigene Waren­nummer:</strong> MF-00000001 bis MF-99999999</p>';
            echo '<p>WooCommerce, Lieferanten, EAN/GTIN, spätere Ladenkasse, Marktplätze und ERP/SAP werden über Zuordnungen mit derselben MF-Waren­nummer verbunden.</p>';
            echo '<p><strong>Noch festzulegen:</strong> Versandpreise je Land, Schweizer Import-/Zollablauf, Steuern und Zahlungsarten.</p>';
        }
    );
});
