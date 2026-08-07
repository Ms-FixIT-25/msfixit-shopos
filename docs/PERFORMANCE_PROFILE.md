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

The path unit reapplies the selected limits and refreshes already active services automatically. The same complete refresh can be started manually:

```bash
sudo systemctl start msfixit-performance-refresh.service
```

The CPU governor defaults to `auto`, which selects `schedutil` when the running kernel exposes it. Wi-Fi and Bluetooth remain available in the default `auto` policy. A permanently Ethernet-connected appliance can explicitly block an unused radio through the same configuration file; this remains opt-in so the setup cannot accidentally cut off its own network connection.

## Hardware report

Create a current report with:

```bash
sudo msfixit-hardware-report
```

The report is saved to `/var/log/msfixit-shopos/hardware-report.txt` and includes temperature, firmware throttle flags, CPU governor and clock, memory pressure, storage transport and scheduler, mount options, UASP topology, TRIM support, service resource use, failed units and recent power or I/O warnings. It intentionally excludes application credentials and secrets.

## Safety policy

The default profile does not overclock, change core voltage or pin the CPU at maximum frequency. It prefers the Linux `schedutil` governor when available, keeps PHP-FPM on demand, bounds caches and journals, limits dirty write bursts and enables periodic TRIM. Hardware-specific changes such as disabling Wi-Fi or Bluetooth remain opt-in because connectivity requirements differ between installations.
