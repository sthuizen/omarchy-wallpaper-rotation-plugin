#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR=$(cd "$(dirname "$0")/.." && pwd)
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT

export TEST_USER_HOME="$TEST_ROOT/home"
export WALLPAPER_ROTATION_HOME="$TEST_USER_HOME"
export XDG_CONFIG_HOME="$TEST_USER_HOME/.config"
export XDG_STATE_HOME="$TEST_USER_HOME/.local/state"
export WALLPAPER_ROTATION_OMARCHY="$TEST_ROOT/bin/omarchy"
export WALLPAPER_ROTATION_SYSTEMCTL="$TEST_ROOT/bin/systemctl"

mkdir -p "$TEST_ROOT/bin" "$TEST_USER_HOME/.local/state/omarchy/current/theme/backgrounds"
mkdir -p "$TEST_USER_HOME/.config/omarchy/backgrounds/test-theme"
printf '%s\n' 'test-theme' >"$TEST_USER_HOME/.local/state/omarchy/current/theme.name"
touch "$TEST_USER_HOME/.local/state/omarchy/current/theme/backgrounds/01-one.png"
touch "$TEST_USER_HOME/.local/state/omarchy/current/theme/backgrounds/02-two.png"
touch "$TEST_USER_HOME/.config/omarchy/backgrounds/test-theme/03-three.png"
ln -s "$TEST_USER_HOME/.local/state/omarchy/current/theme/backgrounds/01-one.png" \
  "$TEST_USER_HOME/.local/state/omarchy/current/background"

cat >"$WALLPAPER_ROTATION_OMARCHY" <<'MOCK'
#!/usr/bin/env bash
printf '%s\0' "$@" >>"$TEST_USER_HOME/omarchy.calls"
if [[ $1 == theme && $2 == bg && $3 == set ]]; then
  ln -nsf "$4" "$TEST_USER_HOME/.local/state/omarchy/current/background"
fi
MOCK
chmod +x "$WALLPAPER_ROTATION_OMARCHY"

cat >"$WALLPAPER_ROTATION_SYSTEMCTL" <<'MOCK'
#!/usr/bin/env bash
printf '%s\0' "$@" >>"$TEST_USER_HOME/systemctl.calls"
case " $* " in
  *" is-active "*) exit 0 ;;
  *" list-timers "*) printf '[{"next":0}]\n' ;;
esac
MOCK
chmod +x "$WALLPAPER_ROTATION_SYSTEMCTL"

control="$PROJECT_DIR/WallpaperRotation.sh"

"$control" init
jq -e '.enabled == true and .intervalMinutes == 60 and .mode == "sequential"' \
  "$TEST_USER_HOME/.config/omarchy/wallpaper-rotation/config.json" >/dev/null
grep -F 'OnActiveSec=60m' "$TEST_USER_HOME/.config/systemd/user/omarchy-wallpaper-rotation.timer" >/dev/null
grep -F 'ExecStopPost=/usr/bin/systemctl --user --no-block try-restart omarchy-wallpaper-rotation.timer' "$TEST_USER_HOME/.config/systemd/user/omarchy-wallpaper-rotation.service" >/dev/null
! grep -Fq 'OnUnitActiveSec=' "$TEST_USER_HOME/.config/systemd/user/omarchy-wallpaper-rotation.timer"
grep -F 'StartLimitIntervalSec=0' "$TEST_USER_HOME/.config/systemd/user/omarchy-wallpaper-rotation.timer" >/dev/null
unit_output=$(systemd-analyze --user verify \
  "$TEST_USER_HOME/.config/systemd/user/omarchy-wallpaper-rotation.service" \
  "$TEST_USER_HOME/.config/systemd/user/omarchy-wallpaper-rotation.timer" 2>&1)
[[ -z $unit_output ]] || { printf '%s\n' "$unit_output" >&2; exit 1; }

# Reloading the shell must not restart an unchanged timer or postpone its due time.
: >"$TEST_USER_HOME/systemctl.calls"
"$control" init
if grep -azq '^restart$' "$TEST_USER_HOME/systemctl.calls"; then
  echo 'unchanged init restarted the timer' >&2
  exit 1
fi
if grep -azq '^enable$' "$TEST_USER_HOME/systemctl.calls"; then
  echo 'unchanged init redundantly enabled the timer (and reloaded the manager)' >&2
  exit 1
fi

catalog=$("$control" catalog)
[[ $(jq 'length' <<<"$catalog") == 3 ]]

: >"$TEST_USER_HOME/omarchy.calls"
"$control" rotate
mapfile -d '' -t call <"$TEST_USER_HOME/omarchy.calls"
[[ ${call[*]} == 'theme bg next' ]]

"$control" configure intervalMinutes 120
grep -F 'OnActiveSec=120m' "$TEST_USER_HOME/.config/systemd/user/omarchy-wallpaper-rotation.timer" >/dev/null

