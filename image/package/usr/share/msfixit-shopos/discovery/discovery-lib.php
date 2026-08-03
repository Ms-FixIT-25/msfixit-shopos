<?php

declare(strict_types=1);

function msfixit_discovery_normalize(string $value): string
{
    $value = mb_strtolower(trim($value), 'UTF-8');
    $value = str_replace(['–', '—', '_', '/', '\\'], ' ', $value);
    $value = preg_replace('/(?<=\d),(?=\d)/u', '.', $value) ?? $value;
    $value = preg_replace('/[^\p{L}\p{N}.+ -]+/u', ' ', $value) ?? $value;
    $value = preg_replace('/\s+/u', ' ', $value) ?? $value;
    return trim($value);
}

function msfixit_discovery_synonyms(): array
{
    return [
        'usb c' => ['usb-c', 'type c', 'type-c', 'usbc'],
        'usb a' => ['usb-a', 'type a', 'type-a', 'usba'],
        'displayport' => ['display port', 'dp'],
        'ethernet' => ['lan', 'patchkabel', 'netzwerkkabel', 'network cable'],
        'hdmi' => ['high definition multimedia interface'],
        'ladekabel' => ['charging cable', 'lademkabel', 'lade kabel'],
        'verlaengerung' => ['verlängerung', 'extension'],
        '1 m' => ['1m', '100 cm'],
        '2 m' => ['2m', '200 cm'],
        '3 m' => ['3m', '300 cm'],
        '5 m' => ['5m', '500 cm'],
        'cat6a' => ['cat 6a', 'category 6a'],
        'cat6' => ['cat 6', 'category 6'],
        '4k 60hz' => ['4k60', '4k 60 hz', 'uhd 60hz'],
        '4k 120hz' => ['4k120', '4k 120 hz', 'uhd 120hz'],
    ];
}

function msfixit_discovery_expand_query(string $query): array
{
    $normalized = msfixit_discovery_normalize($query);
    if ($normalized === '') {
        return [];
    }

    $phrases = [$normalized];
    foreach (msfixit_discovery_synonyms() as $canonical => $alternatives) {
        $group = array_map('msfixit_discovery_normalize', array_merge([$canonical], $alternatives));
        foreach ($group as $member) {
            if ($member !== '' && str_contains($normalized, $member)) {
                $phrases = array_merge($phrases, $group);
                break;
            }
        }
    }

    $tokens = [];
    foreach ($phrases as $phrase) {
        foreach (preg_split('/\s+/u', $phrase) ?: [] as $token) {
            if (mb_strlen($token, 'UTF-8') >= 2 || preg_match('/^\d+(?:\.\d+)?$/', $token)) {
                $tokens[] = $token;
            }
        }
        $tokens[] = $phrase;
    }

    return array_values(array_unique(array_filter($tokens)));
}

function msfixit_discovery_score(array $document, string $query): int
{
    $queryNormalized = msfixit_discovery_normalize($query);
    if ($queryNormalized === '') {
        return 1;
    }

    $tokens = msfixit_discovery_expand_query($query);
    $title = msfixit_discovery_normalize((string) ($document['title'] ?? ''));
    $sku = msfixit_discovery_normalize((string) ($document['sku'] ?? ''));
    $gtin = msfixit_discovery_normalize((string) ($document['gtin'] ?? ''));
    $mpn = msfixit_discovery_normalize((string) ($document['mpn'] ?? ''));
    $attributes = msfixit_discovery_normalize((string) ($document['attributes'] ?? ''));
    $description = msfixit_discovery_normalize((string) ($document['description'] ?? ''));

    $score = 0;
    if ($title === $queryNormalized) {
        $score += 300;
    } elseif (str_contains($title, $queryNormalized)) {
        $score += 140;
    }
    if ($sku === $queryNormalized || $gtin === $queryNormalized || $mpn === $queryNormalized) {
        $score += 500;
    }

    foreach ($tokens as $token) {
        if (str_contains($title, $token)) {
            $score += mb_strlen($token, 'UTF-8') > 3 ? 24 : 12;
        }
        if (str_contains($sku, $token) || str_contains($gtin, $token) || str_contains($mpn, $token)) {
            $score += 45;
        }
        if (str_contains($attributes, $token)) {
            $score += 14;
        }
        if (str_contains($description, $token)) {
            $score += 3;
        }
    }

    return $score;
}

