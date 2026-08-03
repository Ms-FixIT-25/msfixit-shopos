<?php
/**
 * Plugin Name: Ms. FixIT ShopOS Article Master Bridge
 * Description: Assigns immutable Ms. FixIT article numbers and maps WooCommerce products to the external ShopOS article master.
 * Version: 1.0.0
 */

declare(strict_types=1);

if (!defined('ABSPATH')) {
    exit;
}

const MSFIXIT_CATALOG_WORDPRESS_ENV = '/etc/msfixit-shopos/catalog-wordpress.env';

function msfixit_catalog_log(string $message): void
{
    error_log('[Ms. FixIT catalog] ' . $message);
}

function msfixit_catalog_env(): array
{
    static $settings = null;
    if (is_array($settings)) {
        return $settings;
    }

    $settings = [];
    if (!is_readable(MSFIXIT_CATALOG_WORDPRESS_ENV)) {
        return $settings;
    }

    foreach (file(MSFIXIT_CATALOG_WORDPRESS_ENV, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) ?: [] as $line) {
        $line = trim($line);
        if ($line === '' || str_starts_with($line, '#') || !str_contains($line, '=')) {
            continue;
        }
        [$key, $value] = explode('=', $line, 2);
        $settings[trim($key)] = trim($value);
    }

    return $settings;
}

function msfixit_catalog_database(): ?PDO
{
    static $pdo = false;
    if ($pdo instanceof PDO) {
        return $pdo;
    }
    if ($pdo === null) {
        return null;
    }

    $env = msfixit_catalog_env();
    foreach (['CATALOG_DB_HOST', 'CATALOG_DB_PORT', 'CATALOG_DB_NAME', 'CATALOG_DB_USER', 'CATALOG_DB_PASSWORD'] as $key) {
        if (empty($env[$key])) {
            $pdo = null;
            return null;
        }
    }

    try {
        $dsn = sprintf(
            'mysql:host=%s;port=%s;dbname=%s;charset=utf8mb4',
            $env['CATALOG_DB_HOST'],
            $env['CATALOG_DB_PORT'],
            $env['CATALOG_DB_NAME']
        );
        $pdo = new PDO($dsn, $env['CATALOG_DB_USER'], $env['CATALOG_DB_PASSWORD'], [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES => false,
        ]);
        return $pdo;
    } catch (Throwable $exception) {
        msfixit_catalog_log('Database connection failed: ' . $exception->getMessage());
        $pdo = null;
        return null;
    }
}

function msfixit_catalog_uuid(): string
{
    $bytes = random_bytes(16);
    $bytes[6] = chr((ord($bytes[6]) & 0x0f) | 0x40);
    $bytes[8] = chr((ord($bytes[8]) & 0x3f) | 0x80);
    $hex = bin2hex($bytes);

    return sprintf('%s-%s-%s-%s-%s',
        substr($hex, 0, 8),
        substr($hex, 8, 4),
        substr($hex, 12, 4),
        substr($hex, 16, 4),
        substr($hex, 20, 12)
    );
}

function msfixit_catalog_emit(PDO $pdo, string $productId, string $eventType, array $payload): void
{
    $statement = $pdo->prepare(
        'INSERT INTO catalog_sync_outbox
         (event_uuid, aggregate_type, aggregate_id, event_type, payload_json)
         VALUES (?, ?, ?, ?, ?)'
    );
    $statement->execute([
        msfixit_catalog_uuid(),
        'product',
        $productId,
        $eventType,
        wp_json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES),
    ]);
}

function msfixit_catalog_find_by_mapping(PDO $pdo, string $namespace, string $externalId): ?array
{
    $statement = $pdo->prepare(
        'SELECT p.*
         FROM catalog_identifiers i
         INNER JOIN catalog_products p ON p.id = i.product_id
         WHERE i.namespace = ? AND i.external_id = ? AND i.valid_until IS NULL'
    );
    $statement->execute([$namespace, $externalId]);
    $product = $statement->fetch();
    return $product ?: null;
}

