<?php
declare(strict_types=1);

session_name('SHOPOSADMIN');
session_set_cookie_params(['lifetime'=>0,'path'=>'/admin/','secure'=>!empty($_SERVER['HTTPS']),'httponly'=>true,'samesite'=>'Strict']);
session_start();
header('X-Frame-Options: DENY');
header('X-Content-Type-Options: nosniff');
header('Referrer-Policy: no-referrer');
header("Content-Security-Policy: default-src 'self'; style-src 'self' 'unsafe-inline'; script-src 'none'; img-src 'self' data:; frame-ancestors 'none'; base-uri 'none'; form-action 'self'");
header('Cache-Control: no-store');

if (($_SESSION['authenticated'] ?? false) !== true) { header('Location: /admin/'); exit; }
function e(string $v): string { return htmlspecialchars($v, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8'); }
function csrfToken(): string { if (empty($_SESSION['csrf'])) $_SESSION['csrf']=bin2hex(random_bytes(32)); return (string)$_SESSION['csrf']; }
function installApp(string $appId): array {
    if (!preg_match('/^at\.msfixit\.shopos\.[a-z0-9]+(?:[.-][a-z0-9]+)*$/', $appId)) return [2, 'Ungültige App-ID.'];
    $cmd = ['sudo','-n','/usr/local/sbin/msfixit-app-install-helper','install',$appId];
    $spec = [1=>['pipe','w'],2=>['pipe','w']];
    $process = proc_open($cmd, $spec, $pipes, null, ['PATH'=>'/usr/sbin:/usr/bin:/sbin:/bin'], ['bypass_shell'=>true]);
    if (!is_resource($process)) return [1, 'Installationsdienst konnte nicht gestartet werden.'];
    $stdout = stream_get_contents($pipes[1]); $stderr = stream_get_contents($pipes[2]);
    fclose($pipes[1]); fclose($pipes[2]);
    $code = proc_close($process);
    return [$code, trim($code === 0 ? $stdout : $stderr)];
}

$catalogPath='/usr/share/msfixit-shopos/catalog/apps.json';
$licensePath='/run/msfixit-shopos/license-status.json';
$catalog=['schema'=>1,'apps'=>[]]; $license=['valid'=>false,'edition'=>'community','entitlements'=>[]];
try {
    $c=json_decode((string)@file_get_contents($catalogPath),true,32,JSON_THROW_ON_ERROR);
    if (!is_array($c)||($c['schema']??null)!==1||!is_array($c['apps']??null)) throw new RuntimeException();
    $catalog=$c;
    if (is_file($licensePath)) { $l=json_decode((string)file_get_contents($licensePath),true,32,JSON_THROW_ON_ERROR); if (is_array($l)&&($l['valid']??false)===true) $license=$l; }
} catch (Throwable) { $catalogError='Der App-Katalog ist derzeit nicht verfügbar.'; }
$ranks=['community'=>0,'professional'=>1,'enterprise'=>2,'developer'=>3];
$edition=isset($ranks[(string)($license['edition']??'')])?(string)$license['edition']:'community';
$entitlements=array_fill_keys(array_values(array_filter($license['entitlements']??[],'is_string')),true);
$apps=[];
foreach ($catalog['apps'] as $app) {
    if (!is_array($app)) continue;
    $required=(string)($app['edition']??'enterprise'); $entitlement=(string)($app['entitlement']??'');
    $granted=isset($ranks[$required])&&$ranks[$edition]>=$ranks[$required]&&$entitlement!==''&&isset($entitlements[$entitlement]);
    $apps[]=$app+['locked'=>!$granted,'action'=>$granted?'install':'unlock'];
}
$message=''; $messageClass='notice';
if ($_SERVER['REQUEST_METHOD']==='POST') {
    $token=(string)($_POST['csrf']??'');
    if (!hash_equals(csrfToken(),$token)) { http_response_code(403); exit('Ungültige Anfrage.'); }
    $appId=(string)($_POST['app_id']??''); $action=(string)($_POST['store_action']??''); $known=null;
    foreach ($apps as $app) if (($app['id']??'')===$appId) { $known=$app; break; }
    if (!is_array($known)||!in_array($action,['install','unlock'],true)) { http_response_code(400); $message='Die gewählte App-Aktion ist ungültig.'; $messageClass='error'; }
    elseif ($action==='install'&&($known['action']??'')!=='install') { http_response_code(403); $message='Diese App ist für die aktuelle Lizenz nicht freigeschaltet.'; $messageClass='error'; }
    elseif ($action==='install'&&(string)($_POST['confirm_install']??'')!=='yes') { http_response_code(400); $message='Bitte bestätige die Installation ausdrücklich.'; $messageClass='error'; }
    elseif ($action==='install') {
        [$code,$detail]=installApp($appId);
        $message=$code===0?'App wurde erfolgreich geprüft und installiert.':'Installation fehlgeschlagen: '.($detail!==''?$detail:'Unbekannter Fehler.');
        $messageClass=$code===0?'success':'error';
    } else $message='Freischaltung gewählt. Eine Lizenz kann sicher aktiviert oder erworben werden.';
}
$labels=['community'=>'Community','professional'=>'Professional','enterprise'=>'Enterprise','developer'=>'Developer'];
?><!doctype html><html lang="de"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>ShopOS Store</title>
<style>:root{font-family:Inter,system-ui,sans-serif;color:#172033;background:#f4f7fb}*{box-sizing:border-box}body{margin:0}.shell{max-width:1180px;margin:auto;padding:24px}.top{display:flex;justify-content:space-between;gap:18px;align-items:center;margin-bottom:24px}.toplinks{display:flex;gap:16px;flex-wrap:wrap}.back{color:#44506a;text-decoration:none}.license,.card,.empty{background:#fff;border:1px solid #dfe6f0;border-radius:18px}.license{padding:14px 18px}h1{margin:4px 0 6px;font-size:clamp(28px,5vw,44px)}.lead,.card p,.meta{color:#657188}.notice,.success,.error{border-radius:14px;padding:14px 16px;margin:18px 0}.notice{background:#eef6ff}.success{background:#e9f8ef;color:#136b38}.error{background:#fff0f0;color:#8a1f1f}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(260px,1fr));gap:18px}.card{padding:20px;display:flex;flex-direction:column;min-height:280px}.card p{flex:1;line-height:1.5}.badge{display:inline-flex;width:max-content;border-radius:999px;padding:7px 10px;font-size:13px;font-weight:800}.open{background:#e9f8ef;color:#136b38}.locked{background:#fff2df;color:#8a4c00}.button{width:100%;border:0;border-radius:12px;padding:12px 14px;font-weight:800;background:#2156d9;color:#fff}.secondary{background:#172033}.confirm{display:flex;gap:8px;align-items:flex-start;margin:12px 0;font-size:13px}.meta{font-size:13px;margin:12px 0}@media(max-width:650px){.shell{padding:16px}.top{align-items:flex-start;flex-direction:column}.license{width:100%}}</style></head><body><main class="shell">
<div class="top"><div><div class="toplinks"><a class="back" href="/admin/?view=dashboard">← Control Center</a><a class="back" href="/admin/updates">Update Center</a></div><h1>ShopOS Store</h1><p class="lead">Installiere geprüfte Erweiterungen oder schalte professionelle Funktionen frei.</p></div><div class="license"><strong><?=e($labels[$edition]??'Community')?></strong><br><small><?=($license['valid']??false)===true?'Lizenz geprüft':'Basisbetrieb ohne aktive Lizenz'?></small></div></div>
<?php if($message!==''):?><div class="<?=e($messageClass)?>" role="status"><?=e($message)?></div><?php endif;?>
<?php if(isset($catalogError)):?><div class="empty"><?=e($catalogError)?></div><?php else:?><section class="grid" aria-label="Verfügbare ShopOS Apps">
<?php foreach($apps as $app):$locked=(bool)($app['locked']??true);?><article class="card"><small><?=e(ucfirst((string)($app['edition']??'enterprise')))?></small><h2><?=e((string)($app['name']??'Unbenannte App'))?></h2><span class="badge <?=$locked?'locked':'open'?>"><?=$locked?'Freischaltung erforderlich':'Für dich verfügbar'?></span><p><?=e((string)($app['summary']??''))?></p><div class="meta">Berechtigung: <?=e((string)($app['entitlement']??'nicht definiert'))?></div><form method="post"><input type="hidden" name="csrf" value="<?=e(csrfToken())?>"><input type="hidden" name="app_id" value="<?=e((string)($app['id']??''))?>"><input type="hidden" name="store_action" value="<?=$locked?'unlock':'install'?>"><?php if(!$locked):?><label class="confirm"><input type="checkbox" name="confirm_install" value="yes" required><span>Ich bestätige, dass dieses signierte App-Paket jetzt geprüft und installiert werden soll.</span></label><?php endif;?><button class="button <?=$locked?'secondary':''?>" type="submit"><?=$locked?'Professional freischalten':'Prüfen und installieren'?></button></form></article><?php endforeach;?></section><?php endif;?></main></body></html>
