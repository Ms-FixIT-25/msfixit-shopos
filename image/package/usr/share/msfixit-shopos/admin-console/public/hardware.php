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

function apiCall(string $path, string $method = 'GET', array $extra = []): array
{
    $allowedPaths = ['/health', '/status', '/history', '/events', '/recommendations', '/settings', '/diagnostic', '/actions/apply', '/actions/rollback'];
    if (!in_array($path, $allowedPaths, true) || !in_array($method, ['GET', 'POST'], true)) {
        return ['ok' => false, 'error' => 'client_rejected_request'];
    }
    $socket = @stream_socket_client('unix:///run/msfixit-hardware-manager/api.sock', $errno, $error, 1.5, STREAM_CLIENT_CONNECT);
    if ($socket === false) {
        return ['ok' => false, 'error' => 'manager_unavailable', 'detail' => $error ?: ('errno ' . $errno)];
    }
    stream_set_timeout($socket, 4);
    $request = array_merge(['api' => 'v1', 'method' => $method, 'path' => $path], $extra);
    $encoded = json_encode($request, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR);
    fwrite($socket, $encoded . "\n");
    $line = fgets($socket, 1048577);
    fclose($socket);
    if ($line === false || strlen($line) > 1048576) {
        return ['ok' => false, 'error' => 'invalid_manager_response'];
    }
    try {
        $decoded = json_decode($line, true, 128, JSON_THROW_ON_ERROR);
    } catch (JsonException) {
        return ['ok' => false, 'error' => 'invalid_manager_response'];
    }
    return is_array($decoded) ? $decoded : ['ok' => false, 'error' => 'invalid_manager_response'];
}

function bytes(?int $value): string
{
    if ($value === null) return '–';
    $units = ['B', 'KB', 'MB', 'GB', 'TB'];
    $number = (float)$value;
    $index = 0;
    while ($number >= 1024 && $index < count($units) - 1) {
        $number /= 1024;
        $index++;
    }
    return number_format($number, $index >= 2 ? 1 : 0, ',', '.') . ' ' . $units[$index];
}

function pct(?int $part, ?int $total, bool $used = false): ?int
{
    if ($part === null || $total === null || $total <= 0) return null;
    $value = $used ? (1 - $part / $total) * 100 : $part / $total * 100;
    return (int)max(0, min(100, round($value)));
}

function thermalLabel(string $level): string
{
    return match ($level) {
        'normal' => 'Normal',
        'elevated' => 'Erhöht',
        'warning' => 'Warnung',
        'critical' => 'Kritisch',
        'emergency' => 'Notfall',
        default => 'Unbekannt',
    };
}

function modeLabel(string $mode): string
{
    return match ($mode) {
        'observe' => 'Beobachten',
        'recommend' => 'Empfehlen',
        'automatic' => 'Automatisch optimieren',
        default => 'Unbekannt',
    };
}