function msfixit_catalog_map(PDO $pdo, string $productId, string $namespace, string $externalId, bool $primary = false): void
{
    if ($primary) {
        $statement = $pdo->prepare(
            'UPDATE catalog_identifiers SET is_primary = 0 WHERE product_id = ? AND namespace = ?'
        );
        $statement->execute([$productId, $namespace]);
    }

    $statement = $pdo->prepare(
        'INSERT INTO catalog_identifiers
         (product_id, namespace, external_id, is_primary)
         VALUES (?, ?, ?, ?)
         ON DUPLICATE KEY UPDATE
            product_id = VALUES(product_id),
            is_primary = VALUES(is_primary),
            valid_until = NULL'
    );
    $statement->execute([$productId, $namespace, $externalId, $primary ? 1 : 0]);
}

function msfixit_catalog_allocate(PDO $pdo, WC_Product $wcProduct, ?array $parent): array
{
    $existingSku = trim((string) $wcProduct->get_sku('edit'));
    $requestedArticle = preg_match('/^MF-[0-9]{8}$/', strtoupper($existingSku))
        ? strtoupper($existingSku)
        : null;

    if ($requestedArticle !== null) {
        $statement = $pdo->prepare('SELECT * FROM catalog_products WHERE article_number = ?');
        $statement->execute([$requestedArticle]);
        $existing = $statement->fetch();
        if ($existing) {
            return $existing;
        }
    }

    $sequence = $pdo->query(
        "SELECT next_value FROM catalog_sequences WHERE sequence_name = 'article_number' FOR UPDATE"
    )->fetchColumn();
    if ($sequence === false) {
        throw new RuntimeException('Article-number sequence is missing.');
    }

    if ($requestedArticle !== null) {
        $number = (int) substr($requestedArticle, 3);
        $article = $requestedArticle;
        if ((int) $sequence <= $number) {
            $statement = $pdo->prepare(
                "UPDATE catalog_sequences SET next_value = ? WHERE sequence_name = 'article_number'"
            );
            $statement->execute([$number + 1]);
        }
    } else {
        $number = (int) $sequence;
        if ($number < 1 || $number > 99999999) {
            throw new RuntimeException('Article-number range is exhausted.');
        }
        $article = sprintf('MF-%08d', $number);
        $pdo->exec(
            "UPDATE catalog_sequences SET next_value = next_value + 1 WHERE sequence_name = 'article_number'"
        );
    }

    $id = msfixit_catalog_uuid();
    $type = $wcProduct->is_type('variation') ? 'variation' : $wcProduct->get_type();
    $name = trim(wp_strip_all_tags($wcProduct->get_name('edit')));
    $name = $name !== '' ? $name : 'Unbenannter Artikel';

    $statement = $pdo->prepare(
        'INSERT INTO catalog_products
         (id, article_number, parent_id, product_type, product_name, status, source_of_truth)
         VALUES (?, ?, ?, ?, ?, ?, ?)'
    );
    $statement->execute([
        $id,
        $article,
        $parent['id'] ?? null,
        $type,
        $name,
        $wcProduct->get_status('edit'),
        'shopos',
    ]);

    msfixit_catalog_map($pdo, $id, 'shopos:article', $article, true);
    msfixit_catalog_emit($pdo, $id, 'product.created', [
        'article_number' => $article,
        'woocommerce_product_id' => $wcProduct->get_id(),
        'product_name' => $name,
        'product_type' => $type,
    ]);

    return [
        'id' => $id,
        'article_number' => $article,
        'parent_id' => $parent['id'] ?? null,
    ];
}

