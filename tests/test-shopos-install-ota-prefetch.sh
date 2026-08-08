#!/usr/bin/env bash
set -Eeuo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$root/image/package/usr/local/sbin/msfixit-install-update-prefetch"
service="$root/image/package/etc/systemd/system/msfixit-install-update-prefetch.service"
firstboot="$root/image/package/etc/systemd/system/msfixit-firstboot.service"

bash -n "$script"
grep -Fq 'Before=msfixit-firstboot.service' "$service"
grep -Fq 'Wants=msfixit-install-update-prefetch.service' "$firstboot"
grep -Fq 'After=local-fs.target msfixit-install-update-prefetch.service' "$firstboot"
grep -Fq "--proto '=https'" "$script"
grep -Fq "verify \"\$manifest\" --image \"\$image\"" "$script"
grep -Fq 'partial prefetch discarded and installation continues' "$script"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"

cat > "$work/bin/offline-agent" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$work/bin/offline-agent"
SHOPOS_UPDATE_AGENT="$work/bin/offline-agent" \
SHOPOS_UPDATE_PREFETCH_DIR="$work/offline-prefetch" \
bash "$script" > "$work/offline.log"
grep -Fq 'continuing with embedded image' "$work/offline.log"
test ! -e "$work/offline-prefetch.new"

printf 'verified-rootfs-payload\n' > "$work/rootfs"
image_size="$(stat -c '%s' "$work/rootfs")"
image_sha="$(sha256sum "$work/rootfs" | awk '{print $1}')"

cat > "$work/bin/online-agent" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' '{"available":true,"version":"9.9.9","sequence":99,"installed_sequence":1}'
EOF
chmod +x "$work/bin/online-agent"

cat > "$work/bin/fake-verifier" <<EOF
#!/usr/bin/env bash
set -eu
if [ "\${1:-}" != verify ]; then exit 2; fi
printf '%s\n' '{"schema":1,"version":"9.9.9","sequence":99,"image_url":"https://github.com/Ms-FixIT-25/msfixit-shopos/releases/download/v9.9.9/shopos-rootfs.ext4.xz","image_sha256":"$image_sha","image_size":$image_size,"target":"rpi4-usb","minimum_sequence":1,"issued_at":"2026-08-08T00:00:00Z","expires_at":"2099-01-01T00:00:00Z"}'
EOF
chmod +x "$work/bin/fake-verifier"

cat > "$work/bin/fake-curl" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
out=''
url=''
while [ \$# -gt 0 ]; do
  case "\$1" in
    --output) out="\$2"; shift 2 ;;
    http*) url="\$1"; shift ;;
    *) shift ;;
  esac
done
case "\$url" in
  https://api.github.com/*)
    cat > "\$out" <<JSON
{"draft":false,"prerelease":false,"assets":[
{"name":"shopos-update-manifest.json","browser_download_url":"https://github.com/Ms-FixIT-25/msfixit-shopos/releases/download/v9.9.9/shopos-update-manifest.json"},
{"name":"shopos-rootfs.ext4.xz","browser_download_url":"https://github.com/Ms-FixIT-25/msfixit-shopos/releases/download/v9.9.9/shopos-rootfs.ext4.xz"}
]}
JSON
    ;;
  *shopos-update-manifest.json) printf '%s\n' '{"fixture":"signed-by-fake-verifier"}' > "\$out" ;;
  *shopos-rootfs.ext4.xz) cp "$work/rootfs" "\$out" ;;
  *) exit 22 ;;
esac
EOF
chmod +x "$work/bin/fake-curl"

SHOPOS_UPDATE_AGENT="$work/bin/online-agent" \
SHOPOS_UPDATE_VERIFIER="$work/bin/fake-verifier" \
SHOPOS_UPDATE_CURL="$work/bin/fake-curl" \
SHOPOS_UPDATE_PREFETCH_DIR="$work/online-prefetch" \
bash "$script" > "$work/online.log"
grep -Fq 'prefetched successfully' "$work/online.log"
test -s "$work/online-prefetch/shopos-rootfs.ext4.xz"
test "$(sha256sum "$work/online-prefetch/shopos-rootfs.ext4.xz" | awk '{print $1}')" = "$image_sha"
test -s "$work/online-prefetch/payload.json"
test ! -e "$work/online-prefetch.new"

printf 'PASS: install-time OTA prefetch is verified online and non-blocking offline.\n'
