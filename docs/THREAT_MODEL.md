# ShopOS Threat Model

## Assets

Customer identities and service requests, shop and order data, administrator credentials, supplier credentials, signing and licensing trust, application packages, backups, release images and audit records.

## Trust boundaries

1. Public internet to Nginx and WordPress.
2. Browser to the local ShopOS administration console.
3. Web process to privileged fixed-operation helpers.
4. Store catalogue and package inbox to the signed application installer.
5. GitHub Actions and third-party build inputs to release artifacts.
6. ShopOS device to supplier, carrier, mail and Cloudflare integrations.
7. Local storage to removable and off-device backups.
8. Physical access to the Raspberry Pi and boot media.

## Primary threats

- credential theft, session fixation, CSRF, brute force and authorization bypass;
- malicious or modified application and operating-system packages;
- shell or path injection into privileged helpers;
- supply-chain compromise of Actions, dependencies or external downloads;
- rollback to vulnerable software;
- data disclosure through logs, support bundles, backups or public endpoints;
- database corruption or incomplete migration after power loss;
- denial of service through disk exhaustion, request floods or failing peripherals;
- physical replacement or modification of boot media;
- accidental publication, ordering or pricing without required approval.

## Existing controls

Strict application IDs and paths, Ed25519 package and license verification, fail-closed entitlements, CSRF protection, authenticated administration, fixed sudo helper operations, atomic application installation, checksum-verified image artifacts and explicit commercial approval boundaries.

## Required controls before production

- cryptographically attest production images and metadata;
- pin and review CI dependencies;
- implement transactional updates with rollback and anti-downgrade protection;
- harden systemd services and network exposure;
- add rate limits and stronger administrator authentication;
- automate vulnerability, secret and root-filesystem scans;
- prove encrypted backup restore and power-loss recovery;
- create a redacted diagnostic bundle;
- complete independent penetration and physical-device testing.

This document is a living security baseline. Each new privileged helper, network service, external integration or persistent data store must update the trust boundaries and abuse cases.
