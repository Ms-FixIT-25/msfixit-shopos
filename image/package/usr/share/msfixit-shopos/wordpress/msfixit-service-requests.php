<?php
/**
 * Plugin Name: Ms. FixIT ShopOS Service Requests
 * Description: Privacy-conscious repair intake and secret-link status tracking for ShopOS.
 * Version: 1.0.0
 */

declare(strict_types=1);

if (!defined('ABSPATH')) {
    exit;
}

const MSFIXIT_SERVICE_POST_TYPE = 'msfixit_service_request';
const MSFIXIT_SERVICE_FORM_ACTION = 'msfixit_service_request';
const MSFIXIT_SERVICE_VERSION = '1.0.0';

function msfixit_service_states(): array
{
    return [
        'received' => 'Anfrage eingegangen',
        'reviewing' => 'Wird geprüft',
        'awaiting_customer' => 'Rückmeldung benötigt',
        'appointment' => 'Termin vereinbart',
        'device_received' => 'Gerät übernommen',
        'diagnosis' => 'Diagnose läuft',
        'quote' => 'Kosteneinschätzung erstellt',
        'approval' => 'Freigabe ausständig',
        'repair' => 'Reparatur läuft',
        'parts' => 'Ersatzteil wird erwartet',
        'testing' => 'Abschlusstest läuft',
        'ready' => 'Abhol- oder versandbereit',
        'completed' => 'Abgeschlossen',
        'cancelled' => 'Storniert',
    ];
}

function msfixit_service_request_types(): array
{
    return [
        'repair' => 'Reparatur',
        'diagnosis' => 'Fehlerdiagnose',
        'setup' => 'Einrichtung oder Installation',
        'network' => 'FRITZ!Box, WLAN oder Netzwerk',
        'data' => 'Datensicherung oder Datenübernahme',
        'purchase' => 'Produkt- oder Kaufberatung',
        'order' => 'Frage zu einer Bestellung',
        'other' => 'Sonstiges Anliegen',
    ];
}

function msfixit_service_device_types(): array
{
    return [
        'smartphone' => 'Smartphone',
        'tablet' => 'Tablet',
        'notebook' => 'Notebook',
        'pc' => 'PC',
        'console' => 'Spielkonsole',
        'network' => 'Router oder Netzwerkgerät',
        'storage' => 'Festplatte, SSD oder Datenträger',
        'printer' => 'Drucker oder Zubehör',
        'other' => 'Anderes Gerät',
        'none' => 'Kein bestimmtes Gerät',
    ];
}

function msfixit_service_contact_methods(): array
{
    return [
        'email' => 'E-Mail',
        'phone' => 'Telefon',
    ];
}

function msfixit_service_privacy_url(): string
{
    $page = get_page_by_path('datenschutz', OBJECT, 'page');
    if (!$page instanceof WP_Post || $page->post_status !== 'publish') {
        return '';
    }
    return (string) get_permalink($page);
}

function msfixit_service_public_enabled(): bool
{
    return get_option('msfixit_service_public_enabled', 'no') === 'yes'
        && msfixit_service_privacy_url() !== '';
}

function msfixit_service_add_role_capabilities(): void
{
    $capabilities = [
        'read_msfixit_service_request',
        'read_private_msfixit_service_requests',
        'edit_msfixit_service_request',
        'edit_msfixit_service_requests',
        'edit_others_msfixit_service_requests',
        'edit_private_msfixit_service_requests',
        'publish_msfixit_service_requests',
        'delete_msfixit_service_request',
        'delete_msfixit_service_requests',
        'delete_others_msfixit_service_requests',
        'delete_private_msfixit_service_requests',
    ];

    foreach (['administrator', 'shop_manager'] as $roleName) {
        $role = get_role($roleName);
        if (!$role instanceof WP_Role) {
            continue;
        }
        foreach ($capabilities as $capability) {
            if (!$role->has_cap($capability)) {
                $role->add_cap($capability);
            }
        }
    }
}

