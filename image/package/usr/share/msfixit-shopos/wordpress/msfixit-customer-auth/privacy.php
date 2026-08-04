<?php

declare(strict_types=1);

if (!defined('ABSPATH')) {
    exit;
}

const MSFIXIT_CUSTOMER_PRIVACY_ENDPOINT = 'datenschutz';
const MSFIXIT_CUSTOMER_EXPORT_TOKEN_TTL = DAY_IN_SECONDS;

function msfixit_customer_privacy_controller(): array
{
    $config = [];
    if (function_exists('msfixit_office_bridge_env') && defined('MSFIXIT_OFFICE_BUSINESS_ENV')) {
        $config = msfixit_office_bridge_env((string) constant('MSFIXIT_OFFICE_BUSINESS_ENV'));
    }

    return [
        'name' => trim((string) ($config['BUSINESS_LEGAL_NAME'] ?? 'Ms. FixIT')) ?: 'Ms. FixIT',
        'email' => sanitize_email((string) ($config['BUSINESS_EMAIL'] ?? 'office@msfixit.at')) ?: 'office@msfixit.at',
        'street' => trim((string) ($config['BUSINESS_STREET'] ?? '')),
        'postcode' => trim((string) ($config['BUSINESS_POSTCODE'] ?? '')),
        'city' => trim((string) ($config['BUSINESS_CITY'] ?? '')),
        'country' => strtoupper(trim((string) ($config['BUSINESS_COUNTRY'] ?? 'AT'))) ?: 'AT',
        'website' => home_url('/'),
    ];
}

function msfixit_customer_privacy_catalog(): array
{
    return [
        [
            'category' => 'Kundenkonto und Stammdaten',
            'examples' => 'Name, E-Mail-Adresse, Telefonnummer, Rechnungs- und Lieferanschrift, Kontoregistrierung',
            'purpose' => 'Bereitstellung und Verwaltung des Kundenkontos, Kommunikation und Vertragsabwicklung',
            'legal_basis' => 'Art. 6 Abs. 1 lit. b DSGVO; soweit gesetzlich erforderlich Art. 6 Abs. 1 lit. c DSGVO',
            'source' => 'Direkt von der Kundin oder dem Kunden',
            'recipients' => 'Berechtigte Ms.-FixIT-Beschäftigte und technisch notwendige Hosting-Dienste',
            'retention' => 'Bis zur Kontolöschung; Daten in aufbewahrungspflichtigen Belegen bleiben davon getrennt',
        ],
        [
            'category' => 'Bestellungen, Lieferung und Leistungserbringung',
            'examples' => 'Bestellnummer, Artikel, Preise, Status, Adressen, Versand- und Leistungsinformationen',
            'purpose' => 'Vertragsanbahnung, Vertragserfüllung, Lieferung, Support und Gewährleistungsbearbeitung',
            'legal_basis' => 'Art. 6 Abs. 1 lit. b DSGVO',
            'source' => 'Direkt von der Kundschaft sowie aus dem Bestell- und Versandablauf',
            'recipients' => 'Je nach Auftrag Zahlungs-, Versand-, Liefer- oder Fulfillment-Dienstleister',
            'retention' => 'Nach Vertragsende nur noch entsprechend gesetzlicher Aufbewahrungs- und Anspruchsfristen',
        ],
        [
            'category' => 'Rechnungen, Zahlungen und Buchhaltung',
            'examples' => 'Rechnungsdaten, Zahlungsstatus, Betrag, Zahlungsreferenz und Zuordnung zu Belegen',
            'purpose' => 'Zahlungsabwicklung, Buchführung, Steuer- und Nachweispflichten sowie Forderungsverwaltung',
            'legal_basis' => 'Art. 6 Abs. 1 lit. b und lit. c DSGVO',
            'source' => 'Bestellablauf, Zahlungsdienstleister und interne Buchhaltung',
            'recipients' => 'Zahlungsdienstleister, Steuerberatung, Banken und Behörden, soweit erforderlich',
            'retention' => 'Buchungsbelege grundsätzlich sieben Jahre; bei anhängigen Verfahren gegebenenfalls länger',
        ],
        [
            'category' => 'Service- und Reparaturanfragen',
            'examples' => 'Kontaktangaben, Gerät, Modell, Fehlerbeschreibung, Bestellbezug, Status und Kommunikation',
            'purpose' => 'Bearbeitung von Anfragen, Diagnose, Angebot, Terminierung und Durchführung beauftragter Leistungen',
            'legal_basis' => 'Art. 6 Abs. 1 lit. b DSGVO; bei ausdrücklich freiwilliger Einwilligung zusätzlich lit. a',
            'source' => 'Direkt über das Serviceformular oder die Kommunikation mit Ms. FixIT',
            'recipients' => 'Berechtigte Ms.-FixIT-Beschäftigte; weitere Fach- oder Lieferpartner nur soweit erforderlich',
            'retention' => 'Bis zum Abschluss und danach entsprechend Gewährleistungs-, Anspruchs- oder Nachweispflichten',
        ],
        [
            'category' => 'Anmeldung und Kontosicherheit',
            'examples' => 'Google-Kontoverknüpfung, Anmeldemethode, verschlüsselter TOTP-Status, gehashte Wiederherstellungscodes und Sicherheitsereignisse',
            'purpose' => 'Sichere Anmeldung, Missbrauchsschutz, Sitzungsverwaltung und Wiederherstellung des Kontozugangs',
            'legal_basis' => 'Art. 6 Abs. 1 lit. b und lit. f DSGVO',
            'source' => 'Kundenkonto, Authenticator-App und bei Google-Anmeldung Google OpenID Connect',
            'recipients' => 'Google nur bei gewählter Google-Anmeldung; ansonsten interne ShopOS-Sicherheitsdienste',
            'retention' => 'Bis zur Entfernung der jeweiligen Anmeldemethode oder Kontolöschung; Ereignishistorie ist begrenzt',
        ],
        [
            'category' => 'Transaktions- und Servicemails',
            'examples' => 'Empfängeradresse, Betreff, Zustellstatus und Inhalt notwendiger Bestell-, Service- oder Sicherheitsmails',
            'purpose' => 'Bestell-, Service-, Sicherheits- und gesetzlich erforderliche Kommunikation',
            'legal_basis' => 'Art. 6 Abs. 1 lit. b und lit. c DSGVO; Sicherheitskommunikation auch lit. f',
            'source' => 'Kundenkonto und jeweiliger Geschäfts- oder Sicherheitsvorgang',
            'recipients' => 'Google Workspace als Mailtransport sowie beteiligte Mailanbieter',
            'retention' => 'Nach betrieblicher Mail- und Nachweispolitik; nicht länger als für Zweck oder Pflichten erforderlich',
        ],
        [
            'category' => 'Technische Sicherheits- und Protokolldaten',
            'examples' => 'IP-Adresse, Browserangaben, kurzlebige Rate-Limit-Kennungen, Zeitpunkte und Serverprotokolle',
            'purpose' => 'Technischer Betrieb, Fehleranalyse, Angriffserkennung und Schutz vor automatisiertem Missbrauch',
            'legal_basis' => 'Art. 6 Abs. 1 lit. f DSGVO',
            'source' => 'Automatisch beim Aufruf und bei sicherheitsrelevanten Aktionen',
            'recipients' => 'Hosting- und Sicherheitsdienste, soweit für den Betrieb erforderlich',
            'retention' => 'Kurzlebige ShopOS-Kennungen laufen automatisch ab; Serverlogs nach dokumentierter Log-Richtlinie',
        ],
    ];
}

