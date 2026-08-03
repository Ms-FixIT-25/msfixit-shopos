<?php

declare(strict_types=1);

require __DIR__ . '/../image/package/usr/share/msfixit-shopos/discovery/discovery-lib.php';

function expect(bool $condition, string $message): void
{
    if (!$condition) {
        fwrite(STDERR, "Discovery test failed: {$message}\n");
        exit(1);
    }
}

expect(msfixit_discovery_normalize(' USB–C / 2,0 m ') === 'usb c 2.0 m', 'normalization');

$query = 'LAN 2m';
$matching = msfixit_discovery_score([
    'title' => 'Cat 6a Patchkabel 2 m',
    'sku' => 'MF-00000001',
    'gtin' => '4000000000001',
    'mpn' => 'CAT6A-2M',
    'attributes' => 'Netzwerkkabel RJ45 Cat 6a 2 m geschirmt',
    'description' => 'Ethernetkabel für Router und Switch.',
], $query);
$unrelated = msfixit_discovery_score([
    'title' => 'HDMI-Kabel 1 m',
    'sku' => 'MF-00000002',
    'gtin' => '4000000000002',
    'mpn' => 'HDMI-1M',
    'attributes' => 'HDMI 1 m 4K 60 Hz',
    'description' => 'Bildschirmkabel.',
], $query);
expect($matching > $unrelated && $matching > 0, 'LAN and Ethernet synonym ranking');

$inferred = msfixit_discovery_infer_cable_attributes('Premium HDMI 2.1 Kabel HDMI auf HDMI, 2 m, 4K bei 120 Hz');
expect(($inferred['cable_type'] ?? '') === 'HDMI-Kabel', 'HDMI cable type inference');
expect(($inferred['cable_length'] ?? '') === '2 m', 'cable length inference');
expect(($inferred['cable_standard'] ?? '') === 'HDMI 2.1', 'HDMI standard inference');
expect(($inferred['resolution'] ?? '') === '4K @ 120 Hz', 'resolution inference');
expect(($inferred['connector_a'] ?? '') === 'HDMI' && ($inferred['connector_b'] ?? '') === 'HDMI', 'connector inference');

$complete = [
    'pilot_status' => 'approved',
    'compliance_status' => 'approved',
    'discovery_review_status' => 'approved',
    'content_reviewed' => 'yes',
    'image_id' => 42,
    'title' => 'USB-C auf USB-C Kabel 2 m, 60 W',
    'short_description' => str_repeat('Kurze technische Produktinformation. ', 4),
    'description' => str_repeat('Ausführliche, redaktionell geprüfte Beschreibung mit Einsatzbereich und technischen Grenzen. ', 5),
    'brand' => 'Example Brand',
    'gtin' => '4000000000001',
    'mpn' => 'USBCC-2M-60W',
    'cable_type' => 'USB-Kabel',
    'connector_a' => 'USB-C',
    'connector_b' => 'USB-C',
    'cable_length' => '2 m',
    'cable_standard' => 'USB 2.0',
    'price' => 14.90,
];
expect(msfixit_discovery_publication_audit($complete) === [], 'complete cable publication audit');

$incomplete = $complete;
$incomplete['image_id'] = 0;
$incomplete['gtin'] = '';
$incomplete['mpn'] = '';
$incomplete['connector_b'] = '';
$errors = msfixit_discovery_publication_audit($incomplete);
expect(count($errors) >= 3, 'incomplete product must be blocked');
expect(in_array('Ein geprüftes Hauptbild fehlt.', $errors, true), 'image gate');
expect(in_array('EAN/GTIN oder Herstellerartikelnummer fehlt.', $errors, true), 'identifier gate');
expect(in_array('Anschluss B fehlt.', $errors, true), 'connector gate');

expect(msfixit_discovery_has_facet_parameters(['anschluss_a' => 'usb-c']), 'facet URL detection');
expect(!msfixit_discovery_has_facet_parameters(['utm_source' => 'newsletter']), 'unrelated query parameters');

echo "Cable discovery library tests passed.\n";
