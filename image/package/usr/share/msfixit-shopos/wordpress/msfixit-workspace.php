<?php
/**
 * Plugin Name: Ms. FixIT ShopOS Google Workspace
 * Description: Sends ShopOS mail through the Ms. FixIT Google Workspace account using OAuth 2.0 and the Gmail API.
 * Version: 1.0.0
 */

declare(strict_types=1);

if (!defined('ABSPATH')) {
    exit;
}

const MSFIXIT_WORKSPACE_VERSION = '1.0.0';
const MSFIXIT_WORKSPACE_SENDER_EMAIL = 'office@msfixit.at';
const MSFIXIT_WORKSPACE_SENDER_NAME = 'Ms. FixIT';
const MSFIXIT_WORKSPACE_OAUTH_SCOPE = 'openid email https://www.googleapis.com/auth/gmail.send';
const MSFIXIT_WORKSPACE_TOKEN_ENDPOINT = 'https://oauth2.googleapis.com/token';
const MSFIXIT_WORKSPACE_AUTH_ENDPOINT = 'https://accounts.google.com/o/oauth2/v2/auth';
const MSFIXIT_WORKSPACE_USERINFO_ENDPOINT = 'https://openidconnect.googleapis.com/v1/userinfo';
const MSFIXIT_WORKSPACE_SEND_ENDPOINT = 'https://gmail.googleapis.com/gmail/v1/users/me/messages/send';

function msfixit_workspace_sender_email(): string
{
    return MSFIXIT_WORKSPACE_SENDER_EMAIL;
}

function msfixit_workspace_sender_name(): string
{
    return MSFIXIT_WORKSPACE_SENDER_NAME;
}

function msfixit_workspace_secret_key(): string
{
    return hash('sha256', wp_salt('auth') . '|msfixit-workspace-v1', true);
}

function msfixit_workspace_encrypt_secret(string $plaintext): string
{
    if ($plaintext === '') {
        return '';
    }

    $key = msfixit_workspace_secret_key();
    if (function_exists('sodium_crypto_secretbox')) {
        $nonce = random_bytes(SODIUM_CRYPTO_SECRETBOX_NONCEBYTES);
        $ciphertext = sodium_crypto_secretbox($plaintext, $nonce, $key);
        return 's1:' . base64_encode($nonce . $ciphertext);
    }

    if (function_exists('openssl_encrypt')) {
        $iv = random_bytes(12);
        $tag = '';
        $ciphertext = openssl_encrypt(
            $plaintext,
            'aes-256-gcm',
            $key,
            OPENSSL_RAW_DATA,
            $iv,
            $tag
        );
        if (is_string($ciphertext) && $tag !== '') {
            return 'o1:' . base64_encode($iv . $tag . $ciphertext);
        }
    }

    throw new RuntimeException('No supported secret encryption backend is available.');
}

function msfixit_workspace_decrypt_secret(string $encoded): string
{
    if ($encoded === '') {
        return '';
    }

    $key = msfixit_workspace_secret_key();
    if (str_starts_with($encoded, 's1:') && function_exists('sodium_crypto_secretbox_open')) {
        $payload = base64_decode(substr($encoded, 3), true);
        if (!is_string($payload) || strlen($payload) <= SODIUM_CRYPTO_SECRETBOX_NONCEBYTES) {
            return '';
        }
        $nonce = substr($payload, 0, SODIUM_CRYPTO_SECRETBOX_NONCEBYTES);
        $ciphertext = substr($payload, SODIUM_CRYPTO_SECRETBOX_NONCEBYTES);
        $plaintext = sodium_crypto_secretbox_open($ciphertext, $nonce, $key);
        return is_string($plaintext) ? $plaintext : '';
    }

    if (str_starts_with($encoded, 'o1:') && function_exists('openssl_decrypt')) {
        $payload = base64_decode(substr($encoded, 3), true);
        if (!is_string($payload) || strlen($payload) <= 28) {
            return '';
        }
        $iv = substr($payload, 0, 12);
        $tag = substr($payload, 12, 16);
        $ciphertext = substr($payload, 28);
        $plaintext = openssl_decrypt(
            $ciphertext,
            'aes-256-gcm',
            $key,
            OPENSSL_RAW_DATA,
            $iv,
            $tag
        );
        return is_string($plaintext) ? $plaintext : '';
    }

    return '';
}

