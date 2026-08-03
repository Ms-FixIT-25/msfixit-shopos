<?php
/**
 * Idempotent cable catalogue, attribute and SEO landing-page provisioning.
 */

declare(strict_types=1);

if (!defined('ABSPATH')) {
    exit(1);
}

if (!function_exists('wc_create_attribute')) {
    WP_CLI::error('WooCommerce attribute functions are unavailable.');
}

$attributes = [
    'kabeltyp' => 'Kabeltyp',
    'anschluss-a' => 'Anschluss A',
    'anschluss-b' => 'Anschluss B',
    'kabellaenge' => 'Kabellänge',
    'kabelstandard' => 'Kabelstandard',
    'max-leistung' => 'Maximale Ladeleistung',
    'datenrate' => 'Datenrate',
    'aufloesung-bildrate' => 'Auflösung und Bildrate',
    'marke' => 'Marke',
    'farbe' => 'Farbe',
    'schirmung' => 'Schirmung',
];

$existingAttributes = [];
foreach (wc_get_attribute_taxonomies() as $attribute) {
    $existingAttributes[(string) $attribute->attribute_name] = (int) $attribute->attribute_id;
}

foreach ($attributes as $slug => $label) {
    if (isset($existingAttributes[$slug])) {
        continue;
    }
    $result = wc_create_attribute([
        'name' => $label,
        'slug' => $slug,
        'type' => 'select',
        'order_by' => 'name',
        'has_archives' => false,
    ]);
    if (is_wp_error($result)) {
        WP_CLI::warning(sprintf('Attribut %s konnte nicht angelegt werden: %s', $label, $result->get_error_message()));
    }
}

delete_transient('wc_attribute_taxonomies');
wp_cache_delete('woocommerce-attributes', 'woocommerce');

$categories = [
    'usb-kabel' => [
        'name' => 'USB-Kabel',
        'description' => 'USB-C- und USB-A-Kabel für Laden, Datenübertragung und den Anschluss von Geräten. Filtere nach Steckertyp, Länge, USB-Standard, Datenrate und maximaler Ladeleistung, damit das Kabel wirklich zu deinem Gerät passt.',
    ],
    'hdmi-kabel' => [
        'name' => 'HDMI-Kabel',
        'description' => 'HDMI-Kabel für Monitor, Fernseher, Konsole und Beamer. Vergleiche Kabellänge, HDMI-Standard sowie unterstützte Auflösung und Bildrate statt dich auf unklare Werbeangaben zu verlassen.',
    ],
    'displayport-kabel' => [
        'name' => 'DisplayPort-Kabel',
        'description' => 'DisplayPort-Kabel für PC, Dockingstation und hochauflösende Monitore. Die technischen Filter helfen bei der Auswahl nach Anschluss, Standard, Auflösung, Bildrate und Länge.',
    ],
    'netzwerkkabel' => [
        'name' => 'Netzwerkkabel',
        'description' => 'LAN-, Ethernet- und Patchkabel für Router, Switch, PC und Netzwerkdose. Finde das passende RJ45-Kabel nach Cat-Standard, Länge, Farbe und Schirmung.',
    ],
    'usb-verlaengerungen' => [
        'name' => 'USB-Verlängerungen',
        'description' => 'USB-Verlängerungskabel für Zubehör und Geräte, wenn das vorhandene Kabel nicht reicht. Achte auf Steckertyp, Länge und unterstützten USB-Standard.',
    ],
];

$categoryIds = [];
foreach ($categories as $slug => $definition) {
    $existing = get_term_by('slug', $slug, 'product_cat');
    if ($existing instanceof WP_Term) {
        $categoryIds[$slug] = $existing->term_id;
        wp_update_term($existing->term_id, 'product_cat', [
            'name' => $definition['name'],
            'description' => $definition['description'],
        ]);
        continue;
    }
    $created = wp_insert_term($definition['name'], 'product_cat', [
        'slug' => $slug,
        'description' => $definition['description'],
    ]);
    if (is_wp_error($created)) {
        WP_CLI::warning(sprintf('Kategorie %s konnte nicht angelegt werden: %s', $definition['name'], $created->get_error_message()));
        continue;
    }
    $categoryIds[$slug] = (int) $created['term_id'];
}

$categoryLinks = [];
foreach ($categories as $slug => $definition) {
    if (!isset($categoryIds[$slug])) {
        continue;
    }
    $url = get_term_link($categoryIds[$slug], 'product_cat');
    if (!is_wp_error($url)) {
        $categoryLinks[$slug] = $url;
    }
}