add_action('init', static function (): void {
    msfixit_service_add_role_capabilities();

    register_post_type(MSFIXIT_SERVICE_POST_TYPE, [
        'labels' => [
            'name' => 'Serviceanfragen',
            'singular_name' => 'Serviceanfrage',
            'menu_name' => 'Serviceanfragen',
            'add_new_item' => 'Serviceanfrage anlegen',
            'edit_item' => 'Serviceanfrage bearbeiten',
            'view_item' => 'Serviceanfrage anzeigen',
            'search_items' => 'Serviceanfragen durchsuchen',
            'not_found' => 'Keine Serviceanfragen gefunden',
        ],
        'public' => false,
        'publicly_queryable' => false,
        'exclude_from_search' => true,
        'show_ui' => true,
        'show_in_menu' => true,
        'show_in_rest' => false,
        'menu_icon' => 'dashicons-hammer',
        'supports' => ['title'],
        'capability_type' => ['msfixit_service_request', 'msfixit_service_requests'],
        'map_meta_cap' => true,
        'capabilities' => [
            'create_posts' => 'do_not_allow',
        ],
    ]);
}, 5);

function msfixit_service_trim(string $value, int $maximum): string
{
    $value = trim($value);
    if (function_exists('mb_substr')) {
        return mb_substr($value, 0, $maximum);
    }
    return substr($value, 0, $maximum);
}

function msfixit_service_reference_exists(string $reference): bool
{
    $query = new WP_Query([
        'post_type' => MSFIXIT_SERVICE_POST_TYPE,
        'post_status' => 'private',
        'fields' => 'ids',
        'posts_per_page' => 1,
        'meta_key' => '_msfixit_service_reference',
        'meta_value' => $reference,
        'no_found_rows' => true,
    ]);
    return $query->have_posts();
}

function msfixit_service_new_reference(): string
{
    for ($attempt = 0; $attempt < 10; $attempt++) {
        $suffix = strtoupper(wp_generate_password(6, false, false));
        $reference = 'MF-SVC-' . gmdate('Ymd') . '-' . $suffix;
        if (!msfixit_service_reference_exists($reference)) {
            return $reference;
        }
    }
    return 'MF-SVC-' . gmdate('YmdHis') . '-' . strtoupper(wp_generate_password(8, false, false));
}

function msfixit_service_client_fingerprint(string $purpose): string
{
    $address = isset($_SERVER['REMOTE_ADDR']) ? (string) $_SERVER['REMOTE_ADDR'] : 'unknown';
    $agent = isset($_SERVER['HTTP_USER_AGENT']) ? (string) $_SERVER['HTTP_USER_AGENT'] : 'unknown';
    return hash_hmac('sha256', $purpose . '|' . $address . '|' . $agent, wp_salt('nonce'));
}

function msfixit_service_rate_limited(string $purpose, int $limit, int $window): bool
{
    $key = 'msfixit_service_' . $purpose . '_' . msfixit_service_client_fingerprint($purpose);
    $count = (int) get_transient($key);
    if ($count >= $limit) {
        return true;
    }
    set_transient($key, $count + 1, $window);
    return false;
}

function msfixit_service_redirect_error(string $code): void
{
    wp_safe_redirect(add_query_arg('service_error', sanitize_key($code), home_url('/service-anfrage/')));
    exit;
}

function msfixit_service_tracking_url(string $reference, string $secret): string
{
    return add_query_arg([
        'ticket' => $reference,
        'zugang' => $secret,
    ], home_url('/service-status/'));
}

function msfixit_service_send_notifications(int $postId, string $secret): void
{
    $reference = (string) get_post_meta($postId, '_msfixit_service_reference', true);
    $name = (string) get_post_meta($postId, '_msfixit_service_name', true);
    $email = (string) get_post_meta($postId, '_msfixit_service_email', true);
    $type = (string) get_post_meta($postId, '_msfixit_service_type', true);
    $device = (string) get_post_meta($postId, '_msfixit_service_device', true);
    $model = (string) get_post_meta($postId, '_msfixit_service_model', true);
    $trackingUrl = msfixit_service_tracking_url($reference, $secret);
    $types = msfixit_service_request_types();
    $devices = msfixit_service_device_types();

    $adminEmail = sanitize_email((string) get_option('admin_email'));
    if ($adminEmail !== '') {
        wp_mail(
            $adminEmail,
            sprintf('[%s] Neue Serviceanfrage', $reference),
            "Eine neue Serviceanfrage wurde angelegt.\n\n"
            . 'Referenz: ' . $reference . "\n"
            . 'Name: ' . $name . "\n"
            . 'Art: ' . ($types[$type] ?? $type) . "\n"
            . 'Gerät: ' . ($devices[$device] ?? $device) . "\n"
            . 'Modell: ' . $model . "\n\n"
            . "Die vollständigen Angaben sind im WordPress-Backend unter Serviceanfragen gespeichert.\n"
        );
    }

    if ($email !== '' && is_email($email)) {
        wp_mail(
            $email,
            sprintf('Deine Ms. FixIT Serviceanfrage %s', $reference),
            "Hallo " . $name . ",\n\n"
            . "deine Anfrage ist bei Ms. FixIT eingegangen.\n\n"
            . 'Referenz: ' . $reference . "\n"
            . 'Status-Link: ' . $trackingUrl . "\n\n"
            . "Speichere diesen Link. Er enthält deinen geheimen Zugangsschlüssel. Teile ihn nicht öffentlich.\n"
            . "Bitte sende keine Passwörter per E-Mail. Falls Zugangsdaten für einen Funktionstest nötig sind, wird das vorher mit dir abgestimmt.\n\n"
            . "Viele Grüße\nMs. FixIT\n"
        );
    }
}