"$control" configure mode shuffle
: >"$TEST_USER_HOME/omarchy.calls"
"$control" rotate
mapfile -d '' -t call <"$TEST_USER_HOME/omarchy.calls"
[[ ${call[0]} == theme && ${call[1]} == bg && ${call[2]} == set ]]
[[ ${call[3]} != "$TEST_USER_HOME/.local/state/omarchy/current/theme/backgrounds/01-one.png" ]]
jq -e '.theme == "test-theme" and (.remaining | type) == "array"' \
  "$TEST_USER_HOME/.local/state/omarchy/wallpaper-rotation/shuffle.json" >/dev/null

"$control" configure enabled false
: >"$TEST_USER_HOME/omarchy.calls"
"$control" rotate
[[ ! -s $TEST_USER_HOME/omarchy.calls ]]
"$control" next
[[ -s $TEST_USER_HOME/omarchy.calls ]]

if "$control" configure intervalMinutes 1 >/dev/null 2>&1; then
  echo 'invalid interval was accepted' >&2
  exit 1
fi
[[ -z $(find "$TEST_USER_HOME/.config/omarchy/wallpaper-rotation" -name '*.tmp.*' -print -quit) ]]

# Decimal input must not be interpreted as octal or passed to jq with a leading zero.
"$control" configure intervalMinutes 008
jq -e '.intervalMinutes == 8' "$TEST_USER_HOME/.config/omarchy/wallpaper-rotation/config.json" >/dev/null

# Valid JSON of the wrong type and malformed shuffle state recover safely.
printf '[]\n' >"$TEST_USER_HOME/.config/omarchy/wallpaper-rotation/config.json"
"$control" status | jq -e '.intervalMinutes == 60 and .enabled == true' >/dev/null
"$control" configure mode shuffle
printf '"broken queue"\n' >"$TEST_USER_HOME/.local/state/omarchy/wallpaper-rotation/shuffle.json"
"$control" rotate

# An external picker may select the next image before our timer fires.
target=$(jq -r '.remaining[0]' "$TEST_USER_HOME/.local/state/omarchy/wallpaper-rotation/shuffle.json")
ln -nsf "$target" "$TEST_USER_HOME/.local/state/omarchy/current/background"
"$control" rotate
[[ $(readlink "$TEST_USER_HOME/.local/state/omarchy/current/background") != "$target" ]]

# A scheduled tick obeys Omarchy enablement; manual next remains available.
mkdir -p "$TEST_USER_HOME/.config/omarchy"
shell_config="$TEST_USER_HOME/.config/omarchy/shell.json"
printf '{"plugins":[]}\n' >"$shell_config"
: >"$TEST_USER_HOME/omarchy.calls"
"$control" scheduled
[[ ! -s $TEST_USER_HOME/omarchy.calls ]]
printf '{"plugins":[{"id":"thenailedone.wallpaper-rotation"}]}\n' >"$shell_config"
"$control" scheduled
[[ -s $TEST_USER_HOME/omarchy.calls ]]
printf '{"plugins":[{"id":"thenailedone.wallpaper-rotation"}],"disabledPlugins":["thenailedone.wallpaper-rotation"]}\n' >"$shell_config"
: >"$TEST_USER_HOME/omarchy.calls"
"$control" scheduled
[[ ! -s $TEST_USER_HOME/omarchy.calls ]]
printf '{"bar":{"layout":{"right":[{"id":"thenailedone.wallpaper-rotation"}]}}}\n' >"$shell_config"
"$control" scheduled
[[ -s $TEST_USER_HOME/omarchy.calls ]]
rm "$shell_config"
: >"$TEST_USER_HOME/omarchy.calls"
"$control" scheduled
[[ ! -s $TEST_USER_HOME/omarchy.calls ]]

# Unit paths must survive spaces and literal systemd '%' specifiers.
special_dir="$TEST_ROOT/plugin with % and \$ spaces"
mkdir -p "$special_dir"
cp "$control" "$special_dir/WallpaperRotation.sh"
"$special_dir/WallpaperRotation.sh" init
grep -F 'plugin with %% and $ spaces/WallpaperRotation.sh' "$TEST_USER_HOME/.config/systemd/user/omarchy-wallpaper-rotation.service" >/dev/null
unit_output=$(systemd-analyze --user verify \
  "$TEST_USER_HOME/.config/systemd/user/omarchy-wallpaper-rotation.service" \
  "$TEST_USER_HOME/.config/systemd/user/omarchy-wallpaper-rotation.timer" 2>&1)
[[ -z $unit_output ]] || { printf '%s\n' "$unit_output" >&2; exit 1; }

# Cleanup removes the scheduler but preserves preferences for a reinstall.
"$control" uninstall
[[ ! -e $TEST_USER_HOME/.config/systemd/user/omarchy-wallpaper-rotation.timer ]]
[[ ! -e $TEST_USER_HOME/.config/systemd/user/omarchy-wallpaper-rotation.service ]]
[[ -s $TEST_USER_HOME/.config/omarchy/wallpaper-rotation/config.json ]]

printf 'All control tests passed.\n'
