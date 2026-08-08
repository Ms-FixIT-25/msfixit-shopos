<?php
declare(strict_types=1);

require __DIR__ . '/../image/package/usr/share/msfixit-shopos/admin-console/lib/scanner-validation.php';

function expect(bool $condition, string $message): void
{
    if (!$condition) {
        fwrite(STDERR, "FAIL: {$message}\n");
        exit(1);
    }
}

expect(shoposValidEan('96385074'), 'known EAN-8 must validate');
expect(!shoposValidEan('96385075'), 'invalid EAN-8 check digit must fail');
expect(shoposValidEan('4006381333931'), 'known EAN-13 must validate');
expect(!shoposValidEan('4006381333932'), 'invalid EAN-13 check digit must fail');

$ean8 = shoposEvaluateScannerInput('96385074');
expect($ean8['class'] === 'success' && $ean8['title'] === 'EAN-8 gültig', 'EAN-8 evaluation must succeed');
$ean13 = shoposEvaluateScannerInput('4006381333931');
expect($ean13['class'] === 'success' && $ean13['title'] === 'EAN-13 gültig', 'EAN-13 evaluation must succeed');
$generic = shoposEvaluateScannerInput('ABC-123');
expect($generic['class'] === 'success' && $generic['title'] === 'Scannertext empfangen', 'generic scanner text must be accepted without false symbology claim');
$control = shoposEvaluateScannerInput("ABC\x01DEF");
expect($control['class'] === 'warning' && $control['title'] === 'Steuerzeichen erkannt', 'unexpected control characters must be surfaced');
$long = shoposEvaluateScannerInput(str_repeat('X', 300));
expect($long['class'] === 'warning' && strlen($long['scan']) === 256, 'oversized scan input must be bounded');

fwrite(STDOUT, "PASS: scanner acceptance validation covers EAN-8, EAN-13, generic scanner text, control characters and bounded input.\n");
