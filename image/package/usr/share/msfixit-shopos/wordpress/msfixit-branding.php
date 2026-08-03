<?php
/**
 * Plugin Name: Ms. FixIT ShopOS Branding
 * Description: Durable storefront, login and administration branding for ShopOS.
 * Version: 1.0.0
 */

if (!defined('ABSPATH')) {
    exit;
}

function msfixit_shopos_brand_image_url(string $option_name, string $size = 'full'): string
{
    $attachment_id = (int) get_option($option_name, 0);
    if ($attachment_id < 1) {
        return '';
    }

    $url = wp_get_attachment_image_url($attachment_id, $size);
    return is_string($url) ? $url : '';
}

// Existing user-created pages are listed here only while ShopOS provisions
// its own pages. Blocking the ownership marker guarantees that a later re-run
// cannot take over or overwrite those pages, even after an interrupted setup.
add_filter(
    'update_post_metadata',
    static function ($check, int $object_id, string $meta_key) {
        if ($meta_key !== '_msfixit_shopos_managed') {
            return $check;
        }

        $protected_ids = array_map(
            'intval',
            (array) get_option('msfixit_shopos_protected_page_ids', [])
        );

        return in_array($object_id, $protected_ids, true) ? true : $check;
    },
    10,
    3
);

add_filter('body_class', static function (array $classes): array {
    $classes[] = 'msfixit-shopos';
    return $classes;
});

add_action('wp_enqueue_scripts', static function (): void {
    $css = <<<'CSS'
:root {
    --msfixit-navy: #10243f;
    --msfixit-pink: #ed3f91;
    --msfixit-teal: #2bbbc0;
    --msfixit-soft: #f6fbfc;
}
body.msfixit-shopos { color: #24364e; }
.site-header {
    background: #fff;
    border-bottom: 4px solid transparent;
    border-image: linear-gradient(90deg, var(--msfixit-teal), var(--msfixit-pink)) 1;
}
.site-branding .custom-logo { width: auto; max-width: min(520px, 88vw); max-height: 150px; object-fit: contain; }
.site-branding .site-title, .site-branding .site-description { position: absolute; clip: rect(1px, 1px, 1px, 1px); }
a { color: #168f96; }
a:hover, a:focus { color: var(--msfixit-pink); }
button, input[type="button"], input[type="reset"], input[type="submit"], .button, .wp-block-button__link, .added_to_cart {
    border: 0;
    border-radius: 999px;
    background: linear-gradient(90deg, var(--msfixit-teal), var(--msfixit-pink));
    color: #fff;
    font-weight: 700;
    box-shadow: 0 8px 22px rgba(16, 36, 63, .14);
}
button:hover, input[type="submit"]:hover, .button:hover, .wp-block-button__link:hover { color: #fff; filter: brightness(.96); }
.wp-block-button.is-style-outline .wp-block-button__link { background: #fff; color: var(--msfixit-navy); border: 2px solid var(--msfixit-teal); box-shadow: none; }
.msfixit-hero {
    margin-top: 1.5rem;
    padding: clamp(1.2rem, 3vw, 3rem);
    border-radius: 28px;
    background: linear-gradient(135deg, #fff 0%, #effcfc 55%, #fff2f8 100%);
    box-shadow: 0 18px 55px rgba(16, 36, 63, .10);
}
.msfixit-hero img { max-height: 720px; width: auto; }
.msfixit-service-grid > .wp-block-column {
    padding: 1.5rem;
    border: 1px solid rgba(43, 187, 192, .28);
    border-radius: 20px;
    background: #fff;
    box-shadow: 0 10px 30px rgba(16, 36, 63, .07);
}
.woocommerce span.onsale { border-color: var(--msfixit-pink); color: var(--msfixit-pink); }
.site-footer { border-top: 4px solid var(--msfixit-teal); }
.msfixit-footer-credit { text-align: center; color: #fff; }
.msfixit-footer-credit strong { color: #fff; }
@media (max-width: 767px) {
    .site-branding .custom-logo { max-height: 105px; }
    .msfixit-hero { border-radius: 18px; }
}
CSS;

    wp_register_style('msfixit-shopos-branding', false, [], '1.0.0');
    wp_enqueue_style('msfixit-shopos-branding');
    wp_add_inline_style('msfixit-shopos-branding', $css);
}, 30);

add_action('login_enqueue_scripts', static function (): void {
    $logo_url = msfixit_shopos_brand_image_url('msfixit_brand_logo_id', 'large');
    if ($logo_url === '') {
        return;
    }

    printf(
        '<style>body.login{background:linear-gradient(135deg,#effcfc,#fff2f8)}.login h1 a{background-image:url(%s);background-size:contain;width:320px;height:180px}.login form{border-radius:20px;border:0;box-shadow:0 18px 50px rgba(16,36,63,.12)}.wp-core-ui .button-primary{background:linear-gradient(90deg,#2bbbc0,#ed3f91);border:0;border-radius:999px}</style>',
        esc_url($logo_url)
    );
});

add_filter('login_headerurl', static fn (): string => home_url('/'));
add_filter('login_headertext', static fn (): string => 'Ms. FixIT ShopOS');

add_action('after_setup_theme', static function (): void {
    if (function_exists('storefront_credit')) {
        remove_action('storefront_footer', 'storefront_credit', 20);
    }

    add_action('storefront_footer', static function (): void {
        echo '<div class="msfixit-footer-credit">';
        echo '<strong>Ms. FixIT</strong> · IT gelöst. Einfach. Fix. Günstig.<br>';
        echo '<span>Pauschal · Diskont · Fair</span>';
        echo '</div>';
    }, 20);
});

add_action('wp_dashboard_setup', static function (): void {
    wp_add_dashboard_widget(
        'msfixit_shopos_checklist',
        'Ms. FixIT ShopOS – vor dem öffentlichen Start',
        static function (): void {
            $is_private = (string) get_option('blog_public', '0') !== '1';
            echo '<p><strong>Status:</strong> ' . ($is_private ? 'Suchmaschinen sind noch gesperrt.' : 'Website ist öffentlich indexierbar.') . '</p>';
            echo '<ol>';
            echo '<li>Zahlungsanbieter verbinden und Testzahlung durchführen.</li>';
            echo '<li>Versandarten, Liefergebiete und Rücksendekosten festlegen.</li>';
            echo '<li>Steuerdarstellung passend zur tatsächlichen Unternehmenssituation prüfen.</li>';
            echo '<li>Impressum, Datenschutz, AGB sowie Widerruf/Rückgabe rechtlich fertigstellen.</li>';
            echo '<li>Externes Backupziel und Wiederherstellungstest einrichten.</li>';
            echo '<li>Erst danach Suchmaschinenfreigabe und öffentliche Domain aktivieren.</li>';
            echo '</ol>';
        }
    );
});
