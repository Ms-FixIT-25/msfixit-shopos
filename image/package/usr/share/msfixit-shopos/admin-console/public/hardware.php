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
if(($_SESSION['authenticated']??false)!==true){header('Location: /admin/');exit;}
function e(string $v):string{return htmlspecialchars($v,ENT_QUOTES|ENT_SUBSTITUTE,'UTF-8');}
function csrf():string{if(empty($_SESSION['csrf']))$_SESSION['csrf']=bin2hex(random_bytes(32));return(string)$_SESSION['csrf'];}
function hw(array $request):array{
    $request['api']='v1';
    $socket=@stream_socket_client('unix:///run/msfixit-hardware-manager/api.sock',$errno,$errstr,2,STREAM_CLIENT_CONNECT);
    if(!is_resource($socket))return['ok'=>false,'error'=>'hardware_manager_unavailable'];
    stream_set_timeout($socket,3);
    fwrite($socket,json_encode($request,JSON_THROW_ON_ERROR|JSON_UNESCAPED_SLASHES)."\n");
    $raw=fgets($socket,262144);fclose($socket);
    if(!is_string($raw))return['ok'=>false,'error'=>'hardware_manager_timeout'];
    try{$decoded=json_decode($raw,true,64,JSON_THROW_ON_ERROR);}catch(Throwable){return['ok'=>false,'error'=>'invalid_hardware_response'];}
    return is_array($decoded)?$decoded:['ok'=>false,'error'=>'invalid_hardware_response'];
}
function peripheralLabel(string $kind):string{
    return match($kind){
        'keyboard'=>'Tastatur','mouse'=>'Maus','barcode_scanner'=>'Barcode-Scanner','touchscreen'=>'Touchscreen',
        'receipt_printer'=>'Bondrucker','label_printer'=>'Etikettendrucker','a4_printer'=>'A4-Drucker',
        'storage'=>'Datenträger','serial_adapter'=>'Serieller Adapter',default=>'Unbekanntes Gerät'
    };
}
function peripheralReadiness(array $device,int $printerCount):array{
    $kind=(string)($device['kind']??'unknown');
    $caps=is_array($device['capabilities']??null)?$device['capabilities']:[];
    if(in_array($kind,['keyboard','mouse','touchscreen'],true))return['Bereit','success','Eingabegerät erkannt'];
    if($kind==='barcode_scanner')return in_array('barcode-input',$caps,true)
        ?['Bereit','success','Barcode-Eingabe erkannt; physischer Scan-Test bleibt erforderlich']
        :['Prüfen','warning','Scanner erkannt, HID-/Barcode-Fähigkeit noch nicht bestätigt'];
    if(in_array($kind,['receipt_printer','label_printer','a4_printer'],true))return $printerCount>0
        ?['Zuordnung prüfen','warning','CUPS-Queue vorhanden; eindeutige Zuordnung und Testdruck erforderlich']
        :['Einrichtung nötig','warning','Drucker erkannt; noch keine CUPS-Queue nachgewiesen'];
    if($kind==='storage')return['Erkannt','warning','Nur über den sicheren Geräte-Assistenten einbinden'];
    if($kind==='serial_adapter')return['Erkannt','warning','Anwendung und Schnittstellenprofil müssen gewählt werden'];
    return['Prüfen','warning','Gerät erkannt, Funktion noch nicht sicher klassifiziert'];
}
function capabilityLabel(string $cap):string{
    return match($cap){'hid-keyboard'=>'HID-Tastatur','barcode-input'=>'Barcode','pointer'=>'Zeiger','absolute-pointer'=>'Touch','print'=>'Druck','block-storage'=>'Speicher','serial'=>'Seriell','hotplug'=>'Hotplug',default=>$cap};
}
$message='';$kind='info';
if($_SERVER['REQUEST_METHOD']==='POST'){
    if(!hash_equals(csrf(),(string)($_POST['csrf']??''))){http_response_code(403);exit('Ungültige Anfrage.');}
    $action=(string)($_POST['action']??'');$password=(string)($_POST['password']??'');
    if($action==='settings'){
        $mode=(string)($_POST['mode']??'observe');
        if(!in_array($mode,['observe','recommend','automatic'],true))$mode='observe';
        $result=hw(['method'=>'POST','path'=>'/settings','password'=>$password,'body'=>['mode'=>$mode]]);
    }elseif($action==='apply'){
        $id=(string)($_POST['recommendation_id']??'');
        $result=hw(['method'=>'POST','path'=>'/actions/apply','password'=>$password,'recommendation_id'=>$id]);
    }elseif($action==='rollback'){
        $tx=(string)($_POST['transaction_id']??'');
        $result=hw(['method'=>'POST','path'=>'/actions/rollback','password'=>$password,'transaction_id'=>$tx]);
    }else{$result=['ok'=>false,'error'=>'unsupported_action'];}
    $message=($result['ok']??false)?'Aktion erfolgreich abgeschlossen.':'Aktion abgelehnt oder fehlgeschlagen: '.(string)($result['error']??'unbekannt');
    $kind=($result['ok']??false)?'success':'error';
}
$status=hw(['method'=>'GET','path'=>'/status']);
$settings=hw(['method'=>'GET','path'=>'/settings']);
$events=hw(['method'=>'GET','path'=>'/events']);
$s=is_array($status['snapshot']??null)?$status['snapshot']:[];
$platform=is_array($s['platform']??null)?$s['platform']:[];$cpu=is_array($s['cpu']??null)?$s['cpu']:[];$memory=is_array($s['memory']??null)?$s['memory']:[];$thermal=is_array($s['thermal']??null)?$s['thermal']:[];$storage=is_array($s['storage']??null)?$s['storage']:[];
$recommendations=is_array($s['recommendations']??null)?$s['recommendations']:[];$network=is_array($s['network']??null)?$s['network']:[];$usb=is_array($s['usb']??null)?$s['usb']:[];$printers=is_array($s['printers']??null)?$s['printers']:[];
$mode=(string)($settings['settings']['mode']??'observe');
function bytes(?int $v):string{if($v===null)return'–';$u=['B','KB','MB','GB','TB'];$n=(float)$v;$i=0;while($n>=1024&&$i<count($u)-1){$n/=1024;$i++;}return number_format($n,$i>1?1:0,',','.').' '.$u[$i];}
?><!doctype html><html lang="de"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="refresh" content="15"><title>ShopOS Hardware Manager</title><style>
:root{font-family:Inter,system-ui,sans-serif;color:#172033;background:#f4f7fb;--brand:#6a2ca0;--ok:#197447;--warn:#a45b00;--bad:#b4233a}*{box-sizing:border-box}body{margin:0}.shell{max-width:1200px;margin:auto;padding:24px}.top{display:flex;justify-content:space-between;gap:18px;align-items:start}.back{color:#536071;text-decoration:none}.grid{display:grid;grid-template-columns:repeat(12,minmax(0,1fr));gap:16px;margin-top:18px}.card{grid-column:span 4;background:white;border:1px solid #e1e7ee;border-radius:20px;padding:20px;box-shadow:0 8px 28px #1720330a}.wide{grid-column:span 6}.full{grid-column:1/-1}.metric{font-size:32px;font-weight:850}.muted{color:#687684}.pill{display:inline-flex;padding:6px 10px;border-radius:999px;background:#edf0f3;font-weight:800;font-size:12px}.warning{background:#fff0dc;color:var(--warn)}.critical,.emergency,.error{background:#fde8ec;color:var(--bad)}.notice{padding:13px;border-radius:12px;margin:14px 0}.success{background:#e4f5eb;color:var(--ok)}table{width:100%;border-collapse:collapse}td,th{padding:9px;border-bottom:1px solid #edf1f4;text-align:left;vertical-align:top}.device-name{font-weight:800}.caps{display:flex;gap:5px;flex-wrap:wrap}.caps .pill{font-weight:650}form{display:grid;gap:10px;margin-top:12px}input,select,button{font:inherit;padding:10px;border-radius:10px;border:1px solid #ccd5df}button{border:0;background:var(--brand);color:white;font-weight:800}.rec{padding:14px 0;border-bottom:1px solid #edf1f4}.rec:last-child{border:0}@media(max-width:850px){.card,.wide{grid-column:1/-1}.top{display:block}.device-table{display:block;overflow-x:auto}}</style></head><body><main class="shell">
<div class="top"><div><a class="back" href="/admin/?view=dashboard">← Control Center</a><h1>Hardware Manager</h1><p class="muted">Energie, Temperatur, Ressourcen, Netzwerk und Peripherie – konservativ optimiert, ohne Übertaktung.</p></div><span class="pill <?=e((string)($thermal['level']??''))?>"><?=e(strtoupper((string)($thermal['level']??'offline')))?></span></div>
<?php if($message!==''):?><div class="notice <?=e($kind)?>"><?=e($message)?></div><?php endif;?>
<section class="grid"><article class="card"><div class="muted">Plattform</div><div class="metric"><?=e((string)($platform['model']??$platform['distribution']??'–'))?></div><p><?=e((string)($platform['architecture']??'–'))?> · <?=e((string)($platform['kernel']??'–'))?></p><p class="muted">Virtualisierung: <?=e((string)($platform['virtualization']??'keine erkannt'))?></p></article>
<article class="card"><div class="muted">Temperatur</div><div class="metric"><?=isset($thermal['primary_c'])?e(number_format((float)$thermal['primary_c'],1,',','.')).' °C':'–'?></div><p class="muted"><?=e((string)($thermal['decision_reason']??''))?></p></article>
<article class="card"><div class="muted">CPU / RAM</div><div class="metric"><?=isset($cpu['utilization_percent'])?e((string)$cpu['utilization_percent']).' %':'–'?></div><p>Governor: <?=e((string)($cpu['governor']??'–'))?><br>RAM frei: <?=e(bytes(isset($memory['available_bytes'])?(int)$memory['available_bytes']:null))?></p></article>
<article class="card wide"><h2>Netzwerk</h2><table><tr><th>Interface</th><th>Status</th><th>Link</th><th>Duplex</th><th>MTU</th><th>WLAN</th></tr><?php foreach($network as $n):?><tr><td><?=e((string)($n['name']??''))?></td><td><?=e((string)($n['state']??''))?></td><td><?=e(isset($n['speed_mbps'])?(string)$n['speed_mbps'].' Mbit/s':'–')?></td><td><?=e((string)($n['duplex']??'–'))?></td><td><?=e(isset($n['mtu'])?(string)$n['mtu']:'–')?></td><td><?=e(isset($n['wireless_signal_dbm'])?(string)$n['wireless_signal_dbm'].' dBm':'–')?></td></tr><?php endforeach;?></table></article>
<article class="card wide"><h2>Speicher & Drucker</h2><p><strong><?=e((string)($storage['boot_medium']??'unbekannt'))?></strong> · <?=e(bytes(isset($storage['free_bytes'])?(int)$storage['free_bytes']:null))?> frei</p><p><?=count($usb)?> USB-Geräte aktuell verbunden · <?=count($printers)?> CUPS-Druckerqueues</p><?php foreach($printers as $p):?><span class="pill"><?=e((string)($p['name']??''))?>: <?=e((string)($p['state']??''))?></span> <?php endforeach;?></article>
<article class="card full"><h2>Peripherie</h2><p class="muted">Aktueller Hardware-Snapshot; die Seite aktualisiert sich alle 15 Sekunden und zeigt neu verbundene oder entfernte USB-Geräte ohne Neustart. „Bereit“ bestätigt Software-/Treiberfähigkeit, ersetzt aber keinen physischen Abnahmetest.</p><?php if(!$usb):?><p class="muted">Keine klassifizierbaren USB-Geräte im aktuellen Snapshot.</p><?php else:?><div class="device-table"><table><tr><th>Gerät</th><th>Typ</th><th>Status</th><th>Fähigkeiten</th><th>USB</th></tr><?php foreach($usb as $d):$readiness=peripheralReadiness(is_array($d)?$d:[],count($printers));$caps=is_array($d['capabilities']??null)?$d['capabilities']:[];?><tr><td><div class="device-name"><?=e(trim((string)($d['manufacturer']??'').' '.(string)($d['product']??''))?:'USB-Gerät')?></div><span class="muted"><?=e((string)($d['vendor_id']??'----'))?>:<?=e((string)($d['product_id']??'----'))?></span></td><td><?=e(peripheralLabel((string)($d['kind']??'unknown')))?></td><td><span class="pill <?=e($readiness[1])?>"><?=e($readiness[0])?></span><br><span class="muted"><?=e($readiness[2])?></span></td><td><div class="caps"><?php if(!$caps):?><span class="muted">–</span><?php endif;?><?php foreach($caps as $cap):?><span class="pill"><?=e(capabilityLabel((string)$cap))?></span><?php endforeach;?></div></td><td><?=e((string)($d['usb_spec']??'–'))?><br><span class="muted"><?=isset($d['negotiated_mbps'])?e((string)$d['negotiated_mbps']).' Mbit/s':'–'?></span></td></tr><?php endforeach;?></table></div><?php endif;?></article>
<article class="card full"><h2>Empfehlungen</h2><?php if(!$recommendations):?><p class="muted">Aktuell keine konkrete Optimierung empfohlen.</p><?php endif;?><?php foreach($recommendations as $r):?><div class="rec"><span class="pill <?=e((string)($r['severity']??''))?>"><?=e((string)($r['severity']??''))?></span><h3><?=e((string)($r['title']??''))?></h3><p><?=e((string)($r['problem']??''))?></p><p class="muted"><strong>Aktion:</strong> <?=e((string)($r['action']??''))?><br><strong>Nutzen:</strong> <?=e((string)($r['expected_benefit']??''))?><br><strong>Risiko:</strong> <?=e((string)($r['risk']??''))?></p><?php if(($r['automatable']??false)===true):?><form method="post"><input type="hidden" name="csrf" value="<?=e(csrf())?>"><input type="hidden" name="action" value="apply"><input type="hidden" name="recommendation_id" value="<?=e((string)($r['id']??''))?>"><input type="password" name="password" required placeholder="Control-Center-Passwort"><button>Kontrolliert anwenden</button></form><?php endif;?></div><?php endforeach;?></article>
<article class="card full"><h2>Betriebsart</h2><p class="muted">„Automatic“ führt ausschließlich explizit freigegebene, reversible Aktionen aus. Automatische Notabschaltung bleibt bis zur realen Hardware-Laborfreigabe blockiert.</p><form method="post"><input type="hidden" name="csrf" value="<?=e(csrf())?>"><input type="hidden" name="action" value="settings"><select name="mode"><option value="observe" <?=$mode==='observe'?'selected':''?>>Beobachten</option><option value="recommend" <?=$mode==='recommend'?'selected':''?>>Empfehlen</option><option value="automatic" <?=$mode==='automatic'?'selected':''?>>Automatisch – nur sichere reversible Regeln</option></select><input type="password" name="password" required placeholder="Control-Center-Passwort"><button>Speichern</button></form></article>
</section></main></body></html>
