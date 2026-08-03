<?php
/**
 * Plugin Name: Ms. FixIT ShopOS Cable Discovery
 * Description: Accessible cable search, faceted filters, SEO controls, structured data and an Austria Merchant feed.
 * Version: 1.0.0
 */

declare(strict_types=1);

if (!defined('ABSPATH')) {
    exit;
}

require_once '/usr/share/msfixit-shopos/discovery/discovery-lib.php';

const MSFIXIT_DISCOVERY_ENV = '/etc/msfixit-shopos/discovery.env';
const MSFIXIT_DISCOVERY_FILTER_KEYS = [
    'kabeltyp' => 'pa_kabeltyp',
    'anschluss_a' => 'pa_anschluss-a',
    'anschluss_b' => 'pa_anschluss-b',
    'laenge' => 'pa_kabellaenge',
    'standard' => 'pa_kabelstandard',
    'leistung' => 'pa_max-leistung',
    'datenrate' => 'pa_datenrate',
    'aufloesung' => 'pa_aufloesung-bildrate',
    'marke' => 'pa_marke',
];
const MSFIXIT_DISCOVERY_CATEGORIES = [
    'usb-kabel', 'hdmi-kabel', 'displayport-kabel', 'netzwerkkabel', 'usb-verlaengerungen',
];

function msfixit_discovery_settings(): array
{
    static $settings = null;
    if (is_array($settings)) {
        return $settings;
    }

    $settings = [];
    if (is_readable(MSFIXIT_DISCOVERY_ENV)) {
        foreach (file(MSFIXIT_DISCOVERY_ENV, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) ?: [] as $line) {
            $line = trim($line);
            if ($line === '' || str_starts_with($line, '#') || !str_contains($line, '=')) {
                continue;
            }
            [$key, $value] = explode('=', $line, 2);
            $settings[trim($key)] = trim($value, " \t\n\r\0\x0B\"'");
        }
    }

    return array_merge([
        'DISCOVERY_ENABLED' => 'yes',
        'DISCOVERY_LANDING_SLUG' => 'kabel-zubehoer',
        'DISCOVERY_PRODUCTS_PER_PAGE' => '12',
        'DISCOVERY_MAX_SUGGESTIONS' => '8',
        'DISCOVERY_REQUIRE_ORIGINAL_CONTENT' => 'yes',
        'DISCOVERY_MIN_SHORT_DESCRIPTION_CHARS' => '80',
        'DISCOVERY_MIN_DESCRIPTION_CHARS' => '250',
        'GOOGLE_MERCHANT_FEED_ENABLED' => 'no',
        'GOOGLE_MERCHANT_FEED_PATH' => 'google-products.xml',
        'GOOGLE_TARGET_COUNTRY' => 'AT',
        'GOOGLE_CONTENT_LANGUAGE' => 'de',
        'GOOGLE_RETURN_DAYS' => '14',
        'STRUCTURED_SHIPPING_APPROVED' => 'no',
        'STRUCTURED_RETURNS_APPROVED' => 'no',
    ], $settings);
}

function msfixit_discovery_yes(string $value): bool
{
    return in_array(strtolower(trim($value)), ['1', 'yes', 'true', 'on'], true);
}

function msfixit_discovery_enabled(): bool
{
    return msfixit_discovery_yes((string) msfixit_discovery_settings()['DISCOVERY_ENABLED']);
}

function msfixit_discovery_term_names(int $productId, string $taxonomy): array
{
    if (!taxonomy_exists($taxonomy)) {
        return [];
    }
    $terms = wp_get_post_terms($productId, $taxonomy, ['fields' => 'names']);
    return is_wp_error($terms) ? [] : array_values(array_filter(array_map('strval', $terms)));
}

function msfixit_discovery_term_slugs(int $productId, string $taxonomy): array
{
    if (!taxonomy_exists($taxonomy)) {
        return [];
    }
    $terms = wp_get_post_terms($productId, $taxonomy, ['fields' => 'slugs']);
    return is_wp_error($terms) ? [] : array_values(array_filter(array_map('strval', $terms)));
}

function msfixit_discovery_primary_value(int $productId, string $taxonomy): string
{
    return msfixit_discovery_term_names($productId, $taxonomy)[0] ?? '';
}

function msfixit_discovery_is_cable(WC_Product $product): bool
{
    if (get_post_meta($product->get_id(), '_msfixit_discovery_cable', true) === 'yes') {
        return true;
    }
    $slugs = wp_get_post_terms($product->get_id(), 'product_cat', ['fields' => 'slugs']);
    if (is_wp_error($slugs)) {
        return false;
    }
    return (bool) array_intersect(MSFIXIT_DISCOVERY_CATEGORIES, $slugs);
}

function msfixit_discovery_product_document(WC_Product $product): array
{
    $productId = $product->get_id();
    $attributeText = [];
    foreach (MSFIXIT_DISCOVERY_FILTER_KEYS as $taxonomy) {
        $attributeText = array_merge($attributeText, msfixit_discovery_term_names($productId, $taxonomy));
    }

    return [
        'title' => $product->get_name(),
        'sku' => $product->get_sku(),
        'gtin' => (string) get_post_meta($productId, '_msfixit_gtin', true),
        'mpn' => (string) get_post_meta($productId, '_msfixit_manufacturer_sku', true),
        'attributes' => implode(' ', $attributeText),
        'description' => wp_strip_all_tags($product->get_short_description() . ' ' . $product->get_description()),
    ];
}