function msfixit_workspace_client_id(): string
{
    return trim((string) get_option('msfixit_workspace_client_id', ''));
}

function msfixit_workspace_client_secret(): string
{
    return msfixit_workspace_decrypt_secret(
        (string) get_option('msfixit_workspace_client_secret_encrypted', '')
    );
}

function msfixit_workspace_refresh_token(): string
{
    return msfixit_workspace_decrypt_secret(
        (string) get_option('msfixit_workspace_refresh_token_encrypted', '')
    );
}

function msfixit_workspace_account_email(): string
{
    return sanitize_email((string) get_option('msfixit_workspace_account_email', ''));
}

function msfixit_workspace_ready(): bool
{
    return msfixit_workspace_client_id() !== ''
        && msfixit_workspace_client_secret() !== ''
        && msfixit_workspace_refresh_token() !== ''
        && strtolower(msfixit_workspace_account_email()) === strtolower(msfixit_workspace_sender_email());
}

function msfixit_workspace_set_last_error(string $message): void
{
    $message = wp_strip_all_tags($message);
    if (function_exists('mb_substr')) {
        $message = mb_substr($message, 0, 500);
    } else {
        $message = substr($message, 0, 500);
    }
    update_option('msfixit_workspace_last_error', $message, false);
}

function msfixit_workspace_clear_access_token(): void
{
    delete_transient('msfixit_workspace_access_token');
}

function msfixit_workspace_access_token()
{
    $cached = (string) get_transient('msfixit_workspace_access_token');
    if ($cached !== '') {
        $token = msfixit_workspace_decrypt_secret($cached);
        if ($token !== '') {
            return $token;
        }
    }

    if (!msfixit_workspace_ready()) {
        return new WP_Error('workspace_not_connected', 'Google Workspace ist noch nicht verbunden.');
    }

    $response = wp_remote_post(MSFIXIT_WORKSPACE_TOKEN_ENDPOINT, [
        'timeout' => 20,
        'redirection' => 0,
        'headers' => ['Accept' => 'application/json'],
        'body' => [
            'client_id' => msfixit_workspace_client_id(),
            'client_secret' => msfixit_workspace_client_secret(),
            'refresh_token' => msfixit_workspace_refresh_token(),
            'grant_type' => 'refresh_token',
        ],
    ]);
    if (is_wp_error($response)) {
        return $response;
    }

    $status = (int) wp_remote_retrieve_response_code($response);
    $payload = json_decode((string) wp_remote_retrieve_body($response), true);
    if ($status !== 200 || !is_array($payload) || empty($payload['access_token'])) {
        $description = is_array($payload)
            ? (string) ($payload['error_description'] ?? $payload['error'] ?? 'Token request failed')
            : 'Token request failed';
        return new WP_Error('workspace_token_failed', $description);
    }

    $token = (string) $payload['access_token'];
    $expires = max(300, (int) ($payload['expires_in'] ?? 3600) - 120);
    set_transient(
        'msfixit_workspace_access_token',
        msfixit_workspace_encrypt_secret($token),
        $expires
    );
    return $token;
}

function msfixit_workspace_load_phpmailer(): bool
{
    if (!class_exists('PHPMailer\\PHPMailer\\PHPMailer')) {
        require_once ABSPATH . WPINC . '/PHPMailer/PHPMailer.php';
        require_once ABSPATH . WPINC . '/PHPMailer/Exception.php';
    }
    return class_exists('PHPMailer\\PHPMailer\\PHPMailer');
}

function msfixit_workspace_parse_addresses($value): array
{
    $items = [];
    if (is_array($value)) {
        foreach ($value as $part) {
            $items = array_merge($items, msfixit_workspace_parse_addresses($part));
        }
        return $items;
    }

    foreach (str_getcsv((string) $value, ',') as $address) {
        $address = trim($address);
        if ($address === '') {
            continue;
        }
        $name = '';
        $email = $address;
        if (preg_match('/^(.*?)<([^>]+)>$/', $address, $matches) === 1) {
            $name = trim((string) $matches[1], " \t\n\r\0\x0B\"");
            $email = trim((string) $matches[2]);
        }
        $email = sanitize_email($email);
        if ($email !== '' && is_email($email)) {
            $items[] = [$email, sanitize_text_field($name)];
        }
    }
    return $items;
}

