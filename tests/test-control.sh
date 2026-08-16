#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR=$(cd "$(dirname "$0")/.." && pwd)
TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

export HOME="$TEST_HOME/home"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_STATE_HOME="$HOME/.local/state"
export WALLPAPER_ROTATION_OMARCHY="$TEST_HOME/bin/omarchy"
export WALLPAPER_ROTATION_SYSTEMCTL="$TEST_HOME/bin/systemctl"

mkdir -p "$TEST_HOME/bin" "$HOME/.local/state/omarchy/current/theme/backgrounds"
mkdir -p "$HOME/.config/omarchy/backgrounds/test-theme"
printf '%s\n' 'test-theme' >"$HOME/.local/state/omarchy/current/theme.name"
touch "$HOME/.local/state/omarchy/current/theme/backgrounds/01-one.png"
touch "$HOME/.local/state/omarchy/current/theme/backgrounds/02-two.png"
touch "$HOME/.config/omarchy/backgrounds/test-theme/03-three.png"
ln -s "$HOME/.local/state/omarchy/current/theme/backgrounds/01-one.png" \
  "$HOME/.local/state/omarchy/current/background"

cat >"$WALLPAPER_ROTATION_OMARCHY" <<'MOCK'
#!/usr/bin/env bash
printf '%s\0' "$@" >>"$HOME/omarchy.calls"
if [[ $1 == theme && $2 == bg && $3 == set ]]; then
  ln -nsf "$4" "$HOME/.local/state/omarchy/current/background"
fi
MOCK
chmod +x "$WALLPAPER_ROTATION_OMARCHY"

cat >"$WALLPAPER_ROTATION_SYSTEMCTL" <<'MOCK'
#!/usr/bin/env bash
printf '%s\0' "$@" >>"$HOME/systemctl.calls"
case " $* " in
  *" is-active "*) exit 0 ;;
  *" list-timers "*) printf '[{"next":0}]\n' ;;
esac
MOCK
chmod +x "$WALLPAPER_ROTATION_SYSTEMCTL"

control="$PROJECT_DIR/WallpaperRotation.sh"

"$control" init
jq -e '.enabled == true and .intervalMinutes == 60 and .mode == "sequential"' \
  "$HOME/.config/omarchy/wallpaper-rotation/config.json" >/dev/null
grep -F 'OnUnitActiveSec=60m' "$HOME/.config/systemd/user/omarchy-wallpaper-rotation.timer" >/dev/null
grep -F 'StartLimitIntervalSec=0' "$HOME/.config/systemd/user/omarchy-wallpaper-rotation.timer" >/dev/null
systemd-analyze --user verify \
  "$HOME/.config/systemd/user/omarchy-wallpaper-rotation.service" \
  "$HOME/.config/systemd/user/omarchy-wallpaper-rotation.timer"

catalog=$("$control" catalog)
[[ $(jq 'length' <<<"$catalog") == 3 ]]

: >"$HOME/omarchy.calls"
"$control" rotate
mapfile -d '' -t call <"$HOME/omarchy.calls"
[[ ${call[*]} == 'theme bg next' ]]

"$control" configure intervalMinutes 120
grep -F 'OnUnitActiveSec=120m' "$HOME/.config/systemd/user/omarchy-wallpaper-rotation.timer" >/dev/null

"$control" configure mode shuffle
: >"$HOME/omarchy.calls"
"$control" rotate
mapfile -d '' -t call <"$HOME/omarchy.calls"
[[ ${call[0]} == theme && ${call[1]} == bg && ${call[2]} == set ]]
[[ ${call[3]} != "$HOME/.local/state/omarchy/current/theme/backgrounds/01-one.png" ]]
jq -e '.theme == "test-theme" and (.remaining | type) == "array"' \
  "$HOME/.local/state/omarchy/wallpaper-rotation/shuffle.json" >/dev/null

"$control" configure enabled false
: >"$HOME/omarchy.calls"
"$control" rotate
[[ ! -s $HOME/omarchy.calls ]]
"$control" next
[[ -s $HOME/omarchy.calls ]]

if "$control" configure intervalMinutes 1 >/dev/null 2>&1; then
  echo 'invalid interval was accepted' >&2
  exit 1
fi

printf 'All control tests passed.\n'
