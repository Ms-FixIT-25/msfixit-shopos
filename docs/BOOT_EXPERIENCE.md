# ShopOS boot experience and offline first start

## Goal

ShopOS should behave like a dedicated appliance operating system rather than a generic Linux installation with a web shop added later. The downloadable image therefore contains the operating system, Ms. FixIT branding, the web stack and the pinned shop application payload.

The intended normal workflow is:

1. flash the compressed image to supported storage;
2. optionally place `shopos.env` on the boot partition;
3. boot the Raspberry Pi;
4. allow the guided first-start provisioning to complete;
5. open the displayed ShopOS address.

## Branded startup

Plymouth displays the Ms. FixIT ShopOS artwork while the kernel and system services start. The kernel command line uses quiet-display parameters but retains the existing root-device and Raspberry Pi hardware parameters.

The package creates the PNG used by Plymouth from the checksum-verified embedded Ms. FixIT artwork. `plymouth-set-default-theme -R` selects the theme and rebuilds the initial RAM filesystem during image creation.

Normal boots show only the short graphical splash. Diagnostic boot messages remain available by removing `quiet splash` from the boot command line.

## Guided first start

Only an uninitialized installation starts `msfixit-boot-console.service` on `tty1`. It displays:

- Ms. FixIT ShopOS branding;
- the current provisioning stage;
- a progress bar;
- the hostname and detected LAN address;
- a clear success or failure result.

The console does not display generated passwords. After successful provisioning it points to `SHOPOS-CREDENTIALS.txt` on the boot partition. The file should be copied into a password manager and then deleted.

If provisioning fails, the console releases the normal login after showing the relevant log and systemd diagnostic commands. It never reports the system as ready until both first-boot provisioning and the branded shop setup have succeeded.

## Offline application payload

The image build downloads, verifies and embeds these pinned official packages:

- WordPress 7.0.2, German locale;
- WooCommerce 10.9.4;
- Redis Object Cache 2.8.0;
- Storefront 4.6.2.

The German WordPress archive is checked against its published SHA-1 digest. Every archive is checked as a valid ZIP, its internal version metadata is verified, and a SHA-256 manifest is stored in the package.

The ShopOS `wp` wrapper transparently maps the default WordPress, WooCommerce, Redis and Storefront installation commands to the local archives. A deliberately different WordPress version or locale may use WP-CLI's normal network path instead.

Cloudflared and WP-CLI remain separately pinned and checksum verified during the reproducible image build.

## Ready markers

ShopOS uses separate state markers:

- `/data/.shopos-initialized`: base web and database system completed;
- `/data/.shopos-branded`: shop structure and branding completed;
- `/data/.shopos-ready`: the complete first-start flow completed.

The boot console exits only after the ready marker exists. Reboots then proceed directly to the normal login and running shop.

## Login identity

The console login shows a compact ShopOS summary with version, build time, shop address and administration commands. The underlying Debian/Raspberry Pi identity is not overwritten, because package managers and support tools rely on accurate base-system metadata.

Useful commands:

```bash
shopos-version
sudo msfixit-status
sudo msfixit-health
journalctl -u msfixit-firstboot.service
journalctl -u msfixit-brand-shop.service
```

## Limits before public production

A flash-ready image does not automatically make the shop legally or commercially ready for public operation. Legal texts, payment and mail delivery, shipping prices, business details, partner evidence, tax decisions, external backups and the target hardware still require deliberate configuration and testing.
