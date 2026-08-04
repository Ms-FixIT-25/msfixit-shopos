<?php
/**
 * Plugin Name: Ms. FixIT ShopOS Help Center
 * Description: Searchable customer help, cable guidance and evidence-based partner programme display.
 * Version: 1.0.0
 */

declare(strict_types=1);

if (!defined('ABSPATH')) {
    exit;
}

const MSFIXIT_PARTNER_ENV = '/etc/msfixit-shopos/partners-wordpress.env';

function msfixit_help_env(): array
{
    static $env = null;
    if (is_array($env)) {
        return $env;
    }
    $env = [];
    if (!is_readable(MSFIXIT_PARTNER_ENV)) {
        return $env;
    }
    foreach (file(MSFIXIT_PARTNER_ENV, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) ?: [] as $line) {
        $line = trim($line);
        if ($line === '' || str_starts_with($line, '#') || !str_contains($line, '=')) {
            continue;
        }
        [$key, $value] = explode('=', $line, 2);
        $env[trim($key)] = trim($value);
    }
    return $env;
}

function msfixit_help_partner_db(): ?PDO
{
    static $pdo = false;
    if ($pdo instanceof PDO) {
        return $pdo;
    }
    if ($pdo === null) {
        return null;
    }
    $env = msfixit_help_env();
    foreach (['PARTNER_DB_HOST', 'PARTNER_DB_PORT', 'PARTNER_DB_NAME', 'PARTNER_DB_USER', 'PARTNER_DB_PASSWORD'] as $key) {
        if (empty($env[$key])) {
            $pdo = null;
            return null;
        }
    }
    try {
        $pdo = new PDO(
            sprintf('mysql:host=%s;port=%s;dbname=%s;charset=utf8mb4', $env['PARTNER_DB_HOST'], $env['PARTNER_DB_PORT'], $env['PARTNER_DB_NAME']),
            $env['PARTNER_DB_USER'],
            $env['PARTNER_DB_PASSWORD'],
            [
                PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
                PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
                PDO::ATTR_EMULATE_PREPARES => false,
            ]
        );
        return $pdo;
    } catch (Throwable $exception) {
        error_log('[Ms. FixIT help] Partner database unavailable: ' . $exception->getMessage());
        $pdo = null;
        return null;
    }
}

function msfixit_help_public_partners(?string $code = null): array
{
    $pdo = msfixit_help_partner_db();
    if (!$pdo) {
        return [];
    }
    $sql = "SELECT partner_code, provider_name, program_name, public_label,
                   public_claim, official_profile_url, logo_mode, logo_url,
                   valid_until
            FROM partner_profiles
            WHERE public_enabled=1
              AND membership_status='verified'
              AND (valid_until IS NULL OR valid_until >= CURRENT_DATE)";
    $params = [];
    if ($code !== null) {
        $sql .= ' AND partner_code=?';
        $params[] = $code;
    }
    $sql .= ' ORDER BY provider_name, public_label';
    $statement = $pdo->prepare($sql);
    $statement->execute($params);
    return $statement->fetchAll();
}

function msfixit_help_partner_card(array $partner): string
{
    $logo = '';
    if (($partner['logo_mode'] ?? 'none') !== 'none' && !empty($partner['logo_url'])) {
        $logo = sprintf(
            '<img class="msfixit-partner-logo" src="%s" alt="%s" loading="lazy" decoding="async">',
            esc_url((string) $partner['logo_url']),
            esc_attr((string) $partner['public_label'])
        );
    }
    $validity = '';
    if (!empty($partner['valid_until'])) {
        $validity = '<p class="msfixit-partner-validity">Status geprüft bis ' . esc_html(wp_date('d.m.Y', strtotime((string) $partner['valid_until']))) . '.</p>';
    }
    $profileLink = '';
    if (!empty($partner['official_profile_url'])) {
        $profileLink = sprintf(
            '<p><a href="%s" rel="noopener noreferrer">Offiziellen Programmeintrag öffnen</a></p>',
            esc_url((string) $partner['official_profile_url'])
        );
    }
    return sprintf(
        '<article class="msfixit-partner-card">%s<div><h3>%s</h3><p>%s</p>%s%s</div></article>',
        $logo,
        esc_html((string) $partner['public_label']),
        esc_html((string) $partner['public_claim']),
        $validity,
        $profileLink
    );
}