function msfixit_discovery_infer_cable_attributes(string $text): array
{
    $normalized = msfixit_discovery_normalize($text);
    $result = [];

    if (str_contains($normalized, 'hdmi')) {
        $result['cable_type'] = 'HDMI-Kabel';
    } elseif (str_contains($normalized, 'displayport') || preg_match('/\bdp\b/u', $normalized)) {
        $result['cable_type'] = 'DisplayPort-Kabel';
    } elseif (preg_match('/\b(cat ?6a|cat ?6|cat ?7|ethernet|lan|patchkabel|netzwerkkabel)\b/u', $normalized)) {
        $result['cable_type'] = 'Netzwerkkabel';
    } elseif (str_contains($normalized, 'usb')) {
        $result['cable_type'] = str_contains($normalized, 'verlaenger') ? 'USB-Verlängerung' : 'USB-Kabel';
    }

    if (preg_match('/\b(0\.5|1|1\.5|2|3|5|7\.5|10)\s*m\b/u', $normalized, $match)) {
        $result['cable_length'] = rtrim(rtrim($match[1], '0'), '.') . ' m';
    }

    $standards = [
        '/\bhdmi ?2\.1\b/u' => 'HDMI 2.1',
        '/\bhdmi ?2\.0\b/u' => 'HDMI 2.0',
        '/\bdisplayport ?2\.1\b/u' => 'DisplayPort 2.1',
        '/\bdisplayport ?1\.4\b/u' => 'DisplayPort 1.4',
        '/\bcat ?7\b/u' => 'Cat 7',
        '/\bcat ?6a\b/u' => 'Cat 6a',
        '/\bcat ?6\b/u' => 'Cat 6',
        '/\busb ?4\b/u' => 'USB4',
        '/\busb ?3\.2\b/u' => 'USB 3.2',
        '/\busb ?3\.0\b/u' => 'USB 3.0',
        '/\busb ?2\.0\b/u' => 'USB 2.0',
    ];
    foreach ($standards as $pattern => $label) {
        if (preg_match($pattern, $normalized)) {
            $result['cable_standard'] = $label;
            break;
        }
    }

    if (preg_match('/\b(60|100|140|240)\s*w\b/u', $normalized, $match)) {
        $result['max_power'] = $match[1] . ' W';
    }
    if (preg_match('/\b(480\s*mbit\/s|5\s*gbit\/s|10\s*gbit\/s|20\s*gbit\/s|40\s*gbit\/s|80\s*gbit\/s)\b/u', $normalized, $match)) {
        $result['data_rate'] = strtoupper(str_replace(' ', ' ', $match[1]));
    }
    if (preg_match('/\b(4k|8k)\s*(?:bei|@)?\s*(30|60|120|144)\s*hz\b/u', $normalized, $match)) {
        $result['resolution'] = strtoupper($match[1]) . ' @ ' . $match[2] . ' Hz';
    }

    $connectors = [];
    if (preg_match_all('/\b(usb[- ]?c|type[- ]?c|usb[- ]?a|type[- ]?a|hdmi|mini hdmi|micro hdmi|displayport|mini displayport|rj45)\b/u', $normalized, $matches)) {
        foreach ($matches[1] as $connector) {
            $key = str_replace([' ', '-'], '', $connector);
            $connectors[] = match ($key) {
                'usbc', 'typec' => 'USB-C',
                'usba', 'typea' => 'USB-A',
                'minihdmi' => 'Mini-HDMI',
                'microhdmi' => 'Micro-HDMI',
                'displayport' => 'DisplayPort',
                'minidisplayport' => 'Mini DisplayPort',
                'rj45' => 'RJ45',
                default => strtoupper($connector),
            };
        }
    }
    $connectors = array_values(array_unique($connectors));
    if (isset($connectors[0])) {
        $result['connector_a'] = $connectors[0];
    }
    if (isset($connectors[1])) {
        $result['connector_b'] = $connectors[1];
    } elseif (isset($connectors[0]) && in_array($result['cable_type'] ?? '', ['HDMI-Kabel', 'DisplayPort-Kabel', 'Netzwerkkabel'], true)) {
        $result['connector_b'] = $connectors[0];
    }

    return $result;
}

