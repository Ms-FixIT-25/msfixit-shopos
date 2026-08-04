<?php

declare(strict_types=1);

if (!defined('ABSPATH')) {
    exit;
}

const MSFIXIT_CUSTOMER_GOOGLE_FLOW_COOKIE = 'msfixit_google_flow';

function msfixit_customer_google_flow_hash(string $token): string
{
    return hash_hmac('sha256', $token, msfixit_customer_auth_key());
}

function msfixit_customer_google_flow_cookie(string $value, int $expires): void
{
    setcookie(MSFIXIT_CUSTOMER_GOOGLE_FLOW_COOKIE, $value, [
        'expires' => $expires,
        'path' => COOKIEPATH !== '' ? COOKIEPATH : '/',
        'domain' => COOKIE_DOMAIN,
        'secure' => is_ssl(),
        'httponly' => true,
        'samesite' => 'Lax',
    ]);
}

function msfixit_customer_google_start_bound(): void
{
    check_admin_referer('msfixit_customer_google_start');
    if (!msfixit_customer_google_ready()) {
        msfixit_customer_google_error_redirect('google_unavailable');
    }

    $mode = sanitize_key((string) ($_GET['mode'] ?? 'signin')) === 'connect' ? 'connect' : 'signin';
    if ($mode === 'connect' && !is_user_logged_in()) {
        auth_redirect();
    }

    $redirect = msfixit_customer_auth_safe_redirect(
        wp_unslash((string) ($_GET['redirect_to'] ?? msfixit_customer_account_url()))
    );
    $state = msfixit_customer_auth_b64url(random_bytes(32));
    $verifier = msfixit_customer_auth_b64url(random_bytes(64));
    $challenge = msfixit_customer_auth_b64url(hash('sha256', $verifier, true));
    $browserToken = msfixit_customer_auth_b64url(random_bytes(32));

    set_transient(msfixit_customer_auth_state_key($state), [
        'mode' => $mode,
        'verifier' => $verifier,
        'redirect' => $redirect,
        'user_id' => get_current_user_id(),
        'browser_hash' => msfixit_customer_google_flow_hash($browserToken),
    ], 10 * MINUTE_IN_SECONDS);
    msfixit_customer_google_flow_cookie($browserToken, time() + 10 * MINUTE_IN_SECONDS);

    wp_redirect(add_query_arg([
        'client_id' => msfixit_customer_google_client_id(),
        'redirect_uri' => msfixit_customer_google_redirect_uri(),
        'response_type' => 'code',
        'scope' => MSFIXIT_CUSTOMER_GOOGLE_SCOPE,
        'state' => $state,
        'code_challenge' => $challenge,
        'code_challenge_method' => 'S256',
        'prompt' => 'select_account',
    ], MSFIXIT_CUSTOMER_GOOGLE_AUTH_ENDPOINT));
    exit;
}

function msfixit_customer_google_callback_bound(): void
{
    $state = sanitize_text_field(wp_unslash((string) ($_GET['state'] ?? '')));
    if ($state === '' || strlen($state) > 120) {
        msfixit_customer_google_error_redirect('state');
    }

    $key = msfixit_customer_auth_state_key($state);
    $flow = get_transient($key);
    delete_transient($key);
    $browserToken = sanitize_text_field(wp_unslash((string) ($_COOKIE[MSFIXIT_CUSTOMER_GOOGLE_FLOW_COOKIE] ?? '')));
    msfixit_customer_google_flow_cookie('', time() - HOUR_IN_SECONDS);

    if (!is_array($flow) || empty($flow['verifier']) || empty($flow['redirect']) || empty($flow['browser_hash'])) {
        msfixit_customer_google_error_redirect('state');
    }
    if ($browserToken === '' || !hash_equals((string) $flow['browser_hash'], msfixit_customer_google_flow_hash($browserToken))) {
        msfixit_customer_google_error_redirect('browser', (string) $flow['redirect']);
    }

    $redirect = msfixit_customer_auth_safe_redirect((string) $flow['redirect']);
    if (!empty($_GET['error'])) {
        msfixit_customer_google_error_redirect('cancelled', $redirect);
    }

    $code = sanitize_text_field(wp_unslash((string) ($_GET['code'] ?? '')));
    $tokens = $code !== ''
        ? msfixit_customer_google_exchange($code, (string) $flow['verifier'])
        : new WP_Error('code');
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
        update_user_meta($userId, '_msfixit_google_created', 'yes');
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

remove_action('admin_post_nopriv_msfixit_customer_google_start', 'msfixit_customer_google_start');
remove_action('admin_post_msfixit_customer_google_start', 'msfixit_customer_google_start');
remove_action('admin_post_nopriv_msfixit_customer_google_callback', 'msfixit_customer_google_callback');
remove_action('admin_post_msfixit_customer_google_callback', 'msfixit_customer_google_callback');
add_action('admin_post_nopriv_msfixit_customer_google_start', 'msfixit_customer_google_start_bound');
add_action('admin_post_msfixit_customer_google_start', 'msfixit_customer_google_start_bound');
add_action('admin_post_nopriv_msfixit_customer_google_callback', 'msfixit_customer_google_callback_bound');
add_action('admin_post_msfixit_customer_google_callback', 'msfixit_customer_google_callback_bound');

function msfixit_customer_mark_local_password(int $userId): void
{
    update_user_meta($userId, '_msfixit_local_password_ready', 'yes');
}
add_action('after_password_reset', static function (WP_User $user): void {
    msfixit_customer_mark_local_password((int) $user->ID);
});
add_action('woocommerce_save_account_details', static function (int $userId): void {
    if (trim((string) ($_POST['password_1'] ?? '')) !== '') {
        msfixit_customer_mark_local_password($userId);
    }
});

add_action('admin_post_msfixit_customer_security', static function (): void {
    if (!is_user_logged_in() || sanitize_key((string) ($_POST['operation'] ?? '')) !== 'google_disconnect') {
        return;
    }
    $userId = get_current_user_id();
    if (get_user_meta($userId, '_msfixit_google_created', true) === 'yes'
        && get_user_meta($userId, '_msfixit_local_password_ready', true) !== 'yes') {
        if (function_exists('wc_add_notice')) {
            wc_add_notice('Lege zuerst unter Kontodetails ein eigenes Passwort fest, bevor du die einzige Google-Anmeldung entfernst.', 'error');
        }
        wp_safe_redirect(msfixit_customer_security_url());
        exit;
    }
}, 1);