function msfixit_discovery_product_audit(WC_Product $product): array
{
    $productId = $product->get_id();
    $settings = msfixit_discovery_settings();
    return msfixit_discovery_publication_audit([
        'pilot_status' => (string) get_post_meta($productId, '_msfixit_pilot_status', true),
        'compliance_status' => (string) get_post_meta($productId, '_msfixit_compliance_status', true),
        'discovery_review_status' => (string) get_post_meta($productId, '_msfixit_discovery_review_status', true),
        'content_reviewed' => (string) get_post_meta($productId, '_msfixit_content_reviewed', true),
        'image_id' => $product->get_image_id(),
        'title' => $product->get_name(),
        'short_description' => $product->get_short_description(),
        'description' => $product->get_description(),
        'brand' => msfixit_discovery_primary_value($productId, 'pa_marke') ?: (string) get_post_meta($productId, '_msfixit_manufacturer_name', true),
        'gtin' => (string) get_post_meta($productId, '_msfixit_gtin', true),
        'mpn' => (string) get_post_meta($productId, '_msfixit_manufacturer_sku', true),
        'cable_type' => msfixit_discovery_primary_value($productId, 'pa_kabeltyp'),
        'connector_a' => msfixit_discovery_primary_value($productId, 'pa_anschluss-a'),
        'connector_b' => msfixit_discovery_primary_value($productId, 'pa_anschluss-b'),
        'cable_length' => msfixit_discovery_primary_value($productId, 'pa_kabellaenge'),
        'cable_standard' => msfixit_discovery_primary_value($productId, 'pa_kabelstandard'),
        'price' => $product->get_regular_price(),
    ], [
        'minimum_short_description' => (int) $settings['DISCOVERY_MIN_SHORT_DESCRIPTION_CHARS'],
        'minimum_description' => (int) $settings['DISCOVERY_MIN_DESCRIPTION_CHARS'],
        'require_original_content' => msfixit_discovery_yes((string) $settings['DISCOVERY_REQUIRE_ORIGINAL_CONTENT']),
    ]);
}

function msfixit_discovery_is_public_product(WC_Product $product): bool
{
    return $product->get_status() === 'publish'
        && msfixit_discovery_is_cable($product)
        && msfixit_discovery_product_audit($product) === [];
}

function msfixit_discovery_all_products(): array
{
    $products = wc_get_products([
        'status' => ['publish'],
        'limit' => -1,
        'type' => ['simple', 'variable', 'variation'],
        'return' => 'objects',
        'orderby' => 'menu_order',
        'order' => 'ASC',
    ]);

    return array_values(array_filter($products, static fn($product): bool =>
        $product instanceof WC_Product && msfixit_discovery_is_public_product($product)
    ));
}

function msfixit_discovery_request_value(string $key): string
{
    return isset($_GET[$key]) ? sanitize_text_field(wp_unslash((string) $_GET[$key])) : '';
}

function msfixit_discovery_matches_filters(WC_Product $product, array $filters): bool
{
    $productId = $product->get_id();
    foreach (MSFIXIT_DISCOVERY_FILTER_KEYS as $key => $taxonomy) {
        $selected = $filters[$key] ?? '';
        if ($selected === '') {
            continue;
        }
        if (!in_array(sanitize_title($selected), msfixit_discovery_term_slugs($productId, $taxonomy), true)) {
            return false;
        }
    }

    if (($filters['lager'] ?? '') === 'ja' && !$product->is_in_stock()) {
        return false;
    }
    $price = (float) $product->get_price();
    if (($filters['min_preis'] ?? '') !== '' && $price < (float) str_replace(',', '.', $filters['min_preis'])) {
        return false;
    }
    if (($filters['max_preis'] ?? '') !== '' && $price > (float) str_replace(',', '.', $filters['max_preis'])) {
        return false;
    }

    return true;
}

function msfixit_discovery_filtered_products(array $filters): array
{
    $query = trim((string) ($filters['kabelsuche'] ?? ''));
    $results = [];
    foreach (msfixit_discovery_all_products() as $product) {
        if (!msfixit_discovery_matches_filters($product, $filters)) {
            continue;
        }
        $score = msfixit_discovery_score(msfixit_discovery_product_document($product), $query);
        if ($query !== '' && $score < 1) {
            continue;
        }
        $results[] = ['product' => $product, 'score' => $score];
    }

    $sorting = $filters['sortierung'] ?? ($query !== '' ? 'relevanz' : 'standard');
    usort($results, static function (array $left, array $right) use ($sorting): int {
        /** @var WC_Product $a */
        $a = $left['product'];
        /** @var WC_Product $b */
        $b = $right['product'];
        return match ($sorting) {
            'preis-auf' => (float) $a->get_price() <=> (float) $b->get_price(),
            'preis-ab' => (float) $b->get_price() <=> (float) $a->get_price(),
            'neu' => $b->get_date_created()?->getTimestamp() <=> $a->get_date_created()?->getTimestamp(),
            'name' => strnatcasecmp($a->get_name(), $b->get_name()),
            'relevanz' => ($right['score'] <=> $left['score']) ?: strnatcasecmp($a->get_name(), $b->get_name()),
            default => ($b->get_total_sales() <=> $a->get_total_sales()) ?: strnatcasecmp($a->get_name(), $b->get_name()),
        };
    });

    return array_map(static fn(array $row): WC_Product => $row['product'], $results);
}

