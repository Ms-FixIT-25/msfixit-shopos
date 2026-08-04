<?php

declare(strict_types=1);

if (!defined('ABSPATH')) {
    exit;
}

const MSFIXIT_CUSTOMER_DELETE_TOKEN_TTL = DAY_IN_SECONDS;

function msfixit_customer_deletion_orders(int $userId, string $email): array
{
    $result = [
        'available' => function_exists('wc_get_orders'),
        'orders' => [],
        'outstanding' => [],
    ];
    if (!$result['available']) {
        return $result;
    }

    $orders = [];
    foreach ([
        ['customer_id' => $userId],
        ['billing_email' => $email],
    ] as $identity) {
        $found = wc_get_orders(array_merge([
            'limit' => -1,
            'return' => 'objects',
            'status' => array_keys(wc_get_order_statuses()),
        ], $identity));
        foreach (is_array($found) ? $found : [] as $order) {
            if ($order instanceof WC_Order) {
                $orders[$order->get_id()] = $order;
            }
        }
    }

    foreach ($orders as $order) {
        $result['orders'][] = (int) $order->get_id();
        $status = (string) $order->get_status();
        $remaining = max(0.0, (float) $order->get_total() - (float) $order->get_total_refunded());
        $paymentPending = $order->needs_payment() || in_array($status, ['pending', 'on-hold', 'failed'], true);
        if ($remaining > 0.009 && $paymentPending && !in_array($status, ['cancelled', 'refunded', 'trash'], true)) {
            $result['outstanding'][] = [
                'id' => (int) $order->get_id(),
                'number' => (string) $order->get_order_number(),
                'amount' => $remaining,
                'currency' => (string) $order->get_currency(),
                'status' => $status,
            ];
        }
    }

    return $result;
}

function msfixit_customer_deletion_office(string $email): array
{
    $result = [
        'available' => false,
        'documents' => 0,
        'outstanding' => [],
    ];
    if (!function_exists('msfixit_office_bridge_database')) {
        return $result;
    }

    $pdo = msfixit_office_bridge_database();
    if (!$pdo instanceof PDO) {
        return $result;
    }
    $result['available'] = true;

    try {
        $statement = $pdo->prepare(
            "SELECT d.document_number,
                    d.gross_total,
                    d.currency,
                    COALESCE(SUM(CASE WHEN p.payment_status = 'confirmed' THEN a.allocated_amount ELSE 0 END), 0) AS paid_total
               FROM office_documents d
          LEFT JOIN office_payment_allocations a ON a.document_id = d.id
          LEFT JOIN office_payments p ON p.id = a.payment_id
              WHERE d.document_type = 'invoice'
                AND d.document_number IS NOT NULL
                AND d.finalized_at IS NOT NULL
                AND LOWER(COALESCE(d.customer_email, '')) = LOWER(?)
           GROUP BY d.id, d.document_number, d.gross_total, d.currency
           ORDER BY d.issue_date DESC, d.created_at DESC"
        );
        $statement->execute([$email]);
        foreach ($statement->fetchAll() ?: [] as $row) {
            $result['documents']++;
            $gross = round((float) ($row['gross_total'] ?? 0), 4);
            $paid = round((float) ($row['paid_total'] ?? 0), 4);
            $remaining = max(0.0, round($gross - $paid, 4));
            if ($remaining > 0.009) {
                $result['outstanding'][] = [
                    'number' => (string) ($row['document_number'] ?? ''),
                    'amount' => $remaining,
                    'currency' => (string) ($row['currency'] ?? 'EUR'),
                ];
            }
        }
    } catch (Throwable $exception) {
        error_log('[Ms. FixIT Customer Deletion] Office balance check failed: ' . $exception->getMessage());
        $result['available'] = false;
        $result['documents'] = 0;
        $result['outstanding'] = [];
    }

    return $result;
}