function msfixit_service_handle_submission(): void
{
    if (strtoupper((string) ($_SERVER['REQUEST_METHOD'] ?? '')) !== 'POST') {
        msfixit_service_redirect_error('method');
    }

    check_admin_referer('msfixit_service_request', 'msfixit_service_nonce');

    if (!msfixit_service_public_enabled()) {
        msfixit_service_redirect_error('disabled');
    }
    if (!empty($_POST['website'])) {
        msfixit_service_redirect_error('invalid');
    }
    if (msfixit_service_rate_limited('submit', 5, HOUR_IN_SECONDS)) {
        msfixit_service_redirect_error('rate');
    }

    $types = msfixit_service_request_types();
    $devices = msfixit_service_device_types();
    $contactMethods = msfixit_service_contact_methods();

    $name = msfixit_service_trim(sanitize_text_field(wp_unslash((string) ($_POST['name'] ?? ''))), 120);
    $email = sanitize_email(msfixit_service_trim(wp_unslash((string) ($_POST['email'] ?? '')), 190));
    $phone = msfixit_service_trim(sanitize_text_field(wp_unslash((string) ($_POST['phone'] ?? ''))), 60);
    $type = sanitize_key((string) ($_POST['request_type'] ?? ''));
    $device = sanitize_key((string) ($_POST['device_type'] ?? ''));
    $model = msfixit_service_trim(sanitize_text_field(wp_unslash((string) ($_POST['model'] ?? ''))), 160);
    $orderNumber = msfixit_service_trim(sanitize_text_field(wp_unslash((string) ($_POST['order_number'] ?? ''))), 80);
    $fault = msfixit_service_trim(sanitize_textarea_field(wp_unslash((string) ($_POST['fault'] ?? ''))), 4000);
    $contactMethod = sanitize_key((string) ($_POST['contact_method'] ?? 'email'));
    $consent = isset($_POST['privacy_consent']) && (string) $_POST['privacy_consent'] === '1';

    if ($name === '' || !is_email($email) || $fault === '' || !$consent) {
        msfixit_service_redirect_error('required');
    }
    if (!array_key_exists($type, $types) || !array_key_exists($device, $devices)) {
        msfixit_service_redirect_error('selection');
    }
    if (!array_key_exists($contactMethod, $contactMethods)) {
        $contactMethod = 'email';
    }
    if ($contactMethod === 'phone' && $phone === '') {
        msfixit_service_redirect_error('phone');
    }

    $reference = msfixit_service_new_reference();
    $secret = wp_generate_password(32, false, false);
    $secretHash = password_hash($secret, PASSWORD_DEFAULT);
    if (!is_string($secretHash) || $secretHash === '') {
        msfixit_service_redirect_error('internal');
    }

    $postId = wp_insert_post([
        'post_type' => MSFIXIT_SERVICE_POST_TYPE,
        'post_status' => 'private',
        'post_title' => $reference,
        'post_content' => '',
        'comment_status' => 'closed',
        'ping_status' => 'closed',
    ], true);
    if (is_wp_error($postId)) {
        error_log('[Ms. FixIT service] Request creation failed: ' . $postId->get_error_message());
        msfixit_service_redirect_error('internal');
    }

    $meta = [
        '_msfixit_service_reference' => $reference,
        '_msfixit_service_secret_hash' => $secretHash,
        '_msfixit_service_status' => 'received',
        '_msfixit_service_name' => $name,
        '_msfixit_service_email' => $email,
        '_msfixit_service_phone' => $phone,
        '_msfixit_service_type' => $type,
        '_msfixit_service_device' => $device,
        '_msfixit_service_model' => $model,
        '_msfixit_service_order_number' => $orderNumber,
        '_msfixit_service_fault' => $fault,
        '_msfixit_service_contact_method' => $contactMethod,
        '_msfixit_service_privacy_consent_at' => current_time('mysql', true),
        '_msfixit_service_public_note' => 'Die Anfrage wurde erfolgreich aufgenommen.',
        '_msfixit_service_history' => [[
            'time' => current_time('mysql', true),
            'status' => 'received',
            'actor' => 0,
        ]],
    ];
    foreach ($meta as $key => $value) {
        update_post_meta((int) $postId, $key, $value);
    }

    msfixit_service_send_notifications((int) $postId, $secret);
    wp_safe_redirect(add_query_arg([
        'service_created' => '1',
        'ticket' => $reference,
        'zugang' => $secret,
    ], home_url('/service-status/')));
    exit;
}

