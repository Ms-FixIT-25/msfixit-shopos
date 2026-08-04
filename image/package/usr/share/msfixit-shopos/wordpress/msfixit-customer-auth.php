<?php
/**
 * Plugin Name: Ms. FixIT ShopOS Customer Authentication
 * Description: Google sign-in, customer TOTP, recovery codes and account security controls for WooCommerce.
 * Version: 1.0.0
 */

declare(strict_types=1);

if (!defined('ABSPATH')) {
    exit;
}

const MSFIXIT_CUSTOMER_AUTH_VERSION = '1.0.0';
const MSFIXIT_CUSTOMER_AUTH_ENDPOINT = 'sicherheit';
const MSFIXIT_CUSTOMER_GOOGLE_SCOPE = 'openid email profile';
const MSFIXIT_CUSTOMER_GOOGLE_AUTH_ENDPOINT = 'https://accounts.google.com/o/oauth2/v2/auth';
const MSFIXIT_CUSTOMER_GOOGLE_TOKEN_ENDPOINT = 'https://oauth2.googleapis.com/token';
const MSFIXIT_CUSTOMER_GOOGLE_USERINFO_ENDPOINT = 'https://openidconnect.googleapis.com/v1/userinfo';

$msfixitCustomerAuthDirectory = '/usr/share/msfixit-shopos/wordpress/msfixit-customer-auth';
foreach (['google.php', 'flow.php', 'totp.php', 'account.php', 'admin.php'] as $msfixitCustomerAuthModule) {
    require_once $msfixitCustomerAuthDirectory . '/' . $msfixitCustomerAuthModule;
}
