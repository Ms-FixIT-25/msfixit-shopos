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

$configFile = '/etc/msfixit-shopos/admin-console.php';
$config = is_file($configFile) ? require $configFile : [];
$passwordHash = is_array($config) ? (string)($config['password_hash'] ?? '') : '';

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

function command(string $command): string
{
    $output = shell_exec($command . ' 2>/dev/null');
    return trim((string)$output);
}

function serviceState(string $unit): string
{
    $allowed = ['nginx.service', 'mariadb.service', 'redis-server.service'];
    if (!in_array($unit, $allowed, true)) {
        return 'unknown';
    }
    $state = command('systemctl is-active ' . escapeshellarg($unit));
    return in_array($state, ['active', 'inactive', 'failed', 'activating', 'deactivating'], true) ? $state : 'unknown';
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
    $cmd = 'sudo -n /usr/local/sbin/msfixit-admin-action ' . escapeshellarg($action);
    if ($argument !== '') {
        $cmd .= ' ' . escapeshellarg($argument);
    }
    $lines = [];
    $code = 1;
    exec($cmd . ' 2>&1', $lines, $code);
    return [$code, trim(implode("\n", array_slice($lines, -200)))];
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

    if (authenticated() && isset($_POST['action'])) {
        $action = (string)$_POST['action'];
        $argument = (string)($_POST['argument'] ?? '');
        [$actionCode, $actionOutput] = adminAction($action, $argument);
        $actionMessage = $actionCode === 0 ? 'Aktion erfolgreich abgeschlossen.' : 'Aktion fehlgeschlagen.';
    } else {
        $password = (string)($_POST['password'] ?? '');
        if ($passwordHash !== '' && password_verify($password, $passwordHash)) {
            session_regenerate_id(true);
            $_SESSION['authenticated'] = true;
            $_SESSION['csrf'] = bin2hex(random_bytes(32));
            header('Location: /admin/');
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

    $temperatureRaw = command('cat /sys/class/thermal/thermal_zone0/temp');
    $temperature = is_numeric($temperatureRaw) ? round(((float)$temperatureRaw) / 1000, 1) : null;
    $diskFree = @disk_free_space('/data');
    $diskTotal = @disk_total_space('/data');
    $backups = glob('/data/backups/shopos-*.tar.zst') ?: [];
    rsort($backups, SORT_STRING);
    $status = [
        'version' => command('/usr/local/bin/shopos-version'),
        'uptime_seconds' => (int)floor((float)explode(' ', trim((string)@file_get_contents('/proc/uptime')))[0]),
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
            'php_fpm' => command("systemctl is-active 'php*-fpm.service' | head -n1") ?: 'unknown',
        ],
    ];
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode($status, JSON_THROW_ON_ERROR | JSON_UNESCAPED_SLASHES);
    exit;
}

?><!doctype html>
<html lang="de">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>ShopOS Administration</title>
<style>body{font-family:system-ui,sans-serif;margin:0;background:#f4f6f8;color:#152536}.wrap{max-width:980px;margin:3rem auto;padding:1rem}.card{background:#fff;border-radius:14px;padding:1.4rem;margin-bottom:1rem;box-shadow:0 3px 16px #0001}input,select,button{font:inherit;padding:.75rem;border-radius:8px;border:1px solid #bcc7d1}button{background:#123e5a;color:#fff;border:0;cursor:pointer}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(260px,1fr));gap:1rem}.muted{color:#607080}.error{color:#a21b2d}.success{color:#176b35}pre{white-space:pre-wrap;max-height:28rem;overflow:auto;background:#101820;color:#e9f1f7;padding:1rem;border-radius:8px}</style></head>
<body><main class="wrap"><h1>Ms. FixIT ShopOS</h1>
<?php if (!authenticated()): ?>
<section class="card"><h2>Administration</h2><p class="muted">Die Konsole ist nur für autorisierte lokale Administration vorgesehen.</p>
<?php if ($passwordHash === ''): ?><p class="error">Die Admin-Konsole ist noch nicht initialisiert.</p><?php endif; ?>
<?php if (isset($loginError)): ?><p class="error"><?=htmlspecialchars($loginError, ENT_QUOTES)?></p><?php endif; ?>
<form method="post"><input type="hidden" name="csrf" value="<?=htmlspecialchars(csrfToken(), ENT_QUOTES)?>"><label>Passwort<br><input type="password" name="password" required autocomplete="current-password"></label> <button type="submit">Anmelden</button></form></section>
<?php else: ?>
<form method="post" style="text-align:right"><input type="hidden" name="csrf" value="<?=htmlspecialchars(csrfToken(), ENT_QUOTES)?>"><button name="logout" value="1">Abmelden</button></form>
<?php if (isset($actionMessage)): ?><p class="<?=$actionCode === 0 ? 'success' : 'error'?>"><?=htmlspecialchars($actionMessage, ENT_QUOTES)?></p><?php endif; ?>
<?php if (!empty($actionOutput)): ?><pre><?=htmlspecialchars($actionOutput, ENT_QUOTES)?></pre><?php endif; ?>
<section class="grid">
<div class="card"><h2>Systemstatus</h2><p>JSON-Status: <code>/admin/?api=status</code></p></div>
<div class="card"><h2>Backup</h2><form method="post"><input type="hidden" name="csrf" value="<?=htmlspecialchars(csrfToken(), ENT_QUOTES)?>"><input type="hidden" name="action" value="backup-create"><button type="submit">Backup erstellen</button></form></div>
<div class="card"><h2>Cache</h2><form method="post"><input type="hidden" name="csrf" value="<?=htmlspecialchars(csrfToken(), ENT_QUOTES)?>"><input type="hidden" name="action" value="cache-flush"><button type="submit">Cache leeren</button></form></div>
<div class="card"><h2>Dienst neu starten</h2><form method="post"><input type="hidden" name="csrf" value="<?=htmlspecialchars(csrfToken(), ENT_QUOTES)?>"><input type="hidden" name="action" value="service-restart"><select name="argument"><option>nginx</option><option>mariadb</option><option value="redis-server">Redis</option><option value="php-fpm">PHP-FPM</option></select> <button type="submit">Neu starten</button></form></div>
<div class="card"><h2>Protokolle</h2><form method="post"><input type="hidden" name="csrf" value="<?=htmlspecialchars(csrfToken(), ENT_QUOTES)?>"><input type="hidden" name="action" value="logs"><select name="argument"><option>shopos</option><option>nginx</option><option>mariadb</option><option value="redis-server">Redis</option><option value="php-fpm">PHP-FPM</option></select> <button type="submit">Letzte 200 Zeilen</button></form></div>
</section>
<?php endif; ?></main></body></html>
