<?php
/**
 * Plugin Name: Ms. FixIT ShopOS Customer Authentication
 * Description: Google sign-in, customer TOTP, recovery codes and account security controls for WooCommerce.
 * Version: 1.0.0
 */

declare(strict_types=1);

if (!defined('ABSPATH')) {
    exit;
}

const MSFIXIT_CUSTOMER_AUTH_VERSION = '1.0.0';
const MSFIXIT_CUSTOMER_AUTH_ENDPOINT = 'sicherheit';
const MSFIXIT_CUSTOMER_GOOGLE_SCOPE = 'openid email profile';
const MSFIXIT_CUSTOMER_GOOGLE_AUTH_ENDPOINT = 'https://accounts.google.com/o/oauth2/v2/auth';
const MSFIXIT_CUSTOMER_GOOGLE_TOKEN_ENDPOINT = 'https://oauth2.googleapis.com/token';
const MSFIXIT_CUSTOMER_GOOGLE_USERINFO_ENDPOINT = 'https://openidconnect.googleapis.com/v1/userinfo';

function msfixit_customer_auth_key(): string
{
    return hash('sha256', wp_salt('secure_auth') . '|msfixit-customer-auth-v1', true);
}

function msfixit_customer_auth_encrypt(string $plaintext): string
{
    if ($plaintext === '') {
        return '';
    }

    $key = msfixit_customer_auth_key();
    if (function_exists('sodium_crypto_secretbox')) {
        $nonce = random_bytes(SODIUM_CRYPTO_SECRETBOX_NONCEBYTES);
        return 's1:' . base64_encode($nonce . sodium_crypto_secretbox($plaintext, $nonce, $key));
    }

    if (function_exists('openssl_encrypt')) {
        $iv = random_bytes(12);
        $tag = '';
        $ciphertext = openssl_encrypt($plaintext, 'aes-256-gcm', $key, OPENSSL_RAW_DATA, $iv, $tag);
        if (is_string($ciphertext) && $tag !== '') {
            return 'o1:' . base64_encode($iv . $tag . $ciphertext);
        }
    }

    throw new RuntimeException('No supported encryption backend is available.');
}

function msfixit_customer_auth_decrypt(string $encoded): string
{
    if ($encoded === '') {
        return '';
    }

    $key = msfixit_customer_auth_key();
    if (str_starts_with($encoded, 's1:') && function_exists('sodium_crypto_secretbox_open')) {
        $payload = base64_decode(substr($encoded, 3), true);
        if (!is_string($payload) || strlen($payload) <= SODIUM_CRYPTO_SECRETBOX_NONCEBYTES) {
            return '';
        }
        $nonce = substr($payload, 0, SODIUM_CRYPTO_SECRETBOX_NONCEBYTES);
        $plaintext = sodium_crypto_secretbox_open(
            substr($payload, SODIUM_CRYPTO_SECRETBOX_NONCEBYTES),
            $nonce,
            $key
        );
        return is_string($plaintext) ? $plaintext : '';
    }

    if (str_starts_with($encoded, 'o1:') && function_exists('openssl_decrypt')) {
        $payload = base64_decode(substr($encoded, 3), true);
        if (!is_string($payload) || strlen($payload) <= 28) {
            return '';
        }
        $plaintext = openssl_decrypt(
            substr($payload, 28),
            'aes-256-gcm',
            $key,
            OPENSSL_RAW_DATA,
            substr($payload, 0, 12),
            substr($payload, 12, 16)
        );
        return is_string($plaintext) ? $plaintext : '';
    }

    return '';
}

function msfixit_customer_auth_enabled(): bool
{
    return get_option('msfixit_customer_auth_enabled', 'no') === 'yes';
}

function msfixit_customer_auth_registration_enabled(): bool
{
    return get_option('msfixit_customer_auth_registration_enabled', 'yes') === 'yes';
}

function msfixit_customer_google_client_id(): string
{
    return trim((string) get_option('msfixit_customer_google_client_id', ''));
}

function msfixit_customer_google_client_secret(): string
{
    return msfixit_customer_auth_decrypt(
        (string) get_option('msfixit_customer_google_client_secret_encrypted', '')
    );
}

function msfixit_customer_google_ready(): bool
{
    return msfixit_customer_auth_enabled()
        && msfixit_customer_google_client_id() !== ''
        && msfixit_customer_google_client_secret() !== '';
}

function msfixit_customer_google_redirect_uri(): string
{
    return admin_url('admin-post.php?action=msfixit_customer_google_callback');
}

function msfixit_customer_account_url(): string
{
    return function_exists('wc_get_page_permalink')
        ? wc_get_page_permalink('myaccount')
        : wp_login_url();
}

function msfixit_customer_security_url(array $args = []): string
{
    $base = function_exists('wc_get_account_endpoint_url')
        ? wc_get_account_endpoint_url(MSFIXIT_CUSTOMER_AUTH_ENDPOINT)
        : admin_url('profile.php');
    return $args === [] ? $base : add_query_arg($args, $base);
}

function msfixit_customer_auth_redirect(string $url): string
{
    $fallback = msfixit_customer_account_url();
    return wp_validate_redirect($url, $fallback);
}

function msfixit_customer_auth_b64url(string $value): string
{
    return rtrim(strtr(base64_encode($value), '+/', '-_'), '=');
}

function msfixit_customer_auth_state_key(string $state): string
{
    return 'msfixit_customer_google_' . hash('sha256', $state);
}

