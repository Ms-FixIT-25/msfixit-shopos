<?php
/**
 * Plugin Name: Ms. FixIT ShopOS DACH Compliance
 * Description: Blocks unapproved DACH markets/products, captures legal checkout evidence and provides an electronic withdrawal function.
 * Version: 1.0.0
 */

declare(strict_types=1);

if (!defined('ABSPATH')) {
    exit;
}

const MSFIXIT_COMPLIANCE_DB_ENV = '/etc/msfixit-shopos/office-wordpress.env';
const MSFIXIT_COMPLIANCE_BUSINESS_ENV = '/etc/msfixit-shopos/business.env';

function msfixit_compliance_log(string $message): void
{
    error_log('[Ms. FixIT Compliance] ' . $message);
}

function msfixit_compliance_env(string $path): array
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

function msfixit_compliance_bool(mixed $value): bool
{
    return in_array(strtolower(trim((string) $value)), ['1','yes','true','on','ja'], true);
}

function msfixit_compliance_database(): ?PDO
{
    static $pdo = false;
    if ($pdo instanceof PDO) {
        return $pdo;
    }
    if ($pdo === null) {
        return null;
    }
    $env = msfixit_compliance_env(MSFIXIT_COMPLIANCE_DB_ENV);
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
        msfixit_compliance_log('Database connection failed: ' . $exception->getMessage());
        $pdo = null;
        return null;
    }
}

function msfixit_compliance_uuid(): string
{
    $bytes = random_bytes(16);
    $bytes[6] = chr((ord($bytes[6]) & 0x0f) | 0x40);
    $bytes[8] = chr((ord($bytes[8]) & 0x3f) | 0x80);
    $hex = bin2hex($bytes);
    return sprintf('%s-%s-%s-%s-%s', substr($hex,0,8),substr($hex,8,4),substr($hex,12,4),substr($hex,16,4),substr($hex,20,12));
}

function msfixit_compliance_enqueue(string $eventType, string $aggregateId, array $payload): void
{
    $pdo = msfixit_compliance_database();
    if (!$pdo) {
        msfixit_compliance_log("Unable to queue {$eventType}: database unavailable");
        return;
    }
    try {
        $statement = $pdo->prepare(
            'INSERT INTO office_outbox (event_uuid,aggregate_type,aggregate_id,event_type,payload_json)
             VALUES (?,?,?,?,?)'
        );
        $statement->execute([
            msfixit_compliance_uuid(),'compliance',$aggregateId,$eventType,
            wp_json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES),
        ]);
    } catch (Throwable $exception) {
        msfixit_compliance_log("Unable to queue {$eventType}: " . $exception->getMessage());
    }
}

function msfixit_compliance_country(): string
{
    $country = '';
    if (function_exists('WC') && WC()->customer) {
        $country = (string) WC()->customer->get_shipping_country();
        if ($country === '') {
            $country = (string) WC()->customer->get_billing_country();
        }
    }
    if ($country === '' && function_exists('WC') && WC()->countries) {
        $country = (string) WC()->countries->get_base_country();
    }
    return strtoupper($country ?: 'AT');
}

function msfixit_compliance_customer_type_from_request(): string
{
    $company = isset($_POST['billing_company']) ? trim(sanitize_text_field(wp_unslash($_POST['billing_company']))) : '';
    $vat = isset($_POST['billing_vat_id']) ? trim(sanitize_text_field(wp_unslash($_POST['billing_vat_id']))) : '';
    if ($vat === '' && isset($_POST['_billing_vat_id'])) {
        $vat = trim(sanitize_text_field(wp_unslash($_POST['_billing_vat_id'])));
    }
    return ($company !== '' || $vat !== '') ? 'business' : 'consumer';
}

function msfixit_compliance_market(string $country): ?array
{
    $pdo = msfixit_compliance_database();
    if (!$pdo) {
        return null;
    }
    $statement = $pdo->prepare('SELECT * FROM compliance_market_profiles WHERE country_code=?');
    $statement->execute([strtoupper($country)]);
    $market = $statement->fetch();
    return $market ?: null;
}

function msfixit_compliance_legal_documents(string $country, string $customerType): array
{
    $pdo = msfixit_compliance_database();
    if (!$pdo) {
        return [];
    }
    $column = $customerType === 'business' ? 'required_for_b2b' : 'required_for_b2c';
    $statement = $pdo->prepare(
        "SELECT r.document_type,d.version_label,d.wp_page_slug,d.content_sha256,
                d.file_path,d.file_sha256,r.must_be_durable_medium
           FROM compliance_market_required_documents r
           LEFT JOIN compliance_legal_documents d
             ON d.country_code=r.country_code AND d.document_type=r.document_type
            AND d.active=1 AND d.approval_status='approved'
            AND d.valid_from <= CURRENT_DATE
            AND (d.valid_until IS NULL OR d.valid_until >= CURRENT_DATE)
          WHERE r.country_code=? AND r.{$column}=1
          ORDER BY r.document_type"
    );
    $statement->execute([strtoupper($country)]);
    return $statement->fetchAll();
}