function msfixit_customer_privacy_profile(int $userId): array
{
    $user = get_user_by('id', $userId);
    if (!$user instanceof WP_User) {
        return [];
    }

    $metaKeys = [
        'first_name', 'last_name',
        'billing_first_name', 'billing_last_name', 'billing_company', 'billing_address_1',
        'billing_address_2', 'billing_postcode', 'billing_city', 'billing_state', 'billing_country',
        'billing_email', 'billing_phone',
        'shipping_first_name', 'shipping_last_name', 'shipping_company', 'shipping_address_1',
        'shipping_address_2', 'shipping_postcode', 'shipping_city', 'shipping_state', 'shipping_country',
    ];
    $profile = [
        'user_id' => (int) $user->ID,
        'login_name' => (string) $user->user_login,
        'email' => (string) $user->user_email,
        'display_name' => (string) $user->display_name,
        'registered_at' => (string) $user->user_registered,
    ];
    foreach ($metaKeys as $key) {
        $value = get_user_meta($userId, $key, true);
        if ($value !== '' && $value !== null) {
            $profile[$key] = is_scalar($value) ? (string) $value : $value;
        }
    }
    return $profile;
}

function msfixit_customer_privacy_security(int $userId): array
{
    $history = get_user_meta($userId, '_msfixit_auth_audit', true);
    $recovery = get_user_meta($userId, '_msfixit_recovery_hashes', true);

    return [
        'google_subject_identifier' => (string) get_user_meta($userId, '_msfixit_google_sub', true),
        'google_linked_email' => (string) get_user_meta($userId, '_msfixit_google_email', true),
        'google_originated_account' => get_user_meta($userId, '_msfixit_google_created', true) === 'yes',
        'local_password_deliberately_set' => get_user_meta($userId, '_msfixit_local_password_ready', true) === 'yes',
        'two_factor_enabled' => function_exists('msfixit_customer_totp_enabled')
            ? msfixit_customer_totp_enabled($userId)
            : false,
        'recovery_codes_remaining' => is_array($recovery) ? count($recovery) : 0,
        'last_authentication_method' => (string) get_user_meta($userId, '_msfixit_last_auth_method', true),
        'last_authentication_at' => (string) get_user_meta($userId, '_msfixit_last_auth_at', true),
        'security_event_history' => is_array($history) ? array_slice($history, 0, 20) : [],
        'security_secrets_disclosure' => 'Passwörter, TOTP-Geheimnisse, Wiederherstellungscode-Hashes, OAuth-Secrets und geheime Statusschlüssel werden aus Sicherheitsgründen nicht in Datenkopien ausgegeben.',
    ];
}

