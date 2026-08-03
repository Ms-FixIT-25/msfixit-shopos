<?php
/**
 * One-shot, idempotent ShopOS WordPress and WooCommerce provisioning.
 * Executed through WP-CLI by /usr/local/sbin/msfixit-brand-shop.
 */

if (!defined('ABSPATH')) {
    exit(1);
}

$logo_id = (int) getenv('MSFIXIT_LOGO_ID');
$hero_id = (int) getenv('MSFIXIT_HERO_ID');
$icon_id = (int) getenv('MSFIXIT_ICON_ID');

if ($logo_id < 1 || $hero_id < 1 || $icon_id < 1) {
    WP_CLI::error('Branding attachment IDs are missing.');
}

function msfixit_shopos_upsert_page(
    string $slug,
    string $title,
    string $content,
    string $status = 'publish'
): int {
    $page = get_page_by_path($slug, OBJECT, 'page');

    if (!$page) {
        $page_id = wp_insert_post([
            'post_type'    => 'page',
            'post_status'  => $status,
            'post_title'   => $title,
            'post_name'    => $slug,
            'post_content' => $content,
        ], true);

        if (is_wp_error($page_id)) {
            WP_CLI::error($page_id->get_error_message());
        }
    } else {
        $page_id = (int) $page->ID;
        $managed = get_post_meta($page_id, '_msfixit_shopos_managed', true);

        if ($managed === '1') {
            $result = wp_update_post([
                'ID'           => $page_id,
                'post_status'  => $status,
                'post_title'   => $title,
                'post_content' => $content,
            ], true);

            if (is_wp_error($result)) {
                WP_CLI::error($result->get_error_message());
            }
        }
    }

    update_post_meta($page_id, '_msfixit_shopos_managed', '1');
    return $page_id;
}

function msfixit_shopos_add_menu_page(int $menu_id, int $page_id, string $label): void
{
    if ($page_id < 1) {
        return;
    }

    $items = wp_get_nav_menu_items($menu_id) ?: [];
    foreach ($items as $item) {
        if ((int) $item->object_id === $page_id && $item->object === 'page') {
            return;
        }
    }

    wp_update_nav_menu_item($menu_id, 0, [
        'menu-item-title'     => $label,
        'menu-item-object'    => 'page',
        'menu-item-object-id' => $page_id,
        'menu-item-type'      => 'post_type',
        'menu-item-status'    => 'publish',
    ]);
}

if (function_exists('wc_create_pages')) {
    wc_create_pages();
}

update_option('blogdescription', 'IT gelöst. Einfach. Fix. Günstig.');
update_option('timezone_string', 'Europe/Vienna');
update_option('date_format', 'd.m.Y');
update_option('time_format', 'H:i');
update_option('start_of_week', 1);

update_option('woocommerce_default_country', 'AT');
update_option('woocommerce_currency', 'EUR');
update_option('woocommerce_currency_pos', 'right_space');
update_option('woocommerce_price_num_decimals', '2');
update_option('woocommerce_dimension_unit', 'cm');
update_option('woocommerce_weight_unit', 'kg');
update_option('woocommerce_enable_guest_checkout', 'yes');
update_option('woocommerce_enable_myaccount_registration', 'yes');
update_option('woocommerce_allow_tracking', 'no');
update_option('woocommerce_placeholder_image', (string) $icon_id);

set_theme_mod('custom_logo', $logo_id);
set_theme_mod('storefront_background_color', '#ffffff');
set_theme_mod('storefront_header_background_color', '#ffffff');
set_theme_mod('storefront_header_text_color', '#10243f');
set_theme_mod('storefront_header_link_color', '#10243f');
set_theme_mod('storefront_footer_background_color', '#10243f');
set_theme_mod('storefront_footer_heading_color', '#ffffff');
set_theme_mod('storefront_footer_text_color', '#ffffff');
set_theme_mod('storefront_footer_link_color', '#39c0c3');
set_theme_mod('storefront_heading_color', '#10243f');
set_theme_mod('storefront_text_color', '#24364e');
set_theme_mod('storefront_accent_color', '#ed3f91');
set_theme_mod('storefront_button_background_color', '#24b8bd');
set_theme_mod('storefront_button_text_color', '#ffffff');
set_theme_mod('storefront_button_alt_background_color', '#ed3f91');
set_theme_mod('storefront_button_alt_text_color', '#ffffff');
update_option('site_icon', $icon_id);

