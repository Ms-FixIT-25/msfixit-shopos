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

$configFile = '/etc/msfixit-shopos/admin-console.php';
$config = is_file($configFile) ? require $configFile : [];
$passwordHash = is_array($config) ? (string)($config['password_hash'] ?? '') : '';

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

function authenticated(): bool
{
    return ($_SESSION['authenticated'] ?? false) === true;
}

function runCommand(array $argv, int $timeout = 20): array
{
    if ($argv === [] || array_filter($argv, static fn($v): bool => !is_string($v)) !== []) {
        return [2, ''];
    }
    $process = proc_open(
        $argv,
        [1 => ['pipe', 'w'], 2 => ['pipe', 'w']],
        $pipes,
        null,
        ['PATH' => '/usr/sbin:/usr/bin:/sbin:/bin'],
        ['bypass_shell' => true]
    );
    if (!is_resource($process)) {
        return [127, ''];
    }
    stream_set_blocking($pipes[1], false);
    stream_set_blocking($pipes[2], false);
    $stdout = '';
    $stderr = '';
    $deadline = microtime(true) + max(1, $timeout);
    $code = null;
    while (true) {
        $stdout .= stream_get_contents($pipes[1]);
        $stderr .= stream_get_contents($pipes[2]);
        if (strlen($stdout) > 2097152) $stdout = substr($stdout, -2097152);
        if (strlen($stderr) > 2097152) $stderr = substr($stderr, -2097152);
        $status = proc_get_status($process);
        if (!$status['running']) {
            $code = (int)$status['exitcode'];
            break;
        }
        if (microtime(true) >= $deadline) {
            proc_terminate($process, 15);
            $grace = microtime(true) + 1.0;
            while (microtime(true) < $grace) {
                usleep(50000);
                $status = proc_get_status($process);
                if (!$status['running']) break;
            }
            if (($status['running'] ?? false) === true) proc_terminate($process, 9);
            $code = 124;
            break;
        }
        usleep(50000);
    }
    $stdout .= stream_get_contents($pipes[1]);
    $stderr .= stream_get_contents($pipes[2]);
    fclose($pipes[1]);
    fclose($pipes[2]);
    $closed = proc_close($process);
    if ($code === null || $code < 0) $code = $closed >= 0 ? $closed : 1;
    return [$code, trim($code === 0 ? $stdout : ($stderr !== '' ? $stderr : $stdout))];
}

function command(array $argv, int $timeout = 10): string
{
    [$code, $output] = runCommand($argv, $timeout);
    return $code === 0 ? $output : '';
}

function serviceState(string $unit): string
{
    $allowed = ['nginx.service', 'mariadb.service', 'redis-server.service'];
    if (!in_array($unit, $allowed, true)) {
        return 'unknown';
    }
    $state = command(['systemctl', 'is-active', $unit]);
    return in_array($state, ['active', 'inactive', 'failed', 'activating', 'deactivating'], true) ? $state : 'unknown';
}

function phpServiceState(): string
{
    $listing = command(['systemctl', 'list-unit-files', '--type=service', '--no-legend', 'php*-fpm.service']);
    foreach (preg_split('/\R/', $listing) ?: [] as $line) {
        $parts = preg_split('/\s+/', trim($line)) ?: [];
        $unit = (string)($parts[0] ?? '');
        if (!preg_match('/^php[0-9]+(?:\.[0-9]+)?-fpm\.service$/', $unit)) continue;
        $state = command(['systemctl', 'is-active', $unit]);
        return in_array($state, ['active', 'inactive', 'failed', 'activating', 'deactivating'], true) ? $state : 'unknown';
    }
    return 'unknown';
}

