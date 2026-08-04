<?php

declare(strict_types=1);

if (!defined('ABSPATH')) {
    exit;
}

function msfixit_customer_auth_settings_page(): void
{
    if (!current_user_can('manage_options')) {
        return;
    }
    echo '<div class="wrap"><h1>Kundenanmeldung und Sicherheit</h1><p>Verwende einen eigenen externen Google-OAuth-Webclient. Der interne Workspace-Mailclient darf nicht wiederverwendet werden.</p>';
    echo '<form method="post" action="' . esc_url(admin_url('admin-post.php')) . '">';
    wp_nonce_field('msfixit_customer_auth_settings');
    echo '<input type="hidden" name="action" value="msfixit_customer_auth_settings"><table class="form-table">'
        . '<tr><th>Google-Anmeldung</th><td><label><input type="checkbox" name="enabled" value="yes" ' . checked(msfixit_customer_auth_enabled(), true, false) . '> für Kunden anzeigen</label></td></tr>'
        . '<tr><th>Neue Konten</th><td><label><input type="checkbox" name="registration_enabled" value="yes" ' . checked(msfixit_customer_auth_registration_enabled(), true, false) . '> bestätigte neue Google-Adresse als Kunde anlegen</label></td></tr>'
        . '<tr><th>Google Client-ID</th><td><input class="regular-text" name="google_client_id" value="' . esc_attr(msfixit_customer_google_client_id()) . '" autocomplete="off"></td></tr>'
        . '<tr><th>Google Client-Secret</th><td><input class="regular-text" type="password" name="google_client_secret" autocomplete="new-password"><p class="description">Leer lassen, um das verschlüsselte Secret beizubehalten.</p></td></tr>'
        . '<tr><th>Weiterleitungs-URI</th><td><code>' . esc_html(msfixit_customer_google_redirect_uri()) . '</code></td></tr>'
        . '<tr><th>OAuth-Berechtigungen</th><td><code>' . esc_html(MSFIXIT_CUSTOMER_GOOGLE_SCOPE) . '</code><p class="description">Kein Gmail-, Drive-, Kalender- oder Kontaktzugriff.</p></td></tr></table>';
    submit_button('Einstellungen speichern');
    echo '</form></div>';
}
add_action('admin_menu', static function (): void {
    add_options_page('Kundenanmeldung und Sicherheit', 'Kundenanmeldung', 'manage_options', 'msfixit-customer-auth', 'msfixit_customer_auth_settings_page');
});

function msfixit_customer_auth_save_settings(): void
{
    if (!current_user_can('manage_options')) {
        wp_die('Not allowed.');
    }
    check_admin_referer('msfixit_customer_auth_settings');
    update_option('msfixit_customer_auth_enabled', isset($_POST['enabled']) ? 'yes' : 'no', false);
    update_option('msfixit_customer_auth_registration_enabled', isset($_POST['registration_enabled']) ? 'yes' : 'no', false);
    update_option('msfixit_customer_google_client_id', sanitize_text_field(wp_unslash((string) ($_POST['google_client_id'] ?? ''))), false);
    $secret = trim(wp_unslash((string) ($_POST['google_client_secret'] ?? '')));
    if ($secret !== '') {
        update_option('msfixit_customer_google_client_secret_encrypted', msfixit_customer_auth_encrypt($secret), false);
    }
    wp_safe_redirect(add_query_arg(['page' => 'msfixit-customer-auth', 'settings-updated' => '1'], admin_url('options-general.php')));
    exit;
}
add_action('admin_post_msfixit_customer_auth_settings', 'msfixit_customer_auth_save_settings');

add_filter('site_status_tests', static function (array $tests): array {
    $tests['direct']['msfixit_customer_auth'] = [
        'label' => 'Ms. FixIT Kundenanmeldung',
        'test' => static function (): array {
            $enabled = msfixit_customer_auth_enabled();
            $ready = msfixit_customer_google_ready();
            return [
                'label' => !$enabled ? 'Kundenanmeldung ist noch nicht aktiviert' : ($ready ? 'Google-Kundenanmeldung ist konfiguriert' : 'Google-Kundenanmeldung ist unvollständig'),
                'status' => !$enabled ? 'recommended' : ($ready ? 'good' : 'critical'),
                'badge' => ['label' => 'ShopOS', 'color' => 'blue'],
                'description' => '<p>' . ($ready ? 'Client-ID und verschlüsseltes Client-Secret sind vorhanden.' : 'Google-Anmeldung benötigt einen externen Client.') . '</p>',
                'actions' => '',
                'test' => 'msfixit_customer_auth',
            ];
        },
    ];
    return $tests;
});
