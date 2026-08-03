<?php
/**
 * Plugin Name: Ms. FixIT ShopOS Office Bridge
 * Description: Sends WooCommerce order, payment, refund and fulfillment events to the independent ShopOS office core.
 * Version: 1.0.0
 */

declare(strict_types=1);

if (!defined('ABSPATH')) {
    exit;
}

const MSFIXIT_OFFICE_WP_ENV = '/etc/msfixit-shopos/office-wordpress.env';
const MSFIXIT_OFFICE_BUSINESS_ENV = '/etc/msfixit-shopos/business.env';

function msfixit_office_bridge_log(string $message): void
{
    error_log('[Ms. FixIT Office] ' . $message);
}

function msfixit_office_bridge_env(string $path): array
{
    static $cache = [];
    if (isset($cache[$path])) {
        return $cache[$path];
    }
    $settings = [];
    if (!is_readable($path)) {
        return $cache[$path] = $settings;
    }
    foreach (file($path, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) ?: [] as $line) {
        $line = trim($line);
        if ($line === '' || str_starts_with($line, '#') || !str_contains($line, '=')) {
            continue;
        }
        [$key, $value] = explode('=', $line, 2);
        $value = trim($value);
        if ((str_starts_with($value, '"') && str_ends_with($value, '"'))
            || (str_starts_with($value, "'") && str_ends_with($value, "'"))) {
            $value = substr($value, 1, -1);
        }
        $settings[trim($key)] = $value;
    }
    return $cache[$path] = $settings;
}

function msfixit_office_bridge_database(): ?PDO
{
    static $pdo = false;
    if ($pdo instanceof PDO) {
        return $pdo;
    }
    if ($pdo === null) {
        return null;
    }
    $env = msfixit_office_bridge_env(MSFIXIT_OFFICE_WP_ENV);
    foreach (['OFFICE_DB_HOST', 'OFFICE_DB_PORT', 'OFFICE_DB_NAME', 'OFFICE_DB_USER', 'OFFICE_DB_PASSWORD'] as $key) {
        if (empty($env[$key])) {
            $pdo = null;
            return null;
        }
    }
    try {
        $pdo = new PDO(
            sprintf(
                'mysql:host=%s;port=%s;dbname=%s;charset=utf8mb4',
                $env['OFFICE_DB_HOST'],
                $env['OFFICE_DB_PORT'],
                $env['OFFICE_DB_NAME']
            ),
            $env['OFFICE_DB_USER'],
            $env['OFFICE_DB_PASSWORD'],
            [
                PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
                PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
                PDO::ATTR_EMULATE_PREPARES => false,
            ]
        );
        return $pdo;
    } catch (Throwable $exception) {
        msfixit_office_bridge_log('Database connection failed: ' . $exception->getMessage());
        $pdo = null;
        return null;
    }
}

function msfixit_office_bridge_uuid(): string
{
    $bytes = random_bytes(16);
    $bytes[6] = chr((ord($bytes[6]) & 0x0f) | 0x40);
    $bytes[8] = chr((ord($bytes[8]) & 0x3f) | 0x80);
    $hex = bin2hex($bytes);
    return sprintf('%s-%s-%s-%s-%s',
        substr($hex, 0, 8),
        substr($hex, 8, 4),
        substr($hex, 12, 4),
        substr($hex, 16, 4),
        substr($hex, 20, 12)
    );
}

function msfixit_office_bridge_address(WC_Order $order, string $kind): array
{
    $prefix = $kind === 'shipping' ? 'shipping' : 'billing';
    $address = [
        'first_name' => (string) $order->{"get_{$prefix}_first_name"}(),
        'last_name' => (string) $order->{"get_{$prefix}_last_name"}(),
        'company' => (string) $order->{"get_{$prefix}_company"}(),
        'address_1' => (string) $order->{"get_{$prefix}_address_1"}(),
        'address_2' => (string) $order->{"get_{$prefix}_address_2"}(),
        'postcode' => (string) $order->{"get_{$prefix}_postcode"}(),
        'city' => (string) $order->{"get_{$prefix}_city"}(),
        'state' => (string) $order->{"get_{$prefix}_state"}(),
        'country' => strtoupper((string) $order->{"get_{$prefix}_country"}()),
    ];
    if ($kind === 'billing') {
        $address['email'] = (string) $order->get_billing_email();
        $address['phone'] = (string) $order->get_billing_phone();
    }
    return $address;
}

