#!/usr/bin/env bash
set -euo pipefail
mkdir -p linux-settings-evidence
evidence="$PWD/linux-settings-evidence"
exec > >(tee "$evidence/verification.log") 2>&1
export WEBKIT_DISABLE_DMABUF_RENDERER=1
deb=$(find target/debug/bundle/deb -name '*.deb' -print -quit)
sudo dpkg -i "$deb"
config=$(mktemp -d)
openbox >"$evidence/openbox.log" 2>&1 &
wm_pid=$!
app_pid=''
trap 'if [[ -n "$app_pid" ]]; then kill "$app_pid" 2>/dev/null || true; fi; kill "$wm_pid" 2>/dev/null || true' EXIT
mkdir -p "$config/settings-test"
cat >"$config/settings.json" <<'EOF'
{"startupConfigs":[{"pack":"settings-test","widget":"test","preset":"default"}]}
EOF
cat >"$config/settings-test/zpack.json" <<'EOF'
{"name":"settings-test","version":"1.0.0","widgets":[{"name":"test","htmlPath":"index.html","zOrder":"normal","shownInTaskbar":false,"focused":false,"resizable":false,"transparent":false,"includeFiles":["*.html"],"presets":[{"name":"default","anchor":"top_left","offsetX":"0px","offsetY":"0px","width":"100px","height":"100px","monitorSelection":{"type":"primary"}}]}]}
EOF
printf '<html><body>Startup control widget</body></html>' >"$config/settings-test/index.html"
sleep 2
zebar open-settings --config-dir "$config" >"$evidence/zebar.log" 2>&1 &
app_pid=$!
settings=$(timeout 60 xdotool search --sync --onlyvisible --name '^Settings - Zebar$' | head -1)
sleep 3
kill -0 "$app_pid"
if xdotool search --onlyvisible --name '^Zebar - settings-test / test$'; then
  echo 'FAIL: cold settings launch started the configured widget'; exit 1
fi
import -window root "$evidence/cold-settings.png"
xdotool windowminimize "$settings"
sleep 1
xprop -id "$settings" WM_STATE | tee "$evidence/minimized.txt"
grep -q Iconic "$evidence/minimized.txt"
timeout 20 zebar open-settings --config-dir "$config"
sleep 2
test "$(xdotool search --onlyvisible --name '^Settings - Zebar$' | head -1)" = "$settings"
test "$(xdotool getactivewindow)" = "$settings"
kill -0 "$app_pid"
import -window root "$evidence/restored-settings.png"
desktop=/usr/share/applications/zebar-settings.desktop
cp "$desktop" "$evidence/zebar-settings.desktop"
desktop-file-validate "$desktop"
grep -Fx 'Exec=zebar open-settings' "$desktop"
xdotool windowminimize "$settings"
sleep 1
gio launch "$desktop"
sleep 2
test "$(xdotool getactivewindow)" = "$settings"
kill -0 "$app_pid"
timeout 20 zebar startup --config-dir "$config"
timeout 30 xdotool search --sync --onlyvisible --name '^Zebar - settings-test / test$'
echo "PASS: cold settings launch suppressed a valid startup widget; CLI and Debian launcher restored the same settings window ($settings), focused it, and reused process $app_pid."
