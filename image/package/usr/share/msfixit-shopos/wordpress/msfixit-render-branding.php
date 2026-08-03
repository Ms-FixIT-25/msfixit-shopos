<?php
/**
 * Generate web variants from the single embedded Ms. FixIT brand image.
 * Requires PHP GD, which is part of the ShopOS appliance package.
 */

if ($argc !== 3) {
    fwrite(STDERR, "Usage: php msfixit-render-branding.php SOURCE_WEBP OUTPUT_DIRECTORY\n");
    exit(2);
}

[$script, $source, $output_dir] = $argv;

if (!is_file($source)) {
    fwrite(STDERR, "Brand source image not found: {$source}\n");
    exit(1);
}

if (!extension_loaded('gd') || !function_exists('imagecreatefromwebp')) {
    fwrite(STDERR, "PHP GD with WebP support is required.\n");
    exit(1);
}

if (!is_dir($output_dir) && !mkdir($output_dir, 0755, true) && !is_dir($output_dir)) {
    fwrite(STDERR, "Unable to create branding output directory.\n");
    exit(1);
}

$source_image = imagecreatefromwebp($source);
if ($source_image === false) {
    fwrite(STDERR, "Unable to decode brand image.\n");
    exit(1);
}

function msfixit_crop_resize(
    GdImage $source,
    int $x,
    int $y,
    int $width,
    int $height,
    int $target_width,
    int $target_height
): GdImage {
    $target = imagecreatetruecolor($target_width, $target_height);
    $white = imagecolorallocate($target, 255, 255, 255);
    imagefill($target, 0, 0, $white);
    imagecopyresampled(
        $target,
        $source,
        0,
        0,
        $x,
        $y,
        $target_width,
        $target_height,
        $width,
        $height
    );
    return $target;
}

$source_width = imagesx($source_image);
$source_height = imagesy($source_image);
if ($source_width < 1000 || $source_height < 1000) {
    fwrite(STDERR, "Unexpected brand image dimensions.\n");
    exit(1);
}

// The crop coordinates originate from the supplied 1254 x 1254 artwork and
// are scaled to the embedded optimized source size so the result is stable.
$scale_x = $source_width / 1254;
$scale_y = $source_height / 1254;
$scaled = static fn (int $value, float $scale): int => max(1, (int) round($value * $scale));

$header = msfixit_crop_resize(
    $source_image,
    $scaled(45, $scale_x),
    $scaled(35, $scale_y),
    $scaled(1165, $scale_x),
    $scaled(720, $scale_y),
    1000,
    618
);
$icon = msfixit_crop_resize(
    $source_image,
    $scaled(20, $scale_x),
    $scaled(35, $scale_y),
    $scaled(620, $scale_x),
    $scaled(620, $scale_y),
    512,
    512
);

if (!imagewebp($header, $output_dir . '/msfixit-brand-header.webp', 90)) {
    fwrite(STDERR, "Unable to write header logo.\n");
    exit(1);
}
if (!imagejpeg($icon, $output_dir . '/msfixit-site-icon.jpg', 90)) {
    fwrite(STDERR, "Unable to write site icon.\n");
    exit(1);
}

imagedestroy($header);
imagedestroy($icon);
imagedestroy($source_image);