function msfixit_office_bridge_customer_type(WC_Order $order): string
{
    $company = trim((string) $order->get_billing_company());
    $vat = trim((string) $order->get_meta('_billing_vat_id', true));
    if ($vat === '') {
        $vat = trim((string) $order->get_meta('billing_vat_id', true));
    }
    return ($company !== '' || $vat !== '') ? 'business' : 'consumer';
}

function msfixit_office_bridge_product_metadata(?WC_Product $product): array
{
    if (!$product) {
        return [];
    }
    return [
        'woocommerce_product_id' => $product->get_id(),
        'woocommerce_parent_id' => $product->get_parent_id(),
        'hs_code' => trim((string) $product->get_meta('_msfixit_hs_code', true)),
        'origin_country' => strtoupper(trim((string) $product->get_meta('_msfixit_origin_country', true))),
        'net_weight_kg' => $product->get_weight() !== '' ? (float) $product->get_weight() : null,
        'length_cm' => $product->get_length() !== '' ? (float) $product->get_length() : null,
        'width_cm' => $product->get_width() !== '' ? (float) $product->get_width() : null,
        'height_cm' => $product->get_height() !== '' ? (float) $product->get_height() : null,
    ];
}

function msfixit_office_bridge_order_lines(WC_Order $order): array
{
    $lines = [];
    foreach ($order->get_items('line_item') as $item) {
        if (!$item instanceof WC_Order_Item_Product) {
            continue;
        }
        $quantity = max(0.001, (float) $item->get_quantity());
        $net = (float) $item->get_total();
        $tax = (float) $item->get_total_tax();
        $product = $item->get_product();
        $taxRate = $net !== 0.0 ? ($tax / $net) * 100 : 0.0;
        $lines[] = [
            'article_number' => $product ? (string) $product->get_sku() : '',
            'description' => $item->get_name(),
            'quantity' => $quantity,
            'unit' => 'Stk',
            'unit_net' => $net / $quantity,
            'tax_rate' => round($taxRate, 4),
            'line_net' => $net,
            'line_tax' => $tax,
            'line_gross' => $net + $tax,
            'metadata' => array_merge(
                msfixit_office_bridge_product_metadata($product),
                ['variation_attributes' => $item->get_formatted_meta_data('_', true)]
            ),
        ];
    }

    foreach ($order->get_items('shipping') as $item) {
        if (!$item instanceof WC_Order_Item_Shipping) {
            continue;
        }
        $net = (float) $item->get_total();
        $tax = (float) $item->get_total_tax();
        $lines[] = [
            'article_number' => null,
            'description' => 'Versand – ' . $item->get_name(),
            'quantity' => 1,
            'unit' => 'Pauschale',
            'unit_net' => $net,
            'tax_rate' => $net !== 0.0 ? round(($tax / $net) * 100, 4) : 0,
            'line_net' => $net,
            'line_tax' => $tax,
            'line_gross' => $net + $tax,
            'metadata' => ['method_id' => $item->get_method_id(), 'instance_id' => $item->get_instance_id()],
        ];
    }

    foreach ($order->get_items('fee') as $item) {
        if (!$item instanceof WC_Order_Item_Fee) {
            continue;
        }
        $net = (float) $item->get_total();
        $tax = (float) $item->get_total_tax();
        $lines[] = [
            'article_number' => null,
            'description' => $item->get_name(),
            'quantity' => 1,
            'unit' => 'Pauschale',
            'unit_net' => $net,
            'tax_rate' => $net !== 0.0 ? round(($tax / $net) * 100, 4) : 0,
            'line_net' => $net,
            'line_tax' => $tax,
            'line_gross' => $net + $tax,
            'metadata' => ['fee' => true],
        ];
    }

    return $lines;
}