function msfixit_workspace_header_lines($headers): array
{
    if (is_array($headers)) {
        $lines = [];
        foreach ($headers as $header) {
            $lines = array_merge($lines, preg_split('/\r\n|\r|\n/', (string) $header) ?: []);
        }
        return $lines;
    }
    return preg_split('/\r\n|\r|\n/', (string) $headers) ?: [];
}

function msfixit_workspace_add_addresses($mailer, $addresses, string $method): int
{
    $count = 0;
    foreach (msfixit_workspace_parse_addresses($addresses) as [$email, $name]) {
        $mailer->{$method}($email, $name);
        $count++;
    }
    return $count;
}

function msfixit_workspace_build_mime(array $atts)
{
    if (!msfixit_workspace_load_phpmailer()) {
        return new WP_Error('workspace_phpmailer_missing', 'PHPMailer konnte nicht geladen werden.');
    }

    try {
        $mailer = new PHPMailer\PHPMailer\PHPMailer(true);
        $mailer->CharSet = 'UTF-8';
        $mailer->Encoding = '8bit';
        $mailer->Hostname = 'msfixit.at';
        $mailer->setFrom(msfixit_workspace_sender_email(), msfixit_workspace_sender_name(), false);
        $mailer->Sender = msfixit_workspace_sender_email();

        $recipientCount = msfixit_workspace_add_addresses($mailer, $atts['to'] ?? [], 'addAddress');
        $contentType = 'text/plain';
        $charset = 'UTF-8';

        foreach (msfixit_workspace_header_lines($atts['headers'] ?? []) as $line) {
            $line = trim($line);
            if ($line === '' || !str_contains($line, ':')) {
                continue;
            }
            [$name, $value] = array_map('trim', explode(':', $line, 2));
            $lower = strtolower($name);
            if ($lower === 'from') {
                continue;
            }
            if ($lower === 'reply-to') {
                msfixit_workspace_add_addresses($mailer, $value, 'addReplyTo');
                continue;
            }
            if ($lower === 'cc') {
                $recipientCount += msfixit_workspace_add_addresses($mailer, $value, 'addCC');
                continue;
            }
            if ($lower === 'bcc') {
                $recipientCount += msfixit_workspace_add_addresses($mailer, $value, 'addBCC');
                continue;
            }
            if ($lower === 'content-type') {
                $parts = array_map('trim', explode(';', $value));
                if (!empty($parts[0])) {
                    $contentType = strtolower($parts[0]);
                }
                foreach (array_slice($parts, 1) as $part) {
                    if (stripos($part, 'charset=') === 0) {
                        $charset = trim(substr($part, 8), " \t\n\r\0\x0B\"");
                    }
                }
                continue;
            }
            if (in_array($lower, ['mime-version', 'content-transfer-encoding'], true)) {
                continue;
            }
            if (preg_match('/^[A-Za-z0-9-]+$/', $name) === 1
                && !str_contains($value, "\r")
                && !str_contains($value, "\n")) {
                $mailer->addCustomHeader($name, $value);
            }
        }

        if ($recipientCount < 1) {
            return new WP_Error('workspace_no_recipient', 'Die Nachricht enthält keine gültige Empfängeradresse.');
        }

        $mailer->Subject = (string) ($atts['subject'] ?? '');
        $mailer->Body = (string) ($atts['message'] ?? '');
        $mailer->CharSet = $charset !== '' ? $charset : 'UTF-8';
        $mailer->isHTML($contentType === 'text/html');
        if ($contentType === 'text/html') {
            $mailer->AltBody = wp_strip_all_tags($mailer->Body);
        }

        $attachments = $atts['attachments'] ?? [];
        if (!is_array($attachments)) {
            $attachments = preg_split('/\r\n|\r|\n/', (string) $attachments) ?: [];
        }
        foreach ($attachments as $attachment) {
            $path = (string) $attachment;
            if ($path === '') {
                continue;
            }
            if (!is_file($path) || !is_readable($path)) {
                return new WP_Error('workspace_attachment_unreadable', 'Ein E-Mail-Anhang konnte nicht gelesen werden.');
            }
            $mailer->addAttachment($path);
        }

        if (!$mailer->preSend()) {
            return new WP_Error('workspace_mime_failed', 'Die E-Mail konnte nicht vorbereitet werden.');
        }
        return $mailer->getSentMIMEMessage();
    } catch (Throwable $exception) {
        return new WP_Error('workspace_mime_exception', $exception->getMessage());
    }
}