function adminAction(string $action, string $argument = ''): array
{
    $allowed = [
        'cache-flush' => [''],
        'backup-create' => [''],
        'service-restart' => ['nginx', 'mariadb', 'redis-server', 'php-fpm'],
        'logs' => ['nginx', 'mariadb', 'redis-server', 'php-fpm', 'shopos'],
    ];
    if (!isset($allowed[$action]) || !in_array($argument, $allowed[$action], true)) {
        return [2, 'Aktion abgelehnt.'];
    }
    $argv = ['sudo', '-n', '/usr/local/sbin/msfixit-admin-action', $action];
    if ($argument !== '') $argv[] = $argument;
    return runCommand($argv, $action === 'backup-create' ? 900 : 60);
}

function statusSnapshot(): array
{
    $temperatureRaw = trim((string)@file_get_contents('/sys/class/thermal/thermal_zone0/temp'));
    $temperature = is_numeric($temperatureRaw) ? round(((float)$temperatureRaw) / 1000, 1) : null;
    $diskFree = @disk_free_space('/data');
    $diskTotal = @disk_total_space('/data');
    $backups = glob('/data/backups/shopos-*.tar.zst') ?: [];
    rsort($backups, SORT_STRING);
    $uptimeParts = explode(' ', trim((string)@file_get_contents('/proc/uptime')));
    return [
        'version' => command(['/usr/local/bin/shopos-version']) ?: 'unbekannt',
        'uptime_seconds' => (int)floor((float)($uptimeParts[0] ?? 0)),
        'temperature_c' => $temperature,
        'storage' => [
            'free_bytes' => $diskFree === false ? null : (int)$diskFree,
            'total_bytes' => $diskTotal === false ? null : (int)$diskTotal,
        ],
        'latest_backup' => $backups[0] ?? null,
        'services' => [
            'nginx' => serviceState('nginx.service'),
            'mariadb' => serviceState('mariadb.service'),
            'redis' => serviceState('redis-server.service'),
            'php_fpm' => phpServiceState(),
        ],
    ];
}

function humanBytes(?int $bytes): string
{
    if ($bytes === null) return '–';
    $units = ['B', 'KB', 'MB', 'GB', 'TB'];
    $value = (float)$bytes;
    $index = 0;
    while ($value >= 1024 && $index < count($units) - 1) {
        $value /= 1024;
        $index++;
    }
    return number_format($value, $index > 1 ? 1 : 0, ',', '.') . ' ' . $units[$index];
}

function humanUptime(int $seconds): string
{
    $days = intdiv($seconds, 86400);
    $hours = intdiv($seconds % 86400, 3600);
    return $days > 0 ? $days . ' T ' . $hours . ' Std' : $hours . ' Std';
}

function stateLabel(string $state): string
{
    return match ($state) {
        'active' => 'Läuft',
        'inactive' => 'Gestoppt',
        'failed' => 'Fehler',
        'activating' => 'Startet',
        'deactivating' => 'Stoppt',
        default => 'Unbekannt',
    };
}

function healthScore(array $status): int
{
    $score = 100;
    foreach ($status['services'] as $state) {
        if ($state === 'failed') $score -= 25;
        elseif ($state !== 'active') $score -= 10;
    }
    $total = $status['storage']['total_bytes'];
    $free = $status['storage']['free_bytes'];
    if (is_int($total) && $total > 0 && is_int($free) && ($free / $total) < 0.1) $score -= 20;
    if (is_float($status['temperature_c']) && $status['temperature_c'] >= 75) $score -= 15;
    if ($status['latest_backup'] === null) $score -= 10;
    return max(0, $score);
}

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $token = (string)($_POST['csrf'] ?? '');
    if (!hash_equals(csrfToken(), $token)) {
        http_response_code(403);
        exit('Ungültige Anfrage.');
    }

    if (isset($_POST['logout'])) {
        $_SESSION = [];
        session_regenerate_id(true);
        header('Location: /admin/');
        exit;
    }

    if (authenticated() && isset($_POST['wizard_complete'])) {
        $_SESSION['wizard_complete'] = true;
        header('Location: /admin/?view=dashboard');
        exit;
    }

    if (authenticated() && isset($_POST['action'])) {
        $action = (string)$_POST['action'];
        $argument = (string)($_POST['argument'] ?? '');
        $confirmed = (string)($_POST['confirm'] ?? '');
        if ($confirmed !== 'yes') {
            $actionCode = 2;
            $actionOutput = '';
            $actionMessage = 'Bitte bestätige die Aktion ausdrücklich.';
        } else {
            [$actionCode, $actionOutput] = adminAction($action, $argument);
            $actionMessage = $actionCode === 0 ? 'Aktion erfolgreich abgeschlossen.' : 'Aktion fehlgeschlagen.';
        }
    } else {
        $password = (string)($_POST['password'] ?? '');
        if ($passwordHash !== '' && password_verify($password, $passwordHash)) {
            session_regenerate_id(true);
            $_SESSION['authenticated'] = true;
            $_SESSION['csrf'] = bin2hex(random_bytes(32));
            header('Location: /admin/?view=welcome');
            exit;
        }
        usleep(350000);
        $loginError = 'Anmeldung fehlgeschlagen.';
    }
}