function msfixit_customer_auth_audit(int $userId, string $event, string $method): void
{
    $history = get_user_meta($userId, '_msfixit_auth_audit', true);
    if (!is_array($history)) {
        $history = [];
    }
    array_unshift($history, [
        'time' => current_time('mysql', true),
        'event' => sanitize_key($event),
        'method' => sanitize_key($method),
    ]);
    update_user_meta($userId, '_msfixit_auth_audit', array_slice($history, 0, 20));
    update_user_meta($userId, '_msfixit_last_auth_method', sanitize_key($method));
    update_user_meta($userId, '_msfixit_last_auth_at', current_time('mysql', true));
}

function msfixit_customer_google_start_url(string $mode = 'signin', string $redirect = ''): string
{
    $args = [
        'action' => 'msfixit_customer_google_start',
        'mode' => $mode === 'connect' ? 'connect' : 'signin',
        'redirect_to' => $redirect !== '' ? $redirect : msfixit_customer_account_url(),
    ];
    return wp_nonce_url(admin_url('admin-post.php?' . http_build_query($args)), 'msfixit_customer_google_start');
}

function msfixit_customer_google_error_redirect(string $code, string $redirect = ''): void
{
    $target = $redirect !== '' ? msfixit_customer_auth_redirect($redirect) : msfixit_customer_account_url();
    wp_safe_redirect(add_query_arg('msfixit_auth_error', sanitize_key($code), $target));
    exit;
}

function msfixit_customer_google_start(): void
{
    check_admin_referer('msfixit_customer_google_start');
    if (!msfixit_customer_google_ready()) {
        msfixit_customer_google_error_redirect('google_unavailable');
    }

    $mode = sanitize_key((string) ($_GET['mode'] ?? 'signin'));
    $mode = $mode === 'connect' ? 'connect' : 'signin';
    if ($mode === 'connect' && !is_user_logged_in()) {
        auth_redirect();
    }

    $redirect = msfixit_customer_auth_redirect(
        wp_unslash((string) ($_GET['redirect_to'] ?? msfixit_customer_account_url()))
    );
    $state = msfixit_customer_auth_b64url(random_bytes(32));
    $nonce = msfixit_customer_auth_b64url(random_bytes(32));
    $verifier = msfixit_customer_auth_b64url(random_bytes(64));
    $challenge = msfixit_customer_auth_b64url(hash('sha256', $verifier, true));

    set_transient(msfixit_customer_auth_state_key($state), [
        'mode' => $mode,
        'nonce' => $nonce,
        'verifier' => $verifier,
        'redirect' => $redirect,
        'user_id' => get_current_user_id(),
        'created' => time(),
    ], 10 * MINUTE_IN_SECONDS);

    $url = add_query_arg([
        'client_id' => msfixit_customer_google_client_id(),
        'redirect_uri' => msfixit_customer_google_redirect_uri(),
        'response_type' => 'code',
        'scope' => MSFIXIT_CUSTOMER_GOOGLE_SCOPE,
        'state' => $state,
        'nonce' => $nonce,
        'code_challenge' => $challenge,
        'code_challenge_method' => 'S256',
        'prompt' => 'select_account',
        'include_granted_scopes' => 'true',
    ], MSFIXIT_CUSTOMER_GOOGLE_AUTH_ENDPOINT);

    wp_redirect($url);
    exit;
}

add_action('admin_post_nopriv_msfixit_customer_google_start', 'msfixit_customer_google_start');
add_action('admin_post_msfixit_customer_google_start', 'msfixit_customer_google_start');

function msfixit_customer_google_exchange(string $code, string $verifier)
{
    $response = wp_remote_post(MSFIXIT_CUSTOMER_GOOGLE_TOKEN_ENDPOINT, [
        'timeout' => 20,
        'redirection' => 0,
        'headers' => ['Accept' => 'application/json'],
        'body' => [
            'client_id' => msfixit_customer_google_client_id(),
            'client_secret' => msfixit_customer_google_client_secret(),
            'code' => $code,
            'code_verifier' => $verifier,
            'grant_type' => 'authorization_code',
            'redirect_uri' => msfixit_customer_google_redirect_uri(),
        ],
    ]);
    if (is_wp_error($response)) {
        return $response;
    }
    $status = (int) wp_remote_retrieve_response_code($response);
    $body = json_decode((string) wp_remote_retrieve_body($response), true);
    if ($status !== 200 || !is_array($body) || empty($body['access_token'])) {
        return new WP_Error('google_token_failed', 'Google token exchange failed.');
    }
    return $body;
}

function msfixit_customer_google_userinfo(string $accessToken)
{
    $response = wp_remote_get(MSFIXIT_CUSTOMER_GOOGLE_USERINFO_ENDPOINT, [
        'timeout' => 20,
        'redirection' => 0,
        'headers' => [
            'Accept' => 'application/json',
            'Authorization' => 'Bearer ' . $accessToken,
        ],
    ]);
    if (is_wp_error($response)) {
        return $response;
    }
    $status = (int) wp_remote_retrieve_response_code($response);
    $body = json_decode((string) wp_remote_retrieve_body($response), true);
    if ($status !== 200 || !is_array($body)) {
        return new WP_Error('google_userinfo_failed', 'Google identity request failed.');
    }
    return $body;
}

function msfixit_customer_user_by_google_sub(string $sub): int
{
    $ids = get_users([
        'meta_key' => '_msfixit_google_sub',
        'meta_value' => $sub,
        'number' => 2,
        'fields' => 'ids',
    ]);
    return count($ids) === 1 ? (int) $ids[0] : 0;
}

function msfixit_customer_unique_login(string $email): string
{
    $base = sanitize_user((string) strstr($email, '@', true), true);
    if ($base === '') {
        $base = 'kunde';
    }
    $login = $base;
    $counter = 1;
    while (username_exists($login)) {
        $counter++;
        $login = $base . $counter;
    }
    return $login;
}

