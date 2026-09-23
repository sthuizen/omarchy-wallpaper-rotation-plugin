# Wallpaper Rotation for Omarchy

A native Omarchy Quattro bar plugin for previewing, selecting, and automatically rotating the active theme's wallpapers.

The scheduler deliberately uses a persistent user-level systemd timer instead of storing Unix timestamps in QML. Sequential changes delegate directly to Omarchy's supported command:

```bash
omarchy theme bg next
```

Shuffle and manual selections use the supported `omarchy theme bg set` command.

## Features

- Sequential or non-repeating shuffled rotation
- Configurable intervals from 5 minutes to 24 hours
- Wallpaper preview and click-to-apply panel
- Persistent scheduling across shell restarts and suspend/resume
- Manual selections restart the full interval
- Fresh theme and current-wallpaper state on every scheduled run
- No network access, elevated privileges, or packaged-file changes

Omarchy 4.0.4 compatibility was checked against its installed plugin validator,
theme background commands, and user systemd unit syntax. Wallpaper previews
cover the image formats handled by `omarchy theme bg next` in 4.0.4.

## Install

```bash
omarchy plugin add https://github.com/thenailedone/omarchy-wallpaper-rotation-plugin.git --enable --yes
omarchy bar put thenailedone.wallpaper-rotation --section right
```

The default is an hourly sequential rotation. Open the bar widget to change the interval or select shuffle mode. Middle-click the widget to advance immediately.

## Commands

```bash
omarchy-shell -q thenailedone.wallpaper-rotation status
omarchy-shell -q thenailedone.wallpaper-rotation next
omarchy-shell -q thenailedone.wallpaper-rotation enable
omarchy-shell -q thenailedone.wallpaper-rotation disable
```

## Files created at runtime

```text
~/.config/omarchy/wallpaper-rotation/config.json
~/.config/systemd/user/omarchy-wallpaper-rotation.service
~/.config/systemd/user/omarchy-wallpaper-rotation.timer
~/.local/state/omarchy/wallpaper-rotation/
```

## Remove

Disable the timer before removing the plugin:

```bash
systemctl --user disable --now omarchy-wallpaper-rotation.timer
omarchy plugin remove thenailedone.wallpaper-rotation --yes
```

The small configuration and state directories are intentionally retained so reinstalling preserves your preferences.

## Test

```bash
./tests/test-control.sh
omarchy plugin validate .
```

## License

MIT
