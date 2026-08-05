#!/usr/bin/env bash
set -Eeuo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ux="$root/image/package/usr/share/msfixit-shopos/admin-console/lib/ux.php"
css="$root/image/package/usr/share/msfixit-shopos/admin-console/public/assets/shopos-ui.css"

php -l "$ux"
php -r "require '$ux'; \$s=uxWizardState(['welcome','network','finish'],'network'); if(\$s['progress']!==67||\$s['previous']!=='welcome'||\$s['next']!=='finish') exit(1);"
php -r "require '$ux'; try { uxWizardState(['ok','ok'],'ok'); exit(1); } catch (InvalidArgumentException \$e) {}"
php -r "require '$ux'; if(uxAllowedLocale('../evil')!=='de-AT'||uxAllowedTheme('script')!=='system') exit(1);"
php -r "require '$ux'; \$h=uxRenderFlash(uxFlash('error','Fehler','<script>alert(1)</script>')); if(str_contains(\$h,'<script>')||!str_contains(\$h,'&lt;script&gt;')) exit(1);"

grep -Fq 'prefers-reduced-motion:reduce' "$css"
grep -Fq ':focus-visible' "$css"
grep -Fq '.so-sr-only' "$css"
grep -Fq 'min-height:44px' "$css"
grep -Fq 'prefers-color-scheme:dark' "$css"
grep -Fq 'data-theme="dark"' "$css"
grep -Fq 'grid-template-columns:repeat(auto-fit' "$css"
! grep -Eq '(javascript:|expression\(|@import)' "$css"

printf 'PASS: UX framework validates wizard state, escapes notices and provides responsive accessible light/dark design tokens.\n'