function msfixit_customer_privacy_orders(int $userId): array
{
    if (!function_exists('wc_get_orders')) {
        return ['available' => false, 'complete' => false, 'orders' => []];
    }

    $result = [];
    $page = 1;
    $complete = true;
    do {
        $query = wc_get_orders([
            'customer_id' => $userId,
            'limit' => 100,
            'page' => $page,
            'paginate' => true,
            'orderby' => 'date',
            'order' => 'DESC',
            'return' => 'objects',
        ]);
        if (!is_object($query) || !isset($query->orders, $query->max_num_pages)) {
            return ['available' => false, 'complete' => false, 'orders' => []];
        }
        foreach ($query->orders as $order) {
            if (!$order instanceof WC_Order) {
                continue;
            }
            $lines = [];
            foreach ($order->get_items(['line_item', 'shipping', 'fee', 'coupon']) as $itemId => $item) {
                $entry = [
                    'item_id' => (int) $itemId,
                    'name' => method_exists($item, 'get_name') ? (string) $item->get_name() : '',
                    'type' => (string) $item->get_type(),
                ];
                if ($item instanceof WC_Order_Item_Product) {
                    $entry['product_id'] = (int) $item->get_product_id();
                    $entry['variation_id'] = (int) $item->get_variation_id();
                    $entry['quantity'] = (float) $item->get_quantity();
                    $entry['subtotal'] = (string) $item->get_subtotal();
                    $entry['total'] = (string) $item->get_total();
                    $entry['tax'] = (string) $item->get_total_tax();
                } elseif (method_exists($item, 'get_total')) {
                    $entry['total'] = (string) $item->get_total();
                }
                $lines[] = $entry;
            }
            $result[] = [
                'order_id' => (int) $order->get_id(),
                'order_number' => (string) $order->get_order_number(),
                'status' => (string) $order->get_status(),
                'currency' => (string) $order->get_currency(),
                'total' => (string) $order->get_total(),
                'total_tax' => (string) $order->get_total_tax(),
                'payment_method' => (string) $order->get_payment_method_title(),
                'transaction_id' => (string) $order->get_transaction_id(),
                'customer_note' => (string) $order->get_customer_note(),
                'created_at' => $order->get_date_created() ? $order->get_date_created()->date(DATE_ATOM) : null,
                'paid_at' => $order->get_date_paid() ? $order->get_date_paid()->date(DATE_ATOM) : null,
                'completed_at' => $order->get_date_completed() ? $order->get_date_completed()->date(DATE_ATOM) : null,
                'billing' => $order->get_address('billing'),
                'shipping' => $order->get_address('shipping'),
                'items' => $lines,
            ];
        }
        $maxPages = (int) $query->max_num_pages;
        $page++;
        if ($page > 100 && $page <= $maxPages) {
            $complete = false;
            break;
        }
    } while ($page <= $maxPages);

    return ['available' => true, 'complete' => $complete, 'orders' => $result];
}

