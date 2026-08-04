<?php
/**
 * Idempotent help-center and partner-information page provisioning.
 */

declare(strict_types=1);

if (!defined('ABSPATH')) {
    exit(1);
}

function msfixit_help_managed_page(string $slug, string $title, string $content, int $parent = 0): int
{
    $page = get_page_by_path($slug, OBJECT, 'page');
    if (!$page instanceof WP_Post) {
        $pageId = wp_insert_post([
            'post_type' => 'page',
            'post_status' => 'publish',
            'post_title' => $title,
            'post_name' => basename($slug),
            'post_parent' => $parent,
            'post_content' => $content,
            'comment_status' => 'closed',
        ], true);
        if (is_wp_error($pageId)) {
            WP_CLI::error($pageId->get_error_message());
        }
        update_post_meta((int) $pageId, '_msfixit_shopos_managed', '1');
        return (int) $pageId;
    }

    $pageId = (int) $page->ID;
    if (get_post_meta($pageId, '_msfixit_shopos_managed', true) === '1') {
        wp_update_post([
            'ID' => $pageId,
            'post_status' => 'publish',
            'post_title' => $title,
            'post_parent' => $parent,
            'post_content' => $content,
        ]);
    }
    return $pageId;
}

$rootContent = '<!-- wp:heading {"level":1} --><h1 class="wp-block-heading">Hilfe &amp; Beratung</h1><!-- /wp:heading -->
<!-- wp:paragraph {"fontSize":"large"} --><p class="has-large-font-size">Technik verständlich auswählen, einrichten und reparieren – ohne dich durch unklare Produktnamen und Werbeversprechen kämpfen zu müssen.</p><!-- /wp:paragraph -->
<!-- wp:shortcode -->[msfixit_help_center]<!-- /wp:shortcode -->';

$rootId = msfixit_help_managed_page('hilfe', 'Hilfe & Beratung', $rootContent);

$pages = [];
$pages['kabelberater'] = msfixit_help_managed_page(
    'hilfe/kabelberater',
    'Kabelberater',
    '<!-- wp:heading {"level":1} --><h1 class="wp-block-heading">Welches Kabel brauche ich?</h1><!-- /wp:heading -->
<!-- wp:paragraph {"fontSize":"large"} --><p class="has-large-font-size">Steckerform, Datenrate, Ladeleistung und Bildausgabe sind unterschiedliche Eigenschaften. Der Kabelberater grenzt die Auswahl ein.</p><!-- /wp:paragraph -->
<!-- wp:shortcode -->[msfixit_cable_advisor]<!-- /wp:shortcode -->
<!-- wp:heading {"level":2} --><h2 class="wp-block-heading">Häufige Stolperfallen</h2><!-- /wp:heading -->
<!-- wp:list --><ul><li>USB-C sagt nur etwas über die Steckerform aus, nicht automatisch über Datenrate oder Ladeleistung.</li><li>HDMI- und DisplayPort-Kabel müssen zur gewünschten Auflösung und Bildrate passen.</li><li>Sehr lange Kabel können bei hohen Datenraten oder Bildsignalen problematisch sein.</li><li>Bei Notebook-Ladekabeln müssen Kabel, Netzteil und Gerät dieselbe benötigte Leistung unterstützen.</li></ul><!-- /wp:list -->',
    $rootId
);

$pages['fritzbox-wlan'] = msfixit_help_managed_page(
    'hilfe/fritzbox-wlan',
    'FRITZ!Box & WLAN Hilfe',
    '<!-- wp:heading {"level":1} --><h1 class="wp-block-heading">FRITZ!Box, WLAN &amp; Heimnetz</h1><!-- /wp:heading -->
<!-- wp:shortcode -->[msfixit_fritz_help]<!-- /wp:shortcode -->
<!-- wp:heading {"level":2} --><h2 class="wp-block-heading">WLAN langsam oder instabil?</h2><!-- /wp:heading -->
<!-- wp:paragraph --><p>Entscheidend sind nicht nur Tarif und Routermodell. Standort, Gebäudestruktur, Funkkanäle, Mesh-Verbindungen, Endgeräte und die Anbindung zwischen den Zugangspunkten müssen gemeinsam betrachtet werden.</p><!-- /wp:paragraph -->
<!-- wp:heading {"level":2} --><h2 class="wp-block-heading">Vor dem Kauf eines Repeaters</h2><!-- /wp:heading -->
<!-- wp:paragraph --><p>Ein Repeater am falschen Ort verstärkt auch eine schlechte Verbindung. Häufig ist eine andere Platzierung, ein Netzwerkkabel oder ein zusätzlicher Access Point die bessere Lösung.</p><!-- /wp:paragraph -->',
    $rootId
);