add_action('admin_post_nopriv_' . MSFIXIT_SERVICE_FORM_ACTION, 'msfixit_service_handle_submission');
add_action('admin_post_' . MSFIXIT_SERVICE_FORM_ACTION, 'msfixit_service_handle_submission');

function msfixit_service_error_message(string $code): string
{
    $messages = [
        'required' => 'Bitte fülle alle Pflichtfelder aus und bestätige die Datenschutzhinweise.',
        'selection' => 'Bitte wähle eine gültige Anfrageart und Gerätekategorie.',
        'phone' => 'Für den Rückruf wird eine Telefonnummer benötigt.',
        'rate' => 'Es wurden zu viele Anfragen in kurzer Zeit gesendet. Bitte versuche es später erneut.',
        'invalid' => 'Die Anfrage konnte nicht verarbeitet werden.',
        'method' => 'Die Anfrage wurde mit einer ungültigen Methode aufgerufen.',
        'internal' => 'Die Anfrage konnte technisch nicht gespeichert werden. Bitte nutze die Kontaktseite.',
        'disabled' => 'Die Online-Serviceanfrage ist noch nicht freigegeben. Bitte nutze vorerst die Kontaktseite.',
    ];
    return $messages[$code] ?? 'Die Anfrage konnte nicht verarbeitet werden.';
}

function msfixit_service_select(string $name, array $options, string $selected = ''): string
{
    $html = '<select id="msfixit-service-' . esc_attr($name) . '" name="' . esc_attr($name) . '" required>';
    $html .= '<option value="">Bitte wählen</option>';
    foreach ($options as $value => $label) {
        $html .= '<option value="' . esc_attr((string) $value) . '"' . selected($selected, (string) $value, false) . '>' . esc_html((string) $label) . '</option>';
    }
    return $html . '</select>';
}

