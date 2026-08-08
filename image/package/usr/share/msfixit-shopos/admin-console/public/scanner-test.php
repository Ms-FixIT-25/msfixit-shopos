<?php
declare(strict_types=1);

session_name('SHOPOSADMIN');
session_set_cookie_params([
    'lifetime' => 0,
    'path' => '/admin/',
    'secure' => !empty($_SERVER['HTTPS']),
    'httponly' => true,
    'samesite' => 'Strict',
]);
session_start();

header('X-Frame-Options: DENY');
header('X-Content-Type-Options: nosniff');
header('Referrer-Policy: no-referrer');
header("Content-Security-Policy: default-src 'self'; style-src 'self' 'unsafe-inline'; script-src 'none'; img-src 'self' data:; frame-ancestors 'none'; base-uri 'none'; form-action 'self'");
header('Cache-Control: no-store');

if (($_SESSION['authenticated'] ?? false) !== true) {
    header('Location: /admin/');
    exit;
}

function e(string $value): string
{
    return htmlspecialchars($value, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}

function csrfToken(): string
{
    if (empty($_SESSION['csrf'])) {
        $_SESSION['csrf'] = bin2hex(random_bytes(32));
    }
    return (string)$_SESSION['csrf'];
}

function validEan(string $digits): bool
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

$result = null;
$scan = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    if (!hash_equals(csrfToken(), (string)($_POST['csrf'] ?? ''))) {
        http_response_code(403);
        exit('Ungültige Anfrage.');
    }
    $scan = trim((string)($_POST['scan_code'] ?? ''));
    if ($scan === '') {
        $result = ['class' => 'warning', 'title' => 'Kein Scan empfangen', 'detail' => 'Scannerfeld war leer.'];
    } elseif (strlen($scan) > 256) {
        $scan = substr($scan, 0, 256);
        $result = ['class' => 'warning', 'title' => 'Scan zu lang', 'detail' => 'Für den Abnahmetest werden höchstens 256 Bytes verarbeitet.'];
    } elseif (preg_match('/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/', $scan) === 1) {
        $result = ['class' => 'warning', 'title' => 'Steuerzeichen erkannt', 'detail' => 'Der Scanner sendet unerwartete Steuerzeichen. Konfiguration prüfen.'];
    } elseif (ctype_digit($scan) && strlen($scan) === 8) {
        $ok = validEan($scan);
        $result = ['class' => $ok ? 'success' : 'error', 'title' => $ok ? 'EAN-8 gültig' : 'EAN-8 Prüfziffer ungültig', 'detail' => $ok ? 'Der komplette EAN-8-Code wurde an ShopOS übergeben.' : 'Die Länge passt zu EAN-8, aber die Prüfziffer stimmt nicht.'];
    } elseif (ctype_digit($scan) && strlen($scan) === 13) {
        $ok = validEan($scan);
        $result = ['class' => $ok ? 'success' : 'error', 'title' => $ok ? 'EAN-13 gültig' : 'EAN-13 Prüfziffer ungültig', 'detail' => $ok ? 'Der komplette EAN-13-Code wurde an ShopOS übergeben.' : 'Die Länge passt zu EAN-13, aber die Prüfziffer stimmt nicht.'];
    } else {
        $result = ['class' => 'success', 'title' => 'Scannertext empfangen', 'detail' => 'Die Nutzdaten wurden vollständig an das Formular übergeben. Code 128, QR und andere Symbologien lassen sich aus dem ausgegebenen Text allein nicht zuverlässig unterscheiden.'];
    }
}
?><!doctype html>
<html lang="de"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>ShopOS Scanner-Abnahmetest</title><style>
:root{font-family:Inter,system-ui,sans-serif;color:#172033;background:#f4f7fb;--brand:#6a2ca0;--ok:#197447;--warn:#a45b00;--bad:#b4233a}*{box-sizing:border-box}body{margin:0}.shell{max-width:920px;margin:auto;padding:28px}.back{color:#536071;text-decoration:none}.card{background:#fff;border:1px solid #e1e7ee;border-radius:20px;padding:22px;margin-top:18px;box-shadow:0 8px 28px #1720330a}.muted{color:#687684}.notice{padding:14px;border-radius:12px;margin:16px 0}.success{background:#e4f5eb;color:var(--ok)}.warning{background:#fff0dc;color:var(--warn)}.error{background:#fde8ec;color:var(--bad)}form{display:grid;gap:12px}input,button{font:inherit;padding:14px;border-radius:12px;border:1px solid #cbd5df}input:focus{outline:3px solid #6a2ca044;border-color:var(--brand)}button{border:0;background:var(--brand);color:#fff;font-weight:800}.scan{font-family:ui-monospace,monospace;overflow-wrap:anywhere}.check{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:12px}.step{padding:14px;border-radius:14px;background:#f6f7f9}@media(max-width:700px){.check{grid-template-columns:1fr}}</style></head><body><main class="shell">
<a class="back" href="/admin/hardware">← Hardware Manager</a>
<h1>Barcode-Scanner Abnahmetest</h1>
<p class="muted">Lokaler Test für USB-HID-Handscanner. Scandaten werden weder gespeichert noch protokolliert.</p>
<?php if(is_array($result)):?><div class="notice <?=e((string)$result['class'])?>"><strong><?=e((string)$result['title'])?></strong><br><?=e((string)$result['detail'])?><?php if($scan!==''):?><div class="scan">Empfangen: <?=e($scan)?> · <?=strlen($scan)?> Zeichen</div><?php endif;?></div><?php endif;?>
<section class="card"><h2>1. Scan mit Enter-Suffix</h2><p class="muted">In das erste Feld scannen. Sendet der Scanner am Ende Enter, wird das Formular automatisch wie bei einer Tastatur abgeschickt.</p><form method="post"><input type="hidden" name="csrf" value="<?=e(csrfToken())?>"><label for="scan_code">Scanner-Eingabe</label><input id="scan_code" name="scan_code" maxlength="256" autocomplete="off" autofocus inputmode="text" placeholder="Hier EAN-8, EAN-13, Code 128 oder QR scannen"><label for="tab_target">Tab-Zielfeld</label><input id="tab_target" name="tab_target" autocomplete="off" placeholder="Bei Tab-Suffix sollte der Fokus hier landen"><button type="submit">Scan manuell auswerten</button></form></section>
<section class="card"><h2>2. Physische Abnahme</h2><div class="check"><div class="step"><strong>EAN-8</strong><br><span class="muted">gültige Prüfziffer und kompletter Wert</span></div><div class="step"><strong>EAN-13</strong><br><span class="muted">gültige Prüfziffer und kompletter Wert</span></div><div class="step"><strong>Code 128 / QR</strong><br><span class="muted">Nutzdaten vollständig; Symbologie am Scanner/Etikett verifizieren</span></div><div class="step"><strong>Suffix</strong><br><span class="muted">Enter = absenden, Tab = Fokus ins zweite Feld</span></div><div class="step"><strong>Schnelltest</strong><br><span class="muted">mindestens 50 Wiederholungen ohne verlorene Zeichen</span></div><div class="step"><strong>Hotplug</strong><br><span class="muted">abziehen, wieder anstecken und erneut scannen – ohne Neustart</span></div></div></section>
<section class="card"><h2>Was dieser Test noch nicht beweist</h2><p class="muted">Er ersetzt weder den realen Kassen-/Artikelfluss noch die Freigabe einer konkreten Scanner-Serie. Tastaturlayout, Tab-Suffix, schnelle Serien und Boot-mit-angeschlossenem-Scanner müssen auf der echten Release-Hardware dokumentiert werden.</p></section>
</main></body></html>