function msfixit_customer_deletion_status(int $userId): array
{
    $user = get_user_by('id', $userId);
    if (!$user instanceof WP_User || get_user_meta($userId, '_msfixit_account_deleted', true) === 'yes') {
        return [
            'allowed' => false,
            'reasons' => ['Das Kundenkonto ist nicht verfügbar.'],
            'orders' => ['available' => false, 'orders' => [], 'outstanding' => []],
            'office' => ['available' => false, 'documents' => 0, 'outstanding' => []],
        ];
    }

    $email = sanitize_email((string) $user->user_email);
    $orders = msfixit_customer_deletion_orders($userId, $email);
    $office = msfixit_customer_deletion_office($email);
    $reasons = [];

    if (!$orders['available']) {
        $reasons[] = 'Die Bestellungen konnten derzeit nicht sicher geprüft werden.';
    }
    if (!$office['available']) {
        $reasons[] = 'Der Zahlungsstand konnte derzeit nicht sicher geprüft werden.';
    }
    foreach ($orders['outstanding'] as $order) {
        $reasons[] = sprintf(
            'Bestellung %s ist noch nicht vollständig bezahlt (%s %s).',
            (string) $order['number'],
            number_format((float) $order['amount'], 2, ',', '.'),
            (string) $order['currency']
        );
    }
    foreach ($office['outstanding'] as $document) {
        $reasons[] = sprintf(
            'Rechnung %s weist noch %s %s offen aus.',
            (string) $document['number'],
            number_format((float) $document['amount'], 2, ',', '.'),
            (string) $document['currency']
        );
    }

    return [
        'allowed' => $reasons === [],
        'reasons' => $reasons,
        'orders' => $orders,
        'office' => $office,
    ];
}

function msfixit_customer_deletion_url(int $userId, string $token): string
{
    return add_query_arg([
        'action' => 'msfixit_customer_delete_confirm',
        'user_id' => $userId,
        'token' => $token,
    ], admin_url('admin-post.php'));
}

function msfixit_customer_deletion_request(): void
{
    if (!is_user_logged_in()) {
        auth_redirect();
    }
    $userId = get_current_user_id();
    check_admin_referer('msfixit_customer_delete_request');

    $status = msfixit_customer_deletion_status($userId);
    if (!$status['allowed']) {
        wp_safe_redirect(msfixit_customer_security_url(['auth_notice' => 'delete_blocked']));
        exit;
    }

    $user = wp_get_current_user();
    $token = msfixit_customer_auth_b64url(random_bytes(32));
    update_user_meta($userId, '_msfixit_delete_token_hash', hash('sha256', $token));
    update_user_meta($userId, '_msfixit_delete_token_expires', time() + MSFIXIT_CUSTOMER_DELETE_TOKEN_TTL);

    $link = msfixit_customer_deletion_url($userId, $token);
    $subject = 'Löschung deines Ms. FixIT Kundenkontos bestätigen';
    $message = "Hallo,\n\nmit dem folgenden Link bestätigst du die Entfernung deines Ms. FixIT Kundenkontos:\n\n{$link}\n\nDer Link ist 24 Stunden gültig. Vor der Entfernung prüft ShopOS erneut, ob alle Zahlungen erledigt sind. Gesetzlich aufzubewahrende Rechnungs- und Buchungsbelege bleiben getrennt vom Kundenlogin erhalten.\n\nWenn du das nicht angefordert hast, ignoriere diese E-Mail.\n";

    if (!wp_mail((string) $user->user_email, $subject, $message)) {
        delete_user_meta($userId, '_msfixit_delete_token_hash');
        delete_user_meta($userId, '_msfixit_delete_token_expires');
        wp_safe_redirect(msfixit_customer_security_url(['auth_notice' => 'delete_mail_failed']));
        exit;
    }

    msfixit_customer_auth_audit($userId, 'account_deletion_requested', 'email');
    wp_safe_redirect(msfixit_customer_security_url(['auth_notice' => 'delete_mail_sent']));
    exit;
}
add_action('admin_post_msfixit_customer_delete_request', 'msfixit_customer_deletion_request');

