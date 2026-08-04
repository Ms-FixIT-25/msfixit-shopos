<?php
/**
 * Idempotent service-request and status-page provisioning.
 */

declare(strict_types=1);

if (!defined('ABSPATH')) {
    exit(1);
}

function msfixit_service_managed_page(string $slug, string $title, string $content): int
{
    $page = get_page_by_path($slug, OBJECT, 'page');
    if (!$page instanceof WP_Post) {
        $pageId = wp_insert_post([
            'post_type' => 'page',
            'post_status' => 'publish',
            'post_title' => $title,
            'post_name' => $slug,
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
        $result = wp_update_post([
            'ID' => $pageId,
            'post_status' => 'publish',
            'post_title' => $title,
            'post_content' => $content,
            'comment_status' => 'closed',
        ], true);
        if (is_wp_error($result)) {
            WP_CLI::error($result->get_error_message());
        }
    }
    return $pageId;
}

function msfixit_service_menu_page(int $menuId, int $pageId, string $label): void
{
    foreach (wp_get_nav_menu_items($menuId) ?: [] as $item) {
        if ($item->object === 'page' && (int) $item->object_id === $pageId) {
            return;
        }
    }
    wp_update_nav_menu_item($menuId, 0, [
        'menu-item-title' => $label,
        'menu-item-object' => 'page',
        'menu-item-object-id' => $pageId,
        'menu-item-type' => 'post_type',
        'menu-item-status' => 'publish',
    ]);
}

$requestContent = '<!-- wp:heading {"level":1} --><h1 class="wp-block-heading">Serviceanfrage</h1><!-- /wp:heading -->
<!-- wp:paragraph {"fontSize":"large"} --><p class="has-large-font-size">Reparatur, Einrichtung, Netzwerkhilfe oder Frage zu einer Bestellung – mit klarer Referenz und nachvollziehbarem Status.</p><!-- /wp:paragraph -->
<!-- wp:list --><ul><li>Keine Passwörter oder Zahlungsdaten im Formular</li><li>Kein kostenpflichtiger Auftrag ohne gesonderte Abstimmung</li><li>Status nur mit Referenz und geheimem Zugangsschlüssel</li><li>Dateien und Fotos erst nach Rücksprache</li></ul><!-- /wp:list -->
<!-- wp:shortcode -->[msfixit_service_request_form]<!-- /wp:shortcode -->
<!-- wp:paragraph --><p>Du hast bereits eine Referenz? <a href="' . esc_url(home_url('/service-status/')) . '">Service- oder Reparaturstatus öffnen</a>.</p><!-- /wp:paragraph -->';

$statusContent = '<!-- wp:heading {"level":1} --><h1 class="wp-block-heading">Service- und Reparaturstatus</h1><!-- /wp:heading -->
<!-- wp:paragraph {"fontSize":"large"} --><p class="has-large-font-size">Der Status ist nur mit der Referenz und dem geheimen Zugangsschlüssel aus deinem persönlichen Status-Link abrufbar.</p><!-- /wp:paragraph -->
<!-- wp:shortcode -->[msfixit_service_status]<!-- /wp:shortcode -->
<!-- wp:paragraph --><p>Neue Anfrage nötig? <a href="' . esc_url(home_url('/service-anfrage/')) . '">Serviceanfrage öffnen</a>.</p><!-- /wp:paragraph -->';

$requestId = msfixit_service_managed_page('service-anfrage', 'Serviceanfrage', $requestContent);
$statusId = msfixit_service_managed_page('service-status', 'Service- und Reparaturstatus', $statusContent);

update_option('msfixit_service_page_ids', [$requestId, $statusId]);
update_option('msfixit_service_request_page_id', $requestId);
update_option('msfixit_service_status_page_id', $statusId);

if (get_option('msfixit_service_public_enabled', null) === null) {
    update_option('msfixit_service_public_enabled', 'no');
}

$menu = wp_get_nav_menu_object('Hauptmenü');
if ($menu) {
    msfixit_service_menu_page((int) $menu->term_id, $requestId, 'Serviceanfrage');
}

flush_rewrite_rules(false);
wp_cache_flush();
WP_CLI::success('Privacy-gated service intake and secret-link status pages configured.');