function msfixit_workspace_send_via_gmail_api($pre, array $atts)
{
    if ((bool) apply_filters('msfixit_workspace_disable_api_transport', false)) {
        return $pre;
    }

    if (!msfixit_workspace_ready()) {
        $error = new WP_Error(
            'workspace_not_connected',
            'Google Workspace ist nicht verbunden; die E-Mail wurde nicht versendet.'
        );
        msfixit_workspace_set_last_error($error->get_error_message());
        do_action('wp_mail_failed', $error);
        return false;
    }

    $mime = msfixit_workspace_build_mime($atts);
    if (is_wp_error($mime)) {
        msfixit_workspace_set_last_error($mime->get_error_message());
        do_action('wp_mail_failed', $mime);
        return false;
    }

    $accessToken = msfixit_workspace_access_token();
    if (is_wp_error($accessToken)) {
        msfixit_workspace_set_last_error($accessToken->get_error_message());
        do_action('wp_mail_failed', $accessToken);
        return false;
    }

    $raw = rtrim(strtr(base64_encode((string) $mime), '+/', '-_'), '=');
    $response = wp_remote_post(MSFIXIT_WORKSPACE_SEND_ENDPOINT, [
        'timeout' => 30,
        'redirection' => 0,
        'headers' => [
            'Authorization' => 'Bearer ' . $accessToken,
            'Content-Type' => 'application/json; charset=UTF-8',
            'Accept' => 'application/json',
        ],
        'body' => wp_json_encode(['raw' => $raw]),
    ]);

    if (is_wp_error($response)) {
        msfixit_workspace_set_last_error($response->get_error_message());
        do_action('wp_mail_failed', $response);
        return false;
    }

    $status = (int) wp_remote_retrieve_response_code($response);
    $payload = json_decode((string) wp_remote_retrieve_body($response), true);
    if ($status < 200 || $status >= 300 || !is_array($payload) || empty($payload['id'])) {
        $message = is_array($payload)
            ? (string) ($payload['error']['message'] ?? 'Gmail API rejected the message')
            : 'Gmail API rejected the message';
        $error = new WP_Error('workspace_send_failed', $message, ['status' => $status]);
        msfixit_workspace_set_last_error($message);
        if ($status === 401) {
            msfixit_workspace_clear_access_token();
        }
        do_action('wp_mail_failed', $error);
        return false;
    }

    update_option('msfixit_workspace_last_success_at', current_time('mysql', true), false);
    delete_option('msfixit_workspace_last_error');
    do_action('wp_mail_succeeded', $atts);
    return true;
}

add_filter('wp_mail_from', static fn (): string => msfixit_workspace_sender_email(), 999);
add_filter('wp_mail_from_name', static fn (): string => msfixit_workspace_sender_name(), 999);
add_filter('pre_wp_mail', 'msfixit_workspace_send_via_gmail_api', 5, 2);
add_filter('msfixit_mail_transport_ready', static fn (): bool => msfixit_workspace_ready());

add_action('init', static function (): void {
    if ((string) get_option('admin_email', '') !== msfixit_workspace_sender_email()) {
        update_option('admin_email', msfixit_workspace_sender_email());
    }
}, 1);

function msfixit_workspace_redirect_uri(): string
{
    return admin_url('options-general.php?page=msfixit-workspace');
}

function msfixit_workspace_require_admin(): void
{
    if (!current_user_can('manage_options')) {
        wp_die(esc_html__('Du hast keine Berechtigung für diese Einstellung.', 'msfixit-shopos'));
    }
}

function msfixit_workspace_admin_redirect(string $status): void
{
    wp_safe_redirect(add_query_arg([
        'page' => 'msfixit-workspace',
        'workspace_status' => sanitize_key($status),
    ], admin_url('options-general.php')));
    exit;
}