function msfixit_discovery_filter_options(string $taxonomy): array
{
    if (!taxonomy_exists($taxonomy)) {
        return [];
    }
    $terms = get_terms(['taxonomy' => $taxonomy, 'hide_empty' => true]);
    if (is_wp_error($terms)) {
        return [];
    }
    return array_values(array_filter($terms, static fn($term): bool => $term instanceof WP_Term));
}

function msfixit_discovery_render_search_box(string $context = 'catalog'): string
{
    $query = msfixit_discovery_request_value('kabelsuche');
    $landing = get_permalink(get_page_by_path((string) msfixit_discovery_settings()['DISCOVERY_LANDING_SLUG']) ?: 0) ?: home_url('/kabel-zubehoer/');
    ob_start();
    ?>
    <form class="msfixit-discovery-search" action="<?php echo esc_url($landing); ?>" method="get" role="search" data-msfixit-search-context="<?php echo esc_attr($context); ?>">
        <label for="msfixit-kabelsuche-<?php echo esc_attr($context); ?>">Kabel oder Anschluss suchen</label>
        <div class="msfixit-discovery-search-row">
            <input id="msfixit-kabelsuche-<?php echo esc_attr($context); ?>" name="kabelsuche" type="search" value="<?php echo esc_attr($query); ?>" placeholder="z. B. USB-C 2 m, HDMI 4K oder LAN" autocomplete="off" aria-autocomplete="list" aria-controls="msfixit-suggestions-<?php echo esc_attr($context); ?>">
            <button type="submit">Suchen</button>
        </div>
        <div id="msfixit-suggestions-<?php echo esc_attr($context); ?>" class="msfixit-search-suggestions" role="listbox" hidden></div>
    </form>
    <?php
    return (string) ob_get_clean();
}