function msfixit_customer_create_google_user(array $profile)
{
    if (!msfixit_customer_auth_registration_enabled()) {
        return new WP_Error('registration_disabled', 'Customer registration is disabled.');
    }

    $email = sanitize_email((string) ($profile['email'] ?? ''));
    if ($email === '' || !is_email($email)) {
        return new WP_Error('invalid_email', 'Google did not provide a valid email address.');
    }

    $displayName = sanitize_text_field((string) ($profile['name'] ?? ''));
    $userId = wp_insert_user([
        'user_login' => msfixit_customer_unique_login($email),
        'user_email' => $email,
        'user_pass' => wp_generate_password(40, true, true),
        'display_name' => $displayName !== '' ? $displayName : $email,
        'first_name' => sanitize_text_field((string) ($profile['given_name'] ?? '')),
        'last_name' => sanitize_text_field((string) ($profile['family_name'] ?? '')),
        'role' => 'customer',
    ]);
    if (is_wp_error($userId)) {
        return $userId;
    }
    update_user_meta((int) $userId, '_msfixit_google_created', 'yes');
    return (int) $userId;
}

function msfixit_customer_google_callback(): void
{
    $state = sanitize_text_field(wp_unslash((string) ($_GET['state'] ?? '')));
    if ($state === '' || strlen($state) > 120) {
        msfixit_customer_google_error_redirect('state');
    }

    $key = msfixit_customer_auth_state_key($state);
    $flow = get_transient($key);
    delete_transient($key);
    if (!is_array($flow) || empty($flow['verifier']) || empty($flow['redirect'])) {
        msfixit_customer_google_error_redirect('state');
    }
    $redirect = msfixit_customer_auth_redirect((string) $flow['redirect']);

    if (!empty($_GET['error'])) {
        msfixit_customer_google_error_redirect('cancelled', $redirect);
    }
    $code = sanitize_text_field(wp_unslash((string) ($_GET['code'] ?? '')));
    if ($code === '') {
        msfixit_customer_google_error_redirect('code', $redirect);
    }

    $tokens = msfixit_customer_google_exchange($code, (string) $flow['verifier']);
    if (is_wp_error($tokens)) {
        msfixit_customer_google_error_redirect('exchange', $redirect);
    }
    $profile = msfixit_customer_google_userinfo((string) $tokens['access_token']);
    if (is_wp_error($profile)) {
        msfixit_customer_google_error_redirect('identity', $redirect);
    }

    $sub = sanitize_text_field((string) ($profile['sub'] ?? ''));
    $email = sanitize_email((string) ($profile['email'] ?? ''));
    $verified = filter_var($profile['email_verified'] ?? false, FILTER_VALIDATE_BOOLEAN);
    if ($sub === '' || strlen($sub) > 255 || $email === '' || !$verified) {
        msfixit_customer_google_error_redirect('unverified', $redirect);
    }

    $linkedUserId = msfixit_customer_user_by_google_sub($sub);
    if (($flow['mode'] ?? 'signin') === 'connect') {
        $currentUserId = get_current_user_id();
        if ($currentUserId <= 0 || $currentUserId !== (int) ($flow['user_id'] ?? 0)) {
            msfixit_customer_google_error_redirect('session', $redirect);
        }
        if ($linkedUserId > 0 && $linkedUserId !== $currentUserId) {
            msfixit_customer_google_error_redirect('already_linked', $redirect);
        }
        update_user_meta($currentUserId, '_msfixit_google_sub', $sub);
        update_user_meta($currentUserId, '_msfixit_google_email', $email);
        msfixit_customer_auth_audit($currentUserId, 'google_connected', 'google');
        wp_safe_redirect(msfixit_customer_security_url(['auth_notice' => 'google_connected']));
        exit;
    }

    $userId = $linkedUserId;
    if ($userId <= 0) {
        $existing = get_user_by('email', $email);
        if ($existing instanceof WP_User) {
            msfixit_customer_google_error_redirect('link_required', $redirect);
        }
        $created = msfixit_customer_create_google_user($profile);
        if (is_wp_error($created)) {
            msfixit_customer_google_error_redirect('registration', $redirect);
        }
        $userId = (int) $created;
        update_user_meta($userId, '_msfixit_google_sub', $sub);
        update_user_meta($userId, '_msfixit_google_email', $email);
        msfixit_customer_auth_audit($userId, 'account_created', 'google');
    }

    $user = get_user_by('id', $userId);
    if (!$user instanceof WP_User) {
        msfixit_customer_google_error_redirect('account', $redirect);
    }
    if (!empty($user->roles) && array_intersect($user->roles, ['administrator', 'shop_manager'])) {
        msfixit_customer_google_error_redirect('customer_only', $redirect);
    }

    wp_set_current_user($userId);
    wp_set_auth_cookie($userId, true, is_ssl());
    do_action('wp_login', $user->user_login, $user);
    msfixit_customer_auth_audit($userId, 'login', 'google');
    wp_safe_redirect($redirect);
    exit;
}

add_action('admin_post_nopriv_msfixit_customer_google_callback', 'msfixit_customer_google_callback');
add_action('admin_post_msfixit_customer_google_callback', 'msfixit_customer_google_callback');

