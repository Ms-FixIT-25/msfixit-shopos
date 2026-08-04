<?php

declare(strict_types=1);

if (!defined('ABSPATH')) {
    exit;
}

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
        $cipher = openssl_encrypt($plaintext, 'aes-256-gcm', $key, OPENSSL_RAW_DATA, $iv, $tag);
        if (is_string($cipher) && $tag !== '') {
            return 'o1:' . base64_encode($iv . $tag . $cipher);
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
        $plain = sodium_crypto_secretbox_open(substr($payload, SODIUM_CRYPTO_SECRETBOX_NONCEBYTES), $nonce, $key);
        return is_string($plain) ? $plain : '';
    }
    if (str_starts_with($encoded, 'o1:') && function_exists('openssl_decrypt')) {
        $payload = base64_decode(substr($encoded, 3), true);
        if (!is_string($payload) || strlen($payload) <= 28) {
            return '';
        }
        $plain = openssl_decrypt(substr($payload, 28), 'aes-256-gcm', $key, OPENSSL_RAW_DATA, substr($payload, 0, 12), substr($payload, 12, 16));
        return is_string($plain) ? $plain : '';
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
    return msfixit_customer_auth_decrypt((string) get_option('msfixit_customer_google_client_secret_encrypted', ''));
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
    return function_exists('wc_get_page_permalink') ? wc_get_page_permalink('myaccount') : wp_login_url();
}

function msfixit_customer_security_url(array $args = []): string
{
    $base = function_exists('wc_get_account_endpoint_url')
        ? wc_get_account_endpoint_url(MSFIXIT_CUSTOMER_AUTH_ENDPOINT)
        : admin_url('profile.php');
    return $args === [] ? $base : add_query_arg($args, $base);
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
}

function msfixit_customer_google_start_url(string $mode = 'signin', string $redirect = ''): string
{
    $url = add_query_arg([
        'action' => 'msfixit_customer_google_start',
        'mode' => $mode === 'connect' ? 'connect' : 'signin',
        'redirect_to' => $redirect !== '' ? $redirect : msfixit_customer_account_url(),
    ], admin_url('admin-post.php'));
    return wp_nonce_url($url, 'msfixit_customer_google_start');
}

function msfixit_customer_auth_safe_redirect(string $url): string
{
    return wp_validate_redirect($url, msfixit_customer_account_url());
}

function msfixit_customer_google_error_redirect(string $code, string $redirect = ''): void
{
    $target = $redirect !== '' ? msfixit_customer_auth_safe_redirect($redirect) : msfixit_customer_account_url();
    wp_safe_redirect(add_query_arg('msfixit_auth_error', sanitize_key($code), $target));
    exit;
}

function msfixit_customer_google_start(): void
{
    check_admin_referer('msfixit_customer_google_start');
    if (!msfixit_customer_google_ready()) {
        msfixit_customer_google_error_redirect('google_unavailable');
    }
    $mode = sanitize_key((string) ($_GET['mode'] ?? 'signin')) === 'connect' ? 'connect' : 'signin';
    if ($mode === 'connect' && !is_user_logged_in()) {
        auth_redirect();
    }
    $redirect = msfixit_customer_auth_safe_redirect(wp_unslash((string) ($_GET['redirect_to'] ?? msfixit_customer_account_url())));
    $state = msfixit_customer_auth_b64url(random_bytes(32));
    $verifier = msfixit_customer_auth_b64url(random_bytes(64));
    $challenge = msfixit_customer_auth_b64url(hash('sha256', $verifier, true));
    set_transient(msfixit_customer_auth_state_key($state), [
        'mode' => $mode,
        'verifier' => $verifier,
        'redirect' => $redirect,
        'user_id' => get_current_user_id(),
    ], 10 * MINUTE_IN_SECONDS);
    wp_redirect(add_query_arg([
        'client_id' => msfixit_customer_google_client_id(),
        'redirect_uri' => msfixit_customer_google_redirect_uri(),
        'response_type' => 'code',
        'scope' => MSFIXIT_CUSTOMER_GOOGLE_SCOPE,
        'state' => $state,
        'nonce' => msfixit_customer_auth_b64url(random_bytes(32)),
        'code_challenge' => $challenge,
        'code_challenge_method' => 'S256',
        'prompt' => 'select_account',
    ], MSFIXIT_CUSTOMER_GOOGLE_AUTH_ENDPOINT));
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
    $payload = json_decode((string) wp_remote_retrieve_body($response), true);
    if ((int) wp_remote_retrieve_response_code($response) !== 200 || !is_array($payload) || empty($payload['access_token'])) {
        return new WP_Error('google_token_failed', 'Google token exchange failed.');
    }
    return $payload;
}