add_shortcode('msfixit_service_request_form', static function (): string {
    if (!msfixit_service_public_enabled()) {
        $message = '<div class="msfixit-service-alert"><strong>Online-Serviceanfrage noch nicht freigegeben.</strong> Bitte nutze vorerst die Kontaktseite.</div>';
        if (current_user_can('manage_options')) {
            $message .= '<div class="msfixit-help-admin-note">Für die Freigabe muss die Datenschutzerklärung veröffentlicht und die Option <code>msfixit_service_public_enabled</code> auf <code>yes</code> gesetzt sein.</div>';
        }
        return $message;
    }

    $privacyUrl = msfixit_service_privacy_url();
    $errorCode = isset($_GET['service_error']) ? sanitize_key((string) $_GET['service_error']) : '';
    $notice = $errorCode !== ''
        ? '<div class="msfixit-service-alert msfixit-service-alert-error" role="alert">' . esc_html(msfixit_service_error_message($errorCode)) . '</div>'
        : '';

    $html = $notice;
    $html .= '<form class="msfixit-service-form" method="post" action="' . esc_url(admin_url('admin-post.php')) . '">';
    $html .= '<input type="hidden" name="action" value="' . esc_attr(MSFIXIT_SERVICE_FORM_ACTION) . '">';
    $html .= wp_nonce_field('msfixit_service_request', 'msfixit_service_nonce', true, false);
    $html .= '<div class="msfixit-service-honeypot" aria-hidden="true"><label>Website<input type="text" name="website" tabindex="-1" autocomplete="off"></label></div>';
    $html .= '<div class="msfixit-service-grid">';
    $html .= '<label>Dein Name<span aria-hidden="true"> *</span><input type="text" name="name" maxlength="120" autocomplete="name" required></label>';
    $html .= '<label>E-Mail<span aria-hidden="true"> *</span><input type="email" name="email" maxlength="190" autocomplete="email" required></label>';
    $html .= '<label>Telefonnummer<input type="tel" name="phone" maxlength="60" autocomplete="tel"></label>';
    $html .= '<label>Bevorzugter Kontakt<select name="contact_method"><option value="email">E-Mail</option><option value="phone">Telefon</option></select></label>';
    $html .= '<label>Art der Anfrage<span aria-hidden="true"> *</span>' . msfixit_service_select('request_type', msfixit_service_request_types()) . '</label>';
    $html .= '<label>Gerät oder Bereich<span aria-hidden="true"> *</span>' . msfixit_service_select('device_type', msfixit_service_device_types()) . '</label>';
    $html .= '<label class="msfixit-service-wide">Hersteller und Modell<input type="text" name="model" maxlength="160" placeholder="z. B. Lenovo ThinkPad T14 oder FRITZ!Box 7590"></label>';
    $html .= '<label class="msfixit-service-wide">Bestellnummer, falls vorhanden<input type="text" name="order_number" maxlength="80"></label>';
    $html .= '<label class="msfixit-service-wide">Fehler oder Anliegen<span aria-hidden="true"> *</span><textarea name="fault" maxlength="4000" rows="8" required placeholder="Was funktioniert nicht, seit wann besteht das Problem und was wurde bereits versucht?"></textarea></label>';
    $html .= '</div>';
    $html .= '<div class="msfixit-service-warning"><strong>Wichtig:</strong> Bitte keine Passwörter, PINs oder vollständigen Zahlungsdaten eintragen. Dateien und Fotos werden erst nach Rücksprache über einen geeigneten Weg übernommen.</div>';
    $html .= '<label class="msfixit-service-consent"><input type="checkbox" name="privacy_consent" value="1" required> Ich stimme zu, dass meine Angaben zur Bearbeitung der Anfrage gespeichert und zur Kontaktaufnahme verwendet werden, und habe die <a href="' . esc_url($privacyUrl) . '" target="_blank" rel="noopener noreferrer">Datenschutzerklärung</a> zur Kenntnis genommen.</label>';
    $html .= '<button type="submit">Serviceanfrage senden</button>';
    $html .= '<p class="msfixit-service-small">Nach dem Absenden erhältst du eine Referenz und einen geheimen Status-Link. Eine Reparatur oder kostenpflichtige Leistung wird dadurch noch nicht automatisch beauftragt.</p>';
    $html .= '</form>';
    return $html;
});

function msfixit_service_find_request(string $reference, string $secret): ?WP_Post
{
    if ($reference === '' || $secret === '' || strlen($secret) > 128) {
        return null;
    }
    if (msfixit_service_rate_limited('status', 60, HOUR_IN_SECONDS)) {
        return null;
    }

    $posts = get_posts([
        'post_type' => MSFIXIT_SERVICE_POST_TYPE,
        'post_status' => 'private',
        'posts_per_page' => 1,
        'meta_key' => '_msfixit_service_reference',
        'meta_value' => $reference,
        'suppress_filters' => true,
    ]);
    if (!$posts || !$posts[0] instanceof WP_Post) {
        return null;
    }

    $hash = (string) get_post_meta((int) $posts[0]->ID, '_msfixit_service_secret_hash', true);
    if ($hash === '' || !password_verify($secret, $hash)) {
        return null;
    }
    return $posts[0];
}