function msfixit_customer_privacy_service_requests(string $email): array
{
    if (!post_type_exists('msfixit_service_request') || !is_email($email)) {
        return ['available' => true, 'complete' => true, 'requests' => []];
    }

    $posts = get_posts([
        'post_type' => 'msfixit_service_request',
        'post_status' => 'private',
        'posts_per_page' => 500,
        'orderby' => 'date',
        'order' => 'DESC',
        'meta_key' => '_msfixit_service_email',
        'meta_value' => $email,
        'suppress_filters' => true,
    ]);
    $requests = [];
    foreach ($posts as $post) {
        if (!$post instanceof WP_Post) {
            continue;
        }
        $id = (int) $post->ID;
        $requests[] = [
            'reference' => (string) get_post_meta($id, '_msfixit_service_reference', true),
            'status' => (string) get_post_meta($id, '_msfixit_service_status', true),
            'name' => (string) get_post_meta($id, '_msfixit_service_name', true),
            'email' => (string) get_post_meta($id, '_msfixit_service_email', true),
            'phone' => (string) get_post_meta($id, '_msfixit_service_phone', true),
            'request_type' => (string) get_post_meta($id, '_msfixit_service_type', true),
            'device_type' => (string) get_post_meta($id, '_msfixit_service_device', true),
            'model' => (string) get_post_meta($id, '_msfixit_service_model', true),
            'order_number' => (string) get_post_meta($id, '_msfixit_service_order_number', true),
            'fault_or_request' => (string) get_post_meta($id, '_msfixit_service_fault', true),
            'preferred_contact' => (string) get_post_meta($id, '_msfixit_service_contact_method', true),
            'privacy_consent_at' => (string) get_post_meta($id, '_msfixit_service_privacy_consent_at', true),
            'public_status_note' => (string) get_post_meta($id, '_msfixit_service_public_note', true),
            'status_history' => get_post_meta($id, '_msfixit_service_history', true),
            'created_at' => get_post_time(DATE_ATOM, true, $id),
            'updated_at' => get_post_modified_time(DATE_ATOM, true, $id),
            'secret_disclosure' => 'Der geheime Statuszugang wird nicht ausgegeben; ShopOS speichert davon nur einen Einweg-Hash.',
        ];
    }

    return [
        'available' => true,
        'complete' => count($posts) < 500,
        'requests' => $requests,
    ];
}

function msfixit_customer_privacy_office(string $email): array
{
    if (!is_email($email) || !function_exists('msfixit_office_bridge_database')) {
        return ['available' => false, 'complete' => false, 'orders' => [], 'documents' => [], 'payments' => []];
    }
    $pdo = msfixit_office_bridge_database();
    if (!$pdo instanceof PDO) {
        return ['available' => false, 'complete' => false, 'orders' => [], 'documents' => [], 'payments' => []];
    }

    try {
        $orderStatement = $pdo->prepare(
            "SELECT source_system, source_order_id, source_order_number, order_status, customer_type,
                    billing_country, shipping_country, currency, billing_json, shipping_json, totals_json,
                    created_at, updated_at
             FROM office_orders
             WHERE LOWER(JSON_UNQUOTE(JSON_EXTRACT(billing_json, '$.email'))) = LOWER(?)
             ORDER BY created_at DESC"
        );
        $orderStatement->execute([$email]);
        $orders = [];
        foreach ($orderStatement->fetchAll() as $row) {
            foreach (['billing_json', 'shipping_json', 'totals_json'] as $jsonKey) {
                $decoded = json_decode((string) ($row[$jsonKey] ?? ''), true);
                $row[str_replace('_json', '', $jsonKey)] = is_array($decoded) ? $decoded : [];
                unset($row[$jsonKey]);
            }
            $orders[] = $row;
        }

        $documentStatement = $pdo->prepare(
            "SELECT id, order_id, document_type, document_number, document_status, language_code, currency,
                    tax_mode, issue_date, service_date, due_date, customer_type, customer_name, customer_email,
                    billing_json, shipping_json, net_total, tax_total, gross_total, source_system,
                    source_document_id, correction_of_id, finalized_at, sent_at, created_at, updated_at
             FROM office_documents
             WHERE LOWER(customer_email) = LOWER(?)
             ORDER BY created_at DESC"
        );
        $documentStatement->execute([$email]);
        $documents = [];
        foreach ($documentStatement->fetchAll() as $row) {
            foreach (['billing_json', 'shipping_json'] as $jsonKey) {
                $decoded = json_decode((string) ($row[$jsonKey] ?? ''), true);
                $row[str_replace('_json', '', $jsonKey)] = is_array($decoded) ? $decoded : [];
                unset($row[$jsonKey]);
            }
            $documents[] = $row;
        }

        $paymentStatement = $pdo->prepare(
            "SELECT p.payment_source, p.external_payment_id, p.paid_at, p.amount, p.currency,
                    p.payer_name, p.payer_reference, p.payment_status,
                    a.allocated_amount, d.document_number, d.document_type
             FROM office_payments p
             INNER JOIN office_payment_allocations a ON a.payment_id = p.id
             INNER JOIN office_documents d ON d.id = a.document_id
             WHERE LOWER(d.customer_email) = LOWER(?)
             ORDER BY p.paid_at DESC"
        );
        $paymentStatement->execute([$email]);

        return [
            'available' => true,
            'complete' => true,
            'orders' => $orders,
            'documents' => $documents,
            'payments' => $paymentStatement->fetchAll(),
        ];
    } catch (Throwable $exception) {
        error_log('[Ms. FixIT privacy] Office export failed: ' . $exception->getMessage());
        return ['available' => false, 'complete' => false, 'orders' => [], 'documents' => [], 'payments' => []];
    }
}