add_shortcode('msfixit_partner_cards', static function (array $attributes = []): string {
    $attributes = shortcode_atts(['code' => ''], $attributes, 'msfixit_partner_cards');
    $partners = msfixit_help_public_partners($attributes['code'] !== '' ? sanitize_key($attributes['code']) : null);
    if (!$partners) {
        return current_user_can('manage_options')
            ? '<div class="msfixit-help-admin-note">Partnernachweis noch nicht für die öffentliche Anzeige freigegeben.</div>'
            : '';
    }
    return '<div class="msfixit-partner-grid">' . implode('', array_map('msfixit_help_partner_card', $partners)) . '</div>';
});

function msfixit_help_page_ids(): array
{
    return array_values(array_filter(array_map('intval', (array) get_option('msfixit_help_page_ids', []))));
}

function msfixit_help_search_results(string $query): string
{
    $query = trim(wp_strip_all_tags($query));
    if ($query === '') {
        return '';
    }
    $ids = msfixit_help_page_ids();
    if (!$ids) {
        return '<p>Die Hilfe ist noch nicht vollständig eingerichtet.</p>';
    }
    $search = new WP_Query([
        'post_type' => 'page',
        'post_status' => 'publish',
        'post__in' => $ids,
        's' => $query,
        'posts_per_page' => 20,
        'orderby' => 'relevance',
        'no_found_rows' => true,
    ]);
    if (!$search->have_posts()) {
        return '<div class="msfixit-help-empty"><p>Zu „' . esc_html($query) . '“ wurde noch kein passender Hilfetext gefunden.</p><p><a href="' . esc_url(home_url('/kontakt/')) . '">Direkt eine Frage stellen</a></p></div>';
    }
    $items = '';
    foreach ($search->posts as $post) {
        $items .= sprintf(
            '<li><a href="%s"><strong>%s</strong></a><p>%s</p></li>',
            esc_url(get_permalink($post)),
            esc_html(get_the_title($post)),
            esc_html(wp_trim_words(wp_strip_all_tags(strip_shortcodes((string) $post->post_content)), 28))
        );
    }
    return '<h2>Ergebnisse für „' . esc_html($query) . '“</h2><ul class="msfixit-help-results">' . $items . '</ul>';
}

add_shortcode('msfixit_help_center', static function (): string {
    $query = isset($_GET['hilfe_suche']) ? sanitize_text_field(wp_unslash($_GET['hilfe_suche'])) : '';
    $cards = [
        ['Kabelberater', 'Welcher Stecker, welche Länge und welcher Standard passen?', home_url('/hilfe/kabelberater/')],
        ['FRITZ!Box & WLAN', 'Hilfe bei Einrichtung, Mesh, Reichweite, Telefonie und Heimnetz.', home_url('/hilfe/fritzbox-wlan/')],
        ['Reparaturwissen', 'Vorbereitung, Datensicherung, Ersatzteile und Ablauf einer Reparatur.', home_url('/hilfe/reparaturwissen/')],
        ['Bestellung & Service', 'Zahlung, Versand, Rückgabe, Reparaturauftrag und Kontakt.', home_url('/hilfe/bestellung-versand-rueckgabe/')],
    ];
    $html = '<form class="msfixit-help-search" method="get" action="' . esc_url(home_url('/hilfe/')) . '">'
        . '<label for="msfixit-help-query">Wobei brauchst du Hilfe?</label>'
        . '<div><input id="msfixit-help-query" type="search" name="hilfe_suche" value="' . esc_attr($query) . '" placeholder="z. B. USB-C, WLAN langsam oder Reparatur"><button type="submit">Hilfe durchsuchen</button></div>'
        . '</form>';
    $html .= '<div class="msfixit-help-grid">';
    foreach ($cards as [$title, $description, $url]) {
        $html .= sprintf(
            '<article class="msfixit-help-card"><h2><a href="%s">%s</a></h2><p>%s</p><p><a href="%s">Thema öffnen</a></p></article>',
            esc_url($url), esc_html($title), esc_html($description), esc_url($url)
        );
    }
    $html .= '</div>';
    $html .= msfixit_help_search_results($query);
    return $html;
});