add_shortcode('msfixit_service_status', static function (): string {
    $reference = isset($_GET['ticket']) ? msfixit_service_trim(sanitize_text_field(wp_unslash((string) $_GET['ticket'])), 64) : '';
    $secret = isset($_GET['zugang']) ? msfixit_service_trim(sanitize_text_field(wp_unslash((string) $_GET['zugang'])), 128) : '';
    $created = isset($_GET['service_created']) && (string) $_GET['service_created'] === '1';

    $html = $created
        ? '<div class="msfixit-service-alert msfixit-service-alert-success" role="status"><strong>Deine Anfrage wurde gespeichert.</strong> Speichere diese Seite oder den vollständigen Link. Der geheime Zugangsschlüssel wird aus Sicherheitsgründen nicht im System lesbar gespeichert.</div>'
        : '';

    $html .= '<form class="msfixit-service-status-form" method="get" action="' . esc_url(home_url('/service-status/')) . '">';
    $html .= '<label>Referenz<input type="text" name="ticket" maxlength="64" value="' . esc_attr($reference) . '" placeholder="MF-SVC-…" required></label>';
    $html .= '<label>Geheimer Zugangsschlüssel<input type="password" name="zugang" maxlength="128" value="' . esc_attr($secret) . '" autocomplete="off" required></label>';
    $html .= '<button type="submit">Status anzeigen</button></form>';

    if ($reference === '' && $secret === '') {
        return $html . '<p class="msfixit-service-small">Beide Angaben stehen im Status-Link, der nach dem Absenden angezeigt und per E-Mail versendet wird.</p>';
    }

    $request = msfixit_service_find_request($reference, $secret);
    if (!$request) {
        return $html . '<div class="msfixit-service-alert msfixit-service-alert-error" role="alert">Referenz oder Zugangsschlüssel sind ungültig. Aus Datenschutzgründen werden keine weiteren Details angezeigt.</div>';
    }

    $states = msfixit_service_states();
    $types = msfixit_service_request_types();
    $devices = msfixit_service_device_types();
    $postId = (int) $request->ID;
    $status = (string) get_post_meta($postId, '_msfixit_service_status', true);
    $type = (string) get_post_meta($postId, '_msfixit_service_type', true);
    $device = (string) get_post_meta($postId, '_msfixit_service_device', true);
    $model = (string) get_post_meta($postId, '_msfixit_service_model', true);
    $note = (string) get_post_meta($postId, '_msfixit_service_public_note', true);

    $html .= '<section class="msfixit-service-status-card">';
    $html .= '<p class="msfixit-service-reference">' . esc_html($reference) . '</p>';
    $html .= '<h2>' . esc_html($states[$status] ?? 'Status wird geprüft') . '</h2>';
    $html .= '<dl>';
    $html .= '<div><dt>Anfrage</dt><dd>' . esc_html($types[$type] ?? $type) . '</dd></div>';
    $html .= '<div><dt>Gerät</dt><dd>' . esc_html(trim(($devices[$device] ?? $device) . ($model !== '' ? ' – ' . $model : ''))) . '</dd></div>';
    $html .= '<div><dt>Eingegangen</dt><dd>' . esc_html(get_the_date('d.m.Y H:i', $postId)) . '</dd></div>';
    $html .= '<div><dt>Zuletzt aktualisiert</dt><dd>' . esc_html(get_the_modified_date('d.m.Y H:i', $postId)) . '</dd></div>';
    $html .= '</dl>';
    if ($note !== '') {
        $html .= '<div class="msfixit-service-public-note"><h3>Aktuelle Information</h3><p>' . nl2br(esc_html($note)) . '</p></div>';
    }
    $html .= '<p class="msfixit-service-small">Dieser Status ist eine Serviceinformation und keine verbindliche Kosten- oder Terminzusage.</p>';
    $html .= '</section>';
    return $html;
});