function msfixit_compliance_page_hash(string $slug): ?string
{
    if ($slug === '') {
        return null;
    }
    $page = get_page_by_path($slug, OBJECT, 'page');
    if (!$page instanceof WP_Post || $page->post_status !== 'publish') {
        return null;
    }
    return hash('sha256', (string) $page->post_content);
}

function msfixit_compliance_product_check(string $sku, string $country): array
{
    $pdo = msfixit_compliance_database();
    if (!$pdo || $sku === '') {
        return ['approved'=>false,'missing'=>[$pdo ? 'permanent_article_number' : 'compliance_database']];
    }
    $statement = $pdo->prepare(
        'SELECT p.*,s.direct_to_customer,sm.verification_status AS supplier_market_status,
                sm.packaging_registration,sm.packaging_system_participation,
                sm.eee_registration AS supplier_eee_registration,
                sm.battery_registration AS supplier_battery_registration
           FROM compliance_product_markets p
           LEFT JOIN compliance_suppliers s ON s.supplier_code=p.supplier_code
           LEFT JOIN compliance_supplier_markets sm ON sm.supplier_code=p.supplier_code AND sm.country_code=p.country_code
          WHERE p.article_number=? AND p.country_code=?'
    );
    $statement->execute([$sku,strtoupper($country)]);
    $p = $statement->fetch();
    if (!$p) {
        return ['approved'=>false,'missing'=>['product_market_approval']];
    }
    $missing=[];
    foreach (['product_identifier','manufacturer_name','manufacturer_postal_address','manufacturer_email','safety_warnings_de'] as $field) {
        if (trim((string) ($p[$field] ?? ''))==='') $missing[]=$field;
    }
    if ((int) $p['manufacturer_outside_eu']===1 && in_array(strtoupper($country),['AT','DE'],true)) {
        foreach (['eu_responsible_person_name','eu_responsible_person_postal_address','eu_responsible_person_email'] as $field) {
            if (trim((string) ($p[$field] ?? ''))==='') $missing[]=$field;
        }
    }
    if (!$p['delivery_min_days'] || !$p['delivery_max_days'] || (int) $p['delivery_max_days'] < (int) $p['delivery_min_days']) {
        $missing[]='delivery_window';
    }
    if ((int) $p['ce_required']===1 && (int) $p['ce_confirmed']!==1) $missing[]='ce_confirmation';
    if (($p['approval_status'] ?? '')!=='approved') $missing[]='product_approval';
    if (in_array(strtoupper($country),['AT','DE'],true) && (int) ($p['legal_guarantee_months'] ?? 0)<24) $missing[]='legal_guarantee';

    $direct=(int) ($p['direct_to_customer'] ?? 0)===1;
    $supplierVerified=($p['supplier_market_status'] ?? '')==='verified';
    if (strtoupper($country)==='DE') {
        $seller=$pdo->query("SELECT COUNT(*) FROM compliance_business_registrations WHERE country_code='DE' AND legal_entity_code='seller' AND registration_type IN ('LUCID','PACKAGING_SYSTEM') AND registration_status='verified'")->fetchColumn();
        $supplier=$direct && $supplierVerified && trim((string) ($p['packaging_registration'] ?? ''))!=='' && trim((string) ($p['packaging_system_participation'] ?? ''))!=='';
        if ((int) $seller<2 && !$supplier) $missing[]='de_packaging';
        if ((int) $p['electrical_equipment']===1 && trim((string) ($p['eee_registration_number'] ?: $p['supplier_eee_registration']))==='') $missing[]='de_eee_registration';
        if ((int) $p['contains_battery']===1 && trim((string) ($p['battery_registration_number'] ?: $p['supplier_battery_registration']))==='') $missing[]='de_battery_registration';
    }
    if (strtoupper($country)==='AT') {
        $seller=(int) $pdo->query("SELECT COUNT(*) FROM compliance_business_registrations WHERE country_code='AT' AND legal_entity_code='seller' AND registration_type='PACKAGING_SYSTEM' AND registration_status='verified'")->fetchColumn()>0;
        $supplier=$direct && $supplierVerified && trim((string) ($p['packaging_system_participation'] ?? ''))!=='';
        if (!$seller && !$supplier) $missing[]='at_packaging';
        if ((int) $p['electrical_equipment']===1 && trim((string) ($p['eee_registration_number'] ?: $p['supplier_eee_registration']))==='') $missing[]='at_eee_registration';
        if ((int) $p['contains_battery']===1 && trim((string) ($p['battery_registration_number'] ?: $p['supplier_battery_registration']))==='') $missing[]='at_battery_registration';
    }
    return [
        'approved'=>array_values(array_unique($missing))===[],
        'missing'=>array_values(array_unique($missing)),
        'record'=>$p,
    ];
}