function msfixit_customer_privacy_export_payload(int $userId): array
{
    $user = get_user_by('id', $userId);
    if (!$user instanceof WP_User) {
        return ['complete' => false, 'error' => 'customer_not_found'];
    }
    $email = sanitize_email((string) $user->user_email);
    $orders = msfixit_customer_privacy_orders($userId);
    $service = msfixit_customer_privacy_service_requests($email);
    $office = msfixit_customer_privacy_office($email);
    $complete = !empty($orders['available']) && !empty($orders['complete'])
        && !empty($service['complete']) && !empty($office['available']) && !empty($office['complete']);

    return [
        'schema' => 'msfixit-shopos-personal-data-v1',
        'generated_at' => gmdate(DATE_ATOM),
        'complete' => $complete,
        'controller' => msfixit_customer_privacy_controller(),
        'information' => [
            'processing_categories' => msfixit_customer_privacy_catalog(),
            'data_sources' => 'Direkte Angaben, Bestell- und Servicevorgänge, Zahlungs- und Versandereignisse sowie Google OpenID Connect nur bei gewählter Google-Anmeldung.',
            'automated_decisions' => 'ShopOS trifft im Kundenkonto keine ausschließlich automatisierte Entscheidung mit rechtlicher oder vergleichbar erheblicher Wirkung.',
            'rights' => [
                'Auskunft und Datenkopie', 'Berichtigung', 'Löschung', 'Einschränkung der Verarbeitung',
                'Datenübertragbarkeit, soweit anwendbar', 'Widerspruch, soweit die Verarbeitung auf berechtigten Interessen beruht',
                'Beschwerde bei der österreichischen Datenschutzbehörde',
            ],
            'contact' => 'office@msfixit.at',
        ],
        'data' => [
            'customer_profile' => msfixit_customer_privacy_profile($userId),
            'authentication_and_security' => msfixit_customer_privacy_security($userId),
            'woocommerce' => $orders,
            'service_requests' => $service,
            'office_accounting_and_payments' => $office,
        ],
    ];
}

function msfixit_customer_privacy_summary(int $userId): array
{
    $user = get_user_by('id', $userId);
    if (!$user instanceof WP_User) {
        return [];
    }
    $email = sanitize_email((string) $user->user_email);
    $orderCount = function_exists('wc_get_customer_order_count') ? (int) wc_get_customer_order_count($userId) : null;
    $serviceCount = null;
    if (post_type_exists('msfixit_service_request')) {
        $serviceQuery = new WP_Query([
            'post_type' => 'msfixit_service_request',
            'post_status' => 'private',
            'fields' => 'ids',
            'posts_per_page' => 1,
            'meta_key' => '_msfixit_service_email',
            'meta_value' => $email,
            'no_found_rows' => false,
        ]);
        $serviceCount = (int) $serviceQuery->found_posts;
    }
    $office = msfixit_customer_privacy_office($email);

    return [
        'email' => $email,
        'name' => trim((string) $user->display_name),
        'phone' => (string) get_user_meta($userId, 'billing_phone', true),
        'google' => (string) get_user_meta($userId, '_msfixit_google_email', true),
        'two_factor' => function_exists('msfixit_customer_totp_enabled') && msfixit_customer_totp_enabled($userId),
        'orders' => $orderCount,
        'service_requests' => $serviceCount,
        'office_available' => !empty($office['available']),
        'office_documents' => !empty($office['available']) ? count($office['documents']) : null,
        'office_payments' => !empty($office['available']) ? count($office['payments']) : null,
    ];
}