$pages['reparaturwissen'] = msfixit_help_managed_page(
    'hilfe/reparaturwissen',
    'Reparaturwissen',
    '<!-- wp:heading {"level":1} --><h1 class="wp-block-heading">Reparaturwissen &amp; Vorbereitung</h1><!-- /wp:heading -->
<!-- wp:shortcode -->[msfixit_repair_help]<!-- /wp:shortcode -->
<!-- wp:heading {"level":2} --><h2 class="wp-block-heading">Reparieren oder ersetzen?</h2><!-- /wp:heading -->
<!-- wp:paragraph --><p>Die Entscheidung hängt von Fehlerursache, Ersatzteilverfügbarkeit, Gerätezustand, Datenwert, Sicherheitsrisiko und wirtschaftlichem Aufwand ab. Eine Diagnose ist deshalb oft sinnvoller als ein vorschneller Neukauf.</p><!-- /wp:paragraph -->',
    $rootId
);

$pages['bestellung-versand-rueckgabe'] = msfixit_help_managed_page(
    'hilfe/bestellung-versand-rueckgabe',
    'Bestellung, Versand & Service',
    '<!-- wp:heading {"level":1} --><h1 class="wp-block-heading">Bestellung, Versand &amp; Service</h1><!-- /wp:heading -->
<!-- wp:paragraph {"fontSize":"large"} --><p class="has-large-font-size">Hier findest du den Ablauf von der Produktauswahl bis zu Lieferung, Rückgabe oder Reparaturauftrag.</p><!-- /wp:paragraph -->
<!-- wp:heading {"level":2} --><h2 class="wp-block-heading">Bestellung im österreichischen Pilotshop</h2><!-- /wp:heading -->
<!-- wp:paragraph --><p>Der Pilotshop liefert zunächst ausschließlich nach Österreich. Verfügbarkeit, Lieferzeit und Einkaufspreis werden vor der Großhändlerbestellung nochmals geprüft.</p><!-- /wp:paragraph -->
<!-- wp:heading {"level":2} --><h2 class="wp-block-heading">Versand und Sendungsverfolgung</h2><!-- /wp:heading -->
<!-- wp:paragraph --><p>Nach Übergabe an den Versanddienstleister erhältst du – soweit verfügbar – eine Trackinginformation. Versandkosten und Lieferzeit werden vor dem zahlungspflichtigen Abschluss angezeigt.</p><!-- /wp:paragraph -->
<!-- wp:heading {"level":2} --><h2 class="wp-block-heading">Rückgabe und Reklamation</h2><!-- /wp:heading -->
<!-- wp:paragraph --><p>Nutze bei einem Problem zuerst die Kontakt- oder Widerrufsfunktion und gib Bestellnummer, Artikel und Fehlerbild an. Gesetzliche Rechte werden durch freiwillige Serviceleistungen nicht eingeschränkt.</p><!-- /wp:paragraph -->
<!-- wp:buttons --><div class="wp-block-buttons"><!-- wp:button --><div class="wp-block-button"><a class="wp-block-button__link wp-element-button" href="' . esc_url(home_url('/kontakt/')) . '">Kontakt aufnehmen</a></div><!-- /wp:button --></div><!-- /wp:buttons -->',
    $rootId
);

$allIds = array_merge([$rootId], array_values($pages));
update_option('msfixit_help_page_ids', $allIds);
update_option('msfixit_help_root_page_id', $rootId);

$menu = wp_get_nav_menu_object('Hauptmenü');
if ($menu) {
    $exists = false;
    foreach (wp_get_nav_menu_items((int) $menu->term_id) ?: [] as $item) {
        if ($item->object === 'page' && (int) $item->object_id === $rootId) {
            $exists = true;
            break;
        }
    }
    if (!$exists) {
        wp_update_nav_menu_item((int) $menu->term_id, 0, [
            'menu-item-title' => 'Hilfe & Beratung',
            'menu-item-object' => 'page',
            'menu-item-object-id' => $rootId,
            'menu-item-type' => 'post_type',
            'menu-item-status' => 'publish',
        ]);
    }
}

flush_rewrite_rules(false);
wp_cache_flush();
WP_CLI::success('Help center, cable advisor, FRITZ!Box information and repair guidance configured.');