function msfixit_compliance_checkout_report(string $country, string $customerType): array
{
    $errors=[];
    $market=msfixit_compliance_market($country);
    if (!$market) {
        return ['approved'=>false,'errors'=>['Das Zielland besitzt kein Compliance-Profil.'],'legal_documents'=>[],'products'=>[]];
    }
    $enabled=$customerType==='business' ? (int) $market['b2b_enabled']===1 : (int) $market['b2c_enabled']===1;
    if (!$enabled || $market['legal_review_status']!=='approved' || $market['tax_review_status']!=='approved') {
        $errors[]='Der Verkauf in dieses Land ist noch nicht rechtlich und steuerlich freigegeben.';
    }
    $config=msfixit_compliance_env(MSFIXIT_COMPLIANCE_BUSINESS_ENV);
    $taxMode=(string) ($config['TAX_MODE_'.strtoupper($country)] ?? $config['DEFAULT_TAX_MODE'] ?? 'review_required');
    if ($taxMode==='review_required') $errors[]='Das Steuerprofil für das Zielland ist noch nicht freigegeben.';
    if ($country==='CH' && get_woocommerce_currency()!=='CHF') {
        $errors[]='Für die Schweiz ist noch keine gesetzeskonforme CHF-Endpreisdarstellung eingerichtet.';
    }
    if (in_array($country,['AT','DE'],true) && get_option('woocommerce_prices_include_tax')!=='yes' && $taxMode!=='at_small_business_exempt' && $taxMode!=='eu_small_business_exempt') {
        $errors[]='Verbraucher-Endpreise sind nicht als Bruttopreise konfiguriert.';
    }

    $legal=[];
    foreach (msfixit_compliance_legal_documents($country,$customerType) as $document) {
        if (empty($document['version_label']) || empty($document['content_sha256'])) {
            $errors[]='Pflicht-Rechtstext fehlt: '.sanitize_text_field((string) $document['document_type']);
            continue;
        }
        $actual=$document['wp_page_slug'] ? msfixit_compliance_page_hash((string) $document['wp_page_slug']) : null;
        if ($document['wp_page_slug'] && $actual!==strtolower((string) $document['content_sha256'])) {
            $errors[]='Rechtstext wurde nach der Freigabe verändert: '.sanitize_text_field((string) $document['document_type']);
        }
        $legal[]=[
            'type'=>$document['document_type'],'version'=>$document['version_label'],
            'slug'=>$document['wp_page_slug'],'sha256'=>$document['content_sha256'],
            'durable_medium'=>(bool) $document['must_be_durable_medium'],
        ];
    }

    $products=[];
    if (function_exists('WC') && WC()->cart) {
        foreach (WC()->cart->get_cart() as $item) {
            $product=$item['data'] ?? null;
            if (!$product instanceof WC_Product) continue;
            $sku=(string) $product->get_sku();
            $check=msfixit_compliance_product_check($sku,$country);
            $products[]=['product_id'=>$product->get_id(),'article_number'=>$sku,'approved'=>$check['approved'],'missing'=>$check['missing']];
            if (!$check['approved']) {
                $errors[]=sprintf('Artikel „%s“ ist für %s noch nicht vollständig freigegeben (%s).',$product->get_name(),$country,implode(', ',$check['missing']));
            }
        }
    }
    return ['approved'=>$errors===[],'errors'=>$errors,'legal_documents'=>$legal,'products'=>$products,'market'=>$market];
}

add_filter('woocommerce_order_button_text', static fn(): string => 'Zahlungspflichtig bestellen', 999);

add_action('woocommerce_after_checkout_validation', static function (array $data, WP_Error $errors): void {
    $country=strtoupper((string) ($data['shipping_country'] ?: $data['billing_country'] ?: msfixit_compliance_country()));
    $customerType=(!empty($data['billing_company']) || !empty($data['billing_vat_id']) || !empty($data['_billing_vat_id'])) ? 'business' : 'consumer';
    $report=msfixit_compliance_checkout_report($country,$customerType);
    foreach ($report['errors'] as $message) {
        $errors->add('msfixit_compliance',wp_strip_all_tags((string) $message));
    }
}, 50, 2);