function msfixit_customer_auth_error_text(string $code): string
{
    $messages = [
        'google_unavailable' => 'Die Google-Anmeldung ist derzeit nicht eingerichtet.',
        'cancelled' => 'Die Google-Anmeldung wurde abgebrochen.',
        'state' => 'Die Anmeldung ist abgelaufen. Bitte starte sie erneut.',
        'code' => 'Google hat keinen gültigen Anmeldecode geliefert.',
        'exchange' => 'Die Google-Anmeldung konnte nicht abgeschlossen werden.',
        'identity' => 'Die Google-Identität konnte nicht geprüft werden.',
        'unverified' => 'Google hat keine bestätigte E-Mail-Adresse geliefert.',
        'session' => 'Die Sitzung hat sich während der Verknüpfung geändert.',
        'already_linked' => 'Dieses Google-Konto ist bereits mit einem anderen Kundenkonto verbunden.',
        'link_required' => 'Für diese E-Mail-Adresse besteht bereits ein Konto. Melde dich zuerst mit deinem Passwort an und verbinde Google anschließend unter Sicherheit.',
        'registration' => 'Das Kundenkonto konnte nicht angelegt werden.',
        'account' => 'Das Kundenkonto wurde nicht gefunden.',
        'customer_only' => 'Google-Anmeldung ist hier nur für Kundenkonten freigegeben.',
    ];
    return $messages[$code] ?? 'Die Anmeldung konnte nicht abgeschlossen werden.';
}

function msfixit_customer_render_auth_notice(): void
{
    $code = sanitize_key((string) ($_GET['msfixit_auth_error'] ?? ''));
    if ($code !== '') {
        echo '<div class="woocommerce-error" role="alert">' . esc_html(msfixit_customer_auth_error_text($code)) . '</div>';
    }
}
add_action('woocommerce_before_customer_login_form', 'msfixit_customer_render_auth_notice');

function msfixit_customer_render_google_button(): void
{
    static $rendered = false;
    if ($rendered || !msfixit_customer_google_ready() || is_user_logged_in()) {
        return;
    }
    $rendered = true;
    $redirect = msfixit_customer_account_url();
    echo '<div class="msfixit-social-login">';
    echo '<a class="button msfixit-google-button" href="' . esc_url(msfixit_customer_google_start_url('signin', $redirect)) . '">';
    echo '<span aria-hidden="true" class="msfixit-google-g">G</span> Mit Google anmelden</a>';
    echo '<p class="msfixit-auth-hint">Google übermittelt nur die bestätigte Identität, E-Mail-Adresse und den Namen.</p>';
    echo '</div>';
}
add_action('woocommerce_login_form_start', 'msfixit_customer_render_google_button', 5);
add_action('woocommerce_register_form_start', 'msfixit_customer_render_google_button', 5);

function msfixit_customer_render_wp_login_button(): void
{
    if (!msfixit_customer_google_ready()) {
        return;
    }
    echo '<p style="margin:16px 0"><a class="button button-large" style="width:100%;text-align:center" href="'
        . esc_url(msfixit_customer_google_start_url('signin', admin_url())))
        . '">Mit Google anmelden</a></p>';
}
add_action('login_form', 'msfixit_customer_render_wp_login_button');

function msfixit_customer_base32_encode(string $binary): string
{
    $alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    $bits = '';
    foreach (str_split($binary) as $byte) {
        $bits .= str_pad(decbin(ord($byte)), 8, '0', STR_PAD_LEFT);
    }
    $output = '';
    foreach (str_split($bits, 5) as $chunk) {
        $chunk = str_pad($chunk, 5, '0', STR_PAD_RIGHT);
        $output .= $alphabet[bindec($chunk)];
    }
    return $output;
}

function msfixit_customer_base32_decode(string $encoded): string
{
    $alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    $encoded = strtoupper(preg_replace('/[^A-Z2-7]/', '', $encoded) ?? '');
    $bits = '';
    foreach (str_split($encoded) as $character) {
        $position = strpos($alphabet, $character);
        if ($position === false) {
            return '';
        }
        $bits .= str_pad(decbin($position), 5, '0', STR_PAD_LEFT);
    }
    $output = '';
    foreach (str_split($bits, 8) as $chunk) {
        if (strlen($chunk) === 8) {
            $output .= chr(bindec($chunk));
        }
    }
    return $output;
}

function msfixit_customer_totp_secret(): string
{
    return msfixit_customer_base32_encode(random_bytes(20));
}

function msfixit_customer_totp_code(string $secret, int $counter): string
{
    $key = msfixit_customer_base32_decode($secret);
    if ($key === '') {
        return '';
    }
    $binaryCounter = pack('N2', intdiv($counter, 4294967296), $counter % 4294967296);
    $hash = hash_hmac('sha1', $binaryCounter, $key, true);
    $offset = ord($hash[19]) & 0x0f;
    $value = unpack('N', substr($hash, $offset, 4));
    $number = (($value[1] ?? 0) & 0x7fffffff) % 1000000;
    return str_pad((string) $number, 6, '0', STR_PAD_LEFT);
}

function msfixit_customer_totp_verify(string $secret, string $candidate, int $window = 1): bool
{
    $candidate = preg_replace('/\D/', '', $candidate) ?? '';
    if (strlen($candidate) !== 6) {
        return false;
    }
    $counter = intdiv(time(), 30);
    for ($offset = -$window; $offset <= $window; $offset++) {
        if (hash_equals(msfixit_customer_totp_code($secret, $counter + $offset), $candidate)) {
            return true;
        }
    }
    return false;
}

function msfixit_customer_totp_enabled(int $userId): bool
{
    return get_user_meta($userId, '_msfixit_totp_enabled', true) === 'yes'
        && msfixit_customer_auth_decrypt((string) get_user_meta($userId, '_msfixit_totp_secret_encrypted', true)) !== '';
}

function msfixit_customer_auth_fingerprint(int $userId): string
{
    $address = (string) ($_SERVER['REMOTE_ADDR'] ?? 'unknown');
    return hash_hmac('sha256', $userId . '|' . $address, wp_salt('nonce'));
}