if (($_GET['api'] ?? '') === 'status') {
    if (!authenticated()) {
        http_response_code(401);
        header('Content-Type: application/json');
        echo json_encode(['error' => 'authentication_required'], JSON_THROW_ON_ERROR);
        exit;
    }
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode(statusSnapshot(), JSON_THROW_ON_ERROR | JSON_UNESCAPED_SLASHES);
    exit;
}

$allowedViews = ['welcome', 'dashboard', 'assistant', 'maintenance', 'logs', 'about'];
$view = (string)($_GET['view'] ?? (empty($_SESSION['wizard_complete']) ? 'welcome' : 'dashboard'));
if (!in_array($view, $allowedViews, true)) $view = 'dashboard';
$status = authenticated() ? statusSnapshot() : [];
$score = authenticated() ? healthScore($status) : 0;
$serviceNames = ['nginx' => 'Webserver', 'mariadb' => 'Datenbank', 'redis' => 'Cache', 'php_fpm' => 'PHP'];
?><!doctype html>
<html lang="de">
<head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>ShopOS Administration</title>
<style>
:root{--ink:#17212b;--muted:#687684;--line:#dfe6ec;--surface:#fff;--soft:#f4f7f9;--brand:#6a2ca0;--brand2:#9b4dcc;--ok:#197447;--warn:#a45b00;--bad:#b4233a;--shadow:0 16px 44px rgba(23,33,43,.10)}*{box-sizing:border-box}body{margin:0;font-family:Inter,ui-sans-serif,system-ui,-apple-system,"Segoe UI",sans-serif;background:linear-gradient(145deg,#f7f4fa 0,#eef5f8 55%,#f9fbfc 100%);color:var(--ink)}a{color:inherit}.login-shell{min-height:100vh;display:grid;place-items:center;padding:24px}.login-card{width:min(920px,100%);display:grid;grid-template-columns:1.1fr .9fr;background:var(--surface);border:1px solid rgba(255,255,255,.8);border-radius:28px;overflow:hidden;box-shadow:var(--shadow)}.login-hero{padding:52px;background:linear-gradient(145deg,#35154f,#7132a0);color:#fff}.brand-mark{width:54px;height:54px;border-radius:18px;display:grid;place-items:center;background:#ffffff1c;font-size:28px}.login-form{padding:52px;display:flex;flex-direction:column;justify-content:center}.eyebrow{text-transform:uppercase;letter-spacing:.12em;font-size:12px;font-weight:800;color:var(--brand2)}h1,h2,h3,p{margin-top:0}.login-card h1{font-size:clamp(34px,5vw,54px);line-height:1.02;margin:24px 0 18px}.login-card input{width:100%;margin:8px 0 16px}.app{min-height:100vh;display:grid;grid-template-columns:248px 1fr}.sidebar{background:#16121c;color:#fff;padding:26px 18px;display:flex;flex-direction:column;position:sticky;top:0;height:100vh}.brand{display:flex;align-items:center;gap:12px;padding:0 10px 24px;font-weight:800}.brand small{display:block;color:#bfb4c8;font-weight:500}.nav{display:grid;gap:7px}.nav a{padding:12px 14px;border-radius:12px;text-decoration:none;color:#d9d1df}.nav a.active,.nav a:hover{background:#ffffff12;color:#fff}.sidebar-foot{margin-top:auto;font-size:12px;color:#9f93aa;padding:12px}.main{padding:28px 34px 50px;min-width:0}.topbar{display:flex;align-items:center;justify-content:space-between;gap:20px;margin-bottom:28px}.topbar h1{margin:0;font-size:30px}.button,button{appearance:none;border:0;border-radius:12px;padding:11px 16px;font:inherit;font-weight:700;cursor:pointer;background:var(--brand);color:#fff}.button.secondary,button.secondary{background:#eef0f3;color:var(--ink)}.button.danger,button.danger{background:var(--bad)}input,select{font:inherit;border:1px solid #cbd5dd;border-radius:12px;padding:12px;background:#fff;color:var(--ink)}label{font-weight:700;font-size:14px}.grid{display:grid;grid-template-columns:repeat(12,minmax(0,1fr));gap:18px}.card{grid-column:span 4;background:var(--surface);border:1px solid #e6ebef;border-radius:20px;padding:22px;box-shadow:0 7px 24px rgba(23,33,43,.055)}.card.wide{grid-column:span 8}.card.full{grid-column:1/-1}.metric{font-size:34px;font-weight:850;letter-spacing:-.04em}.muted{color:var(--muted)}.status-row{display:flex;justify-content:space-between;align-items:center;padding:12px 0;border-bottom:1px solid var(--line)}.status-row:last-child{border-bottom:0}.pill{display:inline-flex;align-items:center;gap:7px;padding:6px 9px;border-radius:99px;font-size:12px;font-weight:800;background:#edf0f3}.pill.active{background:#e4f5eb;color:var(--ok)}.pill.failed{background:#fde8ec;color:var(--bad)}.pill.inactive,.pill.unknown{background:#fff0dc;color:var(--warn)}.notice{padding:14px 16px;border-radius:14px;margin-bottom:18px;background:#f1e8f8;color:#532371}.notice.error{background:#fde8ec;color:var(--bad)}.notice.success{background:#e4f5eb;color:var(--ok)}.wizard{max-width:880px;margin:0 auto}.steps{display:flex;gap:8px;margin-bottom:22px}.step{height:7px;flex:1;border-radius:99px;background:#dfe4e8}.step.on{background:var(--brand)}.hero-card{background:linear-gradient(135deg,#fff,#f5edf9);border-radius:26px;padding:38px;border:1px solid #eadff0;box-shadow:var(--shadow)}.checklist{display:grid;gap:12px;margin:24px 0}.check{display:flex;gap:12px;align-items:flex-start;padding:14px;border:1px solid var(--line);border-radius:14px;background:#fff}.assistant{display:grid;grid-template-columns:72px 1fr;gap:18px;align-items:start}.assistant-icon{width:72px;height:72px;border-radius:22px;display:grid;place-items:center;font-size:34px;background:#f1e8f8}.action-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:14px}.action-box{padding:18px;border:1px solid var(--line);border-radius:16px}.action-box form{display:grid;gap:12px}.confirm{display:flex;gap:9px;align-items:flex-start;font-weight:500}.confirm input{margin-top:3px}.log{white-space:pre-wrap;max-height:36rem;overflow:auto;background:#11161c;color:#eaf0f4;padding:18px;border-radius:14px;font:13px/1.55 ui-monospace,monospace}.progress{height:9px;background:#e8edf0;border-radius:99px;overflow:hidden}.progress span{display:block;height:100%;background:var(--brand)}@media(max-width:900px){.app{grid-template-columns:1fr}.sidebar{position:static;height:auto}.nav{grid-template-columns:repeat(3,1fr)}.main{padding:22px}.card,.card.wide{grid-column:span 6}.login-card{grid-template-columns:1fr}.login-hero{display:none}}@media(max-width:600px){.nav{grid-template-columns:1fr 1fr}.card,.card.wide{grid-column:1/-1}.action-grid{grid-template-columns:1fr}.topbar{align-items:flex-start}.main{padding:18px}.login-form{padding:30px}.assistant{grid-template-columns:1fr}.assistant-icon{width:56px;height:56px}}
</style>
</head>
<body>
<?php if (!authenticated()): ?>
<main class="login-shell"><section class="login-card"><div class="login-hero"><div class="brand-mark">✦</div><h1>Dein Shop.<br>Dein System.</h1><p>ShopOS bündelt Store, Betrieb und Wartung in einer übersichtlichen Oberfläche – direkt auf deinem Raspberry Pi.</p></div><div class="login-form"><span class="eyebrow">Ms. FixIT ShopOS</span><h2>Willkommen zurück</h2><p class="muted">Melde dich an, um deinen Shop zu verwalten.</p><?php if ($passwordHash === ''): ?><div class="notice error">Die Admin-Konsole ist noch nicht initialisiert.</div><?php endif; ?><?php if (isset($loginError)): ?><div class="notice error"><?=e($loginError)?></div><?php endif; ?><form method="post"><input type="hidden" name="csrf" value="<?=e(csrfToken())?>"><label for="password">Administrator-Passwort</label><input id="password" type="password" name="password" required autocomplete="current-password"><button type="submit">Sicher anmelden</button></form><p class="muted" style="margin-top:18px;font-size:13px">Nur im lokalen Netzwerk erreichbar. Deine Zugangsdaten verlassen das Gerät nicht.</p></div></section></main>
<?php else: ?>
<div class="app"><aside class="sidebar"><div class="brand"><span class="brand-mark" style="width:40px;height:40px;border-radius:13px;font-size:20px">✦</span><div>ShopOS<small>Control Center</small></div></div><nav class="nav"><?php $nav=['dashboard'=>'Übersicht','assistant'=>'Assistent','maintenance'=>'Wartung','logs'=>'Protokolle','about'=>'Systeminfo']; foreach($nav as $key=>$label): ?><a class="<?=$view===$key?'active':''?>" href="/admin/?view=<?=$key?>"><?=e($label)?></a><?php endforeach; ?></nav><div class="sidebar-foot">Version <?=e($status['version'])?></div></aside><main class="main"><header class="topbar"><div><span class="eyebrow">ShopOS Administration</span><h1><?=e(['welcome'=>'Einrichtung','dashboard'=>'Alles im Blick','assistant'=>'ShopOS Assistent','maintenance'=>'Wartung & Pflege','logs'=>'Protokolle','about'=>'Systeminformationen'][$view])?></h1></div><form method="post"><input type="hidden" name="csrf" value="<?=e(csrfToken())?>"><button class="secondary" name="logout" value="1">Abmelden</button></form></header>
<?php if (isset($actionMessage)): ?><div class="notice <?=$actionCode===0?'success':'error'?>"><?=e($actionMessage)?></div><?php endif; ?><?php if (!empty($actionOutput)): ?><pre class="log"><?=e($actionOutput)?></pre><?php endif; ?>
<?php if ($view === 'welcome'): ?><section class="wizard"><div class="steps"><span class="step on"></span><span class="step on"></span><span class="step on"></span></div><div class="hero-card"><span class="eyebrow">Einrichtungsassistent</span><h2>Dein ShopOS ist startklar.</h2><p class="muted">Wir haben die wichtigsten Systembereiche geprüft. Du kannst diese Einführung später jederzeit über den Assistenten erneut aufrufen.</p><div class="checklist"><div class="check"><span>✓</span><div><strong>Lokaler, geschützter Zugang</strong><br><span class="muted">Die Konsole ist auf vertrauenswürdige Netze begrenzt.</span></div></div><div class="check"><span>✓</span><div><strong>Kernsystem geprüft</strong><br><span class="muted">Webserver, Datenbank, Cache und PHP werden laufend überwacht.</span></div></div><div class="check"><span>✓</span><div><strong>Sichere Wartungsaktionen</strong><br><span class="muted">Kritische Aktionen sind begrenzt und müssen bestätigt werden.</span></div></div></div><form method="post"><input type="hidden" name="csrf" value="<?=e(csrfToken())?>"><button name="wizard_complete" value="1">Zur Übersicht</button></form></div></section>
<?php elseif ($view === 'dashboard'): ?><?php $total=$status['storage']['total_bytes'];$free=$status['storage']['free_bytes'];$usedPct=(is_int($total)&&$total>0&&is_int($free))?(int)round((1-$free/$total)*100):0; ?><section class="grid"><article class="card"><span class="eyebrow">Systemzustand</span><div class="metric"><?=$score?>%</div><p class="muted">Gesamtbewertung aus Diensten, Speicher, Temperatur und Backup.</p></article><article class="card"><span class="eyebrow">Temperatur</span><div class="metric"><?=is_float($status['temperature_c'])?e(number_format($status['temperature_c'],1,',','.')).' °C':'–'?></div><p class="muted">Raspberry-Pi-Systemtemperatur</p></article><article class="card"><span class="eyebrow">Laufzeit</span><div class="metric"><?=e(humanUptime($status['uptime_seconds']))?></div><p class="muted">Seit dem letzten Neustart</p></article><article class="card wide"><h2>Dienste</h2><?php foreach($status['services'] as $key=>$state): ?><div class="status-row"><span><?=e($serviceNames[$key]??$key)?></span><span class="pill <?=e($state)?>">● <?=e(stateLabel($state))?></span></div><?php endforeach; ?></article><article class="card"><h2>Speicher</h2><div class="metric"><?=$usedPct?>%</div><div class="progress"><span style="width:<?=$usedPct?>%"></span></div><p class="muted" style="margin-top:12px"><?=e(humanBytes($free))?> frei von <?=e(humanBytes($total))?></p></article><article class="card full assistant"><div class="assistant-icon">✦</div><div><span class="eyebrow">Empfehlung</span><h2><?=$score>=90?'Alles sieht gut aus.':($score>=70?'Ein paar Punkte brauchen Aufmerksamkeit.':'Bitte prüfe dein System.')?></h2><p class="muted"><?=$status['latest_backup']===null?'Erstelle als nächsten Schritt ein erstes Backup.':'Das letzte Backup wurde gefunden. Prüfe regelmäßig, ob neue Sicherungen erstellt werden.'?></p><a class="button" href="/admin/?view=assistant">Empfehlungen öffnen</a></div></article></section>
<?php elseif ($view === 'assistant'): ?><section class="grid"><article class="card full assistant"><div class="assistant-icon">✦</div><div><span class="eyebrow">Geführte Hilfe</span><h2>Was sollte ich als Nächstes tun?</h2><p class="muted">Der Assistent bewertet nur lokale Systemdaten und führt dich zu sicheren, nachvollziehbaren Schritten.</p></div></article><article class="card wide"><h2>Empfohlene Schritte</h2><div class="checklist"><?php if($status['latest_backup']===null): ?><div class="check"><span>1</span><div><strong>Erstes Backup erstellen</strong><br><span class="muted">Sichere deinen Shop, bevor du weitere Änderungen vornimmst.</span></div></div><?php endif; ?><?php foreach($status['services'] as $key=>$state): if($state!=='active'): ?><div class="check"><span>!</span><div><strong><?=e($serviceNames[$key]??$key)?> prüfen</strong><br><span class="muted">Status: <?=e(stateLabel($state))?>. Öffne zuerst die Protokolle und starte den Dienst nur bei klarer Ursache neu.</span></div></div><?php endif; endforeach; ?><div class="check"><span>✓</span><div><strong>Monatliche Routine</strong><br><span class="muted">Backup erstellen, freien Speicher prüfen und ShopOS-Protokoll kontrollieren.</span></div></div></div></article><article class="card"><h2>Sicher arbeiten</h2><p class="muted">Vor Neustarts oder Wartung immer ein aktuelles Backup anlegen. ShopOS verlangt bei jeder Aktion eine ausdrückliche Bestätigung.</p></article></section>
<?php elseif ($view === 'maintenance'): ?><section class="action-grid"><div class="action-box"><h2>Backup erstellen</h2><p class="muted">Erstellt eine neue lokale Sicherung.</p><form method="post"><input type="hidden" name="csrf" value="<?=e(csrfToken())?>"><input type="hidden" name="action" value="backup-create"><label class="confirm"><input type="checkbox" name="confirm" value="yes" required>Ich möchte jetzt ein Backup erstellen.</label><button type="submit">Backup starten</button></form></div><div class="action-box"><h2>Cache leeren</h2><p class="muted">Hilft bei veralteten Shop-Inhalten.</p><form method="post"><input type="hidden" name="csrf" value="<?=e(csrfToken())?>"><input type="hidden" name="action" value="cache-flush"><label class="confirm"><input type="checkbox" name="confirm" value="yes" required>Ich bestätige das Leeren des Cache.</label><button type="submit">Cache leeren</button></form></div><div class="action-box"><h2>Dienst neu starten</h2><p class="muted">Nur verwenden, wenn ein Dienst nicht korrekt läuft.</p><form method="post"><input type="hidden" name="csrf" value="<?=e(csrfToken())?>"><input type="hidden" name="action" value="service-restart"><select name="argument" aria-label="Dienst"><option value="nginx">Webserver</option><option value="mariadb">Datenbank</option><option value="redis-server">Cache</option><option value="php-fpm">PHP</option></select><label class="confirm"><input type="checkbox" name="confirm" value="yes" required>Ich bestätige den Neustart.</label><button class="danger" type="submit">Dienst neu starten</button></form></div><div class="action-box"><h2>Letztes Backup</h2><p><?=e($status['latest_backup'] ? basename((string)$status['latest_backup']) : 'Noch kein Backup vorhanden')?></p><p class="muted">Backups sollten zusätzlich auf ein externes Ziel kopiert werden.</p></div></section>
<?php elseif ($view === 'logs'): ?><section class="card full"><h2>Protokolle sicher anzeigen</h2><p class="muted">Es werden höchstens die letzten 200 bereinigten Zeilen geladen.</p><form method="post" style="display:flex;flex-wrap:wrap;gap:12px;align-items:end"><input type="hidden" name="csrf" value="<?=e(csrfToken())?>"><input type="hidden" name="action" value="logs"><label>Bereich<br><select name="argument"><option value="shopos">ShopOS</option><option value="nginx">Webserver</option><option value="mariadb">Datenbank</option><option value="redis-server">Cache</option><option value="php-fpm">PHP</option></select></label><label class="confirm"><input type="checkbox" name="confirm" value="yes" required>Protokoll laden</label><button type="submit">Anzeigen</button></form></section>
<?php else: ?><section class="grid"><article class="card"><span class="eyebrow">Version</span><div class="metric"><?=e($status['version'])?></div></article><article class="card"><span class="eyebrow">Status API</span><p><code>/admin/?api=status</code></p><p class="muted">Nur nach Anmeldung verfügbar.</p></article><article class="card"><span class="eyebrow">Sicherheit</span><p>Lokaler Zugriff, sichere Sitzung, CSRF-Schutz und begrenzte Systemaktionen.</p></article><article class="card full"><h2>Über ShopOS</h2><p class="muted">ShopOS ist eine lokale E-Commerce-Appliance von Ms. FixIT. Die Administrationsoberfläche ist für Betreiberinnen und Betreiber gedacht, die ihren Shop ohne Linux-Kommandozeile sicher verwalten möchten.</p></article></section><?php endif; ?></main></div>
<?php endif; ?>
</body></html>