add_action('woocommerce_checkout_order_created', static function (WC_Order $order): void {
    $country=strtoupper((string) ($order->get_shipping_country() ?: $order->get_billing_country() ?: 'AT'));
    $vat=trim((string) ($order->get_meta('_billing_vat_id',true) ?: $order->get_meta('billing_vat_id',true)));
    $customerType=($order->get_billing_company()!=='' || $vat!=='') ? 'business' : 'consumer';
    $report=msfixit_compliance_checkout_report($country,$customerType);
    $min=null;$max=null;
    foreach ($report['products'] as $productReport) {
        $check=msfixit_compliance_product_check((string) $productReport['article_number'],$country);
        $record=$check['record'] ?? [];
        if ($record) {
            $min=$min===null ? (int) $record['delivery_min_days'] : max($min,(int) $record['delivery_min_days']);
            $max=$max===null ? (int) $record['delivery_max_days'] : max($max,(int) $record['delivery_max_days']);
        }
    }
    $snapshot=[
        'source_order_id'=>(string) $order->get_id(),'country_code'=>$country,'customer_type'=>$customerType,
        'currency'=>$order->get_currency(),'gross_total'=>(float) $order->get_total(),
        'shipping_total'=>(float) $order->get_shipping_total(),'button_label'=>'Zahlungspflichtig bestellen',
        'payment_method'=>$order->get_payment_method(),'delivery_promise'=>$min!==null ? "{$min}–{$max} Werktage" : null,
        'legal_documents'=>$report['legal_documents'],'products'=>$report['products'],
        'consents'=>[
            'terms'=>(bool) $order->get_meta('_terms_accepted',true),
            'digital_early_performance'=>(bool) $order->get_meta('_msfixit_digital_early_performance',true),
        ],
        'captured_at'=>current_time('mysql',true),
    ];
    $order->update_meta_data('_msfixit_compliance_country',$country);
    $order->update_meta_data('_msfixit_compliance_snapshot_sha256',hash('sha256',wp_json_encode($snapshot,JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES)));
    $order->save();
    msfixit_compliance_enqueue('compliance.checkout.snapshot',(string) $order->get_id(),['snapshot'=>$snapshot]);
}, 20);

add_action('woocommerce_payment_complete', static function (int $orderId): void {
    $order=wc_get_order($orderId);
    if (!$order instanceof WC_Order) return;
    $country=strtoupper((string) ($order->get_shipping_country() ?: $order->get_billing_country() ?: 'AT'));
    $vat=trim((string) ($order->get_meta('_billing_vat_id',true) ?: $order->get_meta('billing_vat_id',true)));
    $items=0;
    foreach ($order->get_items() as $item) $items+=(int) $item->get_quantity();
    msfixit_compliance_enqueue('compliance.sale.completed',(string) $orderId,['sale'=>[
        'source_order_id'=>(string) $orderId,'destination_country'=>$country,
        'customer_type'=>($order->get_billing_company()!=='' || $vat!=='') ? 'business' : 'consumer',
        'currency'=>$order->get_currency(),'gross_total'=>(float) $order->get_total(),
        'item_count'=>$items,'calendar_year'=>(int) current_time('Y'),
    ]]);
}, 30);

function msfixit_compliance_product_payload(WC_Product $product, string $country): array
{
    return [
        'article_number'=>(string) $product->get_sku(),'country_code'=>$country,
        'supplier_code'=>(string) $product->get_meta('_msfixit_supplier_code',true),
        'product_identifier'=>(string) ($product->get_meta('_msfixit_product_identifier',true) ?: $product->get_sku()),
        'manufacturer_name'=>(string) $product->get_meta('_msfixit_manufacturer_name',true),
        'manufacturer_postal_address'=>(string) $product->get_meta('_msfixit_manufacturer_address',true),
        'manufacturer_email'=>(string) $product->get_meta('_msfixit_manufacturer_email',true),
        'manufacturer_outside_eu'=>msfixit_compliance_bool($product->get_meta('_msfixit_manufacturer_outside_eu',true)),
        'eu_responsible_person_name'=>(string) $product->get_meta('_msfixit_eu_responsible_name',true),
        'eu_responsible_person_postal_address'=>(string) $product->get_meta('_msfixit_eu_responsible_address',true),
        'eu_responsible_person_email'=>(string) $product->get_meta('_msfixit_eu_responsible_email',true),
        'safety_warnings_de'=>(string) $product->get_meta('_msfixit_safety_warnings_de',true),
        'safety_warnings_fr'=>(string) $product->get_meta('_msfixit_safety_warnings_fr',true),
        'safety_warnings_it'=>(string) $product->get_meta('_msfixit_safety_warnings_it',true),
        'instructions_languages'=>(string) $product->get_meta('_msfixit_instructions_languages',true),
        'ce_required'=>msfixit_compliance_bool($product->get_meta('_msfixit_ce_required',true)),
        'ce_confirmed'=>msfixit_compliance_bool($product->get_meta('_msfixit_ce_confirmed',true)),
        'electrical_equipment'=>msfixit_compliance_bool($product->get_meta('_msfixit_electrical_equipment',true)),
        'contains_battery'=>msfixit_compliance_bool($product->get_meta('_msfixit_contains_battery',true)),
        'eee_registration_number'=>(string) $product->get_meta('_msfixit_eee_registration',true),
        'battery_registration_number'=>(string) $product->get_meta('_msfixit_battery_registration',true),
        'delivery_min_days'=>(int) $product->get_meta('_msfixit_delivery_min_days',true),
        'delivery_max_days'=>(int) $product->get_meta('_msfixit_delivery_max_days',true),
        'legal_guarantee_months'=>in_array($country,['AT','DE'],true) ? 24 : (int) $product->get_meta('_msfixit_guarantee_months_ch',true),
        'withdrawal_exception_code'=>(string) $product->get_meta('_msfixit_withdrawal_exception',true),
        'economic_operator_role'=>(string) ($product->get_meta('_msfixit_economic_operator_role',true) ?: 'retailer'),
        'approval_status'=>'review_required',
    ];
}

