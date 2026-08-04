<?php

declare(strict_types=1);

if (!defined('ABSPATH')) {
    exit;
}

function msfixit_customer_base32_encode(string $binary): string
{
    $alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    $bits = '';
    foreach (str_split($binary) as $byte) {
        $bits .= str_pad(decbin(ord($byte)), 8, '0', STR_PAD_LEFT);
    }
    $output = '';
    foreach (str_split($bits, 5) as $chunk) {
        $output .= $alphabet[bindec(str_pad($chunk, 5, '0', STR_PAD_RIGHT))];
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
    $hash = hash_hmac('sha1', pack('N2', intdiv($counter, 4294967296), $counter % 4294967296), $key, true);
    $offset = ord($hash[19]) & 0x0f;
    $value = unpack('N', substr($hash, $offset, 4));
    return str_pad((string) ((($value[1] ?? 0) & 0x7fffffff) % 1000000), 6, '0', STR_PAD_LEFT);
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

function msfixit_customer_auth_rate_limited(int $userId): bool
{
    $fingerprint = hash_hmac('sha256', $userId . '|' . (string) ($_SERVER['REMOTE_ADDR'] ?? 'unknown'), wp_salt('nonce'));
    $key = 'msfixit_totp_attempt_' . $fingerprint;
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
    $hashes = get_user_meta($userId, '_msfixit_recovery_hashes', true);
    if (strlen($candidate) < 10 || !is_array($hashes)) {
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
    $secret = msfixit_customer_auth_decrypt((string) get_user_meta($userId, '_msfixit_totp_secret_encrypted', true));
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
    return msfixit_customer_verify_second_factor((int) $user->ID, $candidate)
        ? $user
        : new WP_Error('msfixit_2fa_invalid', '<strong>Bestätigung fehlgeschlagen:</strong> Der Code ist ungültig oder es gab zu viele Versuche.');
}
add_filter('wp_authenticate_user', 'msfixit_customer_require_totp', 50, 2);

function msfixit_customer_render_totp_login_field(): void
{
    echo '<p class="form-row form-row-wide msfixit-2fa-login"><label for="msfixit_2fa_code">2-Faktor-Code <span class="optional">(nur wenn aktiviert)</span></label>'
        . '<input type="text" class="input-text" name="msfixit_2fa_code" id="msfixit_2fa_code" inputmode="numeric" autocomplete="one-time-code" maxlength="24"></p>';
}
add_action('woocommerce_login_form', 'msfixit_customer_render_totp_login_field', 20);

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
        $hashes[] = wp_hash_password(strtoupper(preg_replace('/[^A-Z0-9]/', '', (string) $code) ?? ''));
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
        set_transient('msfixit_totp_pending_' . $userId, msfixit_customer_auth_encrypt(msfixit_customer_totp_secret()), 15 * MINUTE_IN_SECONDS);
        wp_safe_redirect(msfixit_customer_security_url(['auth_notice' => 'totp_pending']));
        exit;
    }
    if ($operation === 'totp_confirm') {
        $secret = msfixit_customer_auth_decrypt((string) get_transient('msfixit_totp_pending_' . $userId));
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
        if (!wp_check_password($password, $user->user_pass, $userId) || !msfixit_customer_verify_second_factor($userId, $code)) {
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
        WP_Session_Tokens::get_instance($userId)->destroy_others(wp_get_session_token());
        msfixit_customer_auth_audit($userId, 'other_sessions_closed', 'session');
        wp_safe_redirect(msfixit_customer_security_url(['auth_notice' => 'sessions_closed']));
        exit;
    }
    wp_safe_redirect(msfixit_customer_security_url());
    exit;
}
add_action('admin_post_msfixit_customer_security', 'msfixit_customer_security_action');
