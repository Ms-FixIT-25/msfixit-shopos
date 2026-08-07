<?php
declare(strict_types=1);
session_name('SHOPOSOOBE');
session_set_cookie_params(['lifetime'=>0,'path'=>'/admin/','secure'=>!empty($_SERVER['HTTPS']),'httponly'=>true,'samesite'=>'Strict']);
session_start();
header('X-Frame-Options: DENY');
header('X-Content-Type-Options: nosniff');
header('Referrer-Policy: no-referrer');
header("Content-Security-Policy: default-src 'self'; style-src 'self' 'unsafe-inline'; script-src 'none'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'");
header('Cache-Control: no-store');

const STEPS=['welcome','locale','network','identity','license','apps','summary','apply','complete'];
const LOCALES=['de_AT','de_DE','en_GB','en_US'];
const KEYBOARDS=['de','de-nodeadkeys','us','gb'];
const TIMEZONES=['Europe/Vienna','Europe/Berlin','Europe/Zurich','Europe/London','UTC'];
const EDITIONS=['community','professional','enterprise'];
const APPS=['commerce','backup','repair','assistant','marketplaces'];

function e(string $v):string{return htmlspecialchars($v,ENT_QUOTES|ENT_SUBSTITUTE,'UTF-8');}
function csrf():string{if(empty($_SESSION['csrf']))$_SESSION['csrf']=bin2hex(random_bytes(32));return (string)$_SESSION['csrf'];}
function cleanHostname(string $v):string{$v=strtolower(trim($v));return preg_match('/^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/',$v)?$v:'';}
function state():array{return is_array($_SESSION['oobe']??null)?$_SESSION['oobe']:[];}
function save(array $s):void{$_SESSION['oobe']=$s;}
function stepIndex(string $s):int{$i=array_search($s,STEPS,true);return $i===false?0:$i;}
function fail(string $m):never{http_response_code(400);exit(e($m));}