function msfixit_discovery_shortcode(): string
{
    if (!msfixit_discovery_enabled() || !function_exists('wc_get_products')) {
        return '';
    }

    $filters = [];
    foreach (array_merge(array_keys(MSFIXIT_DISCOVERY_FILTER_KEYS), ['kabelsuche', 'lager', 'min_preis', 'max_preis', 'sortierung']) as $key) {
        $filters[$key] = msfixit_discovery_request_value($key);
    }
    $products = msfixit_discovery_filtered_products($filters);
    $settings = msfixit_discovery_settings();
    $perPage = max(6, min(48, (int) $settings['DISCOVERY_PRODUCTS_PER_PAGE']));
    $currentPage = max(1, (int) msfixit_discovery_request_value('kabel_seite'));
    $totalPages = max(1, (int) ceil(count($products) / $perPage));
    $currentPage = min($currentPage, $totalPages);
    $pageProducts = array_slice($products, ($currentPage - 1) * $perPage, $perPage);

    $labels = [
        'kabeltyp' => 'Kabeltyp', 'anschluss_a' => 'Anschluss A', 'anschluss_b' => 'Anschluss B',
        'laenge' => 'Länge', 'standard' => 'Standard', 'leistung' => 'Max. Ladeleistung',
        'datenrate' => 'Datenrate', 'aufloesung' => 'Auflösung/Bildrate', 'marke' => 'Marke',
    ];

    ob_start();
    echo '<section class="msfixit-cable-catalog">';
    echo msfixit_discovery_render_search_box('catalog');
    ?>
    <button class="msfixit-filter-toggle" type="button" aria-expanded="false" aria-controls="msfixit-cable-filters">Filter anzeigen</button>
    <div class="msfixit-catalog-layout">
        <aside id="msfixit-cable-filters" class="msfixit-cable-filters" aria-label="Kabelfilter">
            <form method="get">
                <?php if ($filters['kabelsuche'] !== ''): ?>
                    <input type="hidden" name="kabelsuche" value="<?php echo esc_attr($filters['kabelsuche']); ?>">
                <?php endif; ?>
                <?php foreach (MSFIXIT_DISCOVERY_FILTER_KEYS as $key => $taxonomy): ?>
                    <?php $options = msfixit_discovery_filter_options($taxonomy); ?>
                    <?php if ($options !== []): ?>
                        <label for="msfixit-filter-<?php echo esc_attr($key); ?>"><?php echo esc_html($labels[$key]); ?></label>
                        <select id="msfixit-filter-<?php echo esc_attr($key); ?>" name="<?php echo esc_attr($key); ?>">
                            <option value="">Alle</option>
                            <?php foreach ($options as $term): ?>
                                <option value="<?php echo esc_attr($term->slug); ?>" <?php selected($filters[$key], $term->slug); ?>><?php echo esc_html($term->name); ?></option>
                            <?php endforeach; ?>
                        </select>
                    <?php endif; ?>
                <?php endforeach; ?>
                <div class="msfixit-price-filter">
                    <label for="msfixit-min-preis">Preis von</label>
                    <input id="msfixit-min-preis" name="min_preis" inputmode="decimal" value="<?php echo esc_attr($filters['min_preis']); ?>" placeholder="0,00">
                    <label for="msfixit-max-preis">bis</label>
                    <input id="msfixit-max-preis" name="max_preis" inputmode="decimal" value="<?php echo esc_attr($filters['max_preis']); ?>" placeholder="100,00">
                </div>
                <label class="msfixit-checkbox"><input type="checkbox" name="lager" value="ja" <?php checked($filters['lager'], 'ja'); ?>> Nur sofort verfügbare Artikel</label>
                <label for="msfixit-sortierung">Sortierung</label>
                <select id="msfixit-sortierung" name="sortierung">
                    <option value="standard" <?php selected($filters['sortierung'], 'standard'); ?>>Empfohlen</option>
                    <option value="relevanz" <?php selected($filters['sortierung'], 'relevanz'); ?>>Relevanz</option>
                    <option value="preis-auf" <?php selected($filters['sortierung'], 'preis-auf'); ?>>Preis aufsteigend</option>
                    <option value="preis-ab" <?php selected($filters['sortierung'], 'preis-ab'); ?>>Preis absteigend</option>
                    <option value="neu" <?php selected($filters['sortierung'], 'neu'); ?>>Neu im Shop</option>
                    <option value="name" <?php selected($filters['sortierung'], 'name'); ?>>Name</option>
                </select>
                <div class="msfixit-filter-actions">
                    <button type="submit">Filter anwenden</button>
                    <a href="<?php echo esc_url(get_permalink()); ?>">Zurücksetzen</a>
                </div>
            </form>
        </aside>
        <div class="msfixit-catalog-results" aria-live="polite">
            <div class="msfixit-result-summary"><strong><?php echo esc_html((string) count($products)); ?></strong> passende Kabelartikel</div>
            <?php if ($pageProducts === []): ?>
                <div class="woocommerce-info">Kein Kabel passt zu dieser Auswahl. Entferne einzelne Filter oder suche nach einem Anschluss wie USB-C, HDMI oder LAN.</div>
            <?php else: ?>
                <?php woocommerce_product_loop_start(); ?>
                <?php foreach ($pageProducts as $product): ?>
                    <?php
                    $GLOBALS['post'] = get_post($product->get_id());
                    setup_postdata($GLOBALS['post']);
                    wc_get_template_part('content', 'product');
                    ?>
                <?php endforeach; ?>
                <?php woocommerce_product_loop_end(); wp_reset_postdata(); ?>
            <?php endif; ?>
            <?php if ($totalPages > 1): ?>
                <nav class="msfixit-pagination" aria-label="Katalogseiten">
                    <?php
                    $baseArgs = array_filter($filters, static fn(string $value): bool => $value !== '');
                    for ($page = 1; $page <= $totalPages; $page++) {
                        $url = add_query_arg(array_merge($baseArgs, ['kabel_seite' => $page]), get_permalink());
                        printf('<a href="%s"%s>%d</a>', esc_url($url), $page === $currentPage ? ' aria-current="page"' : '', $page);
                    }
                    ?>
                </nav>
            <?php endif; ?>
        </div>
    </div>
    <?php
    echo '</section>';
    return (string) ob_get_clean();
}
add_shortcode('msfixit_cable_catalog', 'msfixit_discovery_shortcode');

function msfixit_discovery_is_frontend_context(): bool
{
    $slug = (string) msfixit_discovery_settings()['DISCOVERY_LANDING_SLUG'];
    return is_page($slug) || (function_exists('is_shop') && is_shop()) || is_product_category() || is_search();
}

add_action('wp_enqueue_scripts', static function (): void {
    if (!msfixit_discovery_enabled() || !msfixit_discovery_is_frontend_context()) {
        return;
    }
    $version = '1.0.0';
    wp_enqueue_style('msfixit-discovery', plugins_url('assets/msfixit-discovery.css', __FILE__), [], $version);
    wp_enqueue_script('msfixit-discovery', plugins_url('assets/msfixit-discovery.js', __FILE__), [], $version, true);
    wp_localize_script('msfixit-discovery', 'MsFixITDiscovery', [
        'suggestionsUrl' => esc_url_raw(rest_url('msfixit/v1/cable-suggestions')),
        'minimumCharacters' => 2,
    ]);
});

add_action('storefront_header', static function (): void {
    if (msfixit_discovery_enabled() && !is_admin()) {
        echo '<div class="msfixit-header-search">' . msfixit_discovery_render_search_box('header') . '</div>';
    }
}, 42);