function msfixit_catalog_ensure_product(WC_Product $wcProduct): ?array
{
    $pdo = msfixit_catalog_database();
    if (!$pdo) {
        return null;
    }

    $woocommerceId = (string) $wcProduct->get_id();
    $mapped = msfixit_catalog_find_by_mapping($pdo, 'woocommerce:product_id', $woocommerceId);

    $parent = null;
    if ($wcProduct->is_type('variation') && $wcProduct->get_parent_id() > 0) {
        $parentProduct = wc_get_product($wcProduct->get_parent_id());
        if ($parentProduct instanceof WC_Product) {
            $parent = msfixit_catalog_ensure_product($parentProduct);
        }
    }

    $pdo->beginTransaction();
    try {
        $product = $mapped ?: msfixit_catalog_allocate($pdo, $wcProduct, $parent);
        $article = $product['article_number'];
        $oldSku = trim((string) $wcProduct->get_sku('edit'));

        if ($oldSku !== '' && strtoupper($oldSku) !== $article) {
            msfixit_catalog_map($pdo, $product['id'], 'woocommerce:legacy_sku', $oldSku, false);
        }

        msfixit_catalog_map($pdo, $product['id'], 'woocommerce:product_id', $woocommerceId, true);

        $statement = $pdo->prepare(
            'UPDATE catalog_products
             SET parent_id = ?, product_type = ?, product_name = ?, status = ?,
                 version_number = version_number + 1
             WHERE id = ?'
        );
        $statement->execute([
            $parent['id'] ?? null,
            $wcProduct->is_type('variation') ? 'variation' : $wcProduct->get_type(),
            trim(wp_strip_all_tags($wcProduct->get_name('edit'))) ?: 'Unbenannter Artikel',
            $wcProduct->get_status('edit'),
            $product['id'],
        ]);

        $statement = $pdo->prepare(
            'INSERT INTO catalog_channel_listings
             (product_id, channel_code, external_id, channel_sku, listing_status, last_sync_at)
             VALUES (?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
             ON DUPLICATE KEY UPDATE
                product_id = VALUES(product_id),
                channel_sku = VALUES(channel_sku),
                listing_status = VALUES(listing_status),
                last_sync_at = CURRENT_TIMESTAMP'
        );
        $statement->execute([
            $product['id'],
            'woocommerce',
            $woocommerceId,
            $article,
            $wcProduct->get_status('edit'),
        ]);

        msfixit_catalog_emit($pdo, $product['id'], 'product.changed', [
            'article_number' => $article,
            'woocommerce_product_id' => $wcProduct->get_id(),
            'status' => $wcProduct->get_status('edit'),
        ]);

        $pdo->commit();
        $product['article_number'] = $article;
        return $product;
    } catch (Throwable $exception) {
        if ($pdo->inTransaction()) {
            $pdo->rollBack();
        }
        msfixit_catalog_log('Product synchronization failed: ' . $exception->getMessage());
        return null;
    }
}

add_action('woocommerce_after_product_object_save', static function (WC_Product $product): void {
    static $syncing = [];
    $productId = $product->get_id();
    if ($productId < 1 || isset($syncing[$productId])) {
        return;
    }

    $syncing[$productId] = true;
    try {
        $catalogProduct = msfixit_catalog_ensure_product($product);
        if ($catalogProduct && $product->get_sku('edit') !== $catalogProduct['article_number']) {
            $product->set_sku($catalogProduct['article_number']);
            $product->save();
        }
    } catch (Throwable $exception) {
        msfixit_catalog_log('WooCommerce SKU assignment failed: ' . $exception->getMessage());
    } finally {
        unset($syncing[$productId]);
    }
}, 20);

add_action('wp_trash_post', static function (int $postId): void {
    if (get_post_type($postId) !== 'product' && get_post_type($postId) !== 'product_variation') {
        return;
    }

    $pdo = msfixit_catalog_database();
    if (!$pdo) {
        return;
    }

    try {
        $product = msfixit_catalog_find_by_mapping($pdo, 'woocommerce:product_id', (string) $postId);
        if (!$product) {
            return;
        }
        $statement = $pdo->prepare(
            "UPDATE catalog_products SET status = 'archived', version_number = version_number + 1 WHERE id = ?"
        );
        $statement->execute([$product['id']]);
        msfixit_catalog_emit($pdo, $product['id'], 'product.archived', [
            'article_number' => $product['article_number'],
            'woocommerce_product_id' => $postId,
        ]);
    } catch (Throwable $exception) {
        msfixit_catalog_log('Archive synchronization failed: ' . $exception->getMessage());
    }
});

add_action('woocommerce_product_options_sku', static function (): void {
    echo '<p class="form-field"><strong>Ms. FixIT Waren-Nr.</strong><br>';
    echo '<span class="description">Die WooCommerce-SKU wird automatisch als unveränderliche MF-Waren­nummer vergeben. Lieferanten-, EAN-, POS- und ERP-Nummern werden im ShopOS-Artikelstamm zugeordnet.</span></p>';
});

add_action('rest_api_init', static function (): void {
    register_rest_field(['product', 'product_variation'], 'msfixit_article_number', [
        'get_callback' => static function (array $object): string {
            return (string) get_post_meta((int) $object['id'], '_sku', true);
        },
        'schema' => [
            'description' => 'Immutable Ms. FixIT article number',
            'type' => 'string',
            'readonly' => true,
        ],
    ]);
});