add_action('admin_post_msfixit_workspace_save', static function (): void {
    msfixit_workspace_require_admin();
    check_admin_referer('msfixit_workspace_save');

    $clientId = sanitize_text_field(wp_unslash((string) ($_POST['client_id'] ?? '')));
    $clientSecret = trim(wp_unslash((string) ($_POST['client_secret'] ?? '')));
    if ($clientId === '') {
        msfixit_workspace_admin_redirect('missing-client-id');
    }
    update_option('msfixit_workspace_client_id', $clientId, false);
    if ($clientSecret !== '') {
        update_option(
            'msfixit_workspace_client_secret_encrypted',
            msfixit_workspace_encrypt_secret($clientSecret),
            false
        );
    }
    msfixit_workspace_clear_access_token();
    msfixit_workspace_admin_redirect('saved');
});

add_action('admin_post_msfixit_workspace_connect', static function (): void {
    msfixit_workspace_require_admin();
    check_admin_referer('msfixit_workspace_connect');

    if (msfixit_workspace_client_id() === '' || msfixit_workspace_client_secret() === '') {
        msfixit_workspace_admin_redirect('missing-credentials');
    }

    $state = bin2hex(random_bytes(24));
    set_transient(
        'msfixit_workspace_oauth_state_' . get_current_user_id(),
        hash('sha256', $state),
        10 * MINUTE_IN_SECONDS
    );

    $authorizationUrl = add_query_arg([
        'client_id' => msfixit_workspace_client_id(),
        'redirect_uri' => msfixit_workspace_redirect_uri(),
        'response_type' => 'code',
        'scope' => MSFIXIT_WORKSPACE_OAUTH_SCOPE,
        'access_type' => 'offline',
        'prompt' => 'consent',
        'include_granted_scopes' => 'true',
        'state' => $state,
    ], MSFIXIT_WORKSPACE_AUTH_ENDPOINT);
    wp_redirect($authorizationUrl);
    exit;
});

function msfixit_workspace_exchange_code(string $code)
{
    $response = wp_remote_post(MSFIXIT_WORKSPACE_TOKEN_ENDPOINT, [
        'timeout' => 20,
        'redirection' => 0,
        'headers' => ['Accept' => 'application/json'],
        'body' => [
            'code' => $code,
            'client_id' => msfixit_workspace_client_id(),
            'client_secret' => msfixit_workspace_client_secret(),
            'redirect_uri' => msfixit_workspace_redirect_uri(),
            'grant_type' => 'authorization_code',
        ],
    ]);
    if (is_wp_error($response)) {
        return $response;
    }

    $status = (int) wp_remote_retrieve_response_code($response);
    $payload = json_decode((string) wp_remote_retrieve_body($response), true);
    if ($status !== 200 || !is_array($payload) || empty($payload['access_token'])) {
        $message = is_array($payload)
            ? (string) ($payload['error_description'] ?? $payload['error'] ?? 'OAuth exchange failed')
            : 'OAuth exchange failed';
        return new WP_Error('workspace_oauth_exchange_failed', $message);
    }
    return $payload;
}

function msfixit_workspace_fetch_userinfo(string $accessToken)
{
    $response = wp_remote_get(MSFIXIT_WORKSPACE_USERINFO_ENDPOINT, [
        'timeout' => 20,
        'redirection' => 0,
        'headers' => [
            'Authorization' => 'Bearer ' . $accessToken,
            'Accept' => 'application/json',
        ],
    ]);
    if (is_wp_error($response)) {
        return $response;
    }

    $status = (int) wp_remote_retrieve_response_code($response);
    $payload = json_decode((string) wp_remote_retrieve_body($response), true);
    if ($status !== 200 || !is_array($payload) || empty($payload['email'])) {
        return new WP_Error('workspace_userinfo_failed', 'Das verbundene Google-Konto konnte nicht geprüft werden.');
    }
    return $payload;
}