add_action('rest_api_init', static function (): void {
    register_rest_route('msfixit/v1', '/cable-suggestions', [
        'methods' => WP_REST_Server::READABLE,
        'permission_callback' => '__return_true',
        'args' => [
            'q' => ['type' => 'string', 'required' => true, 'sanitize_callback' => 'sanitize_text_field'],
        ],
        'callback' => static function (WP_REST_Request $request): WP_REST_Response {
            $query = trim((string) $request->get_param('q'));
            if (mb_strlen($query, 'UTF-8') < 2) {
                return new WP_REST_Response([], 200);
            }
            $rows = [];
            foreach (msfixit_discovery_all_products() as $product) {
                $score = msfixit_discovery_score(msfixit_discovery_product_document($product), $query);
                if ($score < 1) {
                    continue;
                }
                $rows[] = ['product' => $product, 'score' => $score];
            }
            usort($rows, static fn(array $a, array $b): int => $b['score'] <=> $a['score']);
            $limit = max(3, min(12, (int) msfixit_discovery_settings()['DISCOVERY_MAX_SUGGESTIONS']));
            $payload = [];
            foreach (array_slice($rows, 0, $limit) as $row) {
                /** @var WC_Product $product */
                $product = $row['product'];
                $payload[] = [
                    'title' => $product->get_name(),
                    'url' => $product->get_permalink(),
                    'sku' => $product->get_sku(),
                    'price' => wp_strip_all_tags($product->get_price_html()),
                    'image' => wp_get_attachment_image_url($product->get_image_id(), 'woocommerce_thumbnail') ?: wc_placeholder_img_src('woocommerce_thumbnail'),
                    'summary' => implode(' · ', array_filter([
                        msfixit_discovery_primary_value($product->get_id(), 'pa_anschluss-a'),
                        msfixit_discovery_primary_value($product->get_id(), 'pa_anschluss-b'),
                        msfixit_discovery_primary_value($product->get_id(), 'pa_kabellaenge'),
                    ])),
                ];
            }
            return new WP_REST_Response($payload, 200, ['Cache-Control' => 'public, max-age=120']);
        },
    ]);
});

add_action('add_meta_boxes_product', static function (): void {
    add_meta_box('msfixit-discovery-review', 'Ms. FixIT – Suche & Auffindbarkeit', static function (WP_Post $post): void {
        wp_nonce_field('msfixit_discovery_save', 'msfixit_discovery_nonce');
        $product = wc_get_product($post->ID);
        $audit = $product instanceof WC_Product ? msfixit_discovery_product_audit($product) : ['Produkt konnte nicht geprüft werden.'];
        $suggestions = (string) get_post_meta($post->ID, '_msfixit_attribute_suggestions', true);
        ?>
        <p><label for="msfixit-seo-title"><strong>SEO-Titel</strong></label><br><input class="widefat" id="msfixit-seo-title" name="msfixit_seo_title" maxlength="150" value="<?php echo esc_attr((string) get_post_meta($post->ID, '_msfixit_seo_title', true)); ?>"></p>
        <p><label for="msfixit-seo-description"><strong>Beschreibung für Suchergebnisse</strong></label><br><textarea class="widefat" id="msfixit-seo-description" name="msfixit_seo_description" rows="3" maxlength="320"><?php echo esc_textarea((string) get_post_meta($post->ID, '_msfixit_seo_description', true)); ?></textarea></p>
        <p><label for="msfixit-focus-terms"><strong>Wichtige Suchbegriffe</strong></label><br><input class="widefat" id="msfixit-focus-terms" name="msfixit_focus_terms" value="<?php echo esc_attr((string) get_post_meta($post->ID, '_msfixit_focus_terms', true)); ?>" placeholder="USB-C Kabel, Ladekabel 2 m, 60 W"></p>
        <p><label><input type="checkbox" name="msfixit_content_reviewed" value="yes" <?php checked(get_post_meta($post->ID, '_msfixit_content_reviewed', true), 'yes'); ?>> Text und technische Angaben wurden redaktionell geprüft und nicht blind vom Lieferanten übernommen.</label></p>
        <p><label for="msfixit-discovery-status"><strong>Such-/SEO-Freigabe</strong></label><br><select id="msfixit-discovery-status" name="msfixit_discovery_review_status"><option value="pending">Offen</option><option value="approved" <?php selected(get_post_meta($post->ID, '_msfixit_discovery_review_status', true), 'approved'); ?>>Freigegeben</option></select></p>
        <?php if ($suggestions !== ''): ?><details><summary>Automatisch erkannte Attributvorschläge</summary><pre style="white-space:pre-wrap"><?php echo esc_html($suggestions); ?></pre></details><?php endif; ?>
        <?php if ($audit !== []): ?><div class="notice notice-warning inline"><p><strong>Veröffentlichung noch gesperrt:</strong></p><ul><?php foreach ($audit as $error): ?><li><?php echo esc_html($error); ?></li><?php endforeach; ?></ul></div><?php else: ?><div class="notice notice-success inline"><p>Such-, Feed- und Veröffentlichungsprüfung bestanden.</p></div><?php endif; ?>
        <?php
    }, 'product', 'side', 'high');
});