$message = '';
$messageClass = 'success';
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $token = (string)($_POST['csrf'] ?? '');
    if (!hash_equals(csrfToken(), $token)) {
        http_response_code(403);
        exit('Ungültige Anfrage.');
    }
    $password = (string)($_POST['admin_password'] ?? '');
    $operation = (string)($_POST['operation'] ?? '');
    if ($operation === 'apply') {
        $id = (string)($_POST['recommendation_id'] ?? '');
        $result = apiCall('/actions/apply', 'POST', ['recommendation_id' => $id, 'password' => $password]);
        $message = ($result['ok'] ?? false) ? 'Optimierung wurde geprüft, angewandt und als Transaktion protokolliert.' : 'Optimierung wurde nicht angewandt: ' . (string)($result['error'] ?? 'unbekannter Fehler');
        $messageClass = ($result['ok'] ?? false) ? 'success' : 'error';
        if (!empty($result['transaction_id'])) {
            $message .= ' Rollback-ID: ' . (string)$result['transaction_id'];
        }
    } elseif ($operation === 'rollback') {
        $transaction = (string)($_POST['transaction_id'] ?? '');
        $result = apiCall('/actions/rollback', 'POST', ['transaction_id' => $transaction, 'password' => $password]);
        $message = ($result['ok'] ?? false) ? 'Rollback erfolgreich geprüft und ausgeführt.' : 'Rollback fehlgeschlagen: ' . (string)($result['error'] ?? 'unbekannter Fehler');
        $messageClass = ($result['ok'] ?? false) ? 'success' : 'error';
    } elseif ($operation === 'settings') {
        $mode = (string)($_POST['mode'] ?? 'observe');
        $sample = (int)($_POST['sample_interval_seconds'] ?? 30);
        $shutdown = isset($_POST['emergency_shutdown_enabled']);
        $result = apiCall('/settings', 'POST', [
            'password' => $password,
            'body' => [
                'mode' => $mode,
                'sample_interval_seconds' => $sample,
                'emergency_shutdown_enabled' => $shutdown,
                'confirm_emergency_shutdown' => $shutdown && isset($_POST['confirm_emergency_shutdown']),
            ],
        ]);
        $message = ($result['ok'] ?? false) ? 'Hardware-Manager-Einstellungen gespeichert.' : 'Einstellungen wurden abgelehnt: ' . (string)($result['error'] ?? 'unbekannter Fehler');
        $messageClass = ($result['ok'] ?? false) ? 'success' : 'error';
    }
    $password = '';
}

if (isset($_GET['download']) && $_GET['download'] === 'diagnostic') {
    $diagnostic = apiCall('/diagnostic');
    header('Content-Type: application/json; charset=utf-8');
    header('Content-Disposition: attachment; filename="shopos-hardware-diagnostic.json"');
    echo json_encode($diagnostic, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR);
    exit;
}

$statusResponse = apiCall('/status');
$historyResponse = apiCall('/history');
$eventsResponse = apiCall('/events');
$settingsResponse = apiCall('/settings');
$available = ($statusResponse['ok'] ?? false) && is_array($statusResponse['snapshot'] ?? null);
$snapshot = $available ? $statusResponse['snapshot'] : [];
$history = is_array($historyResponse['history'] ?? null) ? $historyResponse['history'] : [];
$events = is_array($eventsResponse['events'] ?? null) ? array_reverse($eventsResponse['events']) : [];
$settings = is_array($settingsResponse['settings'] ?? null) ? $settingsResponse['settings'] : ['mode' => 'observe', 'sample_interval_seconds' => 30, 'emergency_shutdown_enabled' => false];
$section = (string)($_GET['section'] ?? 'dashboard');
$allowedSections = ['dashboard', 'system', 'thermal', 'performance', 'storage', 'network', 'peripherals', 'recommendations', 'events', 'settings', 'expert'];
if (!in_array($section, $allowedSections, true)) $section = 'dashboard';

$thermal = is_array($snapshot['thermal'] ?? null) ? $snapshot['thermal'] : [];
$cpu = is_array($snapshot['cpu'] ?? null) ? $snapshot['cpu'] : [];
$memory = is_array($snapshot['memory'] ?? null) ? $snapshot['memory'] : [];
$storage = is_array($snapshot['storage'] ?? null) ? $snapshot['storage'] : [];
$platform = is_array($snapshot['platform'] ?? null) ? $snapshot['platform'] : [];
$recommendations = is_array($snapshot['recommendations'] ?? null) ? $snapshot['recommendations'] : [];
$network = is_array($snapshot['network'] ?? null) ? $snapshot['network'] : [];
$usb = is_array($snapshot['usb'] ?? null) ? $snapshot['usb'] : [];
$services = is_array($snapshot['services'] ?? null) ? $snapshot['services'] : [];
$ramFreePct = pct(isset($memory['available_bytes']) ? (int)$memory['available_bytes'] : null, isset($memory['total_bytes']) ? (int)$memory['total_bytes'] : null);
$diskUsedPct = pct(isset($storage['free_bytes']) ? (int)$storage['free_bytes'] : null, isset($storage['total_bytes']) ? (int)$storage['total_bytes'] : null, true);
$temperature = isset($thermal['primary_c']) && is_numeric($thermal['primary_c']) ? (float)$thermal['primary_c'] : null;
$thermalLevel = (string)($thermal['level'] ?? 'unknown');

