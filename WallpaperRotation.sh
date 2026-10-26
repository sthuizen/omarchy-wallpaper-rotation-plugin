#!/usr/bin/env bash

set -euo pipefail

PLUGIN_ID="thenailedone.wallpaper-rotation"
OMARCHY_HOME="${WALLPAPER_ROTATION_HOME:-$HOME}"
CONFIG_DIR="${XDG_CONFIG_HOME:-$OMARCHY_HOME/.config}/omarchy/wallpaper-rotation"
SHELL_CONFIG="${XDG_CONFIG_HOME:-$OMARCHY_HOME/.config}/omarchy/shell.json"
CONFIG_FILE="$CONFIG_DIR/config.json"
STATE_DIR="${XDG_STATE_HOME:-$OMARCHY_HOME/.local/state}/omarchy/wallpaper-rotation"
SHUFFLE_FILE="$STATE_DIR/shuffle.json"
LOCK_FILE="$STATE_DIR/rotation.lock"
SYSTEMD_DIR="${XDG_CONFIG_HOME:-$OMARCHY_HOME/.config}/systemd/user"
SERVICE_NAME="omarchy-wallpaper-rotation.service"
TIMER_NAME="omarchy-wallpaper-rotation.timer"
SERVICE_FILE="$SYSTEMD_DIR/$SERVICE_NAME"
TIMER_FILE="$SYSTEMD_DIR/$TIMER_NAME"
SCRIPT_PATH=$(realpath "$0")
OMARCHY_BIN="${WALLPAPER_ROTATION_OMARCHY:-omarchy}"
SYSTEMCTL_BIN="${WALLPAPER_ROTATION_SYSTEMCTL:-systemctl}"
UNITS_CHANGED=0

die() {
  printf 'wallpaper-rotation: %s\n' "$*" >&2
  exit 1
}

atomic_write() {
  local target="$1" mode="${2:-0644}" temporary
  mkdir -p "$(dirname "$target")"
  temporary=$(mktemp "${target}.tmp.XXXXXX")
  cat >"$temporary"
  chmod "$mode" "$temporary"
  mv -f "$temporary" "$target"
}

default_config() {
  printf '%s\n' '{"enabled":true,"intervalMinutes":60,"mode":"sequential"}'
}

normalize_config() {
  jq -c '
    (if type == "object" then . else {} end) as $source |
    {
      enabled: (if ($source.enabled | type) == "boolean" then $source.enabled else true end),
      intervalMinutes: (if (($source.intervalMinutes | type) == "number") and ($source.intervalMinutes | floor == $source.intervalMinutes) and ($source.intervalMinutes >= 5) and ($source.intervalMinutes <= 1440) then $source.intervalMinutes else 60 end),
      mode: (if $source.mode == "shuffle" then "shuffle" else "sequential" end)
    }
  '
}

ensure_config() {
  local current normalized
  mkdir -p "$CONFIG_DIR" "$STATE_DIR" "$SYSTEMD_DIR"
  if [[ ! -f $CONFIG_FILE ]]; then
    default_config | jq . | atomic_write "$CONFIG_FILE"
  elif ! jq -e . "$CONFIG_FILE" >/dev/null 2>&1; then
    cp -a "$CONFIG_FILE" "$CONFIG_FILE.invalid.$(date -u +%Y%m%d%H%M%S)"
    default_config | jq . | atomic_write "$CONFIG_FILE"
  else
    current=$(jq -c . "$CONFIG_FILE")
    normalized=$(normalize_config <<<"$current")
    if [[ $current != "$normalized" ]]; then
      jq . <<<"$normalized" | atomic_write "$CONFIG_FILE"
    fi
  fi
}

config_value() {
  jq -r "$1" "$CONFIG_FILE"
}