add_action('save_post_product', static function (int $postId, WP_Post $post): void {
    if (defined('DOING_AUTOSAVE') && DOING_AUTOSAVE) {
        return;
    }
    if (!isset($_POST['msfixit_discovery_nonce']) || !wp_verify_nonce(sanitize_text_field(wp_unslash((string) $_POST['msfixit_discovery_nonce'])), 'msfixit_discovery_save')) {
        return;
    }
    if (!current_user_can('edit_post', $postId)) {
        return;
    }
    update_post_meta($postId, '_msfixit_seo_title', sanitize_text_field(wp_unslash((string) ($_POST['msfixit_seo_title'] ?? ''))));
    update_post_meta($postId, '_msfixit_seo_description', sanitize_textarea_field(wp_unslash((string) ($_POST['msfixit_seo_description'] ?? ''))));
    update_post_meta($postId, '_msfixit_focus_terms', sanitize_text_field(wp_unslash((string) ($_POST['msfixit_focus_terms'] ?? ''))));
    update_post_meta($postId, '_msfixit_content_reviewed', isset($_POST['msfixit_content_reviewed']) ? 'yes' : 'no');
    update_post_meta($postId, '_msfixit_discovery_review_status', sanitize_key((string) ($_POST['msfixit_discovery_review_status'] ?? 'pending')) === 'approved' ? 'approved' : 'pending');
}, 20, 2);

add_action('save_post_product', static function (int $postId): void {
    static $reverting = false;
    if ($reverting || wp_is_post_revision($postId) || get_post_status($postId) !== 'publish') {
        return;
    }
    $product = wc_get_product($postId);
    if (!$product instanceof WC_Product || !msfixit_discovery_is_cable($product)) {
        return;
    }
    $errors = msfixit_discovery_product_audit($product);
    if ($errors === []) {
        return;
    }
    $reverting = true;
    wp_update_post(['ID' => $postId, 'post_status' => 'draft']);
    $reverting = false;
    set_transient('msfixit_discovery_publish_errors_' . get_current_user_id(), $errors, 120);
}, 100);

add_action('admin_notices', static function (): void {
    $key = 'msfixit_discovery_publish_errors_' . get_current_user_id();
    $errors = get_transient($key);
    if (!is_array($errors) || $errors === []) {
        return;
    }
    delete_transient($key);
    echo '<div class="notice notice-error"><p><strong>Der Kabelartikel blieb als Entwurf gespeichert:</strong></p><ul>';
    foreach ($errors as $error) {
        echo '<li>' . esc_html((string) $error) . '</li>';
    }
    echo '</ul></div>';
});

add_filter('woocommerce_structured_data_product', static function (array $markup, WC_Product $product): array {
    if (!msfixit_discovery_is_public_product($product)) {
        return $markup;
    }
    $productId = $product->get_id();
    $gtin = preg_replace('/\D+/', '', (string) get_post_meta($productId, '_msfixit_gtin', true)) ?: '';
    $mpn = (string) get_post_meta($productId, '_msfixit_manufacturer_sku', true);
    $brand = msfixit_discovery_primary_value($productId, 'pa_marke') ?: (string) get_post_meta($productId, '_msfixit_manufacturer_name', true);
    if ($gtin !== '' && in_array(strlen($gtin), [8, 12, 13, 14], true)) {
        $markup['gtin' . strlen($gtin)] = $gtin;
    }
    if ($mpn !== '') {
        $markup['mpn'] = $mpn;
    }
    if ($brand !== '') {
        $markup['brand'] = ['@type' => 'Brand', 'name' => $brand];
    }
    $properties = [];
    foreach (MSFIXIT_DISCOVERY_FILTER_KEYS as $key => $taxonomy) {
        $value = implode(', ', msfixit_discovery_term_names($productId, $taxonomy));
        if ($value !== '') {
            $properties[] = ['@type' => 'PropertyValue', 'name' => $key, 'value' => $value];
        }
    }
    if ($properties !== []) {
        $markup['additionalProperty'] = $properties;
    }

    $settings = msfixit_discovery_settings();
    if (msfixit_discovery_yes((string) $settings['STRUCTURED_SHIPPING_APPROVED'])
        && is_numeric($settings['GOOGLE_SHIPPING_COST_EUR'] ?? null)
        && is_numeric($settings['GOOGLE_DELIVERY_MIN_DAYS'] ?? null)
        && is_numeric($settings['GOOGLE_DELIVERY_MAX_DAYS'] ?? null)) {
        $shipping = [
            '@type' => 'OfferShippingDetails',
            'shippingDestination' => ['@type' => 'DefinedRegion', 'addressCountry' => 'AT'],
            'shippingRate' => ['@type' => 'MonetaryAmount', 'value' => number_format((float) $settings['GOOGLE_SHIPPING_COST_EUR'], 2, '.', ''), 'currency' => 'EUR'],
            'deliveryTime' => [
                '@type' => 'ShippingDeliveryTime',
                'handlingTime' => ['@type' => 'QuantitativeValue', 'minValue' => 0, 'maxValue' => 1, 'unitCode' => 'DAY'],
                'transitTime' => ['@type' => 'QuantitativeValue', 'minValue' => (int) $settings['GOOGLE_DELIVERY_MIN_DAYS'], 'maxValue' => (int) $settings['GOOGLE_DELIVERY_MAX_DAYS'], 'unitCode' => 'DAY'],
            ],
        ];
        foreach (['offers'] as $offerKey) {
            if (isset($markup[$offerKey]) && is_array($markup[$offerKey])) {
                if (array_is_list($markup[$offerKey])) {
                    foreach ($markup[$offerKey] as &$offer) {
                        if (is_array($offer)) {
                            $offer['shippingDetails'] = $shipping;
                        }
                    }
                    unset($offer);
                } else {
                    $markup[$offerKey]['shippingDetails'] = $shipping;
                }
            }
        }
    }
    return $markup;
}, 20, 2);