$hero_url = wp_get_attachment_image_url($hero_id, 'full') ?: '';
$admin_email = sanitize_email((string) get_option('admin_email'));

$home_content = sprintf(
    <<<'HTML'
<!-- wp:group {"align":"full","className":"msfixit-hero","layout":{"type":"constrained"}} -->
<div class="wp-block-group alignfull msfixit-hero">
<!-- wp:image {"id":%1$d,"sizeSlug":"large","linkDestination":"none","align":"center"} -->
<figure class="wp-block-image aligncenter size-large"><img src="%2$s" alt="Ms. FixIT – IT-Support und Services" class="wp-image-%1$d"/></figure>
<!-- /wp:image -->
<!-- wp:heading {"textAlign":"center","level":1} --><h1 class="wp-block-heading has-text-align-center">IT gelöst. Einfach. Fix. Günstig.</h1><!-- /wp:heading -->
<!-- wp:paragraph {"align":"center","fontSize":"large"} --><p class="has-text-align-center has-large-font-size">Reparatur, IT-Support und ausgewählte Technikprodukte – fair, verständlich und ohne unnötigen Schnickschnack.</p><!-- /wp:paragraph -->
<!-- wp:buttons {"layout":{"type":"flex","justifyContent":"center"}} -->
<div class="wp-block-buttons"><!-- wp:button --><div class="wp-block-button"><a class="wp-block-button__link wp-element-button" href="/shop/">Zum Shop</a></div><!-- /wp:button -->
<!-- wp:button {"className":"is-style-outline"} --><div class="wp-block-button is-style-outline"><a class="wp-block-button__link wp-element-button" href="/reparatur-services/">Reparatur &amp; Services</a></div><!-- /wp:button --></div>
<!-- /wp:buttons --></div>
<!-- /wp:group -->

<!-- wp:columns {"className":"msfixit-service-grid"} -->
<div class="wp-block-columns msfixit-service-grid">
<!-- wp:column --><div class="wp-block-column"><!-- wp:heading {"level":3} --><h3 class="wp-block-heading">Reparatur &amp; Support</h3><!-- /wp:heading --><!-- wp:paragraph --><p>Smartphone, PC, Notebook, Xbox, PlayStation sowie Installation und Fehlerbehebung.</p><!-- /wp:paragraph --></div><!-- /wp:column -->
<!-- wp:column --><div class="wp-block-column"><!-- wp:heading {"level":3} --><h3 class="wp-block-heading">Shop &amp; Hardware</h3><!-- /wp:heading --><!-- wp:paragraph --><p>Ausgewählte IT-Produkte mit nachvollziehbaren Preisen und klaren Leistungsbeschreibungen.</p><!-- /wp:paragraph --></div><!-- /wp:column -->
<!-- wp:column --><div class="wp-block-column"><!-- wp:heading {"level":3} --><h3 class="wp-block-heading">Pauschal. Diskont. Fair.</h3><!-- /wp:heading --><!-- wp:paragraph --><p>Keine unnötige Technikshow: verständliche Lösungen, ehrliche Beratung und ein fairer Umgang.</p><!-- /wp:paragraph --></div><!-- /wp:column -->
</div>
<!-- /wp:columns -->
HTML,
    $hero_id,
    esc_url($hero_url)
);

