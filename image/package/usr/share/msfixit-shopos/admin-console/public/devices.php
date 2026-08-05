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
header("Content-Security-Policy: default-src 'self'; style-src 'self' 'unsafe-inline'; script-src 'none'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'");
header('Cache-Control: no-store');

if (($_SESSION['authenticated'] ?? false) !== true) {
    header('Location: /admin/');
    exit;
}
if (empty($_SESSION['csrf'])) {
    $_SESSION['csrf'] = bin2hex(random_bytes(32));
}
$csrf = (string)$_SESSION['csrf'];

function h(string $value): string { return htmlspecialchars($value, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8'); }
function decodeField(array $data, string $key): string {
    $raw = (string)($data[$key] ?? '');
    $decoded = base64_decode($raw, true);
    return $decoded === false ? '' : $decoded;
}
function queueRecords(): array {
    $records = [];
    foreach (glob('/run/msfixit-shopos/devices/*.pending') ?: [] as $path) {
        $id = basename($path, '.pending');
        if (!preg_match('/^[a-f0-9]{24}$/', $id)) { continue; }
        $data = [];
        foreach (file($path, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) ?: [] as $line) {
            [$key, $value] = array_pad(explode('=', $line, 2), 2, '');
            if (in_array($key, ['DEVICE_B64','UUID_B64','LABEL_B64','FSTYPE_B64','SEEN_AT'], true)) { $data[$key] = $value; }
        }
        $records[] = [
            'id' => $id,
            'device' => decodeField($data, 'DEVICE_B64'),
            'uuid' => decodeField($data, 'UUID_B64'),
            'label' => decodeField($data, 'LABEL_B64'),
            'fstype' => decodeField($data, 'FSTYPE_B64'),
            'seen_at' => (string)($data['SEEN_AT'] ?? ''),
        ];
    }
    return $records;
}
function runDeviceAction(string $action, string $argument): array {
    $allowed = ['device-mount', 'device-ignore'];
    if (!in_array($action, $allowed, true)) { return [2, 'Aktion nicht erlaubt.']; }
    $lines = []; $code = 1;
    exec('sudo -n /usr/local/sbin/msfixit-admin-action ' . escapeshellarg($action) . ' ' . escapeshellarg($argument) . ' 2>&1', $lines, $code);
    return [$code, trim(implode("\n", array_slice($lines, -20)))];
}

$message = '';
$error = false;
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $token = (string)($_POST['csrf'] ?? '');
    if (!hash_equals($csrf, $token)) { http_response_code(403); exit('Ungültige Anfrage.'); }
    $id = (string)($_POST['device_id'] ?? '');
    $choice = (string)($_POST['choice'] ?? '');
    if (!preg_match('/^[a-f0-9]{24}$/', $id)) { $code = 2; $output = 'Ungültige Gerätekennung.'; }
    elseif ($choice === 'read-only') { [$code, $output] = runDeviceAction('device-mount', "$id:read-only"); }
    elseif ($choice === 'read-write') { [$code, $output] = runDeviceAction('device-mount', "$id:read-write"); }
    elseif ($choice === 'ignore') { [$code, $output] = runDeviceAction('device-ignore', $id); }
    else { $code = 2; $output = 'Ungültige Auswahl.'; }
    $error = $code !== 0;
    $message = $error ? 'Das Gerät konnte nicht verarbeitet werden. ' . $output : ($choice === 'ignore' ? 'Das Gerät wird vorerst nicht eingebunden.' : 'Das Gerät wurde sicher eingebunden: ' . $output);
}
$devices = queueRecords();
?><!doctype html>
<html lang="de"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="refresh" content="5"><title>Geräte – ShopOS</title>
<style>
:root{font-family:Inter,ui-sans-serif,system-ui,sans-serif;color:#10243b;background:#f4f7fb}*{box-sizing:border-box}body{margin:0}.shell{max-width:980px;margin:auto;padding:24px}.top{display:flex;justify-content:space-between;align-items:center;gap:16px}.brand{font-size:1.2rem;font-weight:800}.back{color:#174d72;text-decoration:none;font-weight:700}.hero,.device,.empty,.notice{background:#fff;border:1px solid #dce6ef;border-radius:20px;padding:24px;box-shadow:0 10px 30px #16324a12;margin-top:18px}.hero h1{font-size:clamp(1.7rem,5vw,2.6rem);margin:.2rem 0}.hero p,.muted{color:#617286}.device{border-left:6px solid #2878b5}.device-head{display:flex;justify-content:space-between;gap:12px;align-items:flex-start}.badge{background:#e8f4ff;color:#125685;border-radius:999px;padding:6px 10px;font-size:.85rem;font-weight:800}.facts{display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:10px;margin:18px 0}.fact{background:#f6f9fc;border-radius:12px;padding:12px}.fact b{display:block;font-size:.78rem;color:#6e7e8d;margin-bottom:4px}.actions{display:flex;flex-wrap:wrap;gap:10px}.actions form{margin:0}.btn{border:0;border-radius:12px;padding:12px 16px;font:inherit;font-weight:800;cursor:pointer}.primary{background:#174d72;color:#fff}.secondary{background:#dcecf7;color:#174d72}.quiet{background:#eef2f5;color:#394b5b}.notice{font-weight:700}.notice.error{border-color:#efb6bd;color:#9d2433}.notice.ok{border-color:#a8dfbd;color:#176b35}.safe{margin-top:12px;font-size:.9rem;color:#526575}@media(max-width:560px){.shell{padding:14px}.top,.device-head{align-items:flex-start}.actions,.actions form,.btn{width:100%}}
</style></head><body><main class="shell"><header class="top"><div class="brand">Ms. FixIT ShopOS</div><a class="back" href="/admin/">← Zur Übersicht</a></header>
<section class="hero"><span class="badge">Geräte-Assistent</span><h1>Neues Gerät erkannt</h1><p>ShopOS bindet externe Datenträger nie ungefragt ein. Du entscheidest, wie das Gerät verwendet werden soll.</p></section>
<?php if ($message !== ''): ?><div class="notice <?=$error ? 'error' : 'ok'?>"><?=h($message)?></div><?php endif; ?>
<?php if ($devices === []): ?><section class="empty"><h2>Kein neues Gerät wartet</h2><p class="muted">Diese Seite prüft automatisch weiter. Sobald ein USB-Datenträger erkannt wird, erscheint hier eine Auswahl.</p></section><?php endif; ?>
<?php foreach ($devices as $device): $display = $device['label'] !== '' ? $device['label'] : 'Externer Datenträger'; ?>
<section class="device"><div class="device-head"><div><h2><?=h($display)?></h2><p class="muted">Möchtest du dieses Gerät jetzt einbinden?</p></div><span class="badge"><?=h(strtoupper($device['fstype']))?></span></div>
<div class="facts"><div class="fact"><b>Gerät</b><?=h($device['device'])?></div><div class="fact"><b>Kennung</b><?=h($device['uuid'] ?: 'nicht vorhanden')?></div><div class="fact"><b>Erkannt</b><?=h($device['seen_at'])?></div></div>
<div class="actions">
<form method="post"><input type="hidden" name="csrf" value="<?=h($csrf)?>"><input type="hidden" name="device_id" value="<?=h($device['id'])?>"><input type="hidden" name="choice" value="read-only"><button class="btn primary">Nur lesen – empfohlen</button></form>
<form method="post"><input type="hidden" name="csrf" value="<?=h($csrf)?>"><input type="hidden" name="device_id" value="<?=h($device['id'])?>"><input type="hidden" name="choice" value="read-write"><button class="btn secondary">Lesen und speichern</button></form>
<form method="post"><input type="hidden" name="csrf" value="<?=h($csrf)?>"><input type="hidden" name="device_id" value="<?=h($device['id'])?>"><input type="hidden" name="choice" value="ignore"><button class="btn quiet">Später entscheiden</button></form>
</div><p class="safe">Sicherheitsmodus: Programme können von externen Datenträgern nicht ausgeführt werden. System- und Boot-Datenträger werden nie angeboten.</p></section>
<?php endforeach; ?></main></body></html>