add_shortcode('msfixit_cable_advisor', static function (): string {
    $from = isset($_GET['von']) ? sanitize_text_field(wp_unslash($_GET['von'])) : '';
    $to = isset($_GET['zu']) ? sanitize_text_field(wp_unslash($_GET['zu'])) : '';
    $use = isset($_GET['nutzung']) ? sanitize_text_field(wp_unslash($_GET['nutzung'])) : '';
    $length = isset($_GET['laenge']) ? sanitize_text_field(wp_unslash($_GET['laenge'])) : '';
    $options = ['USB-C', 'USB-A', 'HDMI', 'DisplayPort', 'RJ45/LAN', 'Micro-USB', 'Noch unklar'];
    $select = static function (string $name, string $selected, array $values): string {
        $html = '<select name="' . esc_attr($name) . '"><option value="">Bitte wählen</option>';
        foreach ($values as $value) {
            $html .= '<option value="' . esc_attr($value) . '"' . selected($selected, $value, false) . '>' . esc_html($value) . '</option>';
        }
        return $html . '</select>';
    };
    $html = '<form class="msfixit-cable-advisor" method="get">'
        . '<div><label>Ausgang am Gerät' . $select('von', $from, $options) . '</label></div>'
        . '<div><label>Zielgerät oder Anschluss' . $select('zu', $to, $options) . '</label></div>'
        . '<div><label>Hauptnutzung' . $select('nutzung', $use, ['Laden', 'Datenübertragung', 'Monitor/TV', 'Netzwerk', 'Verlängerung']) . '</label></div>'
        . '<div><label>Benötigte Länge' . $select('laenge', $length, ['0,5 m', '1 m', '2 m', '3 m', '5 m']) . '</label></div>'
        . '<button type="submit">Empfehlung anzeigen</button></form>';

    if ($from !== '' || $to !== '' || $use !== '') {
        $terms = array_filter([$from, $to, $use, $length]);
        $searchTerm = implode(' ', $terms);
        $notes = [];
        if ($use === 'Laden') {
            $notes[] = 'Prüfe neben dem Stecker auch die benötigte Watt-Leistung. Ein USB-C-Kabel ist nicht automatisch für jedes Notebook-Ladegerät geeignet.';
        }
        if ($use === 'Datenübertragung') {
            $notes[] = 'Steckerform und Datenrate sind getrennte Eigenschaften. USB-C kann je nach Kabel sehr unterschiedliche Geschwindigkeiten unterstützen.';
        }
        if ($use === 'Monitor/TV') {
            $notes[] = 'Für Bildübertragung müssen Auflösung, Bildrate und Kabelstandard zum Monitor und zur Grafikkarte passen.';
        }
        if ($use === 'Netzwerk') {
            $notes[] = 'Für Router und Switch sind RJ45-Patchkabel üblich. Kategorie, Schirmung und Länge beeinflussen die Eignung.';
        }
        $html .= '<section class="msfixit-advisor-result"><h2>Deine Auswahl</h2><p><strong>' . esc_html($searchTerm) . '</strong></p>';
        foreach ($notes as $note) {
            $html .= '<p>' . esc_html($note) . '</p>';
        }
        $html .= '<p><a class="button" href="' . esc_url(add_query_arg('kabelsuche', $searchTerm, home_url('/kabel-zubehoer/'))) . '">Passende Kabel im Shop suchen</a></p>'
            . '<p>Bei Unsicherheit prüfe ich den Anschluss und die benötigte Leistung gerne vor dem Kauf.</p></section>';
    }
    return $html;
});

add_shortcode('msfixit_fritz_help', static function (): string {
    $services = [
        'Ersteinrichtung und sichere Grundeinstellungen',
        'WLAN-Reichweite und Mesh sinnvoll planen',
        'FRITZ!Repeater und Netzwerkgeräte einbinden',
        'Telefonie, DECT und Anrufbeantworter konfigurieren',
        'Gastnetz, Kindersicherung und Benutzerrechte einrichten',
        'VPN, Fernzugriff und Heimnetz-Verbindungen prüfen',
        'Bestehende Einstellungen bei einem Routerwechsel übernehmen',
    ];
    $items = '<ul>';
    foreach ($services as $service) {
        $items .= '<li>' . esc_html($service) . '</li>';
    }
    $items .= '</ul>';
    return '<div class="msfixit-help-topic"><p class="msfixit-help-lead">FRITZ!Box und WLAN sollen nicht nur irgendwie online sein, sondern stabil, verständlich und sicher funktionieren.</p>'
        . '<h2>Wobei ich helfen kann</h2>' . $items
        . '<h2>Vor einem Termin hilfreich</h2><p>Halte das genaue FRITZ!-Modell, den Internetanbieter, die Anschlussart und – sofern vorhanden – die Zugangsdaten bereit. Passwörter müssen nicht per E-Mail geschickt werden.</p>'
        . do_shortcode('[msfixit_partner_cards code="fritz-business-at"]')
        . '<p class="msfixit-trademark-note">FRITZ! und FRITZ!Box sind Marken des jeweiligen Rechteinhabers. Eine öffentliche Partnerbezeichnung wird nur angezeigt, wenn der aktuelle Status in ShopOS nachgewiesen und freigegeben wurde.</p></div>';
});