function msfixit_office_bridge_order_payload(WC_Order $order): array
{
    $billing = msfixit_office_bridge_address($order, 'billing');
    $shipping = msfixit_office_bridge_address($order, 'shipping');
    if (implode('', $shipping) === '') {
        $shipping = $billing;
    }
    $transactionId = trim((string) $order->get_transaction_id());
    $datePaid = $order->get_date_paid();

    return [
        'source_system' => 'woocommerce',
        'source_order_id' => (string) $order->get_id(),
        'source_order_number' => (string) $order->get_order_number(),
        'source_document_id' => (string) $order->get_id(),
        'order_status' => (string) $order->get_status(),
        'customer_type' => msfixit_office_bridge_customer_type($order),
        'currency' => (string) $order->get_currency(),
        'billing' => $billing,
        'shipping' => $shipping,
        'totals' => [
            'net' => (float) $order->get_total() - (float) $order->get_total_tax(),
            'tax' => (float) $order->get_total_tax(),
            'gross' => (float) $order->get_total(),
            'shipping' => (float) $order->get_shipping_total(),
            'discount' => (float) $order->get_discount_total(),
            'refunded' => (float) $order->get_total_refunded(),
        ],
        'lines' => msfixit_office_bridge_order_lines($order),
        'payment' => $transactionId !== '' ? [
            'source' => strtolower((string) $order->get_payment_method()) ?: 'woocommerce',
            'external_id' => $transactionId,
            'amount' => (float) $order->get_total(),
            'currency' => (string) $order->get_currency(),
            'paid_at' => $datePaid ? $datePaid->date('Y-m-d H:i:s') : current_time('mysql'),
            'payer_name' => trim($order->get_formatted_billing_full_name()),
            'reference' => (string) $order->get_order_number(),
            'status' => 'confirmed',
        ] : [],
        'metadata' => [
            'created_via' => $order->get_created_via(),
            'payment_method' => $order->get_payment_method(),
            'payment_method_title' => $order->get_payment_method_title(),
            'customer_id' => $order->get_customer_id(),
            'customer_ip_address' => $order->get_customer_ip_address(),
            'customer_note' => $order->get_customer_note(),
            'billing_vat_id' => $order->get_meta('_billing_vat_id', true) ?: $order->get_meta('billing_vat_id', true),
        ],
    ];
}

function msfixit_office_bridge_refund_payload(WC_Order $order, WC_Order_Refund $refund): array
{
    $payload = msfixit_office_bridge_order_payload($order);
    $lines = [];
    foreach ($refund->get_items('line_item') as $item) {
        if (!$item instanceof WC_Order_Item_Product) {
            continue;
        }
        $quantity = abs((float) $item->get_quantity());
        $quantity = $quantity > 0 ? $quantity : 1;
        $net = abs((float) $item->get_total());
        $tax = abs((float) $item->get_total_tax());
        $product = $item->get_product();
        $lines[] = [
            'article_number' => $product ? (string) $product->get_sku() : '',
            'description' => 'Gutschrift – ' . $item->get_name(),
            'quantity' => $quantity,
            'unit' => 'Stk',
            'unit_net' => -($net / $quantity),
            'tax_rate' => $net !== 0.0 ? round(($tax / $net) * 100, 4) : 0,
            'line_net' => -$net,
            'line_tax' => -$tax,
            'line_gross' => -($net + $tax),
            'metadata' => msfixit_office_bridge_product_metadata($product),
        ];
    }
    $gross = -abs((float) $refund->get_amount());
    $tax = array_sum(array_column($lines, 'line_tax'));
    $net = $gross - $tax;
    $payload['source_document_id'] = 'refund:' . $refund->get_id();
    $payload['lines'] = $lines;
    $payload['totals'] = ['net' => $net, 'tax' => $tax, 'gross' => $gross];
    $payload['refund_id'] = (string) $refund->get_id();
    $payload['correction_of_source_document_id'] = (string) $order->get_id();
    $payload['metadata']['refund_reason'] = $refund->get_reason();
    return $payload;
}

