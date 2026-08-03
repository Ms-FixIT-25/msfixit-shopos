<?php

declare(strict_types=1);

const MSFIXIT_OFFICE_ADMIN_ENV = '/etc/msfixit-shopos/office.env';
const MSFIXIT_OFFICE_WORKER_ENV = '/etc/msfixit-shopos/office-worker.env';
const MSFIXIT_BUSINESS_ENV = '/etc/msfixit-shopos/business.env';
const MSFIXIT_OFFICE_DATA = '/data/office';
const MSFIXIT_WORDPRESS_ROOT = '/srv/www/wordpress';

function office_read_env(string $path): array
{
    if (!is_file($path) || !is_readable($path)) {
        throw new RuntimeException("Configuration is unavailable: {$path}");
    }

    $settings = [];
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

    return $settings;
}

function office_database(string $envPath = MSFIXIT_OFFICE_ADMIN_ENV): PDO
{
    static $connections = [];
    if (isset($connections[$envPath]) && $connections[$envPath] instanceof PDO) {
        return $connections[$envPath];
    }

    $env = office_read_env($envPath);
    foreach (['OFFICE_DB_HOST', 'OFFICE_DB_PORT', 'OFFICE_DB_NAME', 'OFFICE_DB_USER', 'OFFICE_DB_PASSWORD'] as $key) {
        if (!isset($env[$key]) || $env[$key] === '') {
            throw new RuntimeException("Missing office database setting: {$key}");
        }
    }

    $dsn = sprintf(
        'mysql:host=%s;port=%s;dbname=%s;charset=utf8mb4',
        $env['OFFICE_DB_HOST'],
        $env['OFFICE_DB_PORT'],
        $env['OFFICE_DB_NAME']
    );

    $connections[$envPath] = new PDO($dsn, $env['OFFICE_DB_USER'], $env['OFFICE_DB_PASSWORD'], [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        PDO::ATTR_EMULATE_PREPARES => false,
    ]);

    return $connections[$envPath];
}

function office_business_config(): array
{
    return office_read_env(MSFIXIT_BUSINESS_ENV);
}

function office_bool(mixed $value): bool
{
    return in_array(strtolower(trim((string) $value)), ['1', 'yes', 'true', 'on', 'ja'], true);
}

function office_uuid(): string
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