add_action('admin_init', static function (): void {
    if ((string) ($_GET['page'] ?? '') !== 'msfixit-workspace'
        || !isset($_GET['code'], $_GET['state'])) {
        return;
    }

    msfixit_workspace_require_admin();
    $state = sanitize_text_field(wp_unslash((string) $_GET['state']));
    $stored = (string) get_transient('msfixit_workspace_oauth_state_' . get_current_user_id());
    delete_transient('msfixit_workspace_oauth_state_' . get_current_user_id());
    if ($stored === '' || !hash_equals($stored, hash('sha256', $state))) {
        msfixit_workspace_admin_redirect('invalid-state');
    }

    $tokens = msfixit_workspace_exchange_code(
        sanitize_text_field(wp_unslash((string) $_GET['code']))
    );
    if (is_wp_error($tokens)) {
        msfixit_workspace_set_last_error($tokens->get_error_message());
        msfixit_workspace_admin_redirect('oauth-error');
    }

    $userinfo = msfixit_workspace_fetch_userinfo((string) $tokens['access_token']);
    if (is_wp_error($userinfo)) {
        msfixit_workspace_set_last_error($userinfo->get_error_message());
        msfixit_workspace_admin_redirect('userinfo-error');
    }

    $email = sanitize_email((string) ($userinfo['email'] ?? ''));
    $verified = (bool) ($userinfo['email_verified'] ?? false);
    if (!$verified || strtolower($email) !== strtolower(msfixit_workspace_sender_email())) {
        msfixit_workspace_set_last_error(
            'Verbunden wurde ' . ($email !== '' ? $email : 'ein unbekanntes Konto')
            . '; erforderlich ist ' . msfixit_workspace_sender_email() . '.'
        );
        msfixit_workspace_admin_redirect('wrong-account');
    }

    $refreshToken = (string) ($tokens['refresh_token'] ?? '');
    if ($refreshToken === '' && msfixit_workspace_refresh_token() === '') {
        msfixit_workspace_set_last_error('Google hat keinen dauerhaften Refresh-Token geliefert.');
        msfixit_workspace_admin_redirect('missing-refresh-token');
    }
    if ($refreshToken !== '') {
        update_option(
            'msfixit_workspace_refresh_token_encrypted',
            msfixit_workspace_encrypt_secret($refreshToken),
            false
        );
    }
    update_option('msfixit_workspace_account_email', $email, false);
    update_option('msfixit_workspace_connected_at', current_time('mysql', true), false);
    set_transient(
        'msfixit_workspace_access_token',
        msfixit_workspace_encrypt_secret((string) $tokens['access_token']),
        max(300, (int) ($tokens['expires_in'] ?? 3600) - 120)
    );
    delete_option('msfixit_workspace_last_error');
    msfixit_workspace_admin_redirect('connected');
});

add_action('admin_post_msfixit_workspace_disconnect', static function (): void {
    msfixit_workspace_require_admin();
    check_admin_referer('msfixit_workspace_disconnect');
    delete_option('msfixit_workspace_refresh_token_encrypted');
    delete_option('msfixit_workspace_account_email');
    delete_option('msfixit_workspace_connected_at');
    msfixit_workspace_clear_access_token();
    msfixit_workspace_admin_redirect('disconnected');
});

add_action('admin_post_msfixit_workspace_test', static function (): void {
    msfixit_workspace_require_admin();
    check_admin_referer('msfixit_workspace_test');
    $sent = wp_mail(
        msfixit_workspace_sender_email(),
        'ShopOS Google Workspace Test',
        "Der E-Mail-Versand von Ms. FixIT ShopOS funktioniert.\n\n"
        . 'Zeitpunkt (UTC): ' . current_time('mysql', true) . "\n"
    );
    msfixit_workspace_admin_redirect($sent ? 'test-sent' : 'test-failed');
});

function msfixit_workspace_notice_text(string $status): string
{
    $messages = [
        'saved' => 'OAuth-Zugangsdaten gespeichert.',
        'connected' => 'Google Workspace wurde erfolgreich mit office@msfixit.at verbunden.',
        'disconnected' => 'Google Workspace wurde getrennt.',
        'test-sent' => 'Die Testnachricht wurde über Google Workspace versendet.',
        'test-failed' => 'Die Testnachricht konnte nicht versendet werden. Details stehen unten.',
        'missing-client-id' => 'Bitte trage eine OAuth-Client-ID ein.',
        'missing-credentials' => 'Bitte speichere zuerst Client-ID und Client-Secret.',
        'invalid-state' => 'Die OAuth-Anmeldung ist abgelaufen oder ungültig. Bitte starte sie erneut.',
        'oauth-error' => 'Google konnte den Autorisierungscode nicht einlösen.',
        'userinfo-error' => 'Das verbundene Google-Konto konnte nicht geprüft werden.',
        'wrong-account' => 'Bitte verbinde ausschließlich office@msfixit.at.',
        'missing-refresh-token' => 'Google hat keinen dauerhaften Zugriffsschlüssel geliefert. Bitte trenne den App-Zugriff bei Google und verbinde erneut.',
    ];
    return $messages[$status] ?? '';
}