systemd_quote() {
  # Both command arguments and unit conditions expand systemd specifiers.
  local value="$1"
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  value=${value//%/%%}
  printf '"%s"' "$value"
}

write_units() {
  local interval content script_argument script_condition
  interval=$(config_value '.intervalMinutes')
  script_argument=$(systemd_quote "$SCRIPT_PATH")
  # Conditions take a literal path, not the ExecStart command-line syntax.
  script_condition=${SCRIPT_PATH//%/%%}
  UNITS_CHANGED=0

  content=$(cat <<EOF
[Unit]
Description=Rotate the active Omarchy theme wallpaper
After=graphical-session.target
ConditionPathExists=$script_condition

[Service]
Type=oneshot
ExecStart=$script_argument scheduled
# Rearm from completion; no previous service timestamp can shorten a manual reset.
ExecStopPost=/usr/bin/systemctl --user --no-block try-restart $TIMER_NAME
EOF
)
  if [[ ! -f $SERVICE_FILE ]] || [[ $(<"$SERVICE_FILE") != "$content" ]]; then
    printf '%s\n' "$content" | atomic_write "$SERVICE_FILE"
    UNITS_CHANGED=1
  fi

  content=$(cat <<EOF
[Unit]
Description=Rotate the Omarchy wallpaper every $interval minutes
StartLimitIntervalSec=0

[Timer]
OnActiveSec=${interval}m
AccuracySec=1min
Unit=$SERVICE_NAME

[Install]
WantedBy=timers.target
EOF
)
  if [[ ! -f $TIMER_FILE ]] || [[ $(<"$TIMER_FILE") != "$content" ]]; then
    printf '%s\n' "$content" | atomic_write "$TIMER_FILE"
    UNITS_CHANGED=1
  fi
}

systemctl_user() {
  "$SYSTEMCTL_BIN" --user "$@"
}

sync_timer() {
  write_units
  if (( UNITS_CHANGED )); then systemctl_user daemon-reload; fi
  if [[ $(config_value '.enabled') == true ]]; then
    # Even a redundant enable --now reloads the manager and can postpone an
    # OnActiveSec deadline. Leave an already enabled, active timer untouched.
    if ! systemctl_user is-enabled --quiet "$TIMER_NAME"; then
      systemctl_user enable "$TIMER_NAME" >/dev/null
    fi
    if (( UNITS_CHANGED )); then
      systemctl_user reset-failed "$TIMER_NAME" >/dev/null 2>&1 || true
      systemctl_user restart "$TIMER_NAME"
    elif ! systemctl_user is-active --quiet "$TIMER_NAME"; then
      systemctl_user reset-failed "$TIMER_NAME" >/dev/null 2>&1 || true
      systemctl_user start "$TIMER_NAME"
    fi
  else
    systemctl_user disable --now "$TIMER_NAME" >/dev/null 2>&1 || true
  fi
}

current_theme() {
  cat "$OMARCHY_HOME/.local/state/omarchy/current/theme.name" 2>/dev/null || true
}

current_background() {
  readlink -f "$OMARCHY_HOME/.local/state/omarchy/current/background" 2>/dev/null || true
}

catalog_paths() {
  local theme current_dir user_dir path resolved
  local -A seen=()
  local paths=()
  theme=$(current_theme)
  current_dir="$OMARCHY_HOME/.local/state/omarchy/current/theme/backgrounds"
  user_dir="$OMARCHY_HOME/.config/omarchy/backgrounds/$theme"

  while IFS= read -r -d '' path; do
    resolved=$(realpath -m "$path")
    [[ -f $resolved && -z ${seen[$resolved]+x} ]] || continue
    seen["$resolved"]=1
    paths+=("$resolved")
  done < <(
    find -L "$current_dir" "$user_dir" -maxdepth 1 -type f \
      \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.gif' \
         -o -iname '*.bmp' -o -iname '*.webp' \) -print0 2>/dev/null | sort -z
  )

  (( ${#paths[@]} > 0 )) && printf '%s\0' "${paths[@]}"
}

catalog_json() {
  local paths=() path name
  local json='[]'
  mapfile -d '' -t paths < <(catalog_paths)
  for path in "${paths[@]}"; do
    name=$(basename "$path")
    name=${name%.*}
    name=${name//[-_.]/ }
    json=$(jq -c --arg path "$path" --arg name "$name" '. + [{path:$path,name:$name}]' <<<"$json")
  done
  printf '%s\n' "$json"
}

reset_shuffle() {
  rm -f "$SHUFFLE_FILE"
}

save_shuffle_queue() {
  local theme="$1" signature="$2"
  shift 2
  jq -n --arg theme "$theme" --arg signature "$signature" \
    --args '$ARGS.named + {remaining:$ARGS.positional}' -- "$@" |
    atomic_write "$SHUFFLE_FILE"
}

shuffle_rotate() {
  local catalog signature theme current target saved_signature saved_theme
  local all=() remaining=() candidates=()
  local i j temporary

  catalog=$(catalog_json)
  mapfile -t all < <(jq -r '.[] | .path | @base64' <<<"$catalog")
  (( ${#all[@]} > 1 )) || return 0
  for i in "${!all[@]}"; do all[$i]=$(base64 -d <<<"${all[$i]}"); done

  signature=$(printf '%s' "$catalog" | sha256sum | cut -d ' ' -f 1)
  theme=$(current_theme)
  current=$(current_background)

  if [[ -f $SHUFFLE_FILE ]] && jq -e '
    type == "object" and (.theme | type) == "string"
    and (.signature | type) == "string" and (.remaining | type) == "array"
    and all(.remaining[]; type == "string")
  ' "$SHUFFLE_FILE" >/dev/null 2>&1; then
    saved_signature=$(jq -r '.signature // ""' "$SHUFFLE_FILE")
    saved_theme=$(jq -r '.theme // ""' "$SHUFFLE_FILE")
    if [[ $saved_signature == "$signature" && $saved_theme == "$theme" ]]; then
      mapfile -t remaining < <(jq -r '.remaining[]? | @base64' "$SHUFFLE_FILE")
      for i in "${!remaining[@]}"; do remaining[$i]=$(base64 -d <<<"${remaining[$i]}"); done
    fi
  fi

  # Another wallpaper picker may have selected the next queued image.
  candidates=()
  for i in "${remaining[@]}"; do [[ $i == "$current" ]] || candidates+=("$i"); done
  remaining=("${candidates[@]}")
  candidates=()

  if (( ${#remaining[@]} == 0 )); then
    for i in "${all[@]}"; do [[ $i == "$current" ]] || candidates+=("$i"); done
    for (( i=${#candidates[@]}-1; i>0; i-- )); do
      j=$(( RANDOM % (i + 1) ))
      temporary=${candidates[$i]}
      candidates[$i]=${candidates[$j]}
      candidates[$j]=$temporary
    done
    remaining=("${candidates[@]}")
  fi

  (( ${#remaining[@]} > 0 )) || return 0
  target=${remaining[0]}
  remaining=("${remaining[@]:1}")
  "$OMARCHY_BIN" theme bg set "$target"
  save_shuffle_queue "$theme" "$signature" "${remaining[@]}"
}

rotate_core() {
  exec 9>"$LOCK_FILE"
  flock -n 9 || return 0
  if [[ $(config_value '.mode') == shuffle ]]; then
    shuffle_rotate
  else
    "$OMARCHY_BIN" theme bg next
  fi
}

rotate_once() {
  ensure_config
  [[ $(config_value '.enabled') == true ]] || return 0
  rotate_core
}

plugin_enabled() {
  # Follow Omarchy's own enablement rules, including shelved widgets in plugins[].
  [[ -f $SHELL_CONFIG ]] || return 1
  jq -e --arg id "$PLUGIN_ID" '
    ((.disabledPlugins // [] | index($id)) == null) and
    ([ (.plugins // [])[], (.bar.layout.left // [])[],
       (.bar.layout.center // [])[], (.bar.layout.right // [])[] ] |
      any(.[]; (if type == "string" then . else .id? end) == $id))
  ' "$SHELL_CONFIG" >/dev/null 2>&1
}

scheduled_rotate() {
  plugin_enabled || return 0
  rotate_once
}

uninstall_timer() {
  systemctl_user disable --now "$TIMER_NAME"
  systemctl_user stop "$SERVICE_NAME"
  rm -f "$SERVICE_FILE" "$TIMER_FILE"
  systemctl_user daemon-reload
  systemctl_user reset-failed "$SERVICE_NAME" "$TIMER_NAME" >/dev/null 2>&1 || true
}

set_wallpaper() {
  local target="$1" catalog
  [[ -n $target ]] || die 'a wallpaper path is required'
  ensure_config
  exec 9>"$LOCK_FILE"
  flock 9
  catalog=$(catalog_json)
  jq -e --arg target "$(realpath -m "$target")" 'any(.[]; .path == $target)' <<<"$catalog" >/dev/null \
    || die 'wallpaper is not part of the active theme'
  "$OMARCHY_BIN" theme bg set "$(realpath -m "$target")"
  reset_shuffle
  systemctl_user try-restart "$TIMER_NAME" >/dev/null 2>&1 || true
}

configure() {
  local key="${1:-}" value="${2:-}" temporary
  ensure_config
  case "$key" in
    enabled)
      [[ $value == true || $value == false ]] || die 'enabled must be true or false'
      ;;
    intervalMinutes)
      [[ $value =~ ^[0-9]{1,4}$ ]] && (( 10#$value >= 5 && 10#$value <= 1440 )) \
        || die 'intervalMinutes must be an integer from 5 to 1440'
      value=$((10#$value))
      ;;
    mode)
      [[ $value == sequential || $value == shuffle ]] || die 'mode must be sequential or shuffle'
      ;;
    *)
      die 'unknown configuration key'
      ;;
  esac
  temporary=$(mktemp "$CONFIG_FILE.tmp.XXXXXX")
  if [[ $key == mode ]]; then
    jq --arg value "$value" '.mode = $value' "$CONFIG_FILE" >"$temporary"
  else
    jq --arg key "$key" --argjson value "$value" '.[$key] = $value' "$CONFIG_FILE" >"$temporary"
  fi
  chmod 0644 "$temporary"
  mv -f "$temporary" "$CONFIG_FILE"
  [[ $key != mode ]] || reset_shuffle
  sync_timer
}

status_json() {
  local enabled interval mode active next_us now_us next_minutes current theme
  ensure_config
  enabled=$(config_value '.enabled')
  interval=$(config_value '.intervalMinutes')
  mode=$(config_value '.mode')
  active=false
  systemctl_user is-active --quiet "$TIMER_NAME" 2>/dev/null && active=true
  next_minutes=-1
  next_us=$(systemctl_user list-timers "$TIMER_NAME" --output=json --no-pager 2>/dev/null | jq -r '.[0].next // 0' 2>/dev/null || printf 0)
  if [[ $next_us =~ ^[0-9]+$ ]] && (( next_us > 0 )); then
    now_us=$(( $(date +%s) * 1000000 ))
    next_minutes=$(( (next_us - now_us + 59999999) / 60000000 ))
    (( next_minutes < 0 )) && next_minutes=0
    (( next_minutes > interval )) && next_minutes=$interval
  fi
  current=$(current_background)
  theme=$(current_theme)
  jq -n --argjson enabled "$enabled" --argjson active "$active" \
    --argjson intervalMinutes "$interval" --arg mode "$mode" \
    --argjson nextInMinutes "$next_minutes" --arg current "$current" --arg theme "$theme" \
    '{enabled:$enabled,timerActive:$active,intervalMinutes:$intervalMinutes,mode:$mode,nextInMinutes:$nextInMinutes,current:$current,theme:$theme}'
}

initialize() {
  ensure_config
  sync_timer
}

case "${1:-}" in
  init) initialize ;;
  scheduled) scheduled_rotate ;;
  uninstall) uninstall_timer ;;
  configure) configure "${2:-}" "${3:-}" ;;
  rotate) rotate_once ;;
  next)
    ensure_config
    rotate_core
    systemctl_user try-restart "$TIMER_NAME" >/dev/null 2>&1 || true
    ;;
  set) set_wallpaper "${2:-}" ;;
  catalog) catalog_json ;;
  status) status_json ;;
  *) die 'usage: WallpaperRotation.sh {init|configure KEY VALUE|scheduled|rotate|next|set PATH|catalog|status|uninstall}' ;;
esac