add_action('wp_head', static function (): void {
    if (is_admin()) {
        return;
    }
    $settings = msfixit_discovery_settings();
    foreach (['GOOGLE_SITE_VERIFICATION' => 'google-site-verification', 'BING_SITE_VERIFICATION' => 'msvalidate.01'] as $key => $name) {
        if (!empty($settings[$key])) {
            printf("<meta name=\"%s\" content=\"%s\">\n", esc_attr($name), esc_attr((string) $settings[$key]));
        }
    }

    $schema = [
        '@context' => 'https://schema.org',
        '@graph' => [
            ['@type' => 'WebSite', '@id' => home_url('/#website'), 'url' => home_url('/'), 'name' => get_bloginfo('name'), 'inLanguage' => 'de-AT'],
            ['@type' => 'Organization', '@id' => home_url('/#organization'), 'name' => get_bloginfo('name'), 'url' => home_url('/'), 'logo' => wp_get_attachment_image_url((int) get_option('site_icon'), 'full') ?: null, 'areaServed' => ['@type' => 'Country', 'name' => 'Österreich']],
        ],
    ];
    echo '<script type="application/ld+json">' . wp_json_encode($schema, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE) . '</script>' . "\n";

    if (!defined('WPSEO_VERSION') && !defined('RANK_MATH_VERSION')) {
        $description = '';
        if (is_product()) {
            $product = wc_get_product(get_queried_object_id());
            if ($product instanceof WC_Product) {
                $description = (string) get_post_meta($product->get_id(), '_msfixit_seo_description', true);
                $description = $description ?: wp_strip_all_tags($product->get_short_description());
            }
        } elseif (is_product_category()) {
            $description = wp_strip_all_tags(term_description());
        } elseif (is_page((string) $settings['DISCOVERY_LANDING_SLUG'])) {
            $description = 'Kabel und IT-Zubehör in Österreich finden: USB-C, HDMI, DisplayPort und Netzwerkkabel übersichtlich nach Anschluss, Länge, Standard und Leistung filtern.';
        }
        if ($description !== '') {
            printf("<meta name=\"description\" content=\"%s\">\n", esc_attr(wp_html_excerpt($description, 300, '')));
        }
    }
}, 20);

add_filter('wp_robots', static function (array $robots): array {
    if (is_search() || msfixit_discovery_has_facet_parameters($_GET)) {
        $robots['noindex'] = true;
        $robots['follow'] = true;
        unset($robots['index']);
    }
    if (is_product_category() && (int) get_queried_object()->count === 0) {
        $robots['noindex'] = true;
    }
    return $robots;
});

add_action('wp', static function (): void {
    if (is_page((string) msfixit_discovery_settings()['DISCOVERY_LANDING_SLUG']) && msfixit_discovery_has_facet_parameters($_GET)) {
        remove_action('wp_head', 'rel_canonical');
        add_action('wp_head', static function (): void {
            echo '<link rel="canonical" href="' . esc_url(get_permalink()) . '">' . "\n";
        }, 1);
    }
});

add_filter('robots_txt', static function (string $output, bool $public): string {
    if (!$public) {
        return $output;
    }
    $rules = "\n# ShopOS faceted search parameters\nDisallow: /*?kabelsuche=\nDisallow: /*?kabeltyp=\nDisallow: /*?anschluss_a=\nDisallow: /*?anschluss_b=\nDisallow: /*?laenge=\nDisallow: /*?standard=\n";
    $rules .= 'Sitemap: ' . esc_url(home_url('/wp-sitemap.xml')) . "\n";
    return rtrim($output) . "\n" . $rules;
}, 20, 2);

add_filter('query_vars', static function (array $vars): array {
    $vars[] = 'msfixit_google_products';
    return $vars;
});

add_action('init', static function (): void {
    $path = trim((string) msfixit_discovery_settings()['GOOGLE_MERCHANT_FEED_PATH'], '/');
    if ($path !== '') {
        add_rewrite_rule('^' . preg_quote($path, '#') . '$', 'index.php?msfixit_google_products=1', 'top');
    }
});

function msfixit_discovery_xml(string $value): string
{
    return htmlspecialchars($value, ENT_XML1 | ENT_QUOTES, 'UTF-8');
}