add_action('woocommerce_product_options_general_product_data', static function (): void {
    echo '<div class="options_group"><p><strong>DACH Recht & Produktsicherheit</strong></p>';
    $fields=[
        ['_msfixit_compliance_markets','Freigabemärkte','AT,DE,CH'],
        ['_msfixit_supplier_code','Lieferantencode',''],['_msfixit_product_identifier','Modell/Produktkennung',''],
        ['_msfixit_manufacturer_name','Herstellername',''],['_msfixit_manufacturer_address','Hersteller-Postanschrift',''],
        ['_msfixit_manufacturer_email','Hersteller-E-Mail',''],['_msfixit_eu_responsible_name','EU-verantwortliche Person',''],
        ['_msfixit_eu_responsible_address','EU-verantwortliche Anschrift',''],['_msfixit_eu_responsible_email','EU-verantwortliche E-Mail',''],
        ['_msfixit_instructions_languages','Sprachen Anleitung/Sicherheit','de'],
        ['_msfixit_eee_registration','Elektro-Registrierungsnummer',''],['_msfixit_battery_registration','Batterie-Registrierungsnummer',''],
        ['_msfixit_delivery_min_days','Lieferzeit mindestens (Werktage)',''],['_msfixit_delivery_max_days','Lieferzeit höchstens (Werktage)',''],
        ['_msfixit_guarantee_months_ch','Vertragliche Gewährleistung CH (Monate)',''],
        ['_msfixit_withdrawal_exception','Widerrufsausnahme – geprüfter Code',''],['_msfixit_economic_operator_role','Rolle (retailer/importer/manufacturer/dropshipper)','retailer'],
    ];
    foreach ($fields as [$id,$label,$placeholder]) {
        woocommerce_wp_text_input(['id'=>$id,'label'=>$label,'placeholder'=>$placeholder]);
    }
    woocommerce_wp_checkbox(['id'=>'_msfixit_manufacturer_outside_eu','label'=>'Hersteller außerhalb EU']);
    woocommerce_wp_checkbox(['id'=>'_msfixit_ce_required','label'=>'CE-Kennzeichnung erforderlich']);
    woocommerce_wp_checkbox(['id'=>'_msfixit_ce_confirmed','label'=>'CE-Nachweis geprüft']);
    woocommerce_wp_checkbox(['id'=>'_msfixit_electrical_equipment','label'=>'Elektro-/Elektronikgerät']);
    woocommerce_wp_checkbox(['id'=>'_msfixit_contains_battery','label'=>'Enthält Batterie/Akku']);
    woocommerce_wp_textarea_input(['id'=>'_msfixit_safety_warnings_de','label'=>'Sicherheits-/Warnhinweise Deutsch']);
    woocommerce_wp_textarea_input(['id'=>'_msfixit_safety_warnings_fr','label'=>'Sicherheits-/Warnhinweise Französisch']);
    woocommerce_wp_textarea_input(['id'=>'_msfixit_safety_warnings_it','label'=>'Sicherheits-/Warnhinweise Italienisch']);
    echo '<p class="form-field"><em>Speichern erzeugt nur einen Prüfentwurf. Eine Freigabe erfolgt getrennt mit Nachweis über ShopOS Compliance.</em></p></div>';
});

