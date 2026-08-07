ShopOS Raspberry Pi performance tuning
======================================

Configuration: /etc/msfixit-shopos/performance.env
Profiles: efficiency, balanced, performance
Apply and refresh now: sudo systemctl start msfixit-performance-refresh.service
Hardware report: sudo msfixit-hardware-report
Saved report: /var/log/msfixit-shopos/hardware-report.txt

The default balanced profile does not overclock or change core voltage.
