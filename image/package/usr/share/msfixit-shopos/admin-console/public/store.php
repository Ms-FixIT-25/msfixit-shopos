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

$catalogPath = '/usr/share/msfixit-shopos/catalog/apps.json';
$licensePath = '/run/msfixit-shopos/license-status.json';
$catalog = ['schema' => 1, 'apps' => []];
$license = ['valid' => false, 'edition' => 'community', 'entitlements' => []];

try {
    $catalogData = json_decode((string)@file_get_contents($catalogPath), true, 32, JSON_THROW_ON_ERROR);
    if (!is_array($catalogData) || ($catalogData['schema'] ?? null) !== 1 || !is_array($catalogData['apps'] ?? null)) {
        throw new RuntimeException('Ungültiger App-Katalog.');
    }
    $catalog = $catalogData;
    if (is_file($licensePath)) {
        $licenseData = json_decode((string)file_get_contents($licensePath), true, 32, JSON_THROW_ON_ERROR);
        if (is_array($licenseData) && ($licenseData['valid'] ?? false) === true) {
            $license = $licenseData;
        }
    }
} catch (Throwable $exception) {
    $catalogError = 'Der App-Katalog ist derzeit nicht verfügbar.';
}

$ranks = ['community' => 0, 'professional' => 1, 'enterprise' => 2, 'developer' => 3];
$edition = isset($ranks[(string)($license['edition'] ?? '')]) ? (string)$license['edition'] : 'community';
$entitlements = array_fill_keys(array_values(array_filter($license['entitlements'] ?? [], 'is_string')), true);
$apps = [];
foreach ($catalog['apps'] as $app) {
    if (!is_array($app)) continue;
    $requiredEdition = (string)($app['edition'] ?? 'enterprise');
    $entitlement = (string)($app['entitlement'] ?? '');
    $granted = isset($ranks[$requiredEdition])
        && $ranks[$edition] >= $ranks[$requiredEdition]
        && $entitlement !== ''
        && isset($entitlements[$entitlement]);
    $apps[] = $app + ['locked' => !$granted, 'action' => $granted ? 'install' : 'unlock'];
}

$message = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $token = (string)($_POST['csrf'] ?? '');
    if (!hash_equals(csrfToken(), $token)) {
        http_response_code(403);
        exit('Ungültige Anfrage.');
    }
    $appId = (string)($_POST['app_id'] ?? '');
    $action = (string)($_POST['store_action'] ?? '');
    $known = null;
    foreach ($apps as $app) {
        if (($app['id'] ?? '') === $appId) { $known = $app; break; }
    }
    if (!is_array($known) || !in_array($action, ['install', 'unlock'], true)) {
        http_response_code(400);
        $message = 'Die gewählte App-Aktion ist ungültig.';
    } elseif ($action === 'install' && ($known['action'] ?? '') !== 'install') {
        http_response_code(403);
        $message = 'Diese App ist für die aktuelle Lizenz nicht freigeschaltet.';
    } elseif ($action === 'install') {
        $message = 'Installation ist vorbereitet. Im nächsten Schritt wird das signierte Paket geprüft und transaktional installiert.';
    } else {
        $message = 'Freischaltung gewählt. Eine Lizenz kann sicher aktiviert oder erworben werden.';
    }
}

$editionLabels = ['community' => 'Community', 'professional' => 'Professional', 'enterprise' => 'Enterprise', 'developer' => 'Developer'];
?><!doctype html>
<html lang="de">
<head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>ShopOS Store</title>
<style>
:root{font-family:Inter,system-ui,sans-serif;color:#172033;background:#f4f7fb}*{box-sizing:border-box}body{margin:0}.shell{max-width:1180px;margin:auto;padding:24px}.top{display:flex;justify-content:space-between;gap:18px;align-items:center;margin-bottom:24px}.back{color:#44506a;text-decoration:none}.license{background:#fff;border:1px solid #dfe6f0;border-radius:16px;padding:14px 18px;box-shadow:0 8px 24px rgba(22,35,60,.06)}h1{margin:4px 0 6px;font-size:clamp(28px,5vw,44px)}.lead{color:#5d6980;max-width:720px}.notice{background:#eef6ff;border:1px solid #bcd9ff;border-radius:14px;padding:14px 16px;margin:18px 0}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(260px,1fr));gap:18px}.card{background:#fff;border:1px solid #dfe6f0;border-radius:20px;padding:20px;display:flex;flex-direction:column;min-height:255px;box-shadow:0 10px 30px rgba(22,35,60,.07)}.eyebrow{font-size:12px;font-weight:800;letter-spacing:.08em;text-transform:uppercase;color:#68758c}.card h2{margin:10px 0 8px}.card p{color:#657188;line-height:1.5;flex:1}.badge{display:inline-flex;width:max-content;border-radius:999px;padding:7px 10px;font-size:13px;font-weight:800}.open{background:#e9f8ef;color:#136b38}.locked{background:#fff2df;color:#8a4c00}.button{width:100%;border:0;border-radius:12px;padding:12px 14px;font-weight:800;cursor:pointer;background:#2156d9;color:white}.button.secondary{background:#172033}.meta{font-size:13px;color:#748096;margin:12px 0}.empty{background:#fff;border-radius:18px;padding:24px;border:1px solid #dfe6f0}@media(max-width:650px){.shell{padding:16px}.top{align-items:flex-start;flex-direction:column}.license{width:100%}}
</style>
</head>
<body><main class="shell">
<div class="top"><div><a class="back" href="/admin/?view=dashboard">← Zurück zum Control Center</a><h1>ShopOS Store</h1><p class="lead">Installiere Erweiterungen oder schalte professionelle Funktionen frei. ShopOS zeigt nur Aktionen an, die zur geprüften Lizenz passen.</p></div><div class="license"><strong><?= e($editionLabels[$edition] ?? 'Community') ?></strong><br><small><?= ($license['valid'] ?? false) === true ? 'Lizenz geprüft' : 'Basisbetrieb ohne aktive Lizenz' ?></small></div></div>
<?php if ($message !== ''): ?><div class="notice" role="status"><?= e($message) ?></div><?php endif; ?>
<?php if (isset($catalogError)): ?><div class="empty"><?= e($catalogError) ?></div><?php elseif ($apps === []): ?><div class="empty">Derzeit sind keine Apps verfügbar.</div><?php else: ?><section class="grid" aria-label="Verfügbare ShopOS Apps">
<?php foreach ($apps as $app): $locked = (bool)($app['locked'] ?? true); ?>
<article class="card">
<div class="eyebrow"><?= e(ucfirst((string)($app['edition'] ?? 'enterprise'))) ?></div>
<h2><?= e((string)($app['name'] ?? 'Unbenannte App')) ?></h2>
<span class="badge <?= $locked ? 'locked' : 'open' ?>"><?= $locked ? 'Freischaltung erforderlich' : 'Für dich verfügbar' ?></span>
<p><?= e((string)($app['summary'] ?? '')) ?></p>
<div class="meta">Berechtigung: <?= e((string)($app['entitlement'] ?? 'nicht definiert')) ?></div>
<form method="post">
<input type="hidden" name="csrf" value="<?= e(csrfToken()) ?>">
<input type="hidden" name="app_id" value="<?= e((string)($app['id'] ?? '')) ?>">
<input type="hidden" name="store_action" value="<?= $locked ? 'unlock' : 'install' ?>">
<button class="button <?= $locked ? 'secondary' : '' ?>" type="submit"><?= $locked ? 'Professional freischalten' : 'Installieren' ?></button>
</form>
</article>
<?php endforeach; ?></section><?php endif; ?>
</main></body></html>