add_action('woocommerce_admin_process_product_object', static function (WC_Product $product): void {
    $textFields=['_msfixit_compliance_markets','_msfixit_supplier_code','_msfixit_product_identifier','_msfixit_manufacturer_name','_msfixit_manufacturer_address','_msfixit_manufacturer_email','_msfixit_eu_responsible_name','_msfixit_eu_responsible_address','_msfixit_eu_responsible_email','_msfixit_instructions_languages','_msfixit_eee_registration','_msfixit_battery_registration','_msfixit_delivery_min_days','_msfixit_delivery_max_days','_msfixit_guarantee_months_ch','_msfixit_withdrawal_exception','_msfixit_economic_operator_role'];
    $areaFields=['_msfixit_safety_warnings_de','_msfixit_safety_warnings_fr','_msfixit_safety_warnings_it'];
    $boolFields=['_msfixit_manufacturer_outside_eu','_msfixit_ce_required','_msfixit_ce_confirmed','_msfixit_electrical_equipment','_msfixit_contains_battery'];
    foreach ($textFields as $field) {
        if (isset($_POST[$field])) $product->update_meta_data($field,sanitize_text_field(wp_unslash($_POST[$field])));
    }
    foreach ($areaFields as $field) {
        if (isset($_POST[$field])) $product->update_meta_data($field,sanitize_textarea_field(wp_unslash($_POST[$field])));
    }
    foreach ($boolFields as $field) $product->update_meta_data($field,isset($_POST[$field]) ? 'yes' : 'no');
    $markets=array_filter(array_map('trim',explode(',',strtoupper((string) ($product->get_meta('_msfixit_compliance_markets',true) ?: 'AT,DE,CH')))));
    foreach (array_intersect($markets,['AT','DE','CH']) as $country) {
        msfixit_compliance_enqueue('compliance.product.updated',(string) $product->get_id(),['product'=>msfixit_compliance_product_payload($product,$country)]);
    }
});

add_action('woocommerce_single_product_summary', static function (): void {
    global $product;
    if (!$product instanceof WC_Product) return;
    $country=msfixit_compliance_country();
    $check=msfixit_compliance_product_check((string) $product->get_sku(),$country);
    $r=$check['record'] ?? null;
    if (!$r) return;
    echo '<section class="msfixit-product-safety" aria-label="Hersteller- und Sicherheitsinformationen">';
    echo '<h3>Hersteller- und Sicherheitsinformationen</h3>';
    echo '<p><strong>Hersteller:</strong> '.esc_html((string) $r['manufacturer_name']).'<br>'.nl2br(esc_html((string) $r['manufacturer_postal_address'])).'<br>'.esc_html((string) $r['manufacturer_email']).'</p>';
    if (!empty($r['eu_responsible_person_name'])) {
        echo '<p><strong>Verantwortliche Person in der EU:</strong> '.esc_html((string) $r['eu_responsible_person_name']).'<br>'.nl2br(esc_html((string) $r['eu_responsible_person_postal_address'])).'<br>'.esc_html((string) $r['eu_responsible_person_email']).'</p>';
    }
    echo '<p><strong>Produktkennung:</strong> '.esc_html((string) $r['product_identifier']).'</p>';
    echo '<p><strong>Sicherheits- und Warnhinweise:</strong><br>'.nl2br(esc_html((string) $r['safety_warnings_de'])).'</p>';
    if ($r['delivery_min_days'] && $r['delivery_max_days']) echo '<p><strong>Voraussichtliche Lieferzeit:</strong> '.esc_html((string) $r['delivery_min_days']).'–'.esc_html((string) $r['delivery_max_days']).' Werktage</p>';
    echo '</section>';
}, 35);

add_filter('woocommerce_email_attachments', static function (array $attachments, string $emailId, $object): array {
    if (!$object instanceof WC_Order || !in_array($emailId,['customer_processing_order','customer_completed_order','customer_invoice'],true)) return $attachments;
    $country=strtoupper((string) ($object->get_shipping_country() ?: $object->get_billing_country() ?: 'AT'));
    $vat=trim((string) ($object->get_meta('_billing_vat_id',true) ?: $object->get_meta('billing_vat_id',true)));
    $type=($object->get_billing_company()!=='' || $vat!=='') ? 'business' : 'consumer';
    foreach (msfixit_compliance_legal_documents($country,$type) as $doc) {
        if ((int) $doc['must_be_durable_medium']===1 && !empty($doc['file_path']) && is_readable((string) $doc['file_path']) && hash_file('sha256',(string) $doc['file_path'])===$doc['file_sha256']) {
            $attachments[]=(string) $doc['file_path'];
        }
    }
    return array_values(array_unique($attachments));
}, 20, 3);

function msfixit_compliance_withdrawal_allowed(string $country): bool
{
    if (in_array($country,['AT','DE'],true)) return true;
    $config=msfixit_compliance_env(MSFIXIT_COMPLIANCE_BUSINESS_ENV);
    return $country==='CH' && msfixit_compliance_bool($config['CH_VOLUNTARY_WITHDRAWAL_ENABLED'] ?? 'no');
}