add_action('admin_menu', static function (): void {
    add_options_page(
        'Google Workspace',
        'Google Workspace',
        'manage_options',
        'msfixit-workspace',
        'msfixit_workspace_render_settings_page'
    );
});

function msfixit_workspace_render_settings_page(): void
{
    msfixit_workspace_require_admin();
    $status = sanitize_key((string) ($_GET['workspace_status'] ?? ''));
    $notice = msfixit_workspace_notice_text($status);
    $lastError = (string) get_option('msfixit_workspace_last_error', '');
    $lastSuccess = (string) get_option('msfixit_workspace_last_success_at', '');
    $connectedAt = (string) get_option('msfixit_workspace_connected_at', '');
    ?>
    <div class="wrap">
        <h1>Google Workspace</h1>
        <?php if ($notice !== '') : ?>
            <div class="notice <?php echo str_contains($status, 'error') || str_contains($status, 'failed') || str_contains($status, 'wrong') || str_contains($status, 'missing') || str_contains($status, 'invalid') ? 'notice-error' : 'notice-success'; ?> is-dismissible">
                <p><?php echo esc_html($notice); ?></p>
            </div>
        <?php endif; ?>

        <p>ShopOS versendet WordPress-, WooCommerce- und Service-E-Mails ausschließlich als <strong><?php echo esc_html(msfixit_workspace_sender_email()); ?></strong> über die Gmail API.</p>

        <table class="widefat striped" style="max-width:900px;margin:18px 0;">
            <tbody>
                <tr><th style="width:240px;">Absender</th><td><?php echo esc_html(msfixit_workspace_sender_name() . ' <' . msfixit_workspace_sender_email() . '>'); ?></td></tr>
                <tr><th>Status</th><td><?php echo msfixit_workspace_ready() ? '<strong style="color:#16803a">Verbunden</strong>' : '<strong style="color:#b32d2e">Nicht verbunden</strong>'; ?></td></tr>
                <tr><th>Google-Konto</th><td><?php echo esc_html(msfixit_workspace_account_email() ?: '—'); ?></td></tr>
                <tr><th>Verbunden seit (UTC)</th><td><?php echo esc_html($connectedAt ?: '—'); ?></td></tr>
                <tr><th>Letzter erfolgreicher Versand (UTC)</th><td><?php echo esc_html($lastSuccess ?: '—'); ?></td></tr>
                <tr><th>Letzter Fehler</th><td><?php echo esc_html($lastError ?: '—'); ?></td></tr>
            </tbody>
        </table>

        <h2>1. OAuth-Webclient anlegen</h2>
        <p>Lege im Google-Cloud-Projekt einen OAuth-Client vom Typ <strong>Webanwendung</strong> an. Trage diese URI exakt als autorisierte Weiterleitungs-URI ein:</p>
        <p><code><?php echo esc_html(msfixit_workspace_redirect_uri()); ?></code></p>
        <p>Der Zugriff ist auf Identität, E-Mail-Adresse und das reine Senden von Gmail-Nachrichten begrenzt. ShopOS liest weder Postfach noch Kontakte.</p>

        <h2>2. Zugangsdaten speichern</h2>
        <form method="post" action="<?php echo esc_url(admin_url('admin-post.php')); ?>" style="max-width:900px;">
            <input type="hidden" name="action" value="msfixit_workspace_save">
            <?php wp_nonce_field('msfixit_workspace_save'); ?>
            <table class="form-table" role="presentation">
                <tr>
                    <th scope="row"><label for="client_id">OAuth-Client-ID</label></th>
                    <td><input class="regular-text" type="text" id="client_id" name="client_id" value="<?php echo esc_attr(msfixit_workspace_client_id()); ?>" autocomplete="off" required></td>
                </tr>
                <tr>
                    <th scope="row"><label for="client_secret">OAuth-Client-Secret</label></th>
                    <td>
                        <input class="regular-text" type="password" id="client_secret" name="client_secret" value="" autocomplete="new-password">
                        <p class="description">Leer lassen, um das bereits verschlüsselt gespeicherte Secret beizubehalten.</p>
                    </td>
                </tr>
            </table>
            <?php submit_button('Zugangsdaten speichern'); ?>
        </form>

        <h2>3. office@msfixit.at verbinden</h2>
        <div style="display:flex;gap:10px;flex-wrap:wrap;align-items:center;">
            <form method="post" action="<?php echo esc_url(admin_url('admin-post.php')); ?>">
                <input type="hidden" name="action" value="msfixit_workspace_connect">
                <?php wp_nonce_field('msfixit_workspace_connect'); ?>
                <?php submit_button(msfixit_workspace_ready() ? 'Neu verbinden' : 'Mit Google Workspace verbinden', 'primary', 'submit', false); ?>
            </form>
            <?php if (msfixit_workspace_ready()) : ?>
                <form method="post" action="<?php echo esc_url(admin_url('admin-post.php')); ?>">
                    <input type="hidden" name="action" value="msfixit_workspace_test">
                    <?php wp_nonce_field('msfixit_workspace_test'); ?>
                    <?php submit_button('Testmail senden', 'secondary', 'submit', false); ?>
                </form>
                <form method="post" action="<?php echo esc_url(admin_url('admin-post.php')); ?>" onsubmit="return confirm('Google Workspace wirklich von ShopOS trennen?');">
                    <input type="hidden" name="action" value="msfixit_workspace_disconnect">
                    <?php wp_nonce_field('msfixit_workspace_disconnect'); ?>
                    <?php submit_button('Verbindung trennen', 'delete', 'submit', false); ?>
                </form>
            <?php endif; ?>
        </div>

        <h2>Workspace-Schnellzugriff</h2>
        <p>
            <a class="button" href="https://mail.google.com/" target="_blank" rel="noopener noreferrer">Gmail öffnen</a>
            <a class="button" href="https://calendar.google.com/" target="_blank" rel="noopener noreferrer">Kalender öffnen</a>
            <a class="button" href="https://drive.google.com/" target="_blank" rel="noopener noreferrer">Drive öffnen</a>
            <a class="button" href="https://admin.google.com/" target="_blank" rel="noopener noreferrer">Workspace Admin öffnen</a>
        </p>
    </div>
    <?php
}