function msfixit_discovery_publication_audit(array $product, array $settings = []): array
{
    $minimumShort = max(40, (int) ($settings['minimum_short_description'] ?? 80));
    $minimumDescription = max(120, (int) ($settings['minimum_description'] ?? 250));
    $requireOriginal = (bool) ($settings['require_original_content'] ?? true);
    $errors = [];

    if (($product['pilot_status'] ?? '') !== 'approved') {
        $errors[] = 'Pilotfreigabe fehlt.';
    }
    if (($product['compliance_status'] ?? '') !== 'approved') {
        $errors[] = 'Produktsicherheits- oder Compliancefreigabe fehlt.';
    }
    if (($product['discovery_review_status'] ?? '') !== 'approved') {
        $errors[] = 'SEO- und Suchfreigabe fehlt.';
    }
    if (empty($product['image_id'])) {
        $errors[] = 'Ein geprüftes Hauptbild fehlt.';
    }
    if (mb_strlen(trim((string) ($product['title'] ?? '')), 'UTF-8') < 20) {
        $errors[] = 'Der Produkttitel ist zu kurz.';
    }
    if (mb_strlen(trim(strip_tags((string) ($product['short_description'] ?? ''))), 'UTF-8') < $minimumShort) {
        $errors[] = 'Die Kurzbeschreibung ist zu kurz.';
    }
    if (mb_strlen(trim(strip_tags((string) ($product['description'] ?? ''))), 'UTF-8') < $minimumDescription) {
        $errors[] = 'Die Produktbeschreibung ist zu kurz.';
    }
    if ($requireOriginal && ($product['content_reviewed'] ?? '') !== 'yes') {
        $errors[] = 'Die Produktbeschreibung wurde noch nicht redaktionell geprüft.';
    }
    if (empty($product['brand'])) {
        $errors[] = 'Die Marke fehlt.';
    }
    if (empty($product['gtin']) && empty($product['mpn'])) {
        $errors[] = 'EAN/GTIN oder Herstellerartikelnummer fehlt.';
    }
    foreach (['cable_type' => 'Kabeltyp', 'connector_a' => 'Anschluss A', 'connector_b' => 'Anschluss B', 'cable_length' => 'Kabellänge', 'cable_standard' => 'Kabelstandard'] as $field => $label) {
        if (empty($product[$field])) {
            $errors[] = $label . ' fehlt.';
        }
    }
    if (!isset($product['price']) || !is_numeric($product['price']) || (float) $product['price'] <= 0) {
        $errors[] = 'Ein gültiger Verkaufspreis fehlt.';
    }

    return array_values(array_unique($errors));
}

function msfixit_discovery_has_facet_parameters(array $query): bool
{
    $keys = [
        'kabelsuche', 'kabeltyp', 'anschluss_a', 'anschluss_b', 'laenge',
        'standard', 'leistung', 'datenrate', 'aufloesung', 'marke', 'lager',
        'min_preis', 'max_preis', 'sortierung', 'kabel_seite',
    ];
    foreach ($keys as $key) {
        if (isset($query[$key]) && trim((string) $query[$key]) !== '') {
            return true;
        }
    }
    return false;
}