$cards = '';
foreach ($categories as $slug => $definition) {
    if (!isset($categoryLinks[$slug])) {
        continue;
    }
    $cards .= sprintf(
        '<div class="wp-block-column"><h3 class="wp-block-heading"><a href="%s">%s</a></h3><p>%s</p><p><a href="%s">%s ansehen</a></p></div>',
        esc_url($categoryLinks[$slug]),
        esc_html($definition['name']),
        esc_html($definition['description']),
        esc_url($categoryLinks[$slug]),
        esc_html($definition['name'])
    );
}

$pageContent = sprintf(
    '<!-- wp:heading {"level":1} --><h1 class="wp-block-heading">Kabel &amp; IT-Zubehör in Österreich</h1><!-- /wp:heading -->
<!-- wp:paragraph {"fontSize":"large"} --><p class="has-large-font-size">Finde ein Kabel, das technisch zu deinem Gerät passt – übersichtlich nach Anschlüssen, Länge, Standard, Ladeleistung, Datenrate und Bildausgabe.</p><!-- /wp:paragraph -->
<!-- wp:paragraph --><p>Der österreichische Pilotshop startet bewusst mit einem kleinen, geprüften Sortiment. Produkttexte und technische Angaben werden vor der Veröffentlichung kontrolliert; unklare Großhändlerangaben gehen nicht automatisch online.</p><!-- /wp:paragraph -->
<!-- wp:columns {"className":"msfixit-cable-category-cards"} --><div class="wp-block-columns msfixit-cable-category-cards">%s</div><!-- /wp:columns -->
<!-- wp:heading {"level":2} --><h2 class="wp-block-heading">Kabel suchen und filtern</h2><!-- /wp:heading -->
<!-- wp:shortcode -->[msfixit_cable_catalog]<!-- /wp:shortcode -->
<!-- wp:heading {"level":2} --><h2 class="wp-block-heading">Worauf du bei Kabeln achten solltest</h2><!-- /wp:heading -->
<!-- wp:paragraph --><p>Der gleiche Stecker bedeutet nicht automatisch die gleiche Leistung. Ein USB-C-Kabel kann etwa nur laden, langsame Daten übertragen oder hohe Lade- und Datenleistungen unterstützen. Bei HDMI und DisplayPort sind Auflösung und Bildrate entscheidend; bei Netzwerkkabeln spielen Kategorie und Schirmung eine Rolle.</p><!-- /wp:paragraph -->',
    $cards
);

$page = get_page_by_path('kabel-zubehoer', OBJECT, 'page');
if (!$page instanceof WP_Post) {
    $pageId = wp_insert_post([
        'post_type' => 'page',
        'post_status' => 'publish',
        'post_title' => 'Kabel & IT-Zubehör',
        'post_name' => 'kabel-zubehoer',
        'post_content' => $pageContent,
        'comment_status' => 'closed',
    ], true);
    if (is_wp_error($pageId)) {
        WP_CLI::error($pageId->get_error_message());
    }
    update_post_meta((int) $pageId, '_msfixit_shopos_managed', '1');
} else {
    $pageId = $page->ID;
    if (get_post_meta($pageId, '_msfixit_shopos_managed', true) === '1') {
        wp_update_post([
            'ID' => $pageId,
            'post_status' => 'publish',
            'post_title' => 'Kabel & IT-Zubehör',
            'post_content' => $pageContent,
        ]);
    }
}

$menu = wp_get_nav_menu_object('Hauptmenü');
if ($menu && $pageId > 0) {
    $exists = false;
    foreach (wp_get_nav_menu_items((int) $menu->term_id) ?: [] as $item) {
        if ($item->object === 'page' && (int) $item->object_id === (int) $pageId) {
            $exists = true;
            break;
        }
    }
    if (!$exists) {
        wp_update_nav_menu_item((int) $menu->term_id, 0, [
            'menu-item-title' => 'Kabel & Zubehör',
            'menu-item-object' => 'page',
            'menu-item-object-id' => (int) $pageId,
            'menu-item-type' => 'post_type',
            'menu-item-status' => 'publish',
        ]);
    }
}

update_option('msfixit_discovery_landing_page_id', (int) $pageId);
flush_rewrite_rules(false);
wp_cache_flush();

WP_CLI::success('Cable attributes, indexable categories, landing page and navigation configured.');