function msfixit_customer_auth_rate_limited(int $userId): bool
{
    $key = 'msfixit_totp_attempt_' . msfixit_customer_auth_fingerprint($userId);
    $count = (int) get_transient($key);
    if ($count >= 10) {
        return true;
    }
    set_transient($key, $count + 1, 10 * MINUTE_IN_SECONDS);
    return false;
}

function msfixit_customer_use_recovery_code(int $userId, string $candidate): bool
{
    $candidate = strtoupper(preg_replace('/[^A-Z0-9]/', '', $candidate) ?? '');
    if (strlen($candidate) < 10) {
        return false;
    }
    $hashes = get_user_meta($userId, '_msfixit_recovery_hashes', true);
    if (!is_array($hashes)) {
        return false;
    }
    foreach ($hashes as $index => $hash) {
        if (is_string($hash) && wp_check_password($candidate, $hash)) {
            unset($hashes[$index]);
            update_user_meta($userId, '_msfixit_recovery_hashes', array_values($hashes));
            msfixit_customer_auth_audit($userId, 'recovery_code_used', 'recovery');
            return true;
        }
    }
    return false;
}

function msfixit_customer_verify_second_factor(int $userId, string $candidate): bool
{
    if (msfixit_customer_auth_rate_limited($userId)) {
        return false;
    }
    $secret = msfixit_customer_auth_decrypt(
        (string) get_user_meta($userId, '_msfixit_totp_secret_encrypted', true)
    );
    if ($secret !== '' && msfixit_customer_totp_verify($secret, $candidate)) {
        msfixit_customer_auth_audit($userId, 'second_factor_verified', 'totp');
        return true;
    }
    return msfixit_customer_use_recovery_code($userId, $candidate);
}

function msfixit_customer_require_totp($user, string $password)
{
    if (!$user instanceof WP_User || !msfixit_customer_totp_enabled((int) $user->ID)) {
        return $user;
    }
    $candidate = sanitize_text_field(wp_unslash((string) ($_POST['msfixit_2fa_code'] ?? '')));
    if ($candidate === '') {
        return new WP_Error('msfixit_2fa_required', '<strong>Zusätzliche Bestätigung erforderlich:</strong> Bitte gib den Code deiner Authenticator-App oder einen Wiederherstellungscode ein.');
    }
    if (!msfixit_customer_verify_second_factor((int) $user->ID, $candidate)) {
        return new WP_Error('msfixit_2fa_invalid', '<strong>Bestätigung fehlgeschlagen:</strong> Der Code ist ungültig oder es gab zu viele Versuche.');
    }
    return $user;
}
add_filter('wp_authenticate_user', 'msfixit_customer_require_totp', 50, 2);

function msfixit_customer_render_totp_login_field(): void
{
    echo '<p class="form-row form-row-wide msfixit-2fa-login">';
    echo '<label for="msfixit_2fa_code">2-Faktor-Code <span class="optional">(nur wenn aktiviert)</span></label>';
    echo '<input type="text" class="input-text" name="msfixit_2fa_code" id="msfixit_2fa_code" inputmode="numeric" autocomplete="one-time-code" maxlength="24">';
    echo '</p>';
}
add_action('woocommerce_login_form', 'msfixit_customer_render_totp_login_field', 20);
add_action('login_form', 'msfixit_customer_render_totp_login_field', 20);

function msfixit_customer_generate_recovery_codes(): array
{
    $codes = [];
    for ($index = 0; $index < 10; $index++) {
        $raw = strtoupper(substr(msfixit_customer_auth_b64url(random_bytes(10)), 0, 12));
        $codes[] = substr($raw, 0, 4) . '-' . substr($raw, 4, 4) . '-' . substr($raw, 8, 4);
    }
    return $codes;
}

function msfixit_customer_store_recovery_codes(int $userId, array $codes): void
{
    $hashes = [];
    foreach ($codes as $code) {
        $normalized = strtoupper(preg_replace('/[^A-Z0-9]/', '', (string) $code) ?? '');
        $hashes[] = wp_hash_password($normalized);
    }
    update_user_meta($userId, '_msfixit_recovery_hashes', $hashes);
    set_transient('msfixit_recovery_display_' . $userId, $codes, 10 * MINUTE_IN_SECONDS);
}