add_action('wp_dashboard_setup', static function (): void {
    if (!current_user_can('manage_options')) {
        return;
    }
    wp_add_dashboard_widget(
        'msfixit_workspace_status',
        'Ms. FixIT Google Workspace',
        static function (): void {
            $status = msfixit_workspace_ready() ? 'Verbunden' : 'Nicht verbunden';
            echo '<p><strong>' . esc_html($status) . '</strong><br>'
                . esc_html(msfixit_workspace_sender_email()) . '</p>';
            echo '<p><a class="button" href="' . esc_url(admin_url('options-general.php?page=msfixit-workspace')) . '">Workspace verwalten</a></p>';
        }
    );
});

add_filter('site_status_tests', static function (array $tests): array {
    $tests['direct']['msfixit_workspace_mail'] = [
        'label' => 'Ms. FixIT Google Workspace Mail',
        'test' => static function (): array {
            $ready = msfixit_workspace_ready();
            return [
                'label' => $ready
                    ? 'Google Workspace Mail ist verbunden'
                    : 'Google Workspace Mail ist nicht verbunden',
                'status' => $ready ? 'good' : 'critical',
                'badge' => ['label' => 'ShopOS', 'color' => 'blue'],
                'description' => '<p>' . esc_html(
                    $ready
                        ? 'ShopOS versendet E-Mails über office@msfixit.at.'
                        : 'Ohne die Workspace-Verbindung werden Shop-, Bestell- und Service-E-Mails nicht versendet.'
                ) . '</p>',
                'actions' => '<p><a href="' . esc_url(admin_url('options-general.php?page=msfixit-workspace')) . '">Google Workspace konfigurieren</a></p>',
                'test' => 'msfixit_workspace_mail',
            ];
        },
    ];
    return $tests;
});