add_shortcode('msfixit_repair_help', static function (): string {
    return '<div class="msfixit-help-topic"><p class="msfixit-help-lead">Vor einer Reparatur klären wir Fehlerbild, Datensicherung, Ersatzteilqualität, Kostenrahmen und das Risiko eines Eingriffs.</p>'
        . '<h2>Vorbereitung</h2><ul><li>Wichtige Daten sichern, soweit das Gerät noch bedienbar ist.</li><li>Fehler, Sturz, Flüssigkeit oder vorherige Reparaturversuche ehrlich angeben.</li><li>Gerätepasswörter nur bereitstellen, wenn sie für einen vereinbarten Funktionstest notwendig sind.</li><li>Bei Akku- oder Hitzeschäden das Gerät nicht weiter laden.</li></ul>'
        . '<h2>Reparaturinformationen</h2><p>ShopOS verlinkt bei Bedarf auf passende Originalanleitungen oder Herstellerinformationen. Fremde Anleitungen und Bilder werden nicht einfach in den kommerziellen Shop kopiert.</p>'
        . do_shortcode('[msfixit_partner_cards code="ifixit-pro"]')
        . '<p><a href="https://de.ifixit.com/Device" rel="noopener noreferrer">Öffentliche iFixit-Geräteanleitungen öffnen</a></p>'
        . '<p class="msfixit-trademark-note">iFixit Pro ist ein Programm für Reparaturunternehmen und keine allgemeine Zertifizierung. Das iFixit-Logo wird ohne gesonderte Genehmigung nicht angezeigt.</p></div>';
});

add_action('wp_enqueue_scripts', static function (): void {
    if (!is_page(msfixit_help_page_ids())) {
        return;
    }
    wp_enqueue_style(
        'msfixit-help-center',
        content_url('mu-plugins/assets/msfixit-help-center.css'),
        [],
        '1.0.0'
    );
});

add_filter('wp_robots', static function (array $robots): array {
    if (isset($_GET['hilfe_suche']) && trim((string) $_GET['hilfe_suche']) !== '') {
        $robots['noindex'] = true;
        $robots['follow'] = true;
    }
    return $robots;
});

add_action('wp_head', static function (): void {
    if (!is_page(msfixit_help_page_ids())) {
        return;
    }
    $data = [
        '@context' => 'https://schema.org',
        '@type' => 'WebPage',
        'name' => wp_get_document_title(),
        'url' => get_permalink(),
        'isPartOf' => [
            '@type' => 'WebSite',
            'name' => get_bloginfo('name'),
            'url' => home_url('/'),
        ],
    ];
    echo '<script type="application/ld+json">' . wp_json_encode($data, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . '</script>' . "\n";
});

add_action('wp_dashboard_setup', static function (): void {
    wp_add_dashboard_widget('msfixit_partner_status', 'Ms. FixIT – Partnerprogramme', static function (): void {
        $pdo = msfixit_help_partner_db();
        if (!$pdo) {
            echo '<p>Partnerdatenbank ist noch nicht verfügbar.</p>';
            return;
        }
        $rows = $pdo->query(
            'SELECT partner_code, program_name, membership_status, valid_until, public_enabled, logo_mode
             FROM partner_profiles ORDER BY provider_name'
        )->fetchAll();
        echo '<table class="widefat striped"><thead><tr><th>Programm</th><th>Status</th><th>Öffentlich</th></tr></thead><tbody>';
        foreach ($rows as $row) {
            $status = esc_html((string) $row['membership_status']);
            if (!empty($row['valid_until'])) {
                $status .= '<br>bis ' . esc_html(wp_date('d.m.Y', strtotime((string) $row['valid_until'])));
            }
            echo '<tr><td>' . esc_html((string) $row['program_name']) . '</td><td>' . $status . '</td><td>' . ((int) $row['public_enabled'] === 1 ? 'Ja' : 'Nein') . '</td></tr>';
        }
        echo '</tbody></table><p>Öffentliche Bezeichnungen und Logos werden ausschließlich aus geprüften Partnerprofilen angezeigt.</p>';
    });
});