function msfixit_customer_security_action(): void
{
    if (!is_user_logged_in()) {
        auth_redirect();
    }
    $userId = get_current_user_id();
    $operation = sanitize_key((string) ($_POST['operation'] ?? ''));
    check_admin_referer('msfixit_customer_security_' . $operation);

    if ($operation === 'totp_begin') {
        $secret = msfixit_customer_totp_secret();
        set_transient('msfixit_totp_pending_' . $userId, msfixit_customer_auth_encrypt($secret), 15 * MINUTE_IN_SECONDS);
        wp_safe_redirect(msfixit_customer_security_url(['auth_notice' => 'totp_pending']));
        exit;
    }

    if ($operation === 'totp_confirm') {
        $encoded = (string) get_transient('msfixit_totp_pending_' . $userId);
        $secret = msfixit_customer_auth_decrypt($encoded);
        $code = sanitize_text_field(wp_unslash((string) ($_POST['totp_code'] ?? '')));
        if ($secret === '' || !msfixit_customer_totp_verify($secret, $code)) {
            wp_safe_redirect(msfixit_customer_security_url(['auth_notice' => 'totp_invalid']));
            exit;
        }
        delete_transient('msfixit_totp_pending_' . $userId);
        update_user_meta($userId, '_msfixit_totp_secret_encrypted', msfixit_customer_auth_encrypt($secret));
        update_user_meta($userId, '_msfixit_totp_enabled', 'yes');
        msfixit_customer_store_recovery_codes($userId, msfixit_customer_generate_recovery_codes());
        msfixit_customer_auth_audit($userId, 'totp_enabled', 'totp');
        wp_safe_redirect(msfixit_customer_security_url(['auth_notice' => 'totp_enabled']));
        exit;
    }

    if (in_array($operation, ['totp_disable', 'recovery_regenerate'], true)) {
        $user = wp_get_current_user();
        $password = (string) ($_POST['current_password'] ?? '');
        $code = sanitize_text_field(wp_unslash((string) ($_POST['totp_code'] ?? '')));
        if (!wp_check_password($password, $user->user_pass, $userId)
            || !msfixit_customer_verify_second_factor($userId, $code)) {
            wp_safe_redirect(msfixit_customer_security_url(['auth_notice' => 'verification_failed']));
            exit;
        }
        if ($operation === 'totp_disable') {
            delete_user_meta($userId, '_msfixit_totp_secret_encrypted');
            delete_user_meta($userId, '_msfixit_totp_enabled');
            delete_user_meta($userId, '_msfixit_recovery_hashes');
            msfixit_customer_auth_audit($userId, 'totp_disabled', 'password');
            wp_safe_redirect(msfixit_customer_security_url(['auth_notice' => 'totp_disabled']));
            exit;
        }
        msfixit_customer_store_recovery_codes($userId, msfixit_customer_generate_recovery_codes());
        msfixit_customer_auth_audit($userId, 'recovery_regenerated', 'totp');
        wp_safe_redirect(msfixit_customer_security_url(['auth_notice' => 'recovery_ready']));
        exit;
    }

    if ($operation === 'google_disconnect') {
        delete_user_meta($userId, '_msfixit_google_sub');
        delete_user_meta($userId, '_msfixit_google_email');
        msfixit_customer_auth_audit($userId, 'google_disconnected', 'session');
        wp_safe_redirect(msfixit_customer_security_url(['auth_notice' => 'google_disconnected']));
        exit;
    }

    if ($operation === 'sessions_close') {
        $token = wp_get_session_token();
        $manager = WP_Session_Tokens::get_instance($userId);
        $manager->destroy_others($token);
        msfixit_customer_auth_audit($userId, 'other_sessions_closed', 'session');
        wp_safe_redirect(msfixit_customer_security_url(['auth_notice' => 'sessions_closed']));
        exit;
    }

    wp_safe_redirect(msfixit_customer_security_url());
    exit;
}
add_action('admin_post_msfixit_customer_security', 'msfixit_customer_security_action');

function msfixit_customer_auth_notice_text(string $notice): string
{
    $messages = [
        'google_connected' => 'Google wurde erfolgreich mit deinem Kundenkonto verbunden.',
        'google_disconnected' => 'Die Google-Verknüpfung wurde entfernt.',
        'totp_pending' => 'Scanne oder übertrage den angezeigten Schlüssel und bestätige anschließend den ersten Code.',
        'totp_invalid' => 'Der Bestätigungscode war ungültig oder die Einrichtung ist abgelaufen.',
        'totp_enabled' => 'Die 2-Faktor-Authentifizierung ist aktiv. Speichere jetzt die Wiederherstellungscodes.',
        'totp_disabled' => 'Die 2-Faktor-Authentifizierung wurde deaktiviert.',
        'verification_failed' => 'Passwort oder 2-Faktor-Code war ungültig.',
        'recovery_ready' => 'Neue Wiederherstellungscodes wurden erzeugt. Die alten Codes sind nicht mehr gültig.',
        'sessions_closed' => 'Alle anderen angemeldeten Sitzungen wurden beendet.',
    ];
    return $messages[$notice] ?? '';
}

