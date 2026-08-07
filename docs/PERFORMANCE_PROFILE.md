# ShopOS Raspberry Pi performance profiles

ShopOS uses an adaptive appliance profile instead of a fixed workstation-sized configuration. The default is `balanced`.

## Profiles

- `efficiency`: lowest background footprint for lightly used installations.
- `balanced`: recommended default. Scales MariaDB, Redis, PHP-FPM and Chromium limits to the detected RAM size.
- `performance`: additional headroom for imports, updates and busier periods.

Edit `/etc/msfixit-shopos/performance.env` and set:

```bash
SHOPOS_PERFORMANCE_PROFILE=balanced
```

The path unit reapplies the profile automatically. It can also be applied manually:

```bash
sudo systemctl start msfixit-performance-profile.service
```

## Hardware report

Create a current report with:

```bash
sudo msfixit-hardware-report
```

The report is saved to `/var/log/msfixit-shopos/hardware-report.txt` and includes temperature, firmware throttle flags, CPU governor, memory pressure, storage transport and scheduler, UASP topology, TRIM support, service resource use, failed units and recent power or I/O warnings. It intentionally excludes application credentials and secrets.

## Safety policy

The default profile does not overclock, change core voltage or pin the CPU at maximum frequency. It prefers the Linux `schedutil` governor when available, keeps PHP-FPM on demand, bounds caches and enables periodic TRIM. Hardware-specific changes such as disabling Wi-Fi or Bluetooth remain opt-in because connectivity requirements differ between installations.
