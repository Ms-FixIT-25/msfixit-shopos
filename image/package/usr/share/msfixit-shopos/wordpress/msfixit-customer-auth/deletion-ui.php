<?php

declare(strict_types=1);

if (!defined('ABSPATH')) {
    exit;
}

function msfixit_customer_deletion_panel(): void
{
    if (!is_user_logged_in()) {
        return;
    }

    $notices = [
        'delete_blocked' => ['error', 'Das Konto kann noch nicht automatisch entfernt werden. Prüfe die unten angezeigten offenen Punkte.'],
        'delete_mail_failed' => ['error', 'Die Bestätigungsmail konnte nicht versendet werden. Bitte versuche es später erneut oder schreibe an office@msfixit.at.'],
        'delete_mail_sent' => ['message', 'Die Bestätigungsmail wurde versendet. Der Link ist 24 Stunden gültig.'],
    ];
    $notice = sanitize_key((string) ($_GET['auth_notice'] ?? ''));
    if (isset($notices[$notice])) {
        [$type, $message] = $notices[$notice];
        $class = $type === 'error' ? 'woocommerce-error' : 'woocommerce-message';
        echo '<div class="' . esc_attr($class) . '" role="alert">' . esc_html($message) . '</div>';
    }

    $status = msfixit_customer_deletion_status(get_current_user_id());
    echo '<div class="msfixit-security-grid msfixit-deletion-grid">';
    echo '<section class="msfixit-security-card msfixit-danger-card"><h2>Kundenkonto löschen</h2>';
    echo '<p>Damit entfernst du deinen Login, dein Profil, Google-Verknüpfungen, 2-Faktor-Daten und alle aktiven Sitzungen.</p>';
    echo '<p><strong>Bereits ausgestellte Rechnungen und Buchungsbelege werden dadurch nicht verändert.</strong> Sie bleiben getrennt vom Kundenkonto nur so lange erhalten, wie gesetzliche Aufbewahrungs- oder Anspruchsfristen das erfordern.</p>';

    if (!$status['allowed']) {
        echo '<div class="msfixit-deletion-blocked"><p><strong>Automatische Löschung derzeit gesperrt:</strong></p><ul>';
        foreach ($status['reasons'] as $reason) {
            echo '<li>' . esc_html((string) $reason) . '</li>';
        }
        echo '</ul><p>Sobald alles bezahlt und der Zahlungsstand wieder sicher prüfbar ist, wird die Löschung automatisch freigegeben. Ein Datenschutzanliegen kannst du unabhängig davon jederzeit an <a href="mailto:office@msfixit.at">office@msfixit.at</a> richten.</p></div>';
        echo '<button class="button" type="button" disabled>Konto derzeit nicht löschbar</button>';
    } else {
        echo '<p class="msfixit-deletion-ready"><strong>Keine offenen Zahlungen erkannt.</strong> Nach dem Klick erhältst du eine Bestätigungsmail. Erst der Link in dieser Mail entfernt das Konto.</p>';
        echo '<form method="post" action="' . esc_url(admin_url('admin-post.php')) . '" onsubmit="return window.confirm(\'Bestätigungsmail für die endgültige Kontolöschung senden?\');">';
        wp_nonce_field('msfixit_customer_delete_request');
        echo '<input type="hidden" name="action" value="msfixit_customer_delete_request">';
        echo '<button class="button msfixit-delete-button" type="submit">Kontolöschung per E-Mail bestätigen</button></form>';
    }

    echo '</section></div>';
}
add_action('woocommerce_account_' . MSFIXIT_CUSTOMER_AUTH_ENDPOINT . '_endpoint', 'msfixit_customer_deletion_panel', 20);

add_action('wp_footer', static function (): void {
    if (!isset($_GET['konto-geloescht']) || $_GET['konto-geloescht'] !== '1') {
        return;
    }
    echo '<div class="msfixit-account-deleted-notice" role="status">Dein Kundenkonto wurde entfernt. Gesetzlich aufzubewahrende Belege bleiben getrennt vom Login archiviert.</div>';
});