function msfixit_compliance_withdrawal_shortcode(): string
{
    $message='';
    $stage=1;
    $payloadToken='';$signature='';
    if ($_SERVER['REQUEST_METHOD']==='POST' && isset($_POST['msfixit_withdrawal_action'])) {
        $action=sanitize_key(wp_unslash($_POST['msfixit_withdrawal_action']));
        if (!isset($_POST['msfixit_withdrawal_nonce']) || !wp_verify_nonce(sanitize_text_field(wp_unslash($_POST['msfixit_withdrawal_nonce'])),'msfixit_withdrawal')) {
            return '<p>Die Sicherheitsprüfung ist abgelaufen. Bitte laden Sie die Seite neu.</p>';
        }
        if ($action==='review') {
            $orderNumber=trim(sanitize_text_field(wp_unslash($_POST['order_number'] ?? '')));
            $email=sanitize_email(wp_unslash($_POST['email'] ?? ''));
            $name=trim(sanitize_text_field(wp_unslash($_POST['name'] ?? '')));
            $items=trim(sanitize_textarea_field(wp_unslash($_POST['items'] ?? '')));
            $order=wc_get_order($orderNumber);
            if (!$order instanceof WC_Order || strtolower($order->get_billing_email())!==strtolower($email) || $name==='') {
                $message='<p class="woocommerce-error">Bestellung, E-Mail-Adresse oder Name konnten nicht eindeutig zugeordnet werden.</p>';
            } else {
                $country=strtoupper((string) ($order->get_shipping_country() ?: $order->get_billing_country() ?: 'AT'));
                if (!msfixit_compliance_withdrawal_allowed($country)) {
                    $message='<p class="woocommerce-error">Für diese Bestellung ist keine freigegebene elektronische Widerrufsregel hinterlegt. Vertragliche Rückgabeanfragen bleiben über den Support möglich.</p>';
                } else {
                    $payload=['source_order_id'=>(string) $order->get_id(),'order_number'=>(string) $order->get_order_number(),'country_code'=>$country,'requester_name'=>$name,'requester_email'=>$email,'items'=>$items,'requested_at'=>current_time('mysql',true),'declaration_text'=>'Hiermit widerrufe ich den bezeichneten Vertrag beziehungsweise die bezeichneten Artikel.'];
                    $json=wp_json_encode($payload,JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES);
                    $payloadToken=base64_encode($json);
                    $signature=hash_hmac('sha256',$payloadToken,wp_salt('auth'));
                    $stage=2;
                }
            }
        } elseif ($action==='confirm') {
            $payloadToken=(string) wp_unslash($_POST['payload'] ?? '');
            $signature=(string) wp_unslash($_POST['signature'] ?? '');
            if (!hash_equals(hash_hmac('sha256',$payloadToken,wp_salt('auth')),$signature)) {
                return '<p class="woocommerce-error">Die Bestätigung ist ungültig oder wurde verändert.</p>';
            }
            $payload=json_decode((string) base64_decode($payloadToken,true),true);
            if (!is_array($payload) || empty($payload['source_order_id']) || empty($payload['requester_email'])) return '<p class="woocommerce-error">Die Widerrufsdaten sind unvollständig.</p>';
            $order=wc_get_order((int) $payload['source_order_id']);
            if (!$order instanceof WC_Order || strtolower($order->get_billing_email())!==strtolower((string) $payload['requester_email'])) return '<p class="woocommerce-error">Die Bestellung konnte nicht bestätigt werden.</p>';
            $confirmedAt=current_time('mysql',true);
            $subject='Bestätigung Ihres Widerrufs – Bestellung '.$order->get_order_number();
            $body="Wir bestätigen den Eingang Ihrer Widerrufserklärung.\n\nBestellung: {$order->get_order_number()}\nZeitpunkt (UTC): {$confirmedAt}\nErklärung: {$payload['declaration_text']}\nBetroffene Artikel/Angabe: {$payload['items']}\n\nDie Bestätigung des Eingangs ist noch keine Entscheidung über Voraussetzungen, Umfang oder Rückzahlung.";
            $sent=wp_mail((string) $payload['requester_email'],$subject,$body);
            $payload['confirmation_sent_at']=$sent ? $confirmedAt : null;
            msfixit_compliance_enqueue('compliance.withdrawal.requested',(string) $order->get_id(),['withdrawal'=>$payload]);
            $order->add_order_note('Elektronische Widerrufserklärung am '.$confirmedAt.' eingegangen. Eingangsbestätigung: '.($sent?'versendet':'Versand fehlgeschlagen'));
            return '<div class="woocommerce-message"><strong>Widerruf übermittelt.</strong><br>Der Eingang wurde mit Datum und Uhrzeit erfasst'.($sent?' und per E-Mail bestätigt.':'. Die E-Mail-Bestätigung konnte nicht versendet werden; bitte kontaktieren Sie zusätzlich den Support.').'</div>';
        }
    }
    ob_start();
    echo $message;
    if ($stage===1) {
        echo '<form method="post" class="msfixit-withdrawal-form">';
        wp_nonce_field('msfixit_withdrawal','msfixit_withdrawal_nonce');
        echo '<input type="hidden" name="msfixit_withdrawal_action" value="review">';
        echo '<p><label>Bestellnummer<br><input required name="order_number" autocomplete="off"></label></p>';
        echo '<p><label>Name<br><input required name="name" autocomplete="name"></label></p>';
        echo '<p><label>E-Mail-Adresse der Bestellung<br><input required type="email" name="email" autocomplete="email"></label></p>';
        echo '<p><label>Betroffene Artikel oder „gesamte Bestellung“<br><textarea required name="items" rows="4"></textarea></label></p>';
        echo '<p><button type="submit" class="button">Vertrag widerrufen</button></p></form>';
    } else {
        $payload=json_decode((string) base64_decode($payloadToken,true),true);
        echo '<section><h2>Widerruf prüfen</h2>';
        echo '<p><strong>Bestellung:</strong> '.esc_html((string) ($payload['order_number'] ?? '')).'<br><strong>Name:</strong> '.esc_html((string) ($payload['requester_name'] ?? '')).'<br><strong>Artikel:</strong> '.nl2br(esc_html((string) ($payload['items'] ?? ''))).'</p>';
        echo '<p>'.esc_html((string) ($payload['declaration_text'] ?? '')).'</p>';
        echo '<form method="post">';wp_nonce_field('msfixit_withdrawal','msfixit_withdrawal_nonce');
        echo '<input type="hidden" name="msfixit_withdrawal_action" value="confirm"><input type="hidden" name="payload" value="'.esc_attr($payloadToken).'"><input type="hidden" name="signature" value="'.esc_attr($signature).'">';
        echo '<button type="submit" class="button alt">Widerruf bestätigen</button></form></section>';
    }
    return (string) ob_get_clean();
}
add_shortcode('msfixit_withdrawal','msfixit_compliance_withdrawal_shortcode');