function msfixit_customer_privacy_request_export(): void
{
    if (!is_user_logged_in()) {
        auth_redirect();
    }
    check_admin_referer('msfixit_customer_privacy_export_request');
    $userId = get_current_user_id();
    $user = wp_get_current_user();
    if (array_intersect($user->roles, ['administrator', 'shop_manager'])) {
        wp_die('Diese Selbstbedienungsfunktion ist nur für Kundenkonten bestimmt.', 'Datenauskunft', ['response' => 403]);
    }

    $rateKey = 'msfixit_privacy_export_' . $userId;
    $requests = (int) get_transient($rateKey);
    if ($requests >= 3) {
        wp_safe_redirect(msfixit_customer_privacy_url(['privacy_notice' => 'export_rate']));
        exit;
    }
    set_transient($rateKey, $requests + 1, DAY_IN_SECONDS);

    $token = msfixit_customer_auth_b64url(random_bytes(32));
    update_user_meta($userId, '_msfixit_data_export_token_hash', hash('sha256', $token));
    update_user_meta($userId, '_msfixit_data_export_token_expires', time() + MSFIXIT_CUSTOMER_EXPORT_TOKEN_TTL);
    $link = add_query_arg([
        'action' => 'msfixit_customer_privacy_export_confirm',
        'user_id' => $userId,
        'token' => $token,
    ], admin_url('admin-post.php'));

    $sent = wp_mail(
        (string) $user->user_email,
        'Deine Ms. FixIT Datenkopie bestätigen',
        "Du hast eine Kopie deiner bei Ms. FixIT verarbeiteten personenbezogenen Daten angefordert.\n\n"
        . "Über diesen einmal verwendbaren Link lädst du die Daten als JSON-Datei herunter:\n{$link}\n\n"
        . "Der Link ist 24 Stunden gültig. Falls du die Anfrage nicht gestellt hast, ignoriere diese Nachricht und ändere vorsorglich dein Passwort.\n"
    );
    if (!$sent) {
        delete_user_meta($userId, '_msfixit_data_export_token_hash');
        delete_user_meta($userId, '_msfixit_data_export_token_expires');
        wp_safe_redirect(msfixit_customer_privacy_url(['privacy_notice' => 'export_mail_failed']));
        exit;
    }
    if (function_exists('msfixit_customer_auth_audit')) {
        msfixit_customer_auth_audit($userId, 'personal_data_export_requested', 'email');
    }
    wp_safe_redirect(msfixit_customer_privacy_url(['privacy_notice' => 'export_mail_sent']));
    exit;
}
add_action('admin_post_msfixit_customer_privacy_export_request', 'msfixit_customer_privacy_request_export');