$points = [];
foreach (array_slice($history, -60) as $row) {
    $temp = $row['thermal']['primary_c'] ?? null;
    if (is_numeric($temp)) $points[] = (float)$temp;
}
$svgPoints = '';
if (count($points) > 1) {
    $coords = [];
    $count = count($points);
    foreach ($points as $index => $value) {
        $x = 10 + ($index / ($count - 1)) * 380;
        $y = 110 - max(0, min(100, $value)) / 100 * 95;
        $coords[] = number_format($x, 1, '.', '') . ',' . number_format($y, 1, '.', '');
    }
    $svgPoints = implode(' ', $coords);
}
?>
<!doctype html>
<html lang="de">
<head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="refresh" content="30">
<title>ShopOS Hardware Manager</title>
<style>
:root{--ink:#18212b;--muted:#687684;--line:#dde6ec;--surface:#fff;--soft:#f3f7f9;--brand:#6a2ca0;--brand2:#9b4dcc;--ok:#16845b;--warn:#b36b00;--bad:#c52d49;--blue:#2876c7;--shadow:0 12px 34px rgba(24,33,43,.09)}*{box-sizing:border-box}body{margin:0;background:linear-gradient(145deg,#f8f4fb,#edf5f8 52%,#fbfcfd);color:var(--ink);font-family:Inter,ui-sans-serif,system-ui,-apple-system,"Segoe UI",sans-serif}.app{min-height:100vh;display:grid;grid-template-columns:270px 1fr}.side{background:#17121d;color:#fff;padding:24px 18px;position:sticky;top:0;height:100vh;display:flex;flex-direction:column}.brand{display:flex;gap:12px;align-items:center;padding:4px 10px 24px;font-weight:850}.logo{width:44px;height:44px;display:grid;place-items:center;border-radius:15px;background:#ffffff17;font-size:22px}.brand small{display:block;color:#bdb2c5;font-weight:500}.nav{display:grid;gap:6px}.nav a{color:#d9d1df;text-decoration:none;padding:11px 13px;border-radius:12px}.nav a:hover,.nav a.on{background:#ffffff12;color:#fff}.sidefoot{margin-top:auto;padding:14px 10px;color:#a99db1;font-size:12px}.main{padding:28px 34px 54px;min-width:0}.top{display:flex;justify-content:space-between;gap:18px;align-items:center;margin-bottom:24px}.top h1{margin:3px 0 0;font-size:30px}.eyebrow{font-size:11px;text-transform:uppercase;letter-spacing:.14em;font-weight:850;color:var(--brand2)}.button,button{border:0;border-radius:12px;padding:11px 15px;background:var(--brand);color:#fff;font:inherit;font-weight:750;cursor:pointer;text-decoration:none;display:inline-block}.button.secondary,button.secondary{background:#edf0f3;color:var(--ink)}.grid{display:grid;grid-template-columns:repeat(12,minmax(0,1fr));gap:16px}.card{grid-column:span 3;background:#fff;border:1px solid #e6ebef;border-radius:20px;padding:21px;box-shadow:0 7px 22px rgba(24,33,43,.05)}.card.span6{grid-column:span 6}.card.span8{grid-column:span 8}.card.full{grid-column:1/-1}.metric{font-size:34px;font-weight:880;letter-spacing:-.04em;margin:8px 0}.muted{color:var(--muted)}.pill{display:inline-flex;padding:6px 9px;border-radius:99px;font-size:12px;font-weight:850;background:#edf0f3}.pill.normal,.pill.active{background:#e1f5ec;color:var(--ok)}.pill.elevated,.pill.warning,.pill.inactive{background:#fff0d7;color:var(--warn)}.pill.critical,.pill.emergency,.pill.failed{background:#fde6eb;color:var(--bad)}.bar{height:9px;background:#e7edf1;border-radius:99px;overflow:hidden}.bar span{display:block;height:100%;background:linear-gradient(90deg,var(--brand),var(--brand2))}.notice{padding:14px 16px;border-radius:14px;margin-bottom:18px;background:#e5f5ed;color:#12623f}.notice.error{background:#fde7ec;color:#9d2039}.rows{display:grid}.row{display:grid;grid-template-columns:minmax(160px,.7fr) 1.3fr;gap:14px;padding:11px 0;border-bottom:1px solid var(--line)}.row:last-child{border:0}.rec{border:1px solid var(--line);border-radius:16px;padding:18px;margin:12px 0}.rec h3{margin:0 0 8px}.rec-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:12px;margin-top:12px}.mini{background:var(--soft);border-radius:12px;padding:12px}.mini strong{display:block;margin-bottom:3px}form.stack{display:grid;gap:12px;max-width:680px}input,select{font:inherit;padding:11px;border:1px solid #cbd6de;border-radius:11px;background:#fff}.check{display:flex;gap:9px;align-items:flex-start}.check input{margin-top:4px}.chart{width:100%;height:120px;background:linear-gradient(#fff,#f6f8fa);border-radius:14px;border:1px solid var(--line)}table{width:100%;border-collapse:collapse}th,td{text-align:left;padding:10px;border-bottom:1px solid var(--line);vertical-align:top}code{background:#eef2f4;border-radius:6px;padding:2px 5px}.danger{color:var(--bad);font-weight:750}@media(max-width:1050px){.card{grid-column:span 6}.card.span8{grid-column:span 12}}@media(max-width:760px){.app{grid-template-columns:1fr}.side{position:static;height:auto}.nav{grid-template-columns:repeat(2,1fr)}.main{padding:20px}.card,.card.span6,.card.span8{grid-column:1/-1}.top{align-items:flex-start;flex-direction:column}.row,.rec-grid{grid-template-columns:1fr}}
</style>
</head>
<body><div class="app"><aside class="side"><div class="brand"><span class="logo">⚙</span><div>Hardware Manager<small>Ms. FixIT ShopOS</small></div></div><nav class="nav"><?php foreach(['dashboard'=>'Dashboard','system'=>'System','thermal'=>'Temperatur','performance'=>'CPU & RAM','storage'=>'Datenträger','network'=>'Netzwerk','peripherals'=>'Peripherie','recommendations'=>'Empfehlungen','events'=>'Ereignisse','settings'=>'Automatik','expert'=>'Expertenmodus'] as $key=>$label): ?><a class="<?=$section===$key?'on':''?>" href="/admin/hardware?section=<?=e($key)?>"><?=e($label)?></a><?php endforeach; ?></nav><div class="sidefoot"><a style="color:inherit" href="/admin/">← ShopOS Control Center</a><br><br>Messdaten bleiben lokal.</div></aside><main class="main"><header class="top"><div><span class="eyebrow">Hardware • Energie • Stabilität</span><h1><?=e(['dashboard'=>'Dein System auf einen Blick','system'=>'Systemübersicht','thermal'=>'Temperaturen & Kühlung','performance'=>'CPU & Arbeitsspeicher','storage'=>'Datenträger','network'=>'Netzwerk','peripherals'=>'Peripheriegeräte','recommendations'=>'Optimierungsempfehlungen','events'=>'Ereignisse & Warnungen','settings'=>'Automatische Optimierung','expert'=>'Expertenmodus'][$section])?></h1></div><div><a class="button secondary" href="/admin/hardware?download=diagnostic">Diagnose exportieren</a></div></header>
<?php if ($message !== ''): ?><div class="notice <?=e($messageClass)?>"><?=e($message)?></div><?php endif; ?>
<?php if (!$available): ?><div class="notice error"><strong>Hardware Manager ist noch nicht erreichbar.</strong><br>Die GUI bleibt funktionsfähig, aber es werden keine Werte erfunden. Prüfe <code>systemctl status msfixit-hardware-manager</code>.</div><?php else: ?>
<?php if ($section === 'dashboard'): ?>
<section class="grid"><article class="card"><span class="eyebrow">Temperatur</span><div class="metric"><?=$temperature===null?'–':e(number_format($temperature,1,',','.')).' °C'?></div><span class="pill <?=e($thermalLevel)?>"><?=e(thermalLabel($thermalLevel))?></span></article><article class="card"><span class="eyebrow">CPU</span><div class="metric"><?=isset($cpu['utilization_percent'])&&is_numeric($cpu['utilization_percent'])?e(number_format((float)$cpu['utilization_percent'],1,',','.')).' %':'–'?></div><p class="muted">Aktuelle Auslastung</p></article><article class="card"><span class="eyebrow">RAM verfügbar</span><div class="metric"><?=$ramFreePct===null?'–':$ramFreePct.' %'?></div><div class="bar"><span style="width:<?=($ramFreePct??0)?>%"></span></div></article><article class="card"><span class="eyebrow">Datenträger belegt</span><div class="metric"><?=$diskUsedPct===null?'–':$diskUsedPct.' %'?></div><div class="bar"><span style="width:<?=($diskUsedPct??0)?>%"></span></div></article><article class="card span8"><h2>Temperaturverlauf</h2><svg class="chart" viewBox="0 0 400 120" role="img" aria-label="Temperaturverlauf der letzten Messungen"><line x1="10" y1="110" x2="390" y2="110" stroke="#cad5dd"/><line x1="10" y1="34" x2="390" y2="34" stroke="#e8a941" stroke-dasharray="4 4"/><?php if($svgPoints!==''): ?><polyline fill="none" stroke="#6a2ca0" stroke-width="3" points="<?=e($svgPoints)?>"/><?php endif; ?></svg><p class="muted">Orange Linie ≈ 80 °C. Die Notfalllogik nutzt mehrere Messungen und Hysterese, nicht einen einzelnen Peak.</p></article><article class="card"><h2>Offene Punkte</h2><div class="metric"><?=count($recommendations)?></div><p class="muted">Erkannte, erklärbare Optimierungsmöglichkeiten.</p><a class="button" href="/admin/hardware?section=recommendations">Ansehen</a></article></section>
<?php elseif ($section === 'system'): ?>
<section class="grid"><article class="card full"><div class="rows"><?php foreach(['platform_family'=>'Plattform','model'=>'Modell','board_revision'=>'Board-Revision','distribution'=>'Betriebssystem','distribution_version'=>'Version','kernel'=>'Kernel','architecture'=>'Architektur','cpu_model'=>'CPU','physical_cores'=>'Physische Kerne','logical_cpus'=>'Threads'] as $key=>$label): ?><div class="row"><strong><?=e($label)?></strong><span><?=e((string)($platform[$key]??'nicht verfügbar'))?></span></div><?php endforeach; ?></div></article></section>
<?php elseif ($section === 'thermal'): ?>
<section class="grid"><article class="card span6"><span class="eyebrow">Schutzstatus</span><div class="metric"><?=$temperature===null?'–':e(number_format($temperature,1,',','.')).' °C'?></div><span class="pill <?=e($thermalLevel)?>"><?=e(thermalLabel($thermalLevel))?></span><p class="muted" style="margin-top:12px"><?=e((string)($thermal['decision_reason']??''))?></p></article><article class="card span6"><h2>Raspberry-Pi-Schutzsignale</h2><div class="rows"><div class="row"><strong>Unterspannung jetzt</strong><span><?=($thermal['current_undervoltage']??null)===true?'Ja':(($thermal['current_undervoltage']??null)===false?'Nein':'nicht verfügbar')?></span></div><div class="row"><strong>Unterspannung seit Boot</strong><span><?=($thermal['undervoltage_occurred']??null)===true?'Ja':(($thermal['undervoltage_occurred']??null)===false?'Nein':'nicht verfügbar')?></span></div><div class="row"><strong>Drosselung jetzt</strong><span><?=($thermal['current_throttling']??null)===true?'Ja':(($thermal['current_throttling']??null)===false?'Nein':'nicht verfügbar')?></span></div></div></article><article class="card full"><h2>Erkannte Temperatursensoren</h2><table><thead><tr><th>Sensor</th><th>Wert</th><th>Quelle</th></tr></thead><tbody><?php foreach(($thermal['sensors']??[]) as $sensor): ?><tr><td><?=e((string)($sensor['label']??'Sensor'))?></td><td><?=e(number_format((float)($sensor['temperature_c']??0),1,',','.'))?> °C</td><td><code><?=e((string)($sensor['source']??''))?></code></td></tr><?php endforeach; ?></tbody></table></article></section>
<?php elseif ($section === 'performance'): ?>
<section class="grid"><article class="card span6"><h2>CPU</h2><div class="rows"><div class="row"><strong>Auslastung</strong><span><?=e((string)($cpu['utilization_percent']??'–'))?> %</span></div><div class="row"><strong>I/O-Wartezeit</strong><span><?=e((string)($cpu['iowait_percent']??'–'))?> %</span></div><div class="row"><strong>Takt</strong><span><?=e((string)($cpu['frequency_mhz']??'–'))?> MHz</span></div><div class="row"><strong>Governor</strong><span><?=e((string)($cpu['governor']??'nicht verfügbar'))?></span></div><div class="row"><strong>Load 1/5/15</strong><span><?=e((string)($cpu['load_1m']??'–'))?> / <?=e((string)($cpu['load_5m']??'–'))?> / <?=e((string)($cpu['load_15m']??'–'))?></span></div></div></article><article class="card span6"><h2>RAM & Swap</h2><div class="rows"><div class="row"><strong>RAM gesamt</strong><span><?=e(bytes(isset($memory['total_bytes'])?(int)$memory['total_bytes']:null))?></span></div><div class="row"><strong>RAM verfügbar</strong><span><?=e(bytes(isset($memory['available_bytes'])?(int)$memory['available_bytes']:null))?></span></div><div class="row"><strong>Swap gesamt</strong><span><?=e(bytes(isset($memory['swap_total_bytes'])?(int)$memory['swap_total_bytes']:null))?></span></div><div class="row"><strong>Swap frei</strong><span><?=e(bytes(isset($memory['swap_free_bytes'])?(int)$memory['swap_free_bytes']:null))?></span></div></div><p class="muted">Swap-Nutzung allein ist kein Fehler. ShopOS bewertet sie zusammen mit verfügbarem RAM und I/O-Wartezeit.</p></article><article class="card full"><h2>ShopOS-Dienste</h2><table><thead><tr><th>Dienst</th><th>Status</th><th>RAM</th></tr></thead><tbody><?php foreach($services as $service): ?><tr><td><?=e((string)($service['unit']??''))?></td><td><span class="pill <?=e((string)($service['active_state']??'unknown'))?>"><?=e((string)($service['active_state']??'unknown'))?></span></td><td><?=e(bytes(isset($service['memory_bytes'])&&is_numeric($service['memory_bytes'])?(int)$service['memory_bytes']:null))?></td></tr><?php endforeach; ?></tbody></table></article></section>
<?php elseif ($section === 'storage'): ?>
<section class="grid"><article class="card span6"><h2>Persistenter Speicher</h2><div class="rows"><?php foreach(['mountpoint'=>'Mountpoint','source'=>'Gerät','filesystem'=>'Dateisystem','boot_medium'=>'Medium'] as $key=>$label): ?><div class="row"><strong><?=e($label)?></strong><span><?=e((string)($storage[$key]??'nicht verfügbar'))?></span></div><?php endforeach; ?><div class="row"><strong>Frei</strong><span><?=e(bytes(isset($storage['free_bytes'])?(int)$storage['free_bytes']:null))?></span></div><div class="row"><strong>TRIM</strong><span><?=($storage['trim_supported']??null)===true?'Unterstützt':(($storage['trim_supported']??null)===false?'Nicht gemeldet':'Unbekannt')?></span></div></div></article><article class="card span6"><h2>Warum das wichtig ist</h2><p class="muted">Hohe I/O-Wartezeit kann ShopOS bremsen, obwohl die CPU fast frei ist. Bei USB-SSDs sind Link-Geschwindigkeit, Kabel und TRIM wichtiger als aggressive CPU-Einstellungen.</p></article></section>
<?php elseif ($section === 'network'): ?>
<section class="grid"><article class="card full"><h2>Netzwerkadapter</h2><table><thead><tr><th>Adapter</th><th>Status</th><th>Link</th><th>WLAN</th><th>Fehler</th></tr></thead><tbody><?php foreach($network as $iface): ?><tr><td><?=e((string)($iface['name']??''))?></td><td><?=e((string)($iface['state']??'unknown'))?></td><td><?=isset($iface['speed_mbps'])&&is_numeric($iface['speed_mbps'])?e((string)$iface['speed_mbps']).' Mbit/s':'–'?></td><td><?=isset($iface['wireless_signal_dbm'])&&is_numeric($iface['wireless_signal_dbm'])?e((string)$iface['wireless_signal_dbm']).' dBm':'–'?></td><td>RX <?=e((string)($iface['rx_errors']??0))?> / TX <?=e((string)($iface['tx_errors']??0))?></td></tr><?php endforeach; ?></tbody></table><p class="muted">Aktive Internet-Speedtests laufen standardmäßig nicht. Sie erzeugen selbst Last und benötigen eine ausdrückliche Zustimmung.</p></article></section>
<?php elseif ($section === 'peripherals'): ?>
<section class="grid"><article class="card full"><h2>USB-Geräte</h2><table><thead><tr><th>Gerät</th><th>USB-Spezifikation</th><th>Ausgehandelt</th><th>ID</th></tr></thead><tbody><?php foreach($usb as $device): ?><tr><td><?=e((string)($device['product']??$device['manufacturer']??$device['sysfs_name']??'USB-Gerät'))?></td><td><?=e((string)($device['usb_spec']??'–'))?></td><td><?=isset($device['negotiated_mbps'])&&is_numeric($device['negotiated_mbps'])?e((string)$device['negotiated_mbps']).' Mbit/s':'–'?></td><td><code><?=e((string)($device['vendor_id']??'----'))?>:<?=e((string)($device['product_id']??'----'))?></code></td></tr><?php endforeach; ?></tbody></table></article></section>
<?php elseif ($section === 'recommendations'): ?>
<section><?php if(!$recommendations): ?><div class="notice">Aktuell gibt es keine konkrete Optimierungsempfehlung. Das bedeutet nicht, dass ShopOS „maximal schnell“ ist – nur, dass keine belastbare Auffälligkeit vorliegt.</div><?php endif; ?><?php foreach($recommendations as $rec): ?><article class="rec"><span class="pill <?=e((string)($rec['severity']??'notice'))?>"><?=e((string)($rec['severity']??'notice'))?></span><h3><?=e((string)($rec['title']??'Empfehlung'))?></h3><p><?=e((string)($rec['problem']??''))?></p><div class="rec-grid"><div class="mini"><strong>Ursache</strong><?=e((string)($rec['cause']??''))?></div><div class="mini"><strong>Auswirkung</strong><?=e((string)($rec['impact']??''))?></div><div class="mini"><strong>Maßnahme</strong><?=e((string)($rec['action']??''))?></div><div class="mini"><strong>Risiko</strong><?=e((string)($rec['risk']??''))?></div></div><?php if(!empty($rec['action_id'])): ?><form method="post" class="stack" style="margin-top:14px"><input type="hidden" name="csrf" value="<?=e(csrfToken())?>"><input type="hidden" name="operation" value="apply"><input type="hidden" name="recommendation_id" value="<?=e((string)$rec['id'])?>"><label>Administrator-Passwort zur Bestätigung<input type="password" name="admin_password" required autocomplete="current-password"></label><label class="check"><input type="checkbox" required>Ich habe Nutzen und Risiko gelesen und möchte diese reversible Änderung anwenden.</label><button type="submit">Sicher anwenden</button></form><?php endif; ?></article><?php endforeach; ?></section>
<?php elseif ($section === 'events'): ?>
<section class="grid"><article class="card full"><h2>Letzte Ereignisse</h2><table><thead><tr><th>Zeit</th><th>Stufe</th><th>Ereignis</th></tr></thead><tbody><?php foreach(array_slice($events,0,100) as $event): ?><tr><td><?=e((string)($event['timestamp']??''))?></td><td><?=e((string)($event['severity']??''))?></td><td><?=e((string)($event['message']??''))?></td></tr><?php endforeach; ?></tbody></table></article></section>
<?php elseif ($section === 'settings'): ?>
<section class="grid"><article class="card span8"><h2>Betriebsart</h2><form method="post" class="stack"><input type="hidden" name="csrf" value="<?=e(csrfToken())?>"><input type="hidden" name="operation" value="settings"><label>Modus<select name="mode"><option value="observe" <?=($settings['mode']??'')==='observe'?'selected':''?>>Beobachten – nichts ändern</option><option value="recommend" <?=($settings['mode']??'')==='recommend'?'selected':''?>>Empfehlen – Änderungen bestätigen</option><option value="automatic" <?=($settings['mode']??'')==='automatic'?'selected':''?>>Automatisch – nur getestete reversible Regeln</option></select></label><label>Messintervall<select name="sample_interval_seconds"><?php foreach([10,15,30,60,120] as $seconds): ?><option value="<?=$seconds?>" <?=((int)($settings['sample_interval_seconds']??30))===$seconds?'selected':''?>><?=$seconds?> Sekunden</option><?php endforeach; ?></select></label><label class="check"><input type="checkbox" name="emergency_shutdown_enabled" value="1" <?=($settings['emergency_shutdown_enabled']??false)?'checked':''?>>Notfall-Abschaltentscheidung aktivieren. <strong>Im aktuellen Hardware-Teststand wird nur die Zulässigkeit protokolliert; es erfolgt noch kein automatisches Poweroff.</strong></label><label class="check"><input type="checkbox" name="confirm_emergency_shutdown" value="1">Ich bestätige die Notfalllogik ausdrücklich.</label><label>Administrator-Passwort<input type="password" name="admin_password" required autocomplete="current-password"></label><button type="submit">Einstellungen speichern</button></form></article><article class="card"><span class="eyebrow">Aktiver Modus</span><div class="metric" style="font-size:24px"><?=e(modeLabel((string)($settings['mode']??'observe')))?></div><p class="muted">Overclocking und Spannungsanhebung bleiben in allen Modi ausgeschlossen.</p></article></section>
<?php elseif ($section === 'expert'): ?>
<section class="grid"><article class="card span6"><h2>Rohdaten</h2><p class="muted">Technische Daten sind ergänzend sichtbar. Nicht verfügbare Funktionen werden nicht simuliert.</p><pre style="white-space:pre-wrap;max-height:34rem;overflow:auto;background:#11161c;color:#eaf0f4;padding:16px;border-radius:14px"><?=e(json_encode(['platform'=>$platform,'capabilities'=>$snapshot['capabilities']??[],'thermal'=>$thermal,'storage'=>$storage],JSON_PRETTY_PRINT|JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES) ?: '')?></pre></article><article class="card span6"><h2>Rollback</h2><p class="muted">Gib eine vom Hardware Manager ausgegebene 24-stellige Transaktions-ID ein. Der privilegierte Helper stellt ausschließlich die dafür gesicherten Werte wieder her.</p><form method="post" class="stack"><input type="hidden" name="csrf" value="<?=e(csrfToken())?>"><input type="hidden" name="operation" value="rollback"><label>Transaktions-ID<input name="transaction_id" pattern="[a-f0-9]{24}" maxlength="24" required></label><label>Administrator-Passwort<input type="password" name="admin_password" required autocomplete="current-password"></label><button type="submit">Rollback prüfen und ausführen</button></form><h3 style="margin-top:24px">Sicherheitsgrenze</h3><p class="muted">Die GUI kann keine freien Shell-Befehle, Pfade, Kernelparameter oder beliebige systemd-Dienste an den Helper übergeben.</p></article></section>
<?php endif; ?>
<?php endif; ?></main></div></body></html>