function msfixit_customer_google_userinfo(string $token)
{
    $response = wp_remote_get(MSFIXIT_CUSTOMER_GOOGLE_USERINFO_ENDPOINT, [
        'timeout' => 20,
        'redirection' => 0,
        'headers' => ['Accept' => 'application/json', 'Authorization' => 'Bearer ' . $token],
    ]);
    if (is_wp_error($response)) {
        return $response;
    }
    $payload = json_decode((string) wp_remote_retrieve_body($response), true);
    if ((int) wp_remote_retrieve_response_code($response) !== 200 || !is_array($payload)) {
        return new WP_Error('google_userinfo_failed', 'Google identity request failed.');
    }
    return $payload;
}

function msfixit_customer_user_by_google_sub(string $sub): int
{
    $ids = get_users(['meta_key' => '_msfixit_google_sub', 'meta_value' => $sub, 'number' => 2, 'fields' => 'ids']);
    return count($ids) === 1 ? (int) $ids[0] : 0;
}

function msfixit_customer_unique_login(string $email): string
{
    $base = sanitize_user((string) strstr($email, '@', true), true) ?: 'kunde';
    $login = $base;
    for ($number = 2; username_exists($login); $number++) {
        $login = $base . $number;
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
        return new WP_Error('invalid_email', 'Invalid Google email.');
    }
    return wp_insert_user([
        'user_login' => msfixit_customer_unique_login($email),
        'user_email' => $email,
        'user_pass' => wp_generate_password(40, true, true),
        'display_name' => sanitize_text_field((string) ($profile['name'] ?? $email)),
        'first_name' => sanitize_text_field((string) ($profile['given_name'] ?? '')),
        'last_name' => sanitize_text_field((string) ($profile['family_name'] ?? '')),
        'role' => 'customer',
    ]);
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
    $redirect = msfixit_customer_auth_safe_redirect((string) $flow['redirect']);
    if (!empty($_GET['error'])) {
        msfixit_customer_google_error_redirect('cancelled', $redirect);
    }
    $code = sanitize_text_field(wp_unslash((string) ($_GET['code'] ?? '')));
    $tokens = $code !== '' ? msfixit_customer_google_exchange($code, (string) $flow['verifier']) : new WP_Error('code');
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
    if (!$user instanceof WP_User || array_intersect($user->roles, ['administrator', 'shop_manager'])) {
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
    return [
        'google_unavailable' => 'Die Google-Anmeldung ist derzeit nicht eingerichtet.',
        'cancelled' => 'Die Google-Anmeldung wurde abgebrochen.',
        'state' => 'Die Anmeldung ist abgelaufen. Bitte starte sie erneut.',
        'exchange' => 'Die Google-Anmeldung konnte nicht abgeschlossen werden.',
        'identity' => 'Die Google-Identität konnte nicht geprüft werden.',
        'unverified' => 'Google hat keine bestätigte E-Mail-Adresse geliefert.',
        'session' => 'Die Sitzung hat sich während der Verknüpfung geändert.',
        'already_linked' => 'Dieses Google-Konto ist bereits anderweitig verbunden.',
        'link_required' => 'Für diese E-Mail-Adresse besteht bereits ein Konto. Melde dich zuerst mit deinem Passwort an und verbinde Google anschließend unter Sicherheit.',
        'registration' => 'Das Kundenkonto konnte nicht angelegt werden.',
        'customer_only' => 'Google-Anmeldung ist hier nur für Kundenkonten freigegeben.',
    ][$code] ?? 'Die Anmeldung konnte nicht abgeschlossen werden.';
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
    echo '<div class="msfixit-social-login"><a class="button msfixit-google-button" href="'
        . esc_url(msfixit_customer_google_start_url('signin', msfixit_customer_account_url()))
        . '"><span aria-hidden="true" class="msfixit-google-g">G</span> Mit Google anmelden</a>'
        . '<p class="msfixit-auth-hint">Google übermittelt nur die bestätigte Identität, E-Mail-Adresse und den Namen.</p></div>';
}
add_action('woocommerce_login_form_start', 'msfixit_customer_render_google_button', 5);
add_action('woocommerce_register_form_start', 'msfixit_customer_render_google_button', 5);