add_action('add_meta_boxes_' . MSFIXIT_SERVICE_POST_TYPE, static function (WP_Post $post): void {
    add_meta_box('msfixit_service_details', 'Serviceanfrage', static function (WP_Post $post): void {
        wp_nonce_field('msfixit_service_admin_update', 'msfixit_service_admin_nonce');
        $states = msfixit_service_states();
        $types = msfixit_service_request_types();
        $devices = msfixit_service_device_types();
        $status = (string) get_post_meta($post->ID, '_msfixit_service_status', true);
        $reference = (string) get_post_meta($post->ID, '_msfixit_service_reference', true);
        $type = (string) get_post_meta($post->ID, '_msfixit_service_type', true);
        $device = (string) get_post_meta($post->ID, '_msfixit_service_device', true);
        $name = (string) get_post_meta($post->ID, '_msfixit_service_name', true);
        $email = (string) get_post_meta($post->ID, '_msfixit_service_email', true);
        $phone = (string) get_post_meta($post->ID, '_msfixit_service_phone', true);
        $model = (string) get_post_meta($post->ID, '_msfixit_service_model', true);
        $order = (string) get_post_meta($post->ID, '_msfixit_service_order_number', true);
        $fault = (string) get_post_meta($post->ID, '_msfixit_service_fault', true);
        $note = (string) get_post_meta($post->ID, '_msfixit_service_public_note', true);

        echo '<p><strong>Referenz:</strong> ' . esc_html($reference) . '</p>';
        echo '<p><strong>Kontakt:</strong> ' . esc_html($name) . ' – <a href="mailto:' . esc_attr($email) . '">' . esc_html($email) . '</a>' . ($phone !== '' ? ' – ' . esc_html($phone) : '') . '</p>';
        echo '<p><strong>Anfrage:</strong> ' . esc_html($types[$type] ?? $type) . '</p>';
        echo '<p><strong>Gerät:</strong> ' . esc_html($devices[$device] ?? $device) . ($model !== '' ? ' – ' . esc_html($model) : '') . '</p>';
        if ($order !== '') {
            echo '<p><strong>Bestellnummer:</strong> ' . esc_html($order) . '</p>';
        }
        echo '<p><strong>Fehler oder Anliegen:</strong></p><div style="white-space:pre-wrap;border:1px solid #dcdcde;padding:12px;background:#fff">' . esc_html($fault) . '</div>';
        echo '<p><label for="msfixit-service-status"><strong>Status</strong></label><br><select id="msfixit-service-status" name="msfixit_service_status">';
        foreach ($states as $value => $label) {
            echo '<option value="' . esc_attr($value) . '"' . selected($status, $value, false) . '>' . esc_html($label) . '</option>';
        }
        echo '</select></p>';
        echo '<p><label for="msfixit-service-public-note"><strong>Öffentliche Statusinformation</strong></label><br><textarea id="msfixit-service-public-note" name="msfixit_service_public_note" rows="5" style="width:100%">' . esc_textarea($note) . '</textarea></p>';
        echo '<p class="description">Dieser Text ist mit Referenz und geheimem Zugangsschlüssel öffentlich abrufbar. Keine internen Notizen, Passwörter oder sensiblen Daten eintragen.</p>';
    }, MSFIXIT_SERVICE_POST_TYPE, 'normal', 'high');
}, 10, 1);

add_action('save_post_' . MSFIXIT_SERVICE_POST_TYPE, static function (int $postId, WP_Post $post): void {
    if (wp_is_post_revision($postId) || wp_is_post_autosave($postId)) {
        return;
    }
    if (!isset($_POST['msfixit_service_admin_nonce']) || !wp_verify_nonce((string) $_POST['msfixit_service_admin_nonce'], 'msfixit_service_admin_update')) {
        return;
    }
    if (!current_user_can('edit_msfixit_service_request', $postId)) {
        return;
    }

    $states = msfixit_service_states();
    $newStatus = sanitize_key((string) ($_POST['msfixit_service_status'] ?? ''));
    $oldStatus = (string) get_post_meta($postId, '_msfixit_service_status', true);
    if (!array_key_exists($newStatus, $states)) {
        $newStatus = $oldStatus !== '' ? $oldStatus : 'received';
    }
    $note = msfixit_service_trim(sanitize_textarea_field(wp_unslash((string) ($_POST['msfixit_service_public_note'] ?? ''))), 2000);
    update_post_meta($postId, '_msfixit_service_status', $newStatus);
    update_post_meta($postId, '_msfixit_service_public_note', $note);

    if ($newStatus !== $oldStatus) {
        $history = get_post_meta($postId, '_msfixit_service_history', true);
        if (!is_array($history)) {
            $history = [];
        }
        $history[] = [
            'time' => current_time('mysql', true),
            'status' => $newStatus,
            'actor' => get_current_user_id(),
        ];
        update_post_meta($postId, '_msfixit_service_history', array_slice($history, -100));
    }
}, 10, 2);

add_filter('manage_' . MSFIXIT_SERVICE_POST_TYPE . '_posts_columns', static function (array $columns): array {
    return [
        'cb' => $columns['cb'] ?? '<input type="checkbox">',
        'title' => 'Referenz',
        'msfixit_service_status' => 'Status',
        'msfixit_service_type' => 'Anfrage',
        'msfixit_service_device' => 'Gerät',
        'msfixit_service_contact' => 'Kontakt',
        'date' => 'Eingegangen',
    ];
});

