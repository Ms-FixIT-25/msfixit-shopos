<?php
declare(strict_types=1);

function shoposValidEan(string $digits): bool
{
    $length = strlen($digits);
    if (($length !== 8 && $length !== 13) || !ctype_digit($digits)) return false;
    $sum = 0;
    for ($i = $length - 2, $position = 1; $i >= 0; $i--, $position++) {
        $digit = (int)$digits[$i];
        $sum += ($position % 2 === 1) ? $digit * 3 : $digit;
    }
    $check = (10 - ($sum % 10)) % 10;
    return $check === (int)$digits[$length - 1];
}

function shoposEvaluateScannerInput(string $raw): array
{
    $scan = trim($raw);
    if ($scan === '') {
        return ['scan' => '', 'class' => 'warning', 'title' => 'Kein Scan empfangen', 'detail' => 'Scannerfeld war leer.'];
    }
    if (strlen($scan) > 256) {
        return ['scan' => substr($scan, 0, 256), 'class' => 'warning', 'title' => 'Scan zu lang', 'detail' => 'Für den Abnahmetest werden höchstens 256 Bytes verarbeitet.'];
    }
    if (preg_match('/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/', $scan) === 1) {
        return ['scan' => $scan, 'class' => 'warning', 'title' => 'Steuerzeichen erkannt', 'detail' => 'Der Scanner sendet unerwartete Steuerzeichen. Konfiguration prüfen.'];
    }
    if (ctype_digit($scan) && strlen($scan) === 8) {
        $ok = shoposValidEan($scan);
        return ['scan' => $scan, 'class' => $ok ? 'success' : 'error', 'title' => $ok ? 'EAN-8 gültig' : 'EAN-8 Prüfziffer ungültig', 'detail' => $ok ? 'Der komplette EAN-8-Code wurde an ShopOS übergeben.' : 'Die Länge passt zu EAN-8, aber die Prüfziffer stimmt nicht.'];
    }
    if (ctype_digit($scan) && strlen($scan) === 13) {
        $ok = shoposValidEan($scan);
        return ['scan' => $scan, 'class' => $ok ? 'success' : 'error', 'title' => $ok ? 'EAN-13 gültig' : 'EAN-13 Prüfziffer ungültig', 'detail' => $ok ? 'Der komplette EAN-13-Code wurde an ShopOS übergeben.' : 'Die Länge passt zu EAN-13, aber die Prüfziffer stimmt nicht.'];
    }
    return ['scan' => $scan, 'class' => 'success', 'title' => 'Scannertext empfangen', 'detail' => 'Die Nutzdaten wurden vollständig an das Formular übergeben. Code 128, QR und andere Symbologien lassen sich aus dem ausgegebenen Text allein nicht zuverlässig unterscheiden.'];
}