function office_json(mixed $value): string
{
    return json_encode($value, JSON_THROW_ON_ERROR | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
}

function office_decode_json(mixed $value): array
{
    if (is_array($value)) {
        return $value;
    }
    if (!is_string($value) || trim($value) === '') {
        return [];
    }
    $decoded = json_decode($value, true, 512, JSON_THROW_ON_ERROR);
    return is_array($decoded) ? $decoded : [];
}

function office_money(mixed $value): float
{
    return round((float) $value, 4);
}

function office_html(mixed $value): string
{
    return htmlspecialchars((string) $value, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}

function office_document_label(string $type): string
{
    return match ($type) {
        'invoice' => 'Rechnung',
        'credit_note' => 'Gutschrift',
        'delivery_note' => 'Lieferschein',
        'commercial_invoice' => 'Handelsrechnung',
        'proforma_invoice' => 'Proformarechnung',
        default => ucfirst(str_replace('_', ' ', $type)),
    };
}

function office_document_folder(string $type): string
{
    return match ($type) {
        'invoice' => 'invoices',
        'credit_note' => 'credit-notes',
        'delivery_note' => 'delivery-notes',
        'commercial_invoice', 'proforma_invoice' => 'customs',
        default => 'archive',
    };
}

function office_document_prefix(string $type, array $config): string
{
    $key = match ($type) {
        'invoice' => 'INVOICE_PREFIX',
        'credit_note' => 'CREDIT_NOTE_PREFIX',
        'delivery_note' => 'DELIVERY_NOTE_PREFIX',
        'commercial_invoice' => 'CUSTOMS_INVOICE_PREFIX',
        'proforma_invoice' => 'PROFORMA_PREFIX',
        default => throw new InvalidArgumentException("Unsupported document type: {$type}"),
    };

    $fallback = match ($type) {
        'invoice' => 'RE',
        'credit_note' => 'GU',
        'delivery_note' => 'LS',
        'commercial_invoice' => 'HR',
        'proforma_invoice' => 'PR',
        default => 'DO',
    };

    $prefix = strtoupper(trim((string) ($config[$key] ?? $fallback)));
    if (!preg_match('/^[A-Z0-9-]{1,12}$/', $prefix)) {
        throw new RuntimeException("Invalid document prefix in {$key}");
    }
    return $prefix;
}

function office_alloc_number(PDO $pdo, string $sequenceName, string $prefix, DateTimeImmutable $date): string
{
    $year = (int) $date->format('Y');
    $insert = $pdo->prepare(
        'INSERT IGNORE INTO office_sequences (sequence_name, sequence_year, next_value) VALUES (?, ?, 1)'
    );
    $insert->execute([$sequenceName, $year]);

    $select = $pdo->prepare(
        'SELECT next_value FROM office_sequences WHERE sequence_name = ? AND sequence_year = ? FOR UPDATE'
    );
    $select->execute([$sequenceName, $year]);
    $next = $select->fetchColumn();
    if ($next === false) {
        throw new RuntimeException("Sequence is unavailable: {$sequenceName}/{$year}");
    }

    $number = (int) $next;
    if ($number < 1 || $number > 999999) {
        throw new RuntimeException("Sequence range exhausted: {$sequenceName}/{$year}");
    }

    $update = $pdo->prepare(
        'UPDATE office_sequences SET next_value = next_value + 1 WHERE sequence_name = ? AND sequence_year = ?'
    );
    $update->execute([$sequenceName, $year]);

    return sprintf('%s-%04d-%06d', $prefix, $year, $number);
}

function office_emit(PDO $pdo, string $aggregateType, string $aggregateId, string $eventType, array $payload): void
{
    $statement = $pdo->prepare(
        'INSERT INTO office_outbox
         (event_uuid, aggregate_type, aggregate_id, event_type, payload_json)
         VALUES (?, ?, ?, ?, ?)'
    );
    $statement->execute([
        office_uuid(),
        $aggregateType,
        $aggregateId,
        $eventType,
        office_json($payload),
    ]);
}

function office_business_missing(array $config): array
{
    $required = [
        'BUSINESS_LEGAL_NAME',
        'BUSINESS_STREET',
        'BUSINESS_POSTCODE',
        'BUSINESS_CITY',
        'BUSINESS_COUNTRY',
        'BUSINESS_EMAIL',
        'BUSINESS_IBAN',
    ];
    $missing = [];
    foreach ($required as $key) {
        if (trim((string) ($config[$key] ?? '')) === '') {
            $missing[] = $key;
        }
    }
    if (!office_bool($config['BUSINESS_CONFIG_APPROVED'] ?? 'no')) {
        $missing[] = 'BUSINESS_CONFIG_APPROVED=yes';
    }
    return $missing;
}

function office_tax_mode_for_country(array $config, string $country): string
{
    $country = strtoupper(trim($country));
    $specific = trim((string) ($config['TAX_MODE_' . $country] ?? ''));
    if ($specific !== '') {
        return $specific;
    }
    return trim((string) ($config['DEFAULT_TAX_MODE'] ?? 'review_required')) ?: 'review_required';
}

function office_customer_name(array $billing): string
{
    $company = trim((string) ($billing['company'] ?? ''));
    if ($company !== '') {
        return $company;
    }
    $name = trim(implode(' ', array_filter([
        trim((string) ($billing['first_name'] ?? '')),
        trim((string) ($billing['last_name'] ?? '')),
    ])));
    return $name !== '' ? $name : 'Unbekannte Kundschaft';
}

function office_upsert_order(PDO $pdo, array $payload): string
{
    $sourceSystem = trim((string) ($payload['source_system'] ?? 'woocommerce')) ?: 'woocommerce';
    $sourceOrderId = trim((string) ($payload['source_order_id'] ?? ''));
    if ($sourceOrderId === '') {
        throw new InvalidArgumentException('source_order_id is required');
    }

    $select = $pdo->prepare(
        'SELECT id FROM office_orders WHERE source_system = ? AND source_order_id = ?'
    );
    $select->execute([$sourceSystem, $sourceOrderId]);
    $id = $select->fetchColumn();

    $billing = office_decode_json($payload['billing'] ?? []);
    $shipping = office_decode_json($payload['shipping'] ?? []);
    $totals = office_decode_json($payload['totals'] ?? []);
    $metadata = office_decode_json($payload['metadata'] ?? []);
    $customerType = trim((string) ($payload['customer_type'] ?? 'consumer')) ?: 'consumer';
    $currency = strtoupper(trim((string) ($payload['currency'] ?? 'EUR'))) ?: 'EUR';

    if ($id === false) {
        $id = office_uuid();
        $insert = $pdo->prepare(
            'INSERT INTO office_orders
             (id, source_system, source_order_id, source_order_number, order_status,
              customer_type, billing_country, shipping_country, currency,
              billing_json, shipping_json, totals_json, metadata_json)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'
        );
        $insert->execute([
            $id,
            $sourceSystem,
            $sourceOrderId,
            (string) ($payload['source_order_number'] ?? $sourceOrderId),
            (string) ($payload['order_status'] ?? 'unknown'),
            $customerType,
            strtoupper((string) ($billing['country'] ?? '')) ?: null,
            strtoupper((string) ($shipping['country'] ?? $billing['country'] ?? '')) ?: null,
            $currency,
            office_json($billing),
            office_json($shipping),
            office_json($totals),
            office_json($metadata),
        ]);
    } else {
        $update = $pdo->prepare(
            'UPDATE office_orders SET
                source_order_number = ?, order_status = ?, customer_type = ?,
                billing_country = ?, shipping_country = ?, currency = ?,
                billing_json = ?, shipping_json = ?, totals_json = ?, metadata_json = ?
             WHERE id = ?'
        );
        $update->execute([
            (string) ($payload['source_order_number'] ?? $sourceOrderId),
            (string) ($payload['order_status'] ?? 'unknown'),
            $customerType,
            strtoupper((string) ($billing['country'] ?? '')) ?: null,
            strtoupper((string) ($shipping['country'] ?? $billing['country'] ?? '')) ?: null,
            $currency,
            office_json($billing),
            office_json($shipping),
            office_json($totals),
            office_json($metadata),
            $id,
        ]);
    }

    return (string) $id;
}

function office_create_document(PDO $pdo, string $type, array $payload): string
{
    $allowed = ['invoice', 'credit_note', 'delivery_note', 'commercial_invoice', 'proforma_invoice'];
    if (!in_array($type, $allowed, true)) {
        throw new InvalidArgumentException("Unsupported document type: {$type}");
    }

    $orderId = office_upsert_order($pdo, $payload);
    $sourceSystem = trim((string) ($payload['source_system'] ?? 'woocommerce')) ?: 'woocommerce';
    $sourceDocumentId = trim((string) ($payload['source_document_id'] ?? $payload['source_order_id'] ?? ''));
    if ($sourceDocumentId === '') {
        throw new InvalidArgumentException('source_document_id is required');
    }

    $existing = $pdo->prepare(
        'SELECT id FROM office_documents
         WHERE source_system = ? AND source_document_id = ? AND document_type = ?'
    );
    $existing->execute([$sourceSystem, $sourceDocumentId, $type]);
    $existingId = $existing->fetchColumn();
    if ($existingId !== false) {
        return (string) $existingId;
    }

    $config = office_business_config();
    $billing = office_decode_json($payload['billing'] ?? []);
    $shipping = office_decode_json($payload['shipping'] ?? $billing);
    $totals = office_decode_json($payload['totals'] ?? []);
    $lines = office_decode_json($payload['lines'] ?? []);
    $country = strtoupper((string) ($billing['country'] ?? $shipping['country'] ?? 'AT'));
    $taxMode = trim((string) ($payload['tax_mode'] ?? ''));
    if ($taxMode === '') {
        $taxMode = office_tax_mode_for_country($config, $country);
    }

    $issueDate = new DateTimeImmutable((string) ($payload['issue_date'] ?? 'today'));
    $paymentDays = max(0, (int) ($config['INVOICE_PAYMENT_DAYS'] ?? 14));
    $dueDate = $type === 'invoice'
        ? $issueDate->modify("+{$paymentDays} days")->format('Y-m-d')
        : null;

    $id = office_uuid();
    $pdo->beginTransaction();
    try {
        $insert = $pdo->prepare(
            'INSERT INTO office_documents
             (id, order_id, document_type, document_status, language_code, currency,
              tax_mode, issue_date, service_date, due_date, customer_type,
              customer_name, customer_email, billing_json, shipping_json,
              net_total, tax_total, gross_total, source_system, source_document_id,
              correction_of_id, snapshot_json)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'
        );
        $insert->execute([
            $id,
            $orderId,
            $type,
            'draft',
            (string) ($payload['language_code'] ?? $config['INVOICE_LANGUAGE'] ?? 'de_AT'),
            strtoupper((string) ($payload['currency'] ?? $config['INVOICE_CURRENCY'] ?? 'EUR')),
            $taxMode,
            $issueDate->format('Y-m-d'),
            (string) ($payload['service_date'] ?? $issueDate->format('Y-m-d')),
            $dueDate,
            (string) ($payload['customer_type'] ?? 'consumer'),
            office_customer_name($billing),
            (string) ($billing['email'] ?? $payload['customer_email'] ?? ''),
            office_json($billing),
            office_json($shipping),
            office_money($totals['net'] ?? 0),
            office_money($totals['tax'] ?? 0),
            office_money($totals['gross'] ?? 0),
            $sourceSystem,
            $sourceDocumentId,
            $payload['correction_of_id'] ?? null,
            office_json($payload),
        ]);

        $lineInsert = $pdo->prepare(
            'INSERT INTO office_document_lines
             (document_id, line_number, article_number, description, quantity, unit,
              unit_net, tax_rate, line_net, line_tax, line_gross, metadata_json)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'
        );
        $lineNumber = 0;
        foreach ($lines as $line) {
            if (!is_array($line)) {
                continue;
            }
            $lineNumber++;
            $lineInsert->execute([
                $id,
                $lineNumber,
                trim((string) ($line['article_number'] ?? '')) ?: null,
                trim((string) ($line['description'] ?? 'Artikel')),
                office_money($line['quantity'] ?? 1),
                trim((string) ($line['unit'] ?? 'Stk')) ?: 'Stk',
                office_money($line['unit_net'] ?? 0),
                office_money($line['tax_rate'] ?? 0),
                office_money($line['line_net'] ?? 0),
                office_money($line['line_tax'] ?? 0),
                office_money($line['line_gross'] ?? 0),
                office_json(office_decode_json($line['metadata'] ?? [])),
            ]);
        }

        $hold = $pdo->prepare(
            'INSERT IGNORE INTO office_document_holds (document_id) VALUES (?)'
        );
        $hold->execute([$id]);

        office_emit($pdo, 'document', $id, 'document.created', [
            'document_id' => $id,
            'document_type' => $type,
            'source_system' => $sourceSystem,
            'source_document_id' => $sourceDocumentId,
        ]);

        $pdo->commit();
        return $id;
    } catch (Throwable $exception) {
        if ($pdo->inTransaction()) {
            $pdo->rollBack();
        }
        throw $exception;
    }
}

function office_get_document(PDO $pdo, string $identifier): array
{
    $statement = $pdo->prepare(
        'SELECT d.*, o.source_order_number,
                COALESCE(SUM(a.allocated_amount), 0) AS allocated_amount
         FROM office_documents d
         LEFT JOIN office_orders o ON o.id = d.order_id
         LEFT JOIN office_payment_allocations a ON a.document_id = d.id
         WHERE d.id = ? OR d.document_number = ?
         GROUP BY d.id'
    );
    $statement->execute([$identifier, $identifier]);
    $document = $statement->fetch();
    if (!$document) {
        throw new RuntimeException("Office document not found: {$identifier}");
    }
    $document['open_amount'] = round(
        (float) $document['gross_total'] - (float) $document['allocated_amount'],
        4
    );
    return $document;
}

function office_get_lines(PDO $pdo, string $documentId): array
{
    $statement = $pdo->prepare(
        'SELECT * FROM office_document_lines WHERE document_id = ? ORDER BY line_number'
    );
    $statement->execute([$documentId]);
    return $statement->fetchAll();
}

function office_tcpdf_bootstrap(): void
{
    if (class_exists('TCPDF')) {
        return;
    }
    $candidates = [
        '/usr/share/php/tcpdf/tcpdf.php',
        '/usr/share/php/tcpdf.php',
        '/usr/share/php/TCPDF/tcpdf.php',
    ];
    foreach ($candidates as $candidate) {
        if (is_file($candidate)) {
            require_once $candidate;
            break;
        }
    }
    if (!class_exists('TCPDF')) {
        throw new RuntimeException('TCPDF is not installed or could not be loaded');
    }
}

function office_address_html(array $address): string
{
    $name = office_customer_name($address);
    $parts = [];
    if ($name !== '') {
        $parts[] = office_html($name);
    }
    foreach (['address_1', 'address_2'] as $key) {
        if (trim((string) ($address[$key] ?? '')) !== '') {
            $parts[] = office_html($address[$key]);
        }
    }
    $city = trim(implode(' ', array_filter([
        trim((string) ($address['postcode'] ?? '')),
        trim((string) ($address['city'] ?? '')),
    ])));
    if ($city !== '') {
        $parts[] = office_html($city);
    }
    if (trim((string) ($address['country'] ?? '')) !== '') {
        $parts[] = office_html(strtoupper((string) $address['country']));
    }
    return implode('<br>', $parts);
}

function office_render_document(PDO $pdo, array $document, array $config): array
{
    office_tcpdf_bootstrap();
    $lines = office_get_lines($pdo, $document['id']);
    $billing = office_decode_json($document['billing_json']);
    $shipping = office_decode_json($document['shipping_json']);
    $type = (string) $document['document_type'];
    $label = office_document_label($type);
    $number = (string) $document['document_number'];
    $currency = (string) $document['currency'];

    $pdf = new TCPDF('P', 'mm', 'A4', true, 'UTF-8', false);
    $pdf->SetCreator('Ms. FixIT ShopOS');
    $pdf->SetAuthor((string) ($config['BUSINESS_LEGAL_NAME'] ?? $config['BUSINESS_NAME'] ?? 'Ms. FixIT'));
    $pdf->SetTitle("{$label} {$number}");
    $pdf->setPrintHeader(false);
    $pdf->setPrintFooter(false);
    $pdf->SetMargins(16, 14, 16);
    $pdf->SetAutoPageBreak(true, 18);
    $pdf->AddPage();
    $pdf->SetFont('dejavusans', '', 9);

    $businessName = office_html($config['BUSINESS_LEGAL_NAME'] ?? $config['BUSINESS_NAME'] ?? 'Ms. FixIT');
    $businessAddress = office_html($config['BUSINESS_STREET'] ?? '') . '<br>'
        . office_html(trim(($config['BUSINESS_POSTCODE'] ?? '') . ' ' . ($config['BUSINESS_CITY'] ?? ''))) . '<br>'
        . office_html($config['BUSINESS_COUNTRY'] ?? 'AT');

    $recipient = $type === 'delivery_note' && !empty($shipping) ? $shipping : $billing;
    $metaRows = [
        ['Belegnummer', $number],
        ['Belegdatum', date('d.m.Y', strtotime((string) $document['issue_date']))],
    ];
    if (!empty($document['service_date'])) {
        $metaRows[] = ['Liefer-/Leistungsdatum', date('d.m.Y', strtotime((string) $document['service_date']))];
    }
    if ($type === 'invoice' && !empty($document['due_date'])) {
        $metaRows[] = ['Zahlbar bis', date('d.m.Y', strtotime((string) $document['due_date']))];
    }
    if (!empty($document['source_order_number'])) {
        $metaRows[] = ['Bestellung', (string) $document['source_order_number']];
    }

    $metaHtml = '';
    foreach ($metaRows as [$key, $value]) {
        $metaHtml .= '<tr><td style="width:42%;color:#52657a">' . office_html($key) . '</td>'
            . '<td style="width:58%;font-weight:bold">' . office_html($value) . '</td></tr>';
    }

    $lineHtml = '';
    foreach ($lines as $line) {
        $quantity = rtrim(rtrim(number_format((float) $line['quantity'], 3, ',', '.'), '0'), ',');
        if ($type === 'delivery_note') {
            $lineHtml .= '<tr>'
                . '<td style="width:8%;text-align:right">' . (int) $line['line_number'] . '</td>'
                . '<td style="width:18%">' . office_html($line['article_number'] ?? '') . '</td>'
                . '<td style="width:52%">' . nl2br(office_html($line['description'])) . '</td>'
                . '<td style="width:22%;text-align:right">' . office_html($quantity . ' ' . $line['unit']) . '</td>'
                . '</tr>';
        } else {
            $lineHtml .= '<tr>'
                . '<td style="width:6%;text-align:right">' . (int) $line['line_number'] . '</td>'
                . '<td style="width:15%">' . office_html($line['article_number'] ?? '') . '</td>'
                . '<td style="width:35%">' . nl2br(office_html($line['description'])) . '</td>'
                . '<td style="width:12%;text-align:right">' . office_html($quantity . ' ' . $line['unit']) . '</td>'
                . '<td style="width:14%;text-align:right">' . number_format((float) $line['unit_net'], 2, ',', '.') . '</td>'
                . '<td style="width:8%;text-align:right">' . number_format((float) $line['tax_rate'], 2, ',', '.') . '%</td>'
                . '<td style="width:10%;text-align:right">' . number_format((float) $line['line_gross'], 2, ',', '.') . '</td>'
                . '</tr>';
        }
    }

    $tableHead = $type === 'delivery_note'
        ? '<tr style="font-weight:bold;background-color:#eaf7f8"><th style="width:8%;text-align:right">Pos.</th><th style="width:18%">Waren-Nr.</th><th style="width:52%">Bezeichnung</th><th style="width:22%;text-align:right">Menge</th></tr>'
        : '<tr style="font-weight:bold;background-color:#eaf7f8"><th style="width:6%;text-align:right">Pos.</th><th style="width:15%">Waren-Nr.</th><th style="width:35%">Bezeichnung</th><th style="width:12%;text-align:right">Menge</th><th style="width:14%;text-align:right">Einzel netto</th><th style="width:8%;text-align:right">USt.</th><th style="width:10%;text-align:right">Brutto</th></tr>';

    $totalsHtml = '';
    if ($type !== 'delivery_note') {
        $totalsHtml = '<table cellpadding="4" style="margin-top:10px">'
            . '<tr><td style="width:70%"></td><td style="width:18%">Netto</td><td style="width:12%;text-align:right">' . number_format((float) $document['net_total'], 2, ',', '.') . ' ' . office_html($currency) . '</td></tr>'
            . '<tr><td style="width:70%"></td><td style="width:18%">Umsatzsteuer</td><td style="width:12%;text-align:right">' . number_format((float) $document['tax_total'], 2, ',', '.') . ' ' . office_html($currency) . '</td></tr>'
            . '<tr style="font-weight:bold;background-color:#fff0f7"><td style="width:70%"></td><td style="width:18%">Gesamt</td><td style="width:12%;text-align:right">' . number_format((float) $document['gross_total'], 2, ',', '.') . ' ' . office_html($currency) . '</td></tr>'
            . '</table>';
    }

    $taxNotice = '';
    if (in_array($document['tax_mode'], ['at_small_business_exempt', 'eu_small_business_exempt'], true)) {
        $taxNotice = '<p style="margin-top:8px"><strong>'
            . office_html($config['SMALL_BUSINESS_NOTICE'] ?? 'Umsatzsteuerbefreit aufgrund der Kleinunternehmerregelung.')
            . '</strong></p>';
    } elseif ($document['tax_mode'] === 'export_third_country') {
        $taxNotice = '<p style="margin-top:8px"><strong>Steuerfreie Ausfuhrlieferung; Zoll- und Einfuhrabgaben können beim Empfänger anfallen.</strong></p>';
    }

    $paymentHtml = '';
    if ($type === 'invoice') {
        $paymentHtml = '<p><strong>Zahlungsinformation:</strong><br>'
            . 'IBAN: ' . office_html($config['BUSINESS_IBAN'] ?? '')
            . (!empty($config['BUSINESS_BIC']) ? '<br>BIC: ' . office_html($config['BUSINESS_BIC']) : '')
            . '<br>Verwendungszweck: ' . office_html($number)
            . '</p>';
    }

    $footerParts = array_filter([
        $config['BUSINESS_EMAIL'] ?? '',
        $config['BUSINESS_PHONE'] ?? '',
        $config['BUSINESS_WEBSITE'] ?? '',
        !empty($config['BUSINESS_VAT_ID']) ? 'UID: ' . $config['BUSINESS_VAT_ID'] : '',
        !empty($config['BUSINESS_TAX_NUMBER']) ? 'St.Nr.: ' . $config['BUSINESS_TAX_NUMBER'] : '',
        !empty($config['BUSINESS_COMPANY_REGISTER']) ? 'Firmenbuch: ' . $config['BUSINESS_COMPANY_REGISTER'] : '',
    ]);

    $html = '<style>
        h1{color:#10243f;font-size:24px;margin:0 0 8px 0}
        h2{color:#10243f;font-size:15px}
        table{border-collapse:collapse}
        th,td{border-bottom:0.2mm solid #d7e2ea}
        .small{font-size:8px;color:#52657a}
        </style>'
        . '<table cellpadding="2"><tr><td style="width:60%"><div style="font-size:17px;font-weight:bold;color:#10243f">' . $businessName . '</div>'
        . '<div class="small">' . $businessAddress . '</div></td>'
        . '<td style="width:40%;text-align:right"><h1>' . office_html($label) . '</h1></td></tr></table>'
        . '<table cellpadding="4" style="margin-top:12px"><tr><td style="width:58%"><div class="small">Empfänger</div>'
        . '<div style="font-size:11px">' . office_address_html($recipient) . '</div></td>'
        . '<td style="width:42%"><table cellpadding="2">' . $metaHtml . '</table></td></tr></table>'
        . '<div style="height:10px"></div>'
        . '<table cellpadding="4">' . $tableHead . $lineHtml . '</table>'
        . $totalsHtml . $taxNotice . $paymentHtml;

    if ($type === 'delivery_note') {
        $html .= '<p style="margin-top:16px">Bitte Lieferung auf Vollständigkeit und sichtbare Transportschäden prüfen.</p>';
    }

    $html .= '<div style="height:16px"></div><div class="small" style="border-top:0.3mm solid #2bbbc0;padding-top:4px">'
        . office_html(implode(' · ', $footerParts)) . '</div>';

    $pdf->writeHTML($html, true, false, true, false, '');

    $year = date('Y', strtotime((string) $document['issue_date']));
    $directory = MSFIXIT_OFFICE_DATA . '/documents/' . office_document_folder($type) . '/' . $year;
    if (!is_dir($directory) && !mkdir($directory, 0750, true) && !is_dir($directory)) {
        throw new RuntimeException("Unable to create document directory: {$directory}");
    }
    $path = $directory . '/' . preg_replace('/[^A-Za-z0-9._-]/', '_', $number) . '.pdf';
    $pdf->Output($path, 'F');
    chmod($path, 0640);

    $hash = hash_file('sha256', $path);
    if ($hash === false) {
        throw new RuntimeException("Unable to hash generated PDF: {$path}");
    }
    return ['path' => $path, 'sha256' => $hash];
}

function office_finalize_document(PDO $pdo, string $identifier): array
{
    $config = office_business_config();
    $missing = office_business_missing($config);
    if ($missing !== []) {
        throw new RuntimeException('Business configuration is incomplete: ' . implode(', ', $missing));
    }

    $document = office_get_document($pdo, $identifier);
    if ($document['document_status'] === 'final') {
        return $document;
    }
    if (in_array($document['document_type'], ['invoice', 'credit_note', 'commercial_invoice'], true)
        && $document['tax_mode'] === 'review_required') {
        throw new RuntimeException('Tax mode still requires review; finalization is blocked');
    }

    $date = new DateTimeImmutable((string) ($document['issue_date'] ?: 'today'));
    $pdo->beginTransaction();
    try {
        $number = $document['document_number'];
        if (!$number) {
            $prefix = office_document_prefix((string) $document['document_type'], $config);
            $number = office_alloc_number($pdo, (string) $document['document_type'], $prefix, $date);
        }
        $update = $pdo->prepare(
            "UPDATE office_documents
             SET document_number = ?, document_status = 'rendering', issue_date = COALESCE(issue_date, ?)
             WHERE id = ?"
        );
        $update->execute([$number, $date->format('Y-m-d'), $document['id']]);
        $pdo->commit();
    } catch (Throwable $exception) {
        if ($pdo->inTransaction()) {
            $pdo->rollBack();
        }
        throw $exception;
    }

    $document = office_get_document($pdo, (string) $document['id']);
    try {
        $rendered = office_render_document($pdo, $document, $config);
        $final = $pdo->prepare(
            "UPDATE office_documents
             SET document_status = 'final', pdf_path = ?, pdf_sha256 = ?, finalized_at = CURRENT_TIMESTAMP
             WHERE id = ?"
        );
        $final->execute([$rendered['path'], $rendered['sha256'], $document['id']]);

        office_emit($pdo, 'document', (string) $document['id'], 'document.finalized', [
            'document_id' => $document['id'],
            'document_number' => $document['document_number'],
            'document_type' => $document['document_type'],
            'pdf_path' => $rendered['path'],
            'pdf_sha256' => $rendered['sha256'],
        ]);

        $autoPrintKey = match ($document['document_type']) {
            'invoice' => 'AUTO_PRINT_INVOICES',
            'delivery_note' => 'AUTO_PRINT_DELIVERY_NOTES',
            default => '',
        };
        if ($autoPrintKey !== '' && office_bool($config[$autoPrintKey] ?? 'no')) {
            $printer = trim((string) ($config['PRINTER_A4'] ?? ''));
            if ($printer !== '') {
                office_queue_print($pdo, 'document', (string) $document['id'], $rendered['path'], $printer);
            }
        }

        if ($document['document_type'] === 'invoice' && office_bool($config['AUTO_SEND_INVOICES'] ?? 'no')) {
            office_emit($pdo, 'document', (string) $document['id'], 'dispatch.document.email', [
                'document_id' => $document['id'],
            ]);
        }
    } catch (Throwable $exception) {
        $error = $pdo->prepare("UPDATE office_documents SET document_status = 'render_error' WHERE id = ?");
        $error->execute([$document['id']]);
        throw $exception;
    }

    return office_get_document($pdo, (string) $document['id']);
}

function office_record_payment(PDO $pdo, string $documentIdentifier, array $payment): array
{
    $document = office_get_document($pdo, $documentIdentifier);
    if ($document['document_type'] !== 'invoice') {
        throw new RuntimeException('Payments can currently be allocated only to invoices');
    }

    $amount = office_money($payment['amount'] ?? 0);
    if ($amount <= 0) {
        throw new InvalidArgumentException('Payment amount must be greater than zero');
    }
    $source = trim((string) ($payment['source'] ?? 'manual')) ?: 'manual';
    $externalId = trim((string) ($payment['external_id'] ?? ''));
    if ($externalId === '') {
        $externalId = $source . '-' . hash('sha256', office_json($payment));
    }

    $pdo->beginTransaction();
    try {
        $select = $pdo->prepare(
            'SELECT id FROM office_payments WHERE payment_source = ? AND external_payment_id = ?'
        );
        $select->execute([$source, $externalId]);
        $paymentId = $select->fetchColumn();
        if ($paymentId === false) {
            $paymentId = office_uuid();
            $insert = $pdo->prepare(
                'INSERT INTO office_payments
                 (id, payment_source, external_payment_id, paid_at, amount, currency,
                  payer_name, payer_reference, payment_status, raw_payload_json)
                 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'
            );
            $insert->execute([
                $paymentId,
                $source,
                $externalId,
                (string) ($payment['paid_at'] ?? date('Y-m-d H:i:s')),
                $amount,
                strtoupper((string) ($payment['currency'] ?? $document['currency'])),
                (string) ($payment['payer_name'] ?? ''),
                (string) ($payment['reference'] ?? ''),
                (string) ($payment['status'] ?? 'confirmed'),
                office_json($payment),
            ]);
        }

        $current = office_get_document($pdo, (string) $document['id']);
        $allocatable = min($amount, max(0, (float) $current['open_amount']));
        if ($allocatable > 0) {
            $allocation = $pdo->prepare(
                'INSERT INTO office_payment_allocations
                 (payment_id, document_id, allocated_amount)
                 VALUES (?, ?, ?)
                 ON DUPLICATE KEY UPDATE allocated_amount = VALUES(allocated_amount)'
            );
            $allocation->execute([$paymentId, $document['id'], $allocatable]);
        }

        office_emit($pdo, 'payment', (string) $paymentId, 'payment.recorded', [
            'payment_id' => $paymentId,
            'document_id' => $document['id'],
            'document_number' => $document['document_number'],
            'amount' => $amount,
            'allocated_amount' => $allocatable,
        ]);
        $pdo->commit();
    } catch (Throwable $exception) {
        if ($pdo->inTransaction()) {
            $pdo->rollBack();
        }
        throw $exception;
    }

    return office_get_document($pdo, (string) $document['id']);
}

function office_reminder_label(int $level): string
{
    return match ($level) {
        0 => 'Zahlungserinnerung',
        1 => '1. Mahnung',
        2 => 'Letzte Mahnung',
        default => $level . '. Mahnung',
    };
}

function office_render_reminder(PDO $pdo, array $reminder, array $document, array $config): array
{
    office_tcpdf_bootstrap();
    $pdf = new TCPDF('P', 'mm', 'A4', true, 'UTF-8', false);
    $pdf->SetCreator('Ms. FixIT ShopOS');
    $pdf->SetAuthor((string) ($config['BUSINESS_LEGAL_NAME'] ?? 'Ms. FixIT'));
    $pdf->SetTitle(office_reminder_label((int) $reminder['reminder_level']) . ' ' . $reminder['reminder_number']);
    $pdf->setPrintHeader(false);
    $pdf->setPrintFooter(false);
    $pdf->SetMargins(18, 16, 18);
    $pdf->SetAutoPageBreak(true, 18);
    $pdf->AddPage();
    $pdf->SetFont('dejavusans', '', 10);

    $billing = office_decode_json($document['billing_json']);
    $label = office_reminder_label((int) $reminder['reminder_level']);
    $friendly = (int) $reminder['reminder_level'] === 0;
    $intro = $friendly
        ? 'Bei der Durchsicht unserer offenen Posten ist uns aufgefallen, dass die folgende Rechnung noch nicht vollständig ausgeglichen ist. Vielleicht wurde die Zahlung lediglich übersehen.'
        : 'Die folgende Rechnung ist trotz Fälligkeit noch nicht vollständig ausgeglichen. Wir ersuchen um Zahlung bis zum unten angeführten Termin.';

    $html = '<style>h1{color:#10243f;font-size:22px}.box{background-color:#eaf7f8;padding:8px}.small{font-size:8px;color:#52657a}</style>'
        . '<div style="font-size:16px;font-weight:bold;color:#10243f">' . office_html($config['BUSINESS_LEGAL_NAME'] ?? 'Ms. FixIT') . '</div>'
        . '<div class="small">' . office_html($config['BUSINESS_STREET'] ?? '') . ', '
        . office_html(trim(($config['BUSINESS_POSTCODE'] ?? '') . ' ' . ($config['BUSINESS_CITY'] ?? ''))) . '</div>'
        . '<div style="height:16px"></div><div>' . office_address_html($billing) . '</div>'
        . '<div style="height:14px"></div><h1>' . office_html($label) . '</h1>'
        . '<p>' . office_html($intro) . '</p>'
        . '<table cellpadding="5" class="box">'
        . '<tr><td>Rechnung</td><td style="text-align:right;font-weight:bold">' . office_html($document['document_number']) . '</td></tr>'
        . '<tr><td>Ursprünglich fällig</td><td style="text-align:right">' . date('d.m.Y', strtotime((string) $document['due_date'])) . '</td></tr>'
        . '<tr><td>Offener Rechnungsbetrag</td><td style="text-align:right">' . number_format((float) $reminder['principal_amount'], 2, ',', '.') . ' ' . office_html($document['currency']) . '</td></tr>'
        . '<tr><td>Mahnspesen</td><td style="text-align:right">' . number_format((float) $reminder['fee_amount'], 2, ',', '.') . ' ' . office_html($document['currency']) . '</td></tr>'
        . '<tr><td>Verzugszinsen</td><td style="text-align:right">' . number_format((float) $reminder['interest_amount'], 2, ',', '.') . ' ' . office_html($document['currency']) . '</td></tr>'
        . '<tr style="font-weight:bold"><td>Gesamt offen</td><td style="text-align:right">' . number_format((float) $reminder['total_amount'], 2, ',', '.') . ' ' . office_html($document['currency']) . '</td></tr>'
        . '<tr style="font-weight:bold"><td>Neue Zahlungsfrist</td><td style="text-align:right">' . date('d.m.Y', strtotime((string) $reminder['new_due_date'])) . '</td></tr>'
        . '</table>'
        . '<p>Bitte überweisen Sie auf IBAN ' . office_html($config['BUSINESS_IBAN'] ?? '')
        . ' mit dem Verwendungszweck ' . office_html($document['document_number']) . '.</p>'
        . '<p>Falls die Zahlung bereits erfolgt ist, betrachten Sie dieses Schreiben bitte als gegenstandslos.</p>';

    $pdf->writeHTML($html, true, false, true, false, '');
    $year = date('Y', strtotime((string) $reminder['reminder_date']));
    $directory = MSFIXIT_OFFICE_DATA . '/documents/reminders/' . $year;
    if (!is_dir($directory) && !mkdir($directory, 0750, true) && !is_dir($directory)) {
        throw new RuntimeException("Unable to create reminder directory: {$directory}");
    }
    $path = $directory . '/' . preg_replace('/[^A-Za-z0-9._-]/', '_', (string) $reminder['reminder_number']) . '.pdf';
    $pdf->Output($path, 'F');
    chmod($path, 0640);
    $hash = hash_file('sha256', $path);
    if ($hash === false) {
        throw new RuntimeException('Unable to hash reminder PDF');
    }
    return ['path' => $path, 'sha256' => $hash];
}

function office_finalize_reminder(PDO $pdo, string $reminderId): array
{
    $config = office_business_config();
    $missing = office_business_missing($config);
    if ($missing !== []) {
        throw new RuntimeException('Business configuration is incomplete: ' . implode(', ', $missing));
    }

    $statement = $pdo->prepare('SELECT * FROM office_reminders WHERE id = ?');
    $statement->execute([$reminderId]);
    $reminder = $statement->fetch();
    if (!$reminder) {
        throw new RuntimeException("Reminder not found: {$reminderId}");
    }
    if (in_array($reminder['reminder_status'], ['approved', 'sent'], true) && $reminder['pdf_path']) {
        return $reminder;
    }

    $document = office_get_document($pdo, (string) $reminder['document_id']);
    $date = new DateTimeImmutable((string) $reminder['reminder_date']);
    $pdo->beginTransaction();
    try {
        $number = $reminder['reminder_number'];
        if (!$number) {
            $number = office_alloc_number(
                $pdo,
                'reminder',
                strtoupper((string) ($config['REMINDER_PREFIX'] ?? 'MA')),
                $date
            );
        }
        $update = $pdo->prepare(
            "UPDATE office_reminders
             SET reminder_number = ?, reminder_status = 'rendering', approved_at = CURRENT_TIMESTAMP
             WHERE id = ?"
        );
        $update->execute([$number, $reminderId]);
        $pdo->commit();
    } catch (Throwable $exception) {
        if ($pdo->inTransaction()) {
            $pdo->rollBack();
        }
        throw $exception;
    }

    $statement->execute([$reminderId]);
    $reminder = $statement->fetch();
    $rendered = office_render_reminder($pdo, $reminder, $document, $config);
    $finish = $pdo->prepare(
        "UPDATE office_reminders
         SET reminder_status = 'approved', pdf_path = ?, pdf_sha256 = ?
         WHERE id = ?"
    );
    $finish->execute([$rendered['path'], $rendered['sha256'], $reminderId]);

    if (office_bool($config['AUTO_SEND_REMINDERS'] ?? 'no')) {
        office_emit($pdo, 'reminder', $reminderId, 'dispatch.reminder.email', [
            'reminder_id' => $reminderId,
        ]);
    }

    $statement->execute([$reminderId]);
    return $statement->fetch();
}

function office_dunning_run(PDO $pdo, bool $dryRun = false): array
{
    $config = office_business_config();
    if (!office_bool($config['DUNNING_ENABLED'] ?? 'yes')) {
        return ['created' => [], 'skipped' => ['dunning_disabled']];
    }

    $query = $pdo->query(
        "SELECT d.*,
                COALESCE(SUM(a.allocated_amount), 0) AS allocated_amount,
                COALESCE(h.dunning_blocked, 0) AS dunning_blocked,
                h.dunning_block_reason
         FROM office_documents d
         LEFT JOIN office_payment_allocations a ON a.document_id = d.id
         LEFT JOIN office_document_holds h ON h.document_id = d.id
         WHERE d.document_type = 'invoice'
           AND d.document_status = 'final'
           AND d.due_date IS NOT NULL
           AND d.due_date < CURRENT_DATE
         GROUP BY d.id
         HAVING (d.gross_total - allocated_amount) > 0.009
         ORDER BY d.due_date, d.document_number"
    );

    $created = [];
    $skipped = [];
    $today = new DateTimeImmutable('today');

    foreach ($query->fetchAll() as $document) {
        if ((int) $document['dunning_blocked'] === 1) {
            $skipped[] = [$document['document_number'], 'blocked', $document['dunning_block_reason']];
            continue;
        }

        $levelStatement = $pdo->prepare(
            'SELECT COALESCE(MAX(reminder_level), -1) FROM office_reminders WHERE document_id = ?'
        );
        $levelStatement->execute([$document['id']]);
        $nextLevel = (int) $levelStatement->fetchColumn() + 1;

        $billing = office_decode_json($document['billing_json']);
        $country = strtoupper((string) ($billing['country'] ?? 'AT'));
        $ruleStatement = $pdo->prepare(
            'SELECT * FROM office_reminder_rules
             WHERE customer_type = ? AND country_code = ? AND reminder_level = ? AND enabled = 1'
        );
        $ruleStatement->execute([$document['customer_type'], $country, $nextLevel]);
        $rule = $ruleStatement->fetch();
        if (!$rule) {
            $skipped[] = [$document['document_number'], 'no_enabled_rule', $nextLevel];
            continue;
        }

        $dueDate = new DateTimeImmutable((string) $document['due_date']);
        $daysOverdue = (int) $dueDate->diff($today)->format('%a');
        if ($daysOverdue < (int) $rule['days_after_due']) {
            continue;
        }

        $open = round((float) $document['gross_total'] - (float) $document['allocated_amount'], 4);
        $interest = round(
            $open * ((float) $rule['annual_interest_rate'] / 100) * ($daysOverdue / 365),
            4
        );
        $fee = round((float) $rule['fixed_fee'], 4);
        $newDue = $today->modify('+' . (int) $rule['payment_period_days'] . ' days');
        $requiresApproval = (int) $rule['requires_manual_approval'] === 1;
        $status = $requiresApproval ? 'pending_approval' : 'pending';
        $id = office_uuid();

        if ($dryRun) {
            $created[] = [
                'document_number' => $document['document_number'],
                'level' => $nextLevel,
                'status' => $status,
                'principal' => $open,
                'fee' => $fee,
                'interest' => $interest,
                'new_due_date' => $newDue->format('Y-m-d'),
            ];
            continue;
        }

        $insert = $pdo->prepare(
            'INSERT IGNORE INTO office_reminders
             (id, document_id, reminder_level, reminder_status, reminder_date,
              new_due_date, principal_amount, fee_amount, interest_amount, total_amount)
             VALUES (?, ?, ?, ?, CURRENT_DATE, ?, ?, ?, ?, ?)'
        );
        $insert->execute([
            $id,
            $document['id'],
            $nextLevel,
            $status,
            $newDue->format('Y-m-d'),
            $open,
            $fee,
            $interest,
            round($open + $fee + $interest, 4),
        ]);

        if ($insert->rowCount() > 0) {
            office_emit($pdo, 'reminder', $id, 'reminder.created', [
                'reminder_id' => $id,
                'document_id' => $document['id'],
                'document_number' => $document['document_number'],
                'level' => $nextLevel,
                'requires_manual_approval' => $requiresApproval,
            ]);
            if (!$requiresApproval) {
                office_finalize_reminder($pdo, $id);
            }
            $created[] = $id;
        }
    }

    return ['created' => $created, 'skipped' => $skipped];
}

function office_load_wordpress(): void
{
    if (function_exists('wp_mail')) {
        return;
    }
    $loader = MSFIXIT_WORDPRESS_ROOT . '/wp-load.php';
    if (!is_file($loader)) {
        throw new RuntimeException('WordPress is not installed; e-mail dispatch is unavailable');
    }
    $_SERVER['HTTP_HOST'] = $_SERVER['HTTP_HOST'] ?? 'localhost';
    $_SERVER['REQUEST_METHOD'] = $_SERVER['REQUEST_METHOD'] ?? 'GET';
    require_once $loader;
    if (!function_exists('wp_mail')) {
        throw new RuntimeException('WordPress mail subsystem could not be loaded');
    }
}

function office_dispatch_document(PDO $pdo, string $documentId): void
{
    $document = office_get_document($pdo, $documentId);
    if ($document['document_status'] !== 'final' || !$document['pdf_path']) {
        throw new RuntimeException('Only finalized documents with a PDF can be sent');
    }
    $recipient = trim((string) $document['customer_email']);
    if (!filter_var($recipient, FILTER_VALIDATE_EMAIL)) {
        throw new RuntimeException('Document recipient e-mail is invalid or missing');
    }

    office_load_wordpress();
    $config = office_business_config();
    $label = office_document_label((string) $document['document_type']);
    $subject = sprintf('%s %s – %s', $label, $document['document_number'], $config['BUSINESS_NAME'] ?? 'Ms. FixIT');
    $body = sprintf(
        "Guten Tag,\n\nim Anhang erhalten Sie %s %s.\n\nFreundliche Grüße\n%s",
        strtolower($label),
        $document['document_number'],
        $config['BUSINESS_LEGAL_NAME'] ?? $config['BUSINESS_NAME'] ?? 'Ms. FixIT'
    );

    $logId = office_uuid();
    $log = $pdo->prepare(
        'INSERT INTO office_dispatch_log
         (id, document_kind, source_id, recipient, subject, attachment_sha256, dispatch_status, attempts)
         VALUES (?, ?, ?, ?, ?, ?, ?, 1)'
    );
    $log->execute([
        $logId,
        'document',
        $document['id'],
        $recipient,
        $subject,
        $document['pdf_sha256'],
        'sending',
    ]);

    $sent = wp_mail($recipient, $subject, $body, [], [$document['pdf_path']]);
    if (!$sent) {
        $failed = $pdo->prepare(
            "UPDATE office_dispatch_log SET dispatch_status = 'failed', last_error = ? WHERE id = ?"
        );
        $failed->execute(['wp_mail returned false', $logId]);
        throw new RuntimeException('WordPress could not send the document e-mail');
    }

    $pdo->prepare(
        "UPDATE office_dispatch_log SET dispatch_status = 'sent', dispatched_at = CURRENT_TIMESTAMP WHERE id = ?"
    )->execute([$logId]);
    $pdo->prepare('UPDATE office_documents SET sent_at = CURRENT_TIMESTAMP WHERE id = ?')->execute([$document['id']]);
}

function office_dispatch_reminder(PDO $pdo, string $reminderId): void
{
    $statement = $pdo->prepare(
        'SELECT r.*, d.customer_email, d.customer_name, d.document_number AS invoice_number
         FROM office_reminders r JOIN office_documents d ON d.id = r.document_id
         WHERE r.id = ?'
    );
    $statement->execute([$reminderId]);
    $reminder = $statement->fetch();
    if (!$reminder || !$reminder['pdf_path']) {
        throw new RuntimeException('Approved reminder with PDF not found');
    }
    $recipient = trim((string) $reminder['customer_email']);
    if (!filter_var($recipient, FILTER_VALIDATE_EMAIL)) {
        throw new RuntimeException('Reminder recipient e-mail is invalid or missing');
    }

    office_load_wordpress();
    $config = office_business_config();
    $subject = office_reminder_label((int) $reminder['reminder_level']) . ' zu Rechnung ' . $reminder['invoice_number'];
    $body = "Guten Tag,\n\nim Anhang finden Sie unsere " . strtolower(office_reminder_label((int) $reminder['reminder_level']))
        . " zur Rechnung {$reminder['invoice_number']}.\n\nFreundliche Grüße\n"
        . ($config['BUSINESS_LEGAL_NAME'] ?? $config['BUSINESS_NAME'] ?? 'Ms. FixIT');

    $sent = wp_mail($recipient, $subject, $body, [], [$reminder['pdf_path']]);
    if (!$sent) {
        throw new RuntimeException('WordPress could not send the reminder e-mail');
    }
    $pdo->prepare(
        "UPDATE office_reminders SET reminder_status = 'sent', sent_at = CURRENT_TIMESTAMP WHERE id = ?"
    )->execute([$reminderId]);
}

function office_queue_print(PDO $pdo, string $kind, string $sourceId, string $path, string $printer, int $copies = 1): string
{
    if (!is_file($path)) {
        throw new RuntimeException("Print file does not exist: {$path}");
    }
    if (trim($printer) === '') {
        throw new InvalidArgumentException('Printer queue name is required');
    }
    $id = office_uuid();
    $statement = $pdo->prepare(
        'INSERT INTO office_print_jobs
         (id, document_kind, source_id, file_path, printer_name, copies)
         VALUES (?, ?, ?, ?, ?, ?)'
    );
    $statement->execute([$id, $kind, $sourceId, $path, $printer, max(1, $copies)]);
    return $id;
}

function office_print_run(PDO $pdo, int $limit = 20): array
{
    $statement = $pdo->prepare(
        "SELECT * FROM office_print_jobs
         WHERE print_status IN ('pending', 'retry')
         ORDER BY created_at LIMIT ?"
    );
    $statement->bindValue(1, max(1, min(100, $limit)), PDO::PARAM_INT);
    $statement->execute();
    $results = [];

    foreach ($statement->fetchAll() as $job) {
        $pdo->prepare(
            "UPDATE office_print_jobs SET print_status = 'printing', attempts = attempts + 1 WHERE id = ?"
        )->execute([$job['id']]);
        $command = sprintf(
            'lp -d %s -n %d %s 2>&1',
            escapeshellarg((string) $job['printer_name']),
            max(1, (int) $job['copies']),
            escapeshellarg((string) $job['file_path'])
        );
        exec($command, $output, $exitCode);
        $message = trim(implode("\n", $output));
        if ($exitCode === 0) {
            preg_match('/request id is\s+([^\s]+)/i', $message, $matches);
            $pdo->prepare(
                "UPDATE office_print_jobs
                 SET print_status = 'printed', cups_job_id = ?, printed_at = CURRENT_TIMESTAMP, last_error = NULL
                 WHERE id = ?"
            )->execute([$matches[1] ?? null, $job['id']]);
            $results[] = [$job['id'], 'printed', $message];
        } else {
            $pdo->prepare(
                "UPDATE office_print_jobs
                 SET print_status = IF(attempts >= 5, 'failed', 'retry'), last_error = ?
                 WHERE id = ?"
            )->execute([mb_substr($message, 0, 1000), $job['id']]);
            $results[] = [$job['id'], 'failed', $message];
        }
    }
    return $results;
}

function office_prosaldo_export(PDO $pdo, string $start, string $end): string
{
    $config = office_business_config();
    if (!office_bool($config['PROSALDO_EXPORT_ENABLED'] ?? 'yes')) {
        throw new RuntimeException('ProSaldo export is disabled');
    }
    $startDate = new DateTimeImmutable($start);
    $endDate = new DateTimeImmutable($end);
    if ($endDate < $startDate) {
        throw new InvalidArgumentException('Export end date must not precede start date');
    }

    $select = $pdo->prepare(
        "SELECT d.*, o.source_order_number
         FROM office_documents d
         LEFT JOIN office_orders o ON o.id = d.order_id
         WHERE d.document_status = 'final'
           AND d.document_type IN ('invoice', 'credit_note')
           AND d.issue_date BETWEEN ? AND ?
         ORDER BY d.issue_date, d.document_number"
    );
    $select->execute([$startDate->format('Y-m-d'), $endDate->format('Y-m-d')]);
    $documents = $select->fetchAll();

    $root = rtrim((string) ($config['PROSALDO_EXPORT_PATH'] ?? MSFIXIT_OFFICE_DATA . '/exports/prosaldo'), '/');
    $stamp = date('Ymd-His');
    $directory = $root . '/' . $startDate->format('Ymd') . '-' . $endDate->format('Ymd') . '-' . $stamp;
    if (!mkdir($directory, 0750, true) && !is_dir($directory)) {
        throw new RuntimeException("Unable to create ProSaldo export directory: {$directory}");
    }
    mkdir($directory . '/pdf', 0750, true);

    $documentsCsv = fopen($directory . '/documents.csv', 'wb');
    $contactsCsv = fopen($directory . '/contacts.csv', 'wb');
    $productsCsv = fopen($directory . '/products.csv', 'wb');
    if (!$documentsCsv || !$contactsCsv || !$productsCsv) {
        throw new RuntimeException('Unable to create ProSaldo CSV files');
    }

    fputcsv($documentsCsv, [
        'belegnummer', 'belegart', 'belegdatum', 'faelligkeit', 'bestellung',
        'kunde', 'email', 'land', 'netto', 'ust', 'brutto', 'waehrung',
        'steuerprofil', 'pdf_datei', 'pdf_sha256', 'prosaldo_status',
    ], ';');
    fputcsv($contactsCsv, [
        'externe_referenz', 'firma', 'vorname', 'nachname', 'strasse',
        'adresszusatz', 'plz', 'ort', 'land', 'email', 'telefon',
    ], ';');
    fputcsv($productsCsv, [
        'warennummer', 'bezeichnung', 'einheit', 'letzter_nettopreis', 'steuersatz',
    ], ';');

    $contacts = [];
    $products = [];
    $manifestFiles = [];
    foreach ($documents as $document) {
        $billing = office_decode_json($document['billing_json']);
        $pdfName = basename((string) $document['pdf_path']);
        $targetPdf = $directory . '/pdf/' . $pdfName;
        if (!is_file((string) $document['pdf_path']) || !copy((string) $document['pdf_path'], $targetPdf)) {
            throw new RuntimeException('Unable to copy document PDF: ' . $document['document_number']);
        }
        chmod($targetPdf, 0640);
        $pdfHash = hash_file('sha256', $targetPdf) ?: '';
        $manifestFiles['pdf/' . $pdfName] = $pdfHash;

        fputcsv($documentsCsv, [
            $document['document_number'],
            office_document_label((string) $document['document_type']),
            $document['issue_date'],
            $document['due_date'],
            $document['source_order_number'],
            $document['customer_name'],
            $document['customer_email'],
            strtoupper((string) ($billing['country'] ?? '')),
            number_format((float) $document['net_total'], 2, '.', ''),
            number_format((float) $document['tax_total'], 2, '.', ''),
            number_format((float) $document['gross_total'], 2, '.', ''),
            $document['currency'],
            $document['tax_mode'],
            'pdf/' . $pdfName,
            $pdfHash,
            'manuell_hochladen_und_buchen',
        ], ';');

        $contactKey = strtolower(trim((string) ($document['customer_email'] ?: $document['customer_name'])));
        if (!isset($contacts[$contactKey])) {
            $contacts[$contactKey] = true;
            fputcsv($contactsCsv, [
                ($config['PROSALDO_CONTACT_NUMBER_PREFIX'] ?? 'K') . substr(hash('sha256', $contactKey), 0, 10),
                $billing['company'] ?? '',
                $billing['first_name'] ?? '',
                $billing['last_name'] ?? '',
                $billing['address_1'] ?? '',
                $billing['address_2'] ?? '',
                $billing['postcode'] ?? '',
                $billing['city'] ?? '',
                strtoupper((string) ($billing['country'] ?? '')),
                $billing['email'] ?? $document['customer_email'],
                $billing['phone'] ?? '',
            ], ';');
        }

        foreach (office_get_lines($pdo, (string) $document['id']) as $line) {
            $article = trim((string) ($line['article_number'] ?? ''));
            if ($article === '' || isset($products[$article])) {
                continue;
            }
            $products[$article] = true;
            fputcsv($productsCsv, [
                $article,
                $line['description'],
                $line['unit'],
                number_format((float) $line['unit_net'], 2, '.', ''),
                number_format((float) $line['tax_rate'], 2, '.', ''),
            ], ';');
        }
    }
    fclose($documentsCsv);
    fclose($contactsCsv);
    fclose($productsCsv);

    $readme = "Ms. FixIT ShopOS – ProSaldo Übergabe\n"
        . "====================================\n\n"
        . "ProSaldo unterstützt derzeit keine direkte Shop-API und keinen CSV-Import von Rechnungsdaten.\n"
        . "Die Rechnungs- und Gutschrift-PDFs müssen daher in ProSaldo manuell hochgeladen und geprüft/verbucht werden.\n"
        . "contacts.csv und products.csv können als Stammdatenhilfe bzw. über den ProSaldo-Datenimport verwendet werden.\n"
        . "documents.csv ist die Kontrollliste. Nach erfolgter Verbuchung den Export in ShopOS als importiert markieren.\n";
    file_put_contents($directory . '/README.txt', $readme);

    foreach (['documents.csv', 'contacts.csv', 'products.csv', 'README.txt'] as $file) {
        $manifestFiles[$file] = hash_file('sha256', $directory . '/' . $file) ?: '';
    }
    $manifest = [
        'format' => 'msfixit-shopos-prosaldo-handoff-v1',
        'created_at' => date(DATE_ATOM),
        'period_start' => $startDate->format('Y-m-d'),
        'period_end' => $endDate->format('Y-m-d'),
        'document_count' => count($documents),
        'files' => $manifestFiles,
    ];
    file_put_contents($directory . '/manifest.json', office_json($manifest));
    $manifestHash = hash_file('sha256', $directory . '/manifest.json') ?: '';

    $zipPath = $directory . '.zip';
    $zip = new ZipArchive();
    if ($zip->open($zipPath, ZipArchive::CREATE | ZipArchive::OVERWRITE) !== true) {
        throw new RuntimeException("Unable to create ProSaldo ZIP: {$zipPath}");
    }
    $iterator = new RecursiveIteratorIterator(
        new RecursiveDirectoryIterator($directory, FilesystemIterator::SKIP_DOTS),
        RecursiveIteratorIterator::LEAVES_ONLY
    );
    foreach ($iterator as $fileInfo) {
        if (!$fileInfo->isFile()) {
            continue;
        }
        $local = substr($fileInfo->getPathname(), strlen($directory) + 1);
        $zip->addFile($fileInfo->getPathname(), $local);
    }
    $zip->close();
    chmod($zipPath, 0640);

    $id = office_uuid();
    $insert = $pdo->prepare(
        'INSERT INTO office_prosaldo_exports
         (id, export_period_start, export_period_end, export_path, manifest_sha256, document_count)
         VALUES (?, ?, ?, ?, ?, ?)'
    );
    $insert->execute([
        $id,
        $startDate->format('Y-m-d'),
        $endDate->format('Y-m-d'),
        $zipPath,
        $manifestHash,
        count($documents),
    ]);

    return $zipPath;
}

function office_create_shipment(PDO $pdo, array $payload): string
{
    $orderId = office_upsert_order($pdo, $payload);
    $carrier = strtolower(trim((string) ($payload['carrier_code'] ?? '')));
    if ($carrier === '') {
        throw new InvalidArgumentException('carrier_code is required');
    }
    $config = office_business_config();
    $sender = office_decode_json($payload['sender'] ?? [
        'name' => $config['BUSINESS_LEGAL_NAME'] ?? $config['BUSINESS_NAME'] ?? 'Ms. FixIT',
        'address_1' => $config['BUSINESS_STREET'] ?? '',
        'postcode' => $config['BUSINESS_POSTCODE'] ?? '',
        'city' => $config['BUSINESS_CITY'] ?? '',
        'country' => $config['BUSINESS_COUNTRY'] ?? 'AT',
        'email' => $config['BUSINESS_EMAIL'] ?? '',
        'phone' => $config['BUSINESS_PHONE'] ?? '',
    ]);
    $recipient = office_decode_json($payload['recipient'] ?? $payload['shipping'] ?? []);
    if ($recipient === []) {
        throw new InvalidArgumentException('Shipment recipient is required');
    }

    $id = office_uuid();
    $date = new DateTimeImmutable((string) ($payload['ship_date'] ?? 'today'));
    $pdo->beginTransaction();
    try {
        $number = office_alloc_number(
            $pdo,
            'shipment',
            strtoupper((string) ($config['SHIPMENT_PREFIX'] ?? 'VS')),
            $date
        );
        $insert = $pdo->prepare(
            'INSERT INTO office_shipments
             (id, order_id, shipment_number, carrier_code, carrier_product,
              shipment_status, ship_date, sender_json, recipient_json, customs_json, label_format)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'
        );
        $insert->execute([
            $id,
            $orderId,
            $number,
            $carrier,
            (string) ($payload['carrier_product'] ?? ''),
            'draft',
            $date->format('Y-m-d'),
            office_json($sender),
            office_json($recipient),
            office_json(office_decode_json($payload['customs'] ?? [])),
            (string) ($payload['label_format'] ?? $config['LABEL_FORMAT'] ?? 'PDF_A6'),
        ]);

        $packageInsert = $pdo->prepare(
            'INSERT INTO office_packages
             (shipment_id, package_number, weight_kg, length_cm, width_cm, height_cm,
              contents_description, value_amount, value_currency, metadata_json)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'
        );
        $packages = office_decode_json($payload['packages'] ?? []);
        if ($packages === []) {
            $packages = [[
                'weight_kg' => $config['DEFAULT_PACKAGE_WEIGHT_KG'] ?? 0,
                'length_cm' => $config['DEFAULT_PACKAGE_LENGTH_CM'] ?? null,
                'width_cm' => $config['DEFAULT_PACKAGE_WIDTH_CM'] ?? null,
                'height_cm' => $config['DEFAULT_PACKAGE_HEIGHT_CM'] ?? null,
            ]];
        }
        foreach ($packages as $index => $package) {
            if (!is_array($package) || (float) ($package['weight_kg'] ?? 0) <= 0) {
                throw new InvalidArgumentException('Every package requires a positive weight_kg');
            }
            $packageInsert->execute([
                $id,
                $index + 1,
                office_money($package['weight_kg']),
                isset($package['length_cm']) ? office_money($package['length_cm']) : null,
                isset($package['width_cm']) ? office_money($package['width_cm']) : null,
                isset($package['height_cm']) ? office_money($package['height_cm']) : null,
                (string) ($package['contents_description'] ?? ''),
                isset($package['value_amount']) ? office_money($package['value_amount']) : null,
                (string) ($package['value_currency'] ?? $payload['currency'] ?? 'EUR'),
                office_json(office_decode_json($package['metadata'] ?? [])),
            ]);
        }

        office_emit($pdo, 'shipment', $id, 'carrier.shipment.requested', [
            'shipment_id' => $id,
            'shipment_number' => $number,
            'carrier_code' => $carrier,
        ]);
        $pdo->commit();
    } catch (Throwable $exception) {
        if ($pdo->inTransaction()) {
            $pdo->rollBack();
        }
        throw $exception;
    }
    return $id;
}

function office_import_label(PDO $pdo, string $shipmentId, string $sourceFile, ?string $tracking = null): array
{
    if (!is_file($sourceFile)) {
        throw new RuntimeException("Label file not found: {$sourceFile}");
    }
    $statement = $pdo->prepare('SELECT * FROM office_shipments WHERE id = ? OR shipment_number = ?');
    $statement->execute([$shipmentId, $shipmentId]);
    $shipment = $statement->fetch();
    if (!$shipment) {
        throw new RuntimeException("Shipment not found: {$shipmentId}");
    }

    $extension = strtolower(pathinfo($sourceFile, PATHINFO_EXTENSION));
    if (!in_array($extension, ['pdf', 'zpl', 'png'], true)) {
        throw new InvalidArgumentException('Label must be PDF, ZPL or PNG');
    }
    $directory = MSFIXIT_OFFICE_DATA . '/labels/' . date('Y');
    if (!is_dir($directory) && !mkdir($directory, 0750, true) && !is_dir($directory)) {
        throw new RuntimeException("Unable to create label directory: {$directory}");
    }
    $target = $directory . '/' . preg_replace('/[^A-Za-z0-9._-]/', '_', (string) $shipment['shipment_number']) . '.' . $extension;
    if (!copy($sourceFile, $target)) {
        throw new RuntimeException('Unable to archive carrier label');
    }
    chmod($target, 0640);
    $hash = hash_file('sha256', $target);
    if ($hash === false) {
        throw new RuntimeException('Unable to hash carrier label');
    }

    $update = $pdo->prepare(
        "UPDATE office_shipments
         SET label_path = ?, label_sha256 = ?, tracking_number = COALESCE(?, tracking_number),
             shipment_status = 'label_created'
         WHERE id = ?"
    );
    $update->execute([$target, $hash, $tracking, $shipment['id']]);

    $config = office_business_config();
    if (office_bool($config['AUTO_PRINT_LABELS'] ?? 'no')) {
        $printer = trim((string) ($config['PRINTER_LABEL'] ?? ''));
        if ($printer !== '') {
            office_queue_print($pdo, 'shipment_label', (string) $shipment['id'], $target, $printer);
        }
    }

    return ['path' => $target, 'sha256' => $hash, 'tracking_number' => $tracking];
}

function office_carrier_list(PDO $pdo): array
{
    return $pdo->query(
        'SELECT carrier_code, account_reference, origin_country, adapter_mode,
                default_label_format, default_printer, enabled, updated_at
         FROM office_carrier_accounts ORDER BY carrier_code'
    )->fetchAll();
}

function office_process_wordpress_event(PDO $pdo, string $eventType, array $payload): array
{
    $config = office_business_config();
    $orderPayload = office_decode_json($payload['order'] ?? $payload);
    $orderId = office_upsert_order($pdo, $orderPayload);
    $result = ['order_id' => $orderId];

    $invoiceTrigger = strtolower((string) ($config['INVOICE_TRIGGER'] ?? 'payment'));
    $deliveryTrigger = strtolower((string) ($config['DELIVERY_NOTE_TRIGGER'] ?? 'processing'));

    if ($eventType === 'woocommerce.order.paid' || $eventType === 'woocommerce.order.completed') {
        if ($invoiceTrigger === 'payment' || $eventType === 'woocommerce.order.completed') {
            $invoiceId = office_create_document($pdo, 'invoice', $orderPayload);
            $result['invoice_id'] = $invoiceId;
            if (office_bool($config['AUTO_FINALIZE_INVOICES'] ?? 'no')) {
                $result['invoice'] = office_finalize_document($pdo, $invoiceId);
            }
            $payment = office_decode_json($payload['payment'] ?? $orderPayload['payment'] ?? []);
            if ($payment !== []) {
                $result['payment'] = office_record_payment($pdo, $invoiceId, $payment);
            }
        }
    }

    if ($eventType === 'woocommerce.order.processing' || $eventType === 'woocommerce.order.completed') {
        if ($deliveryTrigger === 'processing' || $eventType === 'woocommerce.order.completed') {
            $deliveryPayload = $orderPayload;
            $deliveryPayload['source_document_id'] = ($orderPayload['source_order_id'] ?? '') . ':delivery';
            $deliveryId = office_create_document($pdo, 'delivery_note', $deliveryPayload);
            $result['delivery_note_id'] = $deliveryId;
            if (office_bool($config['AUTO_FINALIZE_DELIVERY_NOTES'] ?? 'no')) {
                $result['delivery_note'] = office_finalize_document($pdo, $deliveryId);
            }
        }
    }

    if ($eventType === 'woocommerce.order.refunded') {
        $refundPayload = office_decode_json($payload['refund'] ?? []);
        if ($refundPayload !== []) {
            $refundPayload = array_merge($orderPayload, $refundPayload);
            $refundPayload['source_document_id'] = (string) ($refundPayload['refund_id'] ?? office_uuid());
            $result['credit_note_id'] = office_create_document($pdo, 'credit_note', $refundPayload);
        }
    }

    return $result;
}

function office_worker_run(PDO $pdo, int $limit = 25): array
{
    $select = $pdo->prepare(
        "SELECT * FROM office_outbox
         WHERE event_status = 'pending' AND available_at <= CURRENT_TIMESTAMP
         ORDER BY id LIMIT ?"
    );
    $select->bindValue(1, max(1, min(100, $limit)), PDO::PARAM_INT);
    $select->execute();
    $results = [];

    foreach ($select->fetchAll() as $event) {
        $pdo->prepare(
            "UPDATE office_outbox SET event_status = 'processing', attempts = attempts + 1 WHERE id = ?"
        )->execute([$event['id']]);
        try {
            $payload = office_decode_json($event['payload_json']);
            $type = (string) $event['event_type'];
            if (str_starts_with($type, 'woocommerce.order.')) {
                $result = office_process_wordpress_event($pdo, $type, $payload);
            } elseif ($type === 'dispatch.document.email') {
                office_dispatch_document($pdo, (string) ($payload['document_id'] ?? $event['aggregate_id']));
                $result = ['sent' => true];
            } elseif ($type === 'dispatch.reminder.email') {
                office_dispatch_reminder($pdo, (string) ($payload['reminder_id'] ?? $event['aggregate_id']));
                $result = ['sent' => true];
            } else {
                $pdo->prepare(
                    "UPDATE office_outbox SET event_status = 'unhandled', processed_at = CURRENT_TIMESTAMP WHERE id = ?"
                )->execute([$event['id']]);
                $results[] = [$event['id'], 'unhandled', $type];
                continue;
            }

            $pdo->prepare(
                "UPDATE office_outbox
                 SET event_status = 'processed', processed_at = CURRENT_TIMESTAMP, last_error = NULL
                 WHERE id = ?"
            )->execute([$event['id']]);
            $results[] = [$event['id'], 'processed', $result];
        } catch (Throwable $exception) {
            $backoff = min(3600, 60 * (2 ** min(6, (int) $event['attempts'])));
            $update = $pdo->prepare(
                "UPDATE office_outbox
                 SET event_status = IF(attempts >= 8, 'failed', 'pending'),
                     available_at = DATE_ADD(CURRENT_TIMESTAMP, INTERVAL ? SECOND),
                     last_error = ?
                 WHERE id = ?"
            );
            $update->execute([$backoff, mb_substr($exception->getMessage(), 0, 1000), $event['id']]);
            $results[] = [$event['id'], 'failed', $exception->getMessage()];
        }
    }

    return $results;
}