function msfixit_customer_privacy_export_confirm(): void
{
    $userId = absint($_GET['user_id'] ?? 0);
    $token = sanitize_text_field(wp_unslash((string) ($_GET['token'] ?? '')));
    $user = get_user_by('id', $userId);
    if (!$user instanceof WP_User || $token === '') {
        wp_die('Der Datenlink ist ungültig.', 'Datenauskunft', ['response' => 400]);
    }
    $expected = (string) get_user_meta($userId, '_msfixit_data_export_token_hash', true);
    $expires = (int) get_user_meta($userId, '_msfixit_data_export_token_expires', true);
    if ($expected === '' || $expires < time() || !hash_equals($expected, hash('sha256', $token))) {
        wp_die('Der Datenlink ist ungültig oder abgelaufen.', 'Datenauskunft', ['response' => 403]);
    }

    $payload = msfixit_customer_privacy_export_payload($userId);
    if (empty($payload['complete'])) {
        wp_die(
            'Die Datenkopie konnte nicht vollständig erstellt werden, weil ein verbundenes ShopOS-System nicht sicher ausgelesen werden konnte. Der Link bleibt gültig. Bitte versuche es später erneut oder schreibe an office@msfixit.at.',
            'Datenauskunft',
            ['response' => 503]
        );
    }

    delete_user_meta($userId, '_msfixit_data_export_token_hash');
    delete_user_meta($userId, '_msfixit_data_export_token_expires');
    if (function_exists('msfixit_customer_auth_audit')) {
        msfixit_customer_auth_audit($userId, 'personal_data_export_downloaded', 'email');
    }

    nocache_headers();
    header('Content-Type: application/json; charset=utf-8');
    header('Content-Disposition: attachment; filename="msfixit-datenauskunft-' . gmdate('Ymd-His') . '.json"');
    header('X-Content-Type-Options: nosniff');
    header('X-Robots-Tag: noindex, nofollow, noarchive');
    header('Referrer-Policy: no-referrer');
    echo wp_json_encode($payload, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit;
}
add_action('admin_post_nopriv_msfixit_customer_privacy_export_confirm', 'msfixit_customer_privacy_export_confirm');
add_action('admin_post_msfixit_customer_privacy_export_confirm', 'msfixit_customer_privacy_export_confirm');

function msfixit_customer_privacy_url(array $args = []): string
{
    $base = function_exists('wc_get_account_endpoint_url')
        ? wc_get_account_endpoint_url(MSFIXIT_CUSTOMER_PRIVACY_ENDPOINT)
        : admin_url('profile.php');
    return $args === [] ? $base : add_query_arg($args, $base);
}

function msfixit_customer_privacy_render(): void
{
    if (!is_user_logged_in()) {
        echo '<p>Bitte melde dich an.</p>';
        return;
    }
    $summary = msfixit_customer_privacy_summary(get_current_user_id());
    $notice = sanitize_key((string) ($_GET['privacy_notice'] ?? ''));
    $notices = [
        'export_mail_sent' => ['woocommerce-message', 'Die Bestätigungsmail wurde versendet. Der Datenlink ist 24 Stunden und einmalig gültig.'],
        'export_mail_failed' => ['woocommerce-error', 'Die Bestätigungsmail konnte nicht versendet werden. Bitte versuche es später erneut oder schreibe an office@msfixit.at.'],
        'export_rate' => ['woocommerce-error', 'Es wurden heute bereits mehrere Datenkopien angefordert. Bitte nutze den zuletzt erhaltenen Link oder schreibe an office@msfixit.at.'],
    ];
    if (isset($notices[$notice])) {
        echo '<div class="' . esc_attr($notices[$notice][0]) . '" role="status">' . esc_html($notices[$notice][1]) . '</div>';
    }

    echo '<div class="msfixit-privacy-intro"><h2>Deine Daten bei Ms. FixIT</h2>';
    echo '<p>Hier siehst du, welche Datenkategorien ShopOS zu deinem Kundenkonto verarbeitet, wofür sie benötigt werden, woher sie stammen, an wen sie je nach Vorgang übermittelt werden können und wie lange sie grundsätzlich benötigt werden.</p></div>';

    echo '<section class="msfixit-security-card msfixit-privacy-summary"><h2>Aktuell zugeordnet</h2><dl class="msfixit-auth-details">';
    $rows = [
        'Konto-E-Mail' => $summary['email'] ?? '',
        'Name' => $summary['name'] ?? '',
        'Telefon' => $summary['phone'] ?: 'nicht im Profil gespeichert',
        'Google-Anmeldung' => $summary['google'] ?: 'nicht verbunden',
        '2-Faktor-Authentifizierung' => !empty($summary['two_factor']) ? 'aktiv' : 'nicht aktiv',
        'Bestellungen' => $summary['orders'] === null ? 'derzeit nicht prüfbar' : (string) $summary['orders'],
        'Serviceanfragen' => $summary['service_requests'] === null ? 'derzeit nicht prüfbar' : (string) $summary['service_requests'],
        'Office-Belege' => !empty($summary['office_available']) ? (string) $summary['office_documents'] : 'derzeit nicht prüfbar',
        'Zahlungszuordnungen' => !empty($summary['office_available']) ? (string) $summary['office_payments'] : 'derzeit nicht prüfbar',
    ];
    foreach ($rows as $label => $value) {
        echo '<dt>' . esc_html($label) . '</dt><dd>' . esc_html((string) $value) . '</dd>';
    }
    echo '</dl><p><a class="button" href="' . esc_url(wc_get_account_endpoint_url('edit-account')) . '">Kontodaten berichtigen</a> '
        . '<a class="button" href="' . esc_url(wc_get_account_endpoint_url('edit-address')) . '">Adressen berichtigen</a></p></section>';

    echo '<div class="msfixit-privacy-catalog">';
    foreach (msfixit_customer_privacy_catalog() as $entry) {
        echo '<section class="msfixit-security-card msfixit-privacy-card"><h3>' . esc_html($entry['category']) . '</h3><dl>';
        foreach ([
            'Beispiele' => 'examples', 'Zweck' => 'purpose', 'Rechtsgrundlage' => 'legal_basis',
            'Herkunft' => 'source', 'Empfänger oder Kategorien' => 'recipients', 'Speicherdauer' => 'retention',
        ] as $label => $key) {
            echo '<div><dt>' . esc_html($label) . '</dt><dd>' . esc_html($entry[$key]) . '</dd></div>';
        }
        echo '</dl></section>';
    }
    echo '</div>';

    echo '<section class="msfixit-security-card msfixit-export-card"><h2>Vollständige Datenkopie anfordern</h2>';
    echo '<p>Nach der Bestätigung über deine hinterlegte E-Mail-Adresse erstellt ShopOS eine strukturierte, maschinenlesbare JSON-Datei mit Kundenprofil, Sicherheitsinformationen, Bestellungen, Serviceanfragen sowie zugeordneten Office-Belegen und Zahlungen.</p>';
    echo '<p>Geheimnisse wie Passwort-Hashes, TOTP-Schlüssel, Wiederherstellungscode-Hashes, OAuth-Secrets oder geheime Servicezugänge werden nicht offengelegt, weil dies dein Konto und andere Systeme gefährden würde.</p>';
    echo '<form method="post" action="' . esc_url(admin_url('admin-post.php')) . '">';
    wp_nonce_field('msfixit_customer_privacy_export_request');
    echo '<input type="hidden" name="action" value="msfixit_customer_privacy_export_request">';
    echo '<button class="button" type="submit">Datenkopie per E-Mail bestätigen</button></form></section>';

    echo '<section class="msfixit-security-card"><h2>Deine weiteren Rechte</h2>';
    echo '<p>Du kannst außerdem Berichtigung, Löschung, Einschränkung, Datenübertragbarkeit oder – soweit anwendbar – Widerspruch verlangen. ShopOS trifft keine ausschließlich automatisierten Entscheidungen mit rechtlicher oder vergleichbar erheblicher Wirkung über dein Kundenkonto.</p>';
    echo '<p>Für eine individuelle Anfrage, eine Negativauskunft oder Daten außerhalb des automatischen Exports schreibe an <a href="mailto:office@msfixit.at">office@msfixit.at</a>. Du kannst dich außerdem bei der <a href="https://dsb.gv.at/" rel="noopener noreferrer" target="_blank">österreichischen Datenschutzbehörde</a> beschweren.</p>';
    $privacyPage = get_page_by_path('datenschutz', OBJECT, 'page');
    if ($privacyPage instanceof WP_Post && $privacyPage->post_status === 'publish') {
        echo '<p><a href="' . esc_url(get_permalink($privacyPage)) . '">Vollständige Datenschutzerklärung anzeigen</a></p>';
    }
    echo '</section>';
}

add_action('init', static function (): void {
    add_rewrite_endpoint(MSFIXIT_CUSTOMER_PRIVACY_ENDPOINT, EP_ROOT | EP_PAGES);
});
add_action('woocommerce_account_' . MSFIXIT_CUSTOMER_PRIVACY_ENDPOINT . '_endpoint', 'msfixit_customer_privacy_render');
add_filter('woocommerce_account_menu_items', static function (array $items): array {
    $logout = $items['customer-logout'] ?? null;
    unset($items['customer-logout']);
    $items[MSFIXIT_CUSTOMER_PRIVACY_ENDPOINT] = 'Datenschutz';
    if ($logout !== null) {
        $items['customer-logout'] = $logout;
    }
    return $items;
}, 30);

function msfixit_customer_privacy_wordpress_exporter(string $email, int $page = 1): array
{
    if ($page > 1 || !is_email($email)) {
        return ['data' => [], 'done' => true];
    }
    $user = get_user_by('email', $email);
    $userId = $user instanceof WP_User ? (int) $user->ID : 0;
    $service = msfixit_customer_privacy_service_requests($email);
    $office = msfixit_customer_privacy_office($email);
    $data = [];

    if ($userId > 0) {
        $data[] = [
            'group_id' => 'msfixit-customer-security',
            'group_label' => 'Ms. FixIT Kundenkonto und Sicherheit',
            'item_id' => 'msfixit-customer-' . $userId,
            'data' => [
                ['name' => 'Kundenprofil', 'value' => wp_json_encode(msfixit_customer_privacy_profile($userId), JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE)],
                ['name' => 'Anmeldung und Sicherheit', 'value' => wp_json_encode(msfixit_customer_privacy_security($userId), JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE)],
                ['name' => 'Verarbeitungsinformationen', 'value' => wp_json_encode(msfixit_customer_privacy_catalog(), JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE)],
            ],
        ];
    }
    if (!empty($service['requests'])) {
        $data[] = [
            'group_id' => 'msfixit-service-requests',
            'group_label' => 'Ms. FixIT Serviceanfragen',
            'item_id' => 'msfixit-service-' . hash('sha256', strtolower($email)),
            'data' => [[
                'name' => 'Serviceanfragen',
                'value' => wp_json_encode($service['requests'], JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE),
            ]],
        ];
    }
    if (!empty($office['available'])) {
        $data[] = [
            'group_id' => 'msfixit-office',
            'group_label' => 'Ms. FixIT Office-Belege und Zahlungen',
            'item_id' => 'msfixit-office-' . hash('sha256', strtolower($email)),
            'data' => [[
                'name' => 'Office-Daten',
                'value' => wp_json_encode($office, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE),
            ]],
        ];
    }

    return ['data' => $data, 'done' => true];
}

add_filter('wp_privacy_personal_data_exporters', static function (array $exporters): array {
    $exporters['msfixit-shopos-customer'] = [
        'exporter_friendly_name' => 'Ms. FixIT ShopOS Kunden-, Service- und Office-Daten',
        'callback' => 'msfixit_customer_privacy_wordpress_exporter',
    ];
    return $exporters;
});