add_action('storefront_footer', static function (): void {
    $page=get_page_by_path('vertrag-widerrufen');
    if ($page instanceof WP_Post && $page->post_status==='publish') {
        echo '<div class="msfixit-withdrawal-link"><a href="'.esc_url(get_permalink($page)).'">Vertrag widerrufen</a></div>';
    }
}, 5);

add_action('wp_dashboard_setup', static function (): void {
    wp_add_dashboard_widget('msfixit_compliance_status','Ms. FixIT – DACH Rechts- & Produktfreigabe',static function (): void {
        $pdo=msfixit_compliance_database();
        if (!$pdo) { echo '<p><strong>Status:</strong> Compliance-Datenbank nicht verfügbar.</p>'; return; }
        try {
            $markets=$pdo->query('SELECT country_code,b2c_enabled,b2b_enabled,legal_review_status,tax_review_status FROM compliance_market_profiles ORDER BY country_code')->fetchAll();
            echo '<table><thead><tr><th>Land</th><th>B2C</th><th>B2B</th><th>Recht/Steuer</th></tr></thead><tbody>';
            foreach ($markets as $m) echo '<tr><td>'.esc_html($m['country_code']).'</td><td>'.((int)$m['b2c_enabled']?'aktiv':'gesperrt').'</td><td>'.((int)$m['b2b_enabled']?'aktiv':'gesperrt').'</td><td>'.esc_html($m['legal_review_status'].' / '.$m['tax_review_status']).'</td></tr>';
            echo '</tbody></table>';
            $unapproved=(int) $pdo->query("SELECT COUNT(*) FROM compliance_product_markets WHERE approval_status<>'approved'")->fetchColumn();
            $withdrawals=(int) $pdo->query("SELECT COUNT(*) FROM compliance_withdrawals WHERE request_status NOT IN ('completed','rejected')")->fetchColumn();
            echo '<p>Artikel zur Prüfung: <strong>'.esc_html((string)$unapproved).'</strong><br>Offene Widerrufe: <strong>'.esc_html((string)$withdrawals).'</strong></p>';
            echo '<p><small>Eine technische Freigabe ersetzt nicht die inhaltliche Prüfung durch Steuerberatung beziehungsweise Rechtsberatung.</small></p>';
        } catch (Throwable $e) { echo '<p>Status konnte nicht gelesen werden.</p>'; msfixit_compliance_log($e->getMessage()); }
    });
});
