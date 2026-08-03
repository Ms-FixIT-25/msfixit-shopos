<?php
/**
 * Plugin Name: Ms. FixIT ShopOS Compliance Runtime Evidence
 * Description: Revalidates archived legal, registration and product evidence files before checkout.
 * Version: 1.0.0
 */

declare(strict_types=1);

if (!defined('ABSPATH')) {
    exit;
}

const MSFIXIT_RUNTIME_COMPLIANCE_ENV = '/etc/msfixit-shopos/office-wordpress.env';

function msfixit_runtime_compliance_env(): array
{
    static $settings = null;
    if (is_array($settings)) {
        return $settings;
    }
    $settings = [];
    if (!is_readable(MSFIXIT_RUNTIME_COMPLIANCE_ENV)) {
        return $settings;
    }
    foreach (file(MSFIXIT_RUNTIME_COMPLIANCE_ENV, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) ?: [] as $line) {
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

function msfixit_runtime_compliance_database(): ?PDO
{
    static $pdo = false;
    if ($pdo instanceof PDO) {
        return $pdo;
    }
    if ($pdo === null) {
        return null;
    }
    $env = msfixit_runtime_compliance_env();
    foreach (['OFFICE_DB_HOST','OFFICE_DB_PORT','OFFICE_DB_NAME','OFFICE_DB_USER','OFFICE_DB_PASSWORD'] as $key) {
        if (empty($env[$key])) {
            $pdo = null;
            return null;
        }
    }
    try {
        $pdo = new PDO(
            sprintf('mysql:host=%s;port=%s;dbname=%s;charset=utf8mb4', $env['OFFICE_DB_HOST'], $env['OFFICE_DB_PORT'], $env['OFFICE_DB_NAME']),
            $env['OFFICE_DB_USER'],
            $env['OFFICE_DB_PASSWORD'],
            [PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,PDO::ATTR_DEFAULT_FETCH_MODE=>PDO::FETCH_ASSOC,PDO::ATTR_EMULATE_PREPARES=>false]
        );
        return $pdo;
    } catch (Throwable $exception) {
        error_log('[Ms. FixIT Compliance Runtime] ' . $exception->getMessage());
        $pdo = null;
        return null;
    }
}

function msfixit_runtime_compliance_file_valid(?string $path, ?string $expectedHash): bool
{
    $path = trim((string) $path);
    $expectedHash = strtolower(trim((string) $expectedHash));
    if ($path === '' || !preg_match('/^[0-9a-f]{64}$/', $expectedHash)) {
        return false;
    }
    if (!is_file($path) || !is_readable($path)) {
        return false;
    }
    $actual = hash_file('sha256', $path);
    return is_string($actual) && hash_equals($expectedHash, strtolower($actual));
}

function msfixit_runtime_compliance_destination(array $data): string
{
    $country = strtoupper(trim((string) ($data['shipping_country'] ?? $data['billing_country'] ?? '')));
    if ($country !== '') {
        return $country;
    }
    if (function_exists('WC') && WC()->customer) {
        return strtoupper((string) (WC()->customer->get_shipping_country() ?: WC()->customer->get_billing_country() ?: 'AT'));
    }
    return 'AT';
}

function msfixit_runtime_compliance_customer_type(array $data): string
{
    return !empty($data['billing_company']) || !empty($data['billing_vat_id']) || !empty($data['_billing_vat_id'])
        ? 'business' : 'consumer';
}

add_action('woocommerce_after_checkout_validation', static function (array $data, WP_Error $errors): void {
    $pdo = msfixit_runtime_compliance_database();
    if (!$pdo) {
        $errors->add('msfixit_compliance_evidence', 'Die rechtlichen Nachweise können derzeit nicht geprüft werden. Die Bestellung bleibt zum Schutz beider Seiten gesperrt.');
        return;
    }

    $country = msfixit_runtime_compliance_destination($data);
    $customerType = msfixit_runtime_compliance_customer_type($data);
    if (!in_array($country, ['AT','DE','CH'], true)) {
        $errors->add('msfixit_compliance_evidence', 'Für dieses Lieferland besteht keine freigegebene Rechts- und Steuerkonfiguration.');
        return;
    }
    $requiredColumn = $customerType === 'business' ? 'required_for_b2b' : 'required_for_b2c';

    try {
        $legal = $pdo->prepare(
            "SELECT r.document_type,r.must_be_durable_medium,d.file_path,d.file_sha256
               FROM compliance_market_required_documents r
               LEFT JOIN compliance_legal_documents d
                 ON d.country_code=r.country_code AND d.document_type=r.document_type
                AND d.active=1 AND d.approval_status='approved'
                AND d.valid_from<=CURRENT_DATE
                AND (d.valid_until IS NULL OR d.valid_until>=CURRENT_DATE)
              WHERE r.country_code=? AND r.{$requiredColumn}=1"
        );
        $legal->execute([$country]);
        foreach ($legal->fetchAll() as $document) {
            if ((int) $document['must_be_durable_medium'] === 1
                && !msfixit_runtime_compliance_file_valid($document['file_path'], $document['file_sha256'])) {
                $errors->add(
                    'msfixit_compliance_evidence',
                    'Die freigegebene Datei für „' . sanitize_text_field((string) $document['document_type']) . '“ fehlt oder wurde verändert.'
                );
            }
        }

        if (function_exists('WC') && WC()->cart) {
            $productStatement = $pdo->prepare(
                'SELECT p.evidence_path,p.evidence_sha256,p.supplier_code,
                        s.direct_to_customer,sm.verification_status,
                        sm.evidence_path AS supplier_evidence_path,
                        sm.evidence_sha256 AS supplier_evidence_sha256
                   FROM compliance_product_markets p
                   LEFT JOIN compliance_suppliers s ON s.supplier_code=p.supplier_code
                   LEFT JOIN compliance_supplier_markets sm
                     ON sm.supplier_code=p.supplier_code AND sm.country_code=p.country_code
                  WHERE p.article_number=? AND p.country_code=? AND p.approval_status=\'approved\''
            );
            foreach (WC()->cart->get_cart() as $cartItem) {
                $product = $cartItem['data'] ?? null;
                if (!$product instanceof WC_Product) {
                    continue;
                }
                $sku = trim((string) $product->get_sku());
                $productStatement->execute([$sku, $country]);
                $record = $productStatement->fetch();
                if (!$record || !msfixit_runtime_compliance_file_valid($record['evidence_path'] ?? null, $record['evidence_sha256'] ?? null)) {
                    $errors->add('msfixit_compliance_evidence', 'Der Produktsicherheitsnachweis für „' . $product->get_name() . '“ fehlt oder wurde verändert.');
                    continue;
                }
                if ((int) ($record['direct_to_customer'] ?? 0) === 1) {
                    if (($record['verification_status'] ?? '') !== 'verified'
                        || !msfixit_runtime_compliance_file_valid($record['supplier_evidence_path'] ?? null, $record['supplier_evidence_sha256'] ?? null)) {
                        $errors->add('msfixit_compliance_evidence', 'Der Register-/Versendernachweis für „' . $product->get_name() . '“ fehlt oder wurde verändert.');
                    }
                }
            }
        }
    } catch (Throwable $exception) {
        error_log('[Ms. FixIT Compliance Runtime] ' . $exception->getMessage());
        $errors->add('msfixit_compliance_evidence', 'Die Compliance-Nachweise konnten nicht vollständig geprüft werden.');
    }
}, 60, 2);