function msfixit_customer_security_endpoint(): void
{
    if (!is_user_logged_in()) {
        echo '<p>Bitte melde dich an.</p>';
        return;
    }

    $userId = get_current_user_id();
    $user = wp_get_current_user();
    $notice = sanitize_key((string) ($_GET['auth_notice'] ?? ''));
    $message = msfixit_customer_auth_notice_text($notice);
    if ($message !== '') {
        echo '<div class="woocommerce-message" role="status">' . esc_html($message) . '</div>';
    }

    echo '<div class="msfixit-security-grid">';
    echo '<section class="msfixit-security-card"><h2>Google-Anmeldung</h2>';
    $googleEmail = sanitize_email((string) get_user_meta($userId, '_msfixit_google_email', true));
    if ($googleEmail !== '') {
        echo '<p><strong>Verbunden:</strong> ' . esc_html($googleEmail) . '</p>';
        echo '<p>Du kannst dich ohne Shop-Passwort über dein Google-Konto anmelden.</p>';
        echo '<form method="post" action="' . esc_url(admin_url('admin-post.php')) . '">';
        wp_nonce_field('msfixit_customer_security_google_disconnect');
        echo '<input type="hidden" name="action" value="msfixit_customer_security">';
        echo '<input type="hidden" name="operation" value="google_disconnect">';
        echo '<button class="button" type="submit">Google-Verknüpfung entfernen</button></form>';
    } elseif (msfixit_customer_google_ready()) {
        echo '<p>Verbinde dein Kundenkonto mit Google für eine schnelle, passwortlose Anmeldung.</p>';
        echo '<a class="button" href="' . esc_url(msfixit_customer_google_start_url('connect', msfixit_customer_security_url())) . '">Google verbinden</a>';
    } else {
        echo '<p>Die Google-Anmeldung ist derzeit nicht verfügbar.</p>';
    }
    echo '</section>';

    echo '<section class="msfixit-security-card"><h2>Authenticator-App</h2>';
    if (!msfixit_customer_totp_enabled($userId)) {
        $pending = msfixit_customer_auth_decrypt((string) get_transient('msfixit_totp_pending_' . $userId));
        if ($pending === '') {
            echo '<p>Schütze die Passwort-Anmeldung zusätzlich mit einem sechsstelligen Einmalcode.</p>';
            echo '<form method="post" action="' . esc_url(admin_url('admin-post.php')) . '">';
            wp_nonce_field('msfixit_customer_security_totp_begin');
            echo '<input type="hidden" name="action" value="msfixit_customer_security">';
            echo '<input type="hidden" name="operation" value="totp_begin">';
            echo '<button class="button" type="submit">2-Faktor-Authentifizierung einrichten</button></form>';
        } else {
            $issuer = rawurlencode('Ms. FixIT');
            $label = rawurlencode('Ms. FixIT:' . $user->user_email);
            $uri = 'otpauth://totp/' . $label . '?secret=' . rawurlencode($pending) . '&issuer=' . $issuer . '&algorithm=SHA1&digits=6&period=30';
            echo '<p>Füge in deiner Authenticator-App ein zeitbasiertes Konto hinzu.</p>';
            echo '<dl class="msfixit-auth-details"><dt>Kontoname</dt><dd>' . esc_html($user->user_email) . '</dd>';
            echo '<dt>Schlüssel</dt><dd><code>' . esc_html($pending) . '</code></dd>';
            echo '<dt>Einrichtungsadresse</dt><dd><code class="msfixit-wrap">' . esc_html($uri) . '</code></dd></dl>';
            echo '<form method="post" action="' . esc_url(admin_url('admin-post.php')) . '">';
            wp_nonce_field('msfixit_customer_security_totp_confirm');
            echo '<input type="hidden" name="action" value="msfixit_customer_security">';
            echo '<input type="hidden" name="operation" value="totp_confirm">';
            echo '<p><label>Aktueller sechsstelliger Code<br><input name="totp_code" inputmode="numeric" autocomplete="one-time-code" maxlength="6" required></label></p>';
            echo '<button class="button" type="submit">Einrichtung bestätigen</button></form>';
        }
    } else {
        $hashes = get_user_meta($userId, '_msfixit_recovery_hashes', true);
        $remaining = is_array($hashes) ? count($hashes) : 0;
        echo '<p><strong>Aktiv.</strong> Verbleibende Wiederherstellungscodes: ' . esc_html((string) $remaining) . '</p>';
        echo '<details><summary>Neue Wiederherstellungscodes erstellen</summary>';
        msfixit_customer_security_verification_form('recovery_regenerate', 'Neue Codes erstellen');
        echo '</details><details><summary>2-Faktor-Authentifizierung deaktivieren</summary>';
        msfixit_customer_security_verification_form('totp_disable', '2-Faktor deaktivieren');
        echo '</details>';
    }
    echo '</section>';

    $codes = get_transient('msfixit_recovery_display_' . $userId);
    if (is_array($codes) && $codes !== []) {
        delete_transient('msfixit_recovery_display_' . $userId);
        echo '<section class="msfixit-security-card msfixit-recovery-card"><h2>Wiederherstellungscodes</h2>';
        echo '<p>Jeder Code funktioniert nur einmal. Speichere sie offline. Sie werden nach dem Neuladen nicht erneut angezeigt.</p><pre>';
        foreach ($codes as $code) {
            echo esc_html((string) $code) . "\n";
        }
        echo '</pre></section>';
    }

    echo '<section class="msfixit-security-card"><h2>Angemeldete Sitzungen</h2>';
    echo '<p>Beende alle anderen Browser- und Gerätesitzungen, falls dir etwas verdächtig vorkommt.</p>';
    echo '<form method="post" action="' . esc_url(admin_url('admin-post.php')) . '">';
    wp_nonce_field('msfixit_customer_security_sessions_close');
    echo '<input type="hidden" name="action" value="msfixit_customer_security">';
    echo '<input type="hidden" name="operation" value="sessions_close">';
    echo '<button class="button" type="submit">Andere Sitzungen beenden</button></form></section>';

    echo '<section class="msfixit-security-card"><h2>Letzte Sicherheitsereignisse</h2>';
    $history = get_user_meta($userId, '_msfixit_auth_audit', true);
    if (!is_array($history) || $history === []) {
        echo '<p>Noch keine Ereignisse gespeichert.</p>';
    } else {
        echo '<ul class="msfixit-auth-history">';
        foreach (array_slice($history, 0, 10) as $entry) {
            if (!is_array($entry)) {
                continue;
            }
            $time = sanitize_text_field((string) ($entry['time'] ?? ''));
            $event = sanitize_key((string) ($entry['event'] ?? 'event'));
            $method = sanitize_key((string) ($entry['method'] ?? ''));
            echo '<li><time>' . esc_html($time) . ' UTC</time><span>' . esc_html($event) . '</span><small>' . esc_html($method) . '</small></li>';
        }
        echo '</ul>';
    }
    echo '</section></div>';
}

