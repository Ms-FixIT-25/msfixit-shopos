<?php

declare(strict_types=1);

if (!defined('ABSPATH')) {
    exit;
}

function msfixit_customer_security_verification_form(string $operation, string $label): void
{
    echo '<form class="msfixit-security-verify" method="post" action="' . esc_url(admin_url('admin-post.php')) . '">';
    wp_nonce_field('msfixit_customer_security_' . $operation);
    echo '<input type="hidden" name="action" value="msfixit_customer_security"><input type="hidden" name="operation" value="' . esc_attr($operation) . '">'
        . '<p><label>Aktuelles Passwort<br><input type="password" name="current_password" autocomplete="current-password" required></label></p>'
        . '<p><label>Authenticator- oder Wiederherstellungscode<br><input name="totp_code" autocomplete="one-time-code" maxlength="24" required></label></p>'
        . '<button class="button" type="submit">' . esc_html($label) . '</button></form>';
}

function msfixit_customer_security_endpoint(): void
{
    if (!is_user_logged_in()) {
        echo '<p>Bitte melde dich an.</p>';
        return;
    }
    $userId = get_current_user_id();
    $user = wp_get_current_user();
    $notices = [
        'google_connected' => 'Google wurde erfolgreich verbunden.',
        'google_disconnected' => 'Die Google-Verknüpfung wurde entfernt.',
        'totp_pending' => 'Übertrage den Schlüssel in deine Authenticator-App und bestätige den ersten Code.',
        'totp_invalid' => 'Der Bestätigungscode war ungültig oder die Einrichtung ist abgelaufen.',
        'totp_enabled' => '2-Faktor-Authentifizierung ist aktiv. Speichere jetzt die Wiederherstellungscodes.',
        'totp_disabled' => '2-Faktor-Authentifizierung wurde deaktiviert.',
        'verification_failed' => 'Passwort oder Sicherheitscode war ungültig.',
        'recovery_ready' => 'Neue Wiederherstellungscodes wurden erzeugt.',
        'sessions_closed' => 'Alle anderen Sitzungen wurden beendet.',
    ];
    $notice = sanitize_key((string) ($_GET['auth_notice'] ?? ''));
    if (isset($notices[$notice])) {
        echo '<div class="woocommerce-message" role="status">' . esc_html($notices[$notice]) . '</div>';
    }

    echo '<div class="msfixit-security-grid"><section class="msfixit-security-card"><h2>Google-Anmeldung</h2>';
    $googleEmail = sanitize_email((string) get_user_meta($userId, '_msfixit_google_email', true));
    if ($googleEmail !== '') {
        echo '<p><strong>Verbunden:</strong> ' . esc_html($googleEmail) . '</p><form method="post" action="' . esc_url(admin_url('admin-post.php')) . '">';
        wp_nonce_field('msfixit_customer_security_google_disconnect');
        echo '<input type="hidden" name="action" value="msfixit_customer_security"><input type="hidden" name="operation" value="google_disconnect"><button class="button" type="submit">Google-Verknüpfung entfernen</button></form>';
    } elseif (msfixit_customer_google_ready()) {
        echo '<p>Verbinde dein Kundenkonto für eine schnelle Anmeldung ohne Shop-Passwort.</p><a class="button" href="'
            . esc_url(msfixit_customer_google_start_url('connect', msfixit_customer_security_url())) . '">Google verbinden</a>';
    } else {
        echo '<p>Die Google-Anmeldung ist derzeit nicht verfügbar.</p>';
    }
    echo '</section><section class="msfixit-security-card"><h2>Authenticator-App</h2>';

    if (!msfixit_customer_totp_enabled($userId)) {
        $pending = msfixit_customer_auth_decrypt((string) get_transient('msfixit_totp_pending_' . $userId));
        if ($pending === '') {
            echo '<p>Schütze die Passwort-Anmeldung mit einem zusätzlichen Einmalcode.</p><form method="post" action="' . esc_url(admin_url('admin-post.php')) . '">';
            wp_nonce_field('msfixit_customer_security_totp_begin');
            echo '<input type="hidden" name="action" value="msfixit_customer_security"><input type="hidden" name="operation" value="totp_begin"><button class="button" type="submit">2-Faktor einrichten</button></form>';
        } else {
            $uri = 'otpauth://totp/' . rawurlencode('Ms. FixIT:' . $user->user_email)
                . '?secret=' . rawurlencode($pending) . '&issuer=' . rawurlencode('Ms. FixIT') . '&algorithm=SHA1&digits=6&period=30';
            echo '<dl class="msfixit-auth-details"><dt>Kontoname</dt><dd>' . esc_html($user->user_email) . '</dd><dt>Schlüssel</dt><dd><code>' . esc_html($pending)
                . '</code></dd><dt>Einrichtungsadresse</dt><dd><code class="msfixit-wrap">' . esc_html($uri) . '</code></dd></dl>';
            echo '<form method="post" action="' . esc_url(admin_url('admin-post.php')) . '">';
            wp_nonce_field('msfixit_customer_security_totp_confirm');
            echo '<input type="hidden" name="action" value="msfixit_customer_security"><input type="hidden" name="operation" value="totp_confirm">'
                . '<p><label>Aktueller sechsstelliger Code<br><input name="totp_code" inputmode="numeric" autocomplete="one-time-code" maxlength="6" required></label></p>'
                . '<button class="button" type="submit">Einrichtung bestätigen</button></form>';
        }
    } else {
        $hashes = get_user_meta($userId, '_msfixit_recovery_hashes', true);
        echo '<p><strong>Aktiv.</strong> Verbleibende Wiederherstellungscodes: ' . esc_html((string) (is_array($hashes) ? count($hashes) : 0)) . '</p>';
        echo '<details><summary>Neue Wiederherstellungscodes</summary>';
        msfixit_customer_security_verification_form('recovery_regenerate', 'Neue Codes erstellen');
        echo '</details><details><summary>2-Faktor deaktivieren</summary>';
        msfixit_customer_security_verification_form('totp_disable', '2-Faktor deaktivieren');
        echo '</details>';
    }
    echo '</section>';

    $codes = get_transient('msfixit_recovery_display_' . $userId);
    if (is_array($codes) && $codes !== []) {
        delete_transient('msfixit_recovery_display_' . $userId);
        echo '<section class="msfixit-security-card msfixit-recovery-card"><h2>Wiederherstellungscodes</h2><p>Jeder Code funktioniert nur einmal. Speichere sie offline.</p><pre>';
        foreach ($codes as $code) {
            echo esc_html((string) $code) . "\n";
        }
        echo '</pre></section>';
    }

    echo '<section class="msfixit-security-card"><h2>Sitzungen</h2><p>Beende alle anderen Browser- und Gerätesitzungen.</p><form method="post" action="' . esc_url(admin_url('admin-post.php')) . '">';
    wp_nonce_field('msfixit_customer_security_sessions_close');
    echo '<input type="hidden" name="action" value="msfixit_customer_security"><input type="hidden" name="operation" value="sessions_close"><button class="button" type="submit">Andere Sitzungen beenden</button></form></section>';

    echo '<section class="msfixit-security-card"><h2>Letzte Sicherheitsereignisse</h2><ul class="msfixit-auth-history">';
    $history = get_user_meta($userId, '_msfixit_auth_audit', true);
    foreach (is_array($history) ? array_slice($history, 0, 10) : [] as $entry) {
        if (is_array($entry)) {
            echo '<li><time>' . esc_html((string) ($entry['time'] ?? '')) . ' UTC</time><span>'
                . esc_html((string) ($entry['event'] ?? 'event')) . '</span><small>' . esc_html((string) ($entry['method'] ?? '')) . '</small></li>';
        }
    }
    echo '</ul></section></div>';
}

add_action('init', static function (): void {
    add_rewrite_endpoint(MSFIXIT_CUSTOMER_AUTH_ENDPOINT, EP_ROOT | EP_PAGES);
});
add_action('woocommerce_account_' . MSFIXIT_CUSTOMER_AUTH_ENDPOINT . '_endpoint', 'msfixit_customer_security_endpoint');
add_filter('woocommerce_account_menu_items', static function (array $items): array {
    $logout = $items['customer-logout'] ?? null;
    unset($items['customer-logout']);
    $items[MSFIXIT_CUSTOMER_AUTH_ENDPOINT] = 'Sicherheit';
    if ($logout !== null) {
        $items['customer-logout'] = $logout;
    }
    return $items;
});
add_action('wp_enqueue_scripts', static function (): void {
    if (function_exists('is_account_page') && is_account_page()) {
        wp_enqueue_style('msfixit-customer-auth', content_url('mu-plugins/assets/msfixit-customer-auth.css'), [], MSFIXIT_CUSTOMER_AUTH_VERSION);
    }
});