add_action('template_redirect', static function (): void {
    if ((string) get_query_var('msfixit_google_products') !== '1') {
        return;
    }
    $settings = msfixit_discovery_settings();
    if (!msfixit_discovery_yes((string) $settings['GOOGLE_MERCHANT_FEED_ENABLED'])
        || !is_numeric($settings['GOOGLE_SHIPPING_COST_EUR'] ?? null)
        || !is_numeric($settings['GOOGLE_DELIVERY_MIN_DAYS'] ?? null)
        || !is_numeric($settings['GOOGLE_DELIVERY_MAX_DAYS'] ?? null)) {
        status_header(503);
        header('Content-Type: text/plain; charset=utf-8');
        echo 'Der Google-Produktfeed ist noch nicht freigegeben oder die geprüften Österreich-Versanddaten fehlen.';
        exit;
    }

    nocache_headers();
    header('Content-Type: application/rss+xml; charset=utf-8');
    echo '<?xml version="1.0" encoding="UTF-8"?>' . "\n";
    echo '<rss version="2.0" xmlns:g="http://base.google.com/ns/1.0"><channel>';
    echo '<title>' . msfixit_discovery_xml(get_bloginfo('name') . ' – Kabel') . '</title>';
    echo '<link>' . msfixit_discovery_xml(home_url('/')) . '</link>';
    echo '<description>Freigegebene Kabelartikel für Österreich</description>';
    foreach (msfixit_discovery_all_products() as $product) {
        $productId = $product->get_id();
        $image = wp_get_attachment_image_url($product->get_image_id(), 'full');
        if (!$image) {
            continue;
        }
        $title = (string) get_post_meta($productId, '_msfixit_seo_title', true) ?: $product->get_name();
        $description = (string) get_post_meta($productId, '_msfixit_seo_description', true) ?: wp_strip_all_tags($product->get_description());
        $brand = msfixit_discovery_primary_value($productId, 'pa_marke') ?: (string) get_post_meta($productId, '_msfixit_manufacturer_name', true);
        $gtin = preg_replace('/\D+/', '', (string) get_post_meta($productId, '_msfixit_gtin', true)) ?: '';
        $mpn = (string) get_post_meta($productId, '_msfixit_manufacturer_sku', true);
        echo '<item>';
        echo '<g:id>' . msfixit_discovery_xml($product->get_sku()) . '</g:id>';
        echo '<g:title>' . msfixit_discovery_xml(wp_html_excerpt($title, 150, '')) . '</g:title>';
        echo '<g:description>' . msfixit_discovery_xml(wp_html_excerpt($description, 5000, '')) . '</g:description>';
        echo '<g:link>' . msfixit_discovery_xml($product->get_permalink()) . '</g:link>';
        echo '<g:image_link>' . msfixit_discovery_xml($image) . '</g:image_link>';
        echo '<g:availability>' . ($product->is_in_stock() ? 'in_stock' : 'out_of_stock') . '</g:availability>';
        echo '<g:price>' . msfixit_discovery_xml(number_format((float) $product->get_price(), 2, '.', '') . ' EUR') . '</g:price>';
        echo '<g:condition>new</g:condition>';
        if ($brand !== '') echo '<g:brand>' . msfixit_discovery_xml($brand) . '</g:brand>';
        if ($gtin !== '') echo '<g:gtin>' . msfixit_discovery_xml($gtin) . '</g:gtin>';
        if ($mpn !== '') echo '<g:mpn>' . msfixit_discovery_xml($mpn) . '</g:mpn>';
        if ($gtin === '' && $mpn === '') echo '<g:identifier_exists>no</g:identifier_exists>';
        $category = msfixit_discovery_primary_value($productId, 'pa_kabeltyp');
        if ($category !== '') echo '<g:product_type>' . msfixit_discovery_xml('Kabel & Zubehör > ' . $category) . '</g:product_type>';
        if (!empty($settings['GOOGLE_PRODUCT_CATEGORY'])) echo '<g:google_product_category>' . msfixit_discovery_xml((string) $settings['GOOGLE_PRODUCT_CATEGORY']) . '</g:google_product_category>';
        echo '<g:shipping><g:country>AT</g:country><g:service>' . msfixit_discovery_xml((string) $settings['GOOGLE_SHIPPING_SERVICE']) . '</g:service><g:price>' . msfixit_discovery_xml(number_format((float) $settings['GOOGLE_SHIPPING_COST_EUR'], 2, '.', '') . ' EUR') . '</g:price><g:min_transit_time>' . (int) $settings['GOOGLE_DELIVERY_MIN_DAYS'] . '</g:min_transit_time><g:max_transit_time>' . (int) $settings['GOOGLE_DELIVERY_MAX_DAYS'] . '</g:max_transit_time></g:shipping>';
        if ($product->has_weight()) echo '<g:shipping_weight>' . msfixit_discovery_xml($product->get_weight() . ' kg') . '</g:shipping_weight>';
        echo '</item>';
    }
    echo '</channel></rss>';
    exit;
});

add_filter('document_title_parts', static function (array $parts): array {
    if (is_page((string) msfixit_discovery_settings()['DISCOVERY_LANDING_SLUG'])) {
        $parts['title'] = 'Kabel & IT-Zubehör in Österreich';
    } elseif (is_product()) {
        $seoTitle = (string) get_post_meta(get_queried_object_id(), '_msfixit_seo_title', true);
        if ($seoTitle !== '') {
            $parts['title'] = $seoTitle;
        }
    }
    return $parts;
});