function msfixit_office_bridge_enqueue(string $eventType, WC_Order $order, array $additional = []): void
{
    $pdo = msfixit_office_bridge_database();
    if (!$pdo) {
        msfixit_office_bridge_log("Event {$eventType} was not queued because Office is unavailable");
        return;
    }
    try {
        $payload = array_merge(['order' => msfixit_office_bridge_order_payload($order)], $additional);
        $statement = $pdo->prepare(
            'INSERT INTO office_outbox
             (event_uuid, aggregate_type, aggregate_id, event_type, payload_json)
             VALUES (?, ?, ?, ?, ?)'
        );
        $statement->execute([
            msfixit_office_bridge_uuid(),
            'woocommerce_order',
            (string) $order->get_id(),
            $eventType,
            wp_json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES),
        ]);
    } catch (Throwable $exception) {
        msfixit_office_bridge_log("Unable to queue {$eventType}: " . $exception->getMessage());
    }
}

add_action('woocommerce_payment_complete', static function (int $orderId): void {
    $order = wc_get_order($orderId);
    if ($order instanceof WC_Order) {
        msfixit_office_bridge_enqueue('woocommerce.order.paid', $order, [
            'payment' => msfixit_office_bridge_order_payload($order)['payment'],
        ]);
    }
}, 20);

add_action('woocommerce_order_status_processing', static function (int $orderId): void {
    $order = wc_get_order($orderId);
    if ($order instanceof WC_Order) {
        msfixit_office_bridge_enqueue('woocommerce.order.processing', $order);
    }
}, 20);

add_action('woocommerce_order_status_completed', static function (int $orderId): void {
    $order = wc_get_order($orderId);
    if ($order instanceof WC_Order) {
        msfixit_office_bridge_enqueue('woocommerce.order.completed', $order);
    }
}, 20);

add_action('woocommerce_order_refunded', static function (int $orderId, int $refundId): void {
    $order = wc_get_order($orderId);
    $refund = wc_get_order($refundId);
    if ($order instanceof WC_Order && $refund instanceof WC_Order_Refund) {
        msfixit_office_bridge_enqueue('woocommerce.order.refunded', $order, [
            'refund' => msfixit_office_bridge_refund_payload($order, $refund),
        ]);
    }
}, 20, 2);

add_action('woocommerce_product_options_shipping', static function (): void {
    woocommerce_wp_text_input([
        'id' => '_msfixit_hs_code',
        'label' => 'Zolltarifnummer (HS-Code)',
        'description' => 'Für Sendungen in die Schweiz und andere Drittländer. Nicht raten; anhand der tatsächlichen Ware prüfen.',
        'desc_tip' => true,
    ]);
    woocommerce_wp_text_input([
        'id' => '_msfixit_origin_country',
        'label' => 'Ursprungsland',
        'description' => 'ISO-Ländercode der Warenherkunft, zum Beispiel AT, DE oder CN.',
        'desc_tip' => true,
        'custom_attributes' => ['maxlength' => '2', 'pattern' => '[A-Za-z]{2}'],
    ]);
});

add_action('woocommerce_admin_process_product_object', static function (WC_Product $product): void {
    if (isset($_POST['_msfixit_hs_code'])) {
        $product->update_meta_data('_msfixit_hs_code', sanitize_text_field(wp_unslash($_POST['_msfixit_hs_code'])));
    }
    if (isset($_POST['_msfixit_origin_country'])) {
        $country = strtoupper(sanitize_text_field(wp_unslash($_POST['_msfixit_origin_country'])));
        $product->update_meta_data('_msfixit_origin_country', preg_match('/^[A-Z]{2}$/', $country) ? $country : '');
    }
});