add_action('manage_' . MSFIXIT_SERVICE_POST_TYPE . '_posts_custom_column', static function (string $column, int $postId): void {
    if ($column === 'msfixit_service_status') {
        $states = msfixit_service_states();
        $value = (string) get_post_meta($postId, '_msfixit_service_status', true);
        echo esc_html($states[$value] ?? $value);
    } elseif ($column === 'msfixit_service_type') {
        $types = msfixit_service_request_types();
        $value = (string) get_post_meta($postId, '_msfixit_service_type', true);
        echo esc_html($types[$value] ?? $value);
    } elseif ($column === 'msfixit_service_device') {
        $devices = msfixit_service_device_types();
        $value = (string) get_post_meta($postId, '_msfixit_service_device', true);
        $model = (string) get_post_meta($postId, '_msfixit_service_model', true);
        echo esc_html(trim(($devices[$value] ?? $value) . ($model !== '' ? ' – ' . $model : '')));
    } elseif ($column === 'msfixit_service_contact') {
        $name = (string) get_post_meta($postId, '_msfixit_service_name', true);
        $email = (string) get_post_meta($postId, '_msfixit_service_email', true);
        echo esc_html($name) . '<br><a href="mailto:' . esc_attr($email) . '">' . esc_html($email) . '</a>';
    }
}, 10, 2);

add_action('restrict_manage_posts', static function (string $postType): void {
    if ($postType !== MSFIXIT_SERVICE_POST_TYPE) {
        return;
    }
    $selected = isset($_GET['service_status']) ? sanitize_key((string) $_GET['service_status']) : '';
    echo '<select name="service_status"><option value="">Alle Status</option>';
    foreach (msfixit_service_states() as $value => $label) {
        echo '<option value="' . esc_attr($value) . '"' . selected($selected, $value, false) . '>' . esc_html($label) . '</option>';
    }
    echo '</select>';
});

add_action('pre_get_posts', static function (WP_Query $query): void {
    if (!is_admin() || !$query->is_main_query() || $query->get('post_type') !== MSFIXIT_SERVICE_POST_TYPE) {
        return;
    }
    $status = isset($_GET['service_status']) ? sanitize_key((string) $_GET['service_status']) : '';
    if ($status !== '' && array_key_exists($status, msfixit_service_states())) {
        $query->set('meta_key', '_msfixit_service_status');
        $query->set('meta_value', $status);
    }
});

add_action('wp_enqueue_scripts', static function (): void {
    $pageIds = array_values(array_filter(array_map('intval', (array) get_option('msfixit_service_page_ids', []))));
    if (!$pageIds || !is_page($pageIds)) {
        return;
    }
    wp_enqueue_style(
        'msfixit-service-requests',
        content_url('mu-plugins/assets/msfixit-service-requests.css'),
        [],
        MSFIXIT_SERVICE_VERSION
    );
});

add_filter('wp_robots', static function (array $robots): array {
    $statusPageId = (int) get_option('msfixit_service_status_page_id', 0);
    if ($statusPageId > 0 && is_page($statusPageId)) {
        $robots['noindex'] = true;
        $robots['nofollow'] = true;
        $robots['noarchive'] = true;
    }
    return $robots;
});

add_action('send_headers', static function (): void {
    $statusPageId = (int) get_option('msfixit_service_status_page_id', 0);
    if ($statusPageId > 0 && is_page($statusPageId) && !headers_sent()) {
        header('Referrer-Policy: no-referrer');
        header('Cache-Control: private, no-store, max-age=0');
    }
});

add_action('wp_dashboard_setup', static function (): void {
    wp_add_dashboard_widget('msfixit_service_dashboard', 'Ms. FixIT – Serviceanfragen', static function (): void {
        $states = msfixit_service_states();
        $openStatuses = ['received', 'reviewing', 'awaiting_customer', 'appointment', 'device_received', 'diagnosis', 'quote', 'approval', 'repair', 'parts', 'testing', 'ready'];
        $counts = [];
        foreach ($openStatuses as $status) {
            $query = new WP_Query([
                'post_type' => MSFIXIT_SERVICE_POST_TYPE,
                'post_status' => 'private',
                'fields' => 'ids',
                'posts_per_page' => 1,
                'meta_key' => '_msfixit_service_status',
                'meta_value' => $status,
            ]);
            $counts[$status] = (int) $query->found_posts;
        }
        $total = array_sum($counts);
        echo '<p><strong>Öffentliche Annahme:</strong> ' . (msfixit_service_public_enabled() ? 'freigegeben' : 'gesperrt') . '</p>';
        echo '<p><strong>' . esc_html((string) $total) . '</strong> offene Serviceanfragen</p><ul>';
        foreach ($counts as $status => $count) {
            if ($count > 0) {
                echo '<li>' . esc_html($states[$status]) . ': ' . esc_html((string) $count) . '</li>';
            }
        }
        echo '</ul><p><a class="button button-primary" href="' . esc_url(admin_url('edit.php?post_type=' . MSFIXIT_SERVICE_POST_TYPE)) . '">Serviceanfragen öffnen</a></p>';
    });
});