$step=(string)($_GET['step']??'welcome');if(!in_array($step,STEPS,true))$step='welcome';
$s=state();$message='';
if($_SERVER['REQUEST_METHOD']==='POST'){
 if(!hash_equals(csrf(),(string)($_POST['csrf']??''))){http_response_code(403);exit('Ungültige Anfrage.');}
 $action=(string)($_POST['action']??'next');
 if($action==='back'){header('Location: /admin/oobe.php?step='.STEPS[max(0,stepIndex($step)-1)]);exit;}
 switch($step){
  case 'locale':
   $locale=(string)($_POST['locale']??'');$keyboard=(string)($_POST['keyboard']??'');$timezone=(string)($_POST['timezone']??'');
   if(!in_array($locale,LOCALES,true)||!in_array($keyboard,KEYBOARDS,true)||!in_array($timezone,TIMEZONES,true))fail('Ungültige Regionsauswahl.');
   $s+=[];$s['locale']=$locale;$s['keyboard']=$keyboard;$s['timezone']=$timezone;break;
  case 'network':
   $mode=(string)($_POST['network_mode']??'dhcp');if(!in_array($mode,['dhcp','static'],true))fail('Ungültiger Netzwerkmodus.');
   $s['network_mode']=$mode;
   if($mode==='static'){
    $ip=(string)($_POST['ip']??'');$gateway=(string)($_POST['gateway']??'');$dns=(string)($_POST['dns']??'');
    if(filter_var($ip,FILTER_VALIDATE_IP,FILTER_FLAG_IPV4)===false||filter_var($gateway,FILTER_VALIDATE_IP,FILTER_FLAG_IPV4)===false||filter_var($dns,FILTER_VALIDATE_IP,FILTER_FLAG_IPV4)===false)fail('Ungültige IPv4-Konfiguration.');
    $s['ip']=$ip;$s['gateway']=$gateway;$s['dns']=$dns;
   }break;
  case 'identity':
   $hostname=cleanHostname((string)($_POST['hostname']??''));$user=trim((string)($_POST['admin_user']??''));$p1=(string)($_POST['password']??'');$p2=(string)($_POST['password_repeat']??'');
   if($hostname===''||!preg_match('/^[a-z][a-z0-9_-]{2,31}$/i',$user)||strlen($p1)<12||$p1!==$p2)fail('Hostname, Benutzername oder Passwort ist ungültig.');
   $s['hostname']=$hostname;$s['admin_user']=$user;$s['password_hash']=password_hash($p1,PASSWORD_DEFAULT);break;
  case 'license':
   $edition=(string)($_POST['edition']??'community');if(!in_array($edition,EDITIONS,true))fail('Ungültige Edition.');
   $s['edition']=$edition;$s['license_file']='';break;
  case 'apps':
   $apps=array_values(array_intersect(APPS,array_filter((array)($_POST['apps']??[]),'is_string')));$s['apps']=$apps;break;
  case 'summary':
   if((string)($_POST['confirm']??'')!=='yes')fail('Bitte bestätige die Einrichtung.');
   $payload=['schema'=>1,'locale'=>$s['locale']??'de_AT','keyboard'=>$s['keyboard']??'de','timezone'=>$s['timezone']??'Europe/Vienna','network_mode'=>$s['network_mode']??'dhcp','ip'=>$s['ip']??null,'gateway'=>$s['gateway']??null,'dns'=>$s['dns']??null,'hostname'=>$s['hostname']??'shopos','admin_user'=>$s['admin_user']??'admin','password_hash'=>$s['password_hash']??'','edition'=>$s['edition']??'community','apps'=>$s['apps']??[]];
   $tmp=tempnam('/run','shopos-oobe-');if($tmp===false)fail('Einrichtung konnte nicht vorbereitet werden.');file_put_contents($tmp,json_encode($payload,JSON_THROW_ON_ERROR|JSON_UNESCAPED_SLASHES));chmod($tmp,0600);
   $cmd=['sudo','-n','/usr/local/sbin/msfixit-oobe-apply',$tmp];$pipes=[];$proc=proc_open($cmd,[1=>['pipe','w'],2=>['pipe','w']],$pipes,null,null,['bypass_shell'=>true]);
   if(!is_resource($proc))fail('Einrichtungsdienst ist nicht verfügbar.');$out=stream_get_contents($pipes[1]);$err=stream_get_contents($pipes[2]);fclose($pipes[1]);fclose($pipes[2]);$code=proc_close($proc);@unlink($tmp);
   if($code!==0)fail('Einrichtung fehlgeschlagen: '.trim((string)$err));$_SESSION['oobe_complete']=true;$message=trim((string)$out);break;
 }
 save($s);$next=STEPS[min(count(STEPS)-1,stepIndex($step)+1)];if($step==='summary')$next='complete';header('Location: /admin/oobe.php?step='.$next);exit;
}
$progress=(int)round((stepIndex($step)/(count(STEPS)-1))*100);
?><!doctype html><html lang="de"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>ShopOS Einrichtung</title><style>:root{font-family:system-ui,sans-serif;color:#172033;background:#f4f7fb}*{box-sizing:border-box}body{margin:0}.shell{max-width:860px;margin:auto;padding:24px}.card{background:#fff;border:1px solid #dfe6f0;border-radius:24px;padding:clamp(20px,5vw,44px);box-shadow:0 18px 50px rgba(22,35,60,.1)}progress{width:100%;height:12px}.grid{display:grid;gap:16px}.two{grid-template-columns:repeat(auto-fit,minmax(220px,1fr))}label{display:grid;gap:7px;font-weight:700}input,select{min-height:46px;padding:10px 12px;border:1px solid #aeb9cb;border-radius:10px;font:inherit}.actions{display:flex;justify-content:space-between;gap:12px;margin-top:26px}.btn{min-height:46px;padding:11px 18px;border:0;border-radius:12px;font-weight:800;background:#2156d9;color:#fff}.secondary{background:#e9eef7;color:#172033}fieldset{border:1px solid #dfe6f0;border-radius:14px;padding:16px}h1{font-size:clamp(30px,6vw,48px)}:focus-visible{outline:3px solid #5b8cff;outline-offset:3px}@media(prefers-reduced-motion:reduce){*{scroll-behavior:auto!important;transition:none!important}}</style></head><body><main class="shell"><progress max="100" value="<?= $progress ?>" aria-label="Einrichtungsfortschritt"></progress><section class="card"><form method="post"><input type="hidden" name="csrf" value="<?= e(csrf()) ?>">
<?php if($step==='welcome'):?><h1>Willkommen bei ShopOS</h1><p>Dieser Assistent richtet das System Schritt für Schritt ein. Linux-Kenntnisse sind nicht nötig.</p>
<?php elseif($step==='locale'):?><h1>Sprache und Region</h1><div class="grid two"><label>Sprache<select name="locale"><?php foreach(LOCALES as $v):?><option><?=e($v)?></option><?php endforeach?></select></label><label>Tastatur<select name="keyboard"><?php foreach(KEYBOARDS as $v):?><option><?=e($v)?></option><?php endforeach?></select></label><label>Zeitzone<select name="timezone"><?php foreach(TIMEZONES as $v):?><option><?=e($v)?></option><?php endforeach?></select></label></div>
<?php elseif($step==='network'):?><h1>Netzwerk</h1><fieldset><label><input type="radio" name="network_mode" value="dhcp" checked> Automatisch per DHCP</label><label><input type="radio" name="network_mode" value="static"> Feste IPv4-Adresse</label></fieldset><div class="grid two"><label>IP-Adresse<input name="ip" inputmode="decimal"></label><label>Gateway<input name="gateway" inputmode="decimal"></label><label>DNS<input name="dns" inputmode="decimal"></label></div>
<?php elseif($step==='identity'):?><h1>Gerät und Administratorkonto</h1><div class="grid"><label>Gerätename<input name="hostname" value="shopos-server" required></label><label>Administrator<input name="admin_user" autocomplete="username" required></label><label>Passwort (mindestens 12 Zeichen)<input type="password" name="password" autocomplete="new-password" required></label><label>Passwort wiederholen<input type="password" name="password_repeat" autocomplete="new-password" required></label></div>
<?php elseif($step==='license'):?><h1>ShopOS Edition</h1><fieldset><?php foreach(EDITIONS as $v):?><label><input type="radio" name="edition" value="<?=e($v)?>" <?=$v==='community'?'checked':''?>> <?=e(ucfirst($v))?></label><?php endforeach?></fieldset><p>Professional und Enterprise werden erst nach einer gültig signierten Lizenz freigeschaltet.</p>
<?php elseif($step==='apps'):?><h1>Apps auswählen</h1><fieldset><?php foreach(APPS as $v):?><label><input type="checkbox" name="apps[]" value="<?=e($v)?>"> <?=e(ucfirst($v))?></label><?php endforeach?></fieldset>
<?php elseif($step==='summary'):?><h1>Zusammenfassung</h1><dl><dt>Gerät</dt><dd><?=e((string)($s['hostname']??''))?></dd><dt>Netzwerk</dt><dd><?=e((string)($s['network_mode']??'dhcp'))?></dd><dt>Edition</dt><dd><?=e((string)($s['edition']??'community'))?></dd><dt>Apps</dt><dd><?=e(implode(', ',(array)($s['apps']??[])))?></dd></dl><label><input type="checkbox" name="confirm" value="yes" required> Einstellungen prüfen und Einrichtung starten</label>
<?php elseif($step==='complete'):?><h1>ShopOS ist eingerichtet</h1><p>Die Grundkonfiguration wurde übernommen. Nach dem Neustart öffnet sich das Control Center.</p><a class="btn" href="/admin/">Zum Control Center</a>
<?php endif;?>
<?php if($step!=='complete'):?><div class="actions"><?php if(stepIndex($step)>0):?><button class="btn secondary" name="action" value="back" type="submit">Zurück</button><?php else:?><span></span><?php endif?><button class="btn" name="action" value="next" type="submit"><?=$step==='summary'?'Einrichten':'Weiter'?></button></div><?php endif?></form></section></main></body></html>