add_action('phpmailer_init', static function (PHPMailer\PHPMailer\PHPMailer $phpmailer): void {
    $config = msfixit_office_bridge_env(MSFIXIT_OFFICE_BUSINESS_ENV);
    if (!in_array(strtolower((string) ($config['SMTP_ENABLED'] ?? 'no')), ['yes', 'true', '1', 'on'], true)) {
        return;
    }
    $host = trim((string) ($config['SMTP_HOST'] ?? ''));
    $username = trim((string) ($config['SMTP_USERNAME'] ?? ''));
    if ($host === '' || $username === '') {
        msfixit_office_bridge_log('SMTP is enabled but host or username is missing');
        return;
    }
    $phpmailer->isSMTP();
    $phpmailer->Host = $host;
    $phpmailer->Port = max(1, (int) ($config['SMTP_PORT'] ?? 587));
    $phpmailer->SMTPAuth = true;
    $phpmailer->Username = $username;
    $phpmailer->Password = (string) ($config['SMTP_PASSWORD'] ?? '');
    $security = strtolower((string) ($config['SMTP_SECURITY'] ?? 'tls'));
    if (in_array($security, ['tls', 'ssl'], true)) {
        $phpmailer->SMTPSecure = $security;
    }
    $fromEmail = trim((string) ($config['SMTP_FROM_EMAIL'] ?? ''));
    if ($fromEmail !== '') {
        $phpmailer->setFrom($fromEmail, (string) ($config['SMTP_FROM_NAME'] ?? 'Ms. FixIT'), false);
    }
});

add_action('wp_dashboard_setup', static function (): void {
    wp_add_dashboard_widget(
        'msfixit_office_status',
        'Ms. FixIT – Rechnung, Mahnung & Versand',
        static function (): void {
            $pdo = msfixit_office_bridge_database();
            if (!$pdo) {
                echo '<p><strong>Status:</strong> Office-Datenbank noch nicht verfügbar.</p>';
                return;
            }
            try {
                $drafts = (int) $pdo->query("SELECT COUNT(*) FROM office_documents WHERE document_status='draft'")->fetchColumn();
                $open = (int) $pdo->query("SELECT COUNT(*) FROM office_documents d WHERE d.document_type='invoice' AND d.document_status='final' AND d.gross_total > COALESCE((SELECT SUM(a.allocated_amount) FROM office_payment_allocations a WHERE a.document_id=d.id),0)")->fetchColumn();
                $reminders = (int) $pdo->query("SELECT COUNT(*) FROM office_reminders WHERE reminder_status='pending_approval'")->fetchColumn();
                $shipments = (int) $pdo->query("SELECT COUNT(*) FROM office_shipments WHERE shipment_status='draft'")->fetchColumn();
                $exports = (int) $pdo->query("SELECT COUNT(*) FROM office_prosaldo_exports WHERE marked_imported_at IS NULL")->fetchColumn();
                $config = msfixit_office_bridge_env(MSFIXIT_OFFICE_BUSINESS_ENV);
                $approved = strtolower((string) ($config['BUSINESS_CONFIG_APPROVED'] ?? 'no')) === 'yes';
                echo '<p><strong>Belegkonfiguration:</strong> ' . ($approved ? 'freigegeben' : 'noch gesperrt – Geschäftsdaten und Steuerprofil prüfen') . '</p>';
                echo '<ul>';
                echo '<li>Belegentwürfe: ' . esc_html((string) $drafts) . '</li>';
                echo '<li>Offene Rechnungen: ' . esc_html((string) $open) . '</li>';
                echo '<li>Mahnungen zur Freigabe: ' . esc_html((string) $reminders) . '</li>';
                echo '<li>Sendungen ohne Label: ' . esc_html((string) $shipments) . '</li>';
                echo '<li>ProSaldo-Übergaben noch nicht bestätigt: ' . esc_html((string) $exports) . '</li>';
                echo '</ul>';
                echo '<p><small>Automatische Gebühren, Verzugszinsen und Versanddienstleister bleiben deaktiviert, bis Regeln beziehungsweise Verträge ausdrücklich eingerichtet wurden.</small></p>';
            } catch (Throwable $exception) {
                echo '<p>Office-Status konnte nicht gelesen werden.</p>';
                msfixit_office_bridge_log($exception->getMessage());
            }
        }
    );
});