$repair_content = <<<'HTML'
<!-- wp:heading {"level":1} --><h1 class="wp-block-heading">Reparatur &amp; Services</h1><!-- /wp:heading -->
<!-- wp:paragraph {"fontSize":"large"} --><p class="has-large-font-size">Technik soll funktionieren – und verständlich bleiben.</p><!-- /wp:paragraph -->
<!-- wp:list -->
<ul><!-- wp:list-item --><li>Smartphone- und Tablet-Reparatur</li><!-- /wp:list-item --><!-- wp:list-item --><li>PC- und Notebook-Reparatur</li><!-- /wp:list-item --><!-- wp:list-item --><li>Xbox- und PlayStation-Reparatur</li><!-- /wp:list-item --><!-- wp:list-item --><li>Installation, Einrichtung und Datenübernahme</li><!-- /wp:list-item --><!-- wp:list-item --><li>IT-Hardware, Beratung und Support</li><!-- /wp:list-item --></ul>
<!-- /wp:list -->
<!-- wp:buttons --><div class="wp-block-buttons"><!-- wp:button --><div class="wp-block-button"><a class="wp-block-button__link wp-element-button" href="/kontakt/">Anfrage senden</a></div><!-- /wp:button --></div><!-- /wp:buttons -->
HTML;

$contact_content = sprintf(
    <<<'HTML'
<!-- wp:heading {"level":1} --><h1 class="wp-block-heading">Kontakt</h1><!-- /wp:heading -->
<!-- wp:paragraph {"fontSize":"large"} --><p class="has-large-font-size">Beschreibe kurz dein Gerät, den Fehler und was bereits versucht wurde.</p><!-- /wp:paragraph -->
<!-- wp:paragraph --><p>E-Mail: <a href="mailto:%1$s">%1$s</a></p><!-- /wp:paragraph -->
<!-- wp:paragraph --><p>Bitte keine Passwörter oder vertraulichen Zugangsdaten in die erste Nachricht schreiben.</p><!-- /wp:paragraph -->
HTML,
    esc_attr($admin_email)
);

$legal_placeholder = <<<'HTML'
<!-- wp:heading {"level":1} --><h1 class="wp-block-heading">Rechtlicher Entwurf</h1><!-- /wp:heading -->
<!-- wp:paragraph --><p><strong>Diese Seite ist noch nicht veröffentlicht.</strong> Inhalt vor dem Shop-Start rechtlich prüfen und vervollständigen.</p><!-- /wp:paragraph -->
HTML;

$home_id = msfixit_shopos_upsert_page('startseite', 'Startseite', $home_content);
$repair_id = msfixit_shopos_upsert_page('reparatur-services', 'Reparatur & Services', $repair_content);
$contact_id = msfixit_shopos_upsert_page('kontakt', 'Kontakt', $contact_content);
msfixit_shopos_upsert_page('impressum', 'Impressum', $legal_placeholder, 'draft');
msfixit_shopos_upsert_page('datenschutz', 'Datenschutz', $legal_placeholder, 'draft');
msfixit_shopos_upsert_page('agb', 'AGB', $legal_placeholder, 'draft');
msfixit_shopos_upsert_page('widerruf-rueckgabe', 'Widerruf & Rückgabe', $legal_placeholder, 'draft');

update_option('show_on_front', 'page');
update_option('page_on_front', $home_id);

$menu_name = 'Hauptmenü';
$menu = wp_get_nav_menu_object($menu_name);
$menu_id = $menu ? (int) $menu->term_id : (int) wp_create_nav_menu($menu_name);

msfixit_shopos_add_menu_page($menu_id, $home_id, 'Startseite');
msfixit_shopos_add_menu_page($menu_id, (int) get_option('woocommerce_shop_page_id'), 'Shop');
msfixit_shopos_add_menu_page($menu_id, $repair_id, 'Reparatur & Services');
msfixit_shopos_add_menu_page($menu_id, $contact_id, 'Kontakt');
msfixit_shopos_add_menu_page($menu_id, (int) get_option('woocommerce_myaccount_page_id'), 'Mein Konto');

$locations = (array) get_theme_mod('nav_menu_locations', []);
$locations['primary'] = $menu_id;
set_theme_mod('nav_menu_locations', $locations);

flush_rewrite_rules(false);
wp_cache_flush();

WP_CLI::success('Storefront, WooCommerce structure and Ms. FixIT branding configured.');