function msfixit_customer_security_verification_form(string $operation, string $label): void
{
    echo '<form class="msfixit-security-verify" method="post" action="' . esc_url(admin_url('admin-post.php')) . '">';
    wp_nonce_field('msfixit_customer_security_' . $operation);
    echo '<input type="hidden" name="action" value="msfixit_customer_security">';
    echo '<input type="hidden" name="operation" value="' . esc_attr($operation) . '">';
    echo '<p><label>Aktuelles Passwort<br><input type="password" name="current_password" autocomplete="current-password" required></label></p>';
    echo '<p><label>Authenticator- oder Wiederherstellungscode<br><input name="totp_code" autocomplete="one-time-code" maxlength="24" required></label></p>';
    echo '<button class="button" type="submit">' . esc_html($label) . '</button></form>';
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

function msfixit_customer_auth_assets(): void
{
    if (!function_exists('is_account_page') || !is_account_page()) {
        return;
    }
    wp_enqueue_style(
        'msfixit-customer-auth',
        content_url('mu-plugins/assets/msfixit-customer-auth.css'),
        [],
        MSFIXIT_CUSTOMER_AUTH_VERSION
    );
}
add_action('wp_enqueue_scripts', 'msfixit_customer_auth_assets');

function msfixit_customer_auth_settings_page(): void
{
    if (!current_user_can('manage_options')) {
        return;
    }
    $saved = isset($_GET['settings-updated']);
    echo '<div class="wrap"><h1>Kundenanmeldung und Sicherheit</h1>';
    if ($saved) {
        echo '<div class="notice notice-success"><p>Einstellungen gespeichert.</p></div>';
    }
    echo '<p>Verwende für Kunden einen eigenen externen Google-OAuth-Webclient. Der interne Workspace-Mailclient darf nicht wiederverwendet werden.</p>';
    echo '<form method="post" action="' . esc_url(admin_url('admin-post.php')) . '">';
    wp_nonce_field('msfixit_customer_auth_settings');
    echo '<input type="hidden" name="action" value="msfixit_customer_auth_settings">';
    echo '<table class="form-table"><tr><th>Google-Anmeldung</th><td><label><input type="checkbox" name="enabled" value="yes" ' . checked(msfixit_customer_auth_enabled(), true, false) . '> für Kunden anzeigen</label></td></tr>';
    echo '<tr><th>Neue Konten</th><td><label><input type="checkbox" name="registration_enabled" value="yes" ' . checked(msfixit_customer_auth_registration_enabled(), true, false) . '> bei einer neuen bestätigten Google-Adresse automatisch als Kunde anlegen</label></td></tr>';
    echo '<tr><th><label for="google_client_id">Google Client-ID</label></th><td><input class="regular-text" id="google_client_id" name="google_client_id" value="' . esc_attr(msfixit_customer_google_client_id()) . '" autocomplete="off"></td></tr>';
    echo '<tr><th><label for="google_client_secret">Google Client-Secret</label></th><td><input class="regular-text" type="password" id="google_client_secret" name="google_client_secret" value="" autocomplete="new-password"><p class="description">Leer lassen, um das gespeicherte verschlüsselte Secret beizubehalten.</p></td></tr>';
    echo '<tr><th>Autorisierte Weiterleitungs-URI</th><td><code>' . esc_html(msfixit_customer_google_redirect_uri()) . '</code></td></tr>';
    echo '<tr><th>OAuth-Berechtigungen</th><td><code>' . esc_html(MSFIXIT_CUSTOMER_GOOGLE_SCOPE) . '</code><p class="description">Kein Gmail-, Drive-, Kalender- oder Kontaktzugriff.</p></td></tr></table>';
    submit_button('Einstellungen speichern');
    echo '</form></div>';
}

add_action('admin_menu', static function (): void {
    add_options_page(
        'Kundenanmeldung und Sicherheit',
        'Kundenanmeldung',
        'manage_options',
        'msfixit-customer-auth',
        'msfixit_customer_auth_settings_page'
    );
});

function msfixit_customer_auth_save_settings(): void
{
    if (!current_user_can('manage_options')) {
        wp_die('Not allowed.');
    }
    check_admin_referer('msfixit_customer_auth_settings');
    update_option('msfixit_customer_auth_enabled', isset($_POST['enabled']) ? 'yes' : 'no', false);
    update_option('msfixit_customer_auth_registration_enabled', isset($_POST['registration_enabled']) ? 'yes' : 'no', false);
    update_option(
        'msfixit_customer_google_client_id',
        sanitize_text_field(wp_unslash((string) ($_POST['google_client_id'] ?? ''))),
        false
    );
    $secret = trim(wp_unslash((string) ($_POST['google_client_secret'] ?? '')));
    if ($secret !== '') {
        update_option(
            'msfixit_customer_google_client_secret_encrypted',
            msfixit_customer_auth_encrypt($secret),
            false
        );
    }
    wp_safe_redirect(add_query_arg([
        'page' => 'msfixit-customer-auth',
        'settings-updated' => '1',
    ], admin_url('options-general.php')));
    exit;
}
add_action('admin_post_msfixit_customer_auth_settings', 'msfixit_customer_auth_save_settings');

add_filter('site_status_tests', static function (array $tests): array {
    $tests['direct']['msfixit_customer_auth'] = [
        'label' => 'Ms. FixIT Kundenanmeldung',
        'test' => static function (): array {
            if (!msfixit_customer_auth_enabled()) {
                return [
                    'label' => 'Kundenanmeldung ist noch nicht öffentlich aktiviert',
                    'status' => 'recommended',
                    'badge' => ['label' => 'ShopOS', 'color' => 'blue'],
                    'description' => '<p>Google-Anmeldung bleibt ausgeblendet. Passwortkonten und lokale 2FA funktionieren weiterhin.</p>',
                    'actions' => '',
                    'test' => 'msfixit_customer_auth',
                ];
            }
            $ready = msfixit_customer_google_ready();
            return [
                'label' => $ready ? 'Google-Kundenanmeldung ist konfiguriert' : 'Google-Kundenanmeldung ist unvollständig',
                'status' => $ready ? 'good' : 'critical',
                'badge' => ['label' => 'ShopOS', 'color' => 'blue'],
                'description' => '<p>' . ($ready
                    ? 'Client-ID und verschlüsseltes Client-Secret sind vorhanden.'
                    : 'Aktivierte Google-Anmeldung benötigt Client-ID und Client-Secret.') . '</p>',
                'actions' => '',
                'test' => 'msfixit_customer_auth',
            ];
        },
    ];
    return $tests;
});