function msfixit_customer_deletion_anonymize(int $userId): bool
{
    global $wpdb;

    $user = get_user_by('id', $userId);
    if (!$user instanceof WP_User) {
        return false;
    }

    $opaque = 'deleted-' . $userId . '-' . substr(hash_hmac('sha256', (string) $userId, wp_salt('auth')), 0, 12);
    WP_Session_Tokens::get_instance($userId)->destroy_all();

    foreach (array_keys(get_user_meta($userId)) as $key) {
        delete_user_meta($userId, (string) $key);
    }

    $updated = $wpdb->update(
        $wpdb->users,
        [
            'user_login' => $opaque,
            'user_pass' => wp_hash_password(wp_generate_password(64, true, true)),
            'user_nicename' => $opaque,
            'user_email' => $opaque . '@deleted.invalid',
            'user_url' => '',
            'user_activation_key' => '',
            'display_name' => 'Gelöschtes Kundenkonto',
        ],
        ['ID' => $userId],
        ['%s', '%s', '%s', '%s', '%s', '%s', '%s'],
        ['%d']
    );
    if ($updated === false) {
        return false;
    }

    update_user_meta($userId, '_msfixit_account_deleted', 'yes');
    update_user_meta($userId, '_msfixit_account_deleted_at', current_time('mysql', true));
    update_user_meta($userId, '_msfixit_retention_reference', $opaque);
    clean_user_cache($userId);
    return true;
}

function msfixit_customer_deletion_confirm(): void
{
    $userId = absint($_GET['user_id'] ?? 0);
    $token = sanitize_text_field(wp_unslash((string) ($_GET['token'] ?? '')));
    $user = get_user_by('id', $userId);
    if (!$user instanceof WP_User || $token === '') {
        wp_die('Der Löschlink ist ungültig.', 'Konto löschen', ['response' => 400]);
    }

    $expected = (string) get_user_meta($userId, '_msfixit_delete_token_hash', true);
    $expires = (int) get_user_meta($userId, '_msfixit_delete_token_expires', true);
    if ($expected === '' || $expires < time() || !hash_equals($expected, hash('sha256', $token))) {
        wp_die('Der Löschlink ist ungültig oder abgelaufen.', 'Konto löschen', ['response' => 403]);
    }

    delete_user_meta($userId, '_msfixit_delete_token_hash');
    delete_user_meta($userId, '_msfixit_delete_token_expires');

    $status = msfixit_customer_deletion_status($userId);
    if (!$status['allowed']) {
        wp_die('Das Konto kann noch nicht automatisch entfernt werden, weil eine Zahlung offen ist oder der Zahlungsstand nicht sicher geprüft werden konnte. Bitte melde dich erneut an oder wende dich an office@msfixit.at.', 'Konto löschen', ['response' => 409]);
    }

    $email = sanitize_email((string) $user->user_email);
    $hasRetainedTransactions = !empty($status['orders']['orders']) || (int) $status['office']['documents'] > 0;
    $removed = false;

    if ($hasRetainedTransactions) {
        $removed = msfixit_customer_deletion_anonymize($userId);
    } else {
        require_once ABSPATH . 'wp-admin/includes/user.php';
        WP_Session_Tokens::get_instance($userId)->destroy_all();
        $removed = wp_delete_user($userId) === true;
    }

    if (!$removed) {
        wp_die('Das Konto konnte nicht vollständig entfernt werden. Bitte wende dich an office@msfixit.at.', 'Konto löschen', ['response' => 500]);
    }

    wp_clear_auth_cookie();
    wp_mail(
        $email,
        'Dein Ms. FixIT Kundenkonto wurde entfernt',
        "Dein Kundenlogin und dein Profil wurden entfernt. Gesetzlich aufzubewahrende Rechnungs- und Buchungsbelege bleiben nur für die vorgeschriebene Dauer im getrennten Office-Archiv erhalten.\n"
    );
    wp_safe_redirect(add_query_arg('konto-geloescht', '1', home_url('/')));
    exit;
}
add_action('admin_post_nopriv_msfixit_customer_delete_confirm', 'msfixit_customer_deletion_confirm');
add_action('admin_post_msfixit_customer_delete_confirm', 'msfixit_customer_deletion_confirm');

add_filter('wp_authenticate_user', static function ($user) {
    if ($user instanceof WP_User && get_user_meta((int) $user->ID, '_msfixit_account_deleted', true) === 'yes') {
        return new WP_Error('msfixit_account_deleted', 'Dieses Kundenkonto wurde gelöscht.');
    }
    return $user;
}, 5);
