# Wallpaper Rotation for Omarchy

A native Omarchy Quattro bar plugin for previewing, selecting, and automatically rotating the active theme's wallpapers.

The scheduler uses a user-level systemd timer independently of the shell's QML lifetime. Sequential changes delegate directly to Omarchy's supported command:

```bash
omarchy theme bg next
```

Shuffle and manual selections use the supported `omarchy theme bg set` command.

## Features

- Sequential or non-repeating shuffled rotation
- Configurable intervals from 5 minutes to 24 hours
- Wallpaper preview and click-to-apply panel
- Shell restarts and plugin reloads preserve the existing rotation countdown
- Scheduled runs respect Omarchy's plugin enable/disable state
- Manual selections restart the full interval
- Fresh theme and current-wallpaper state on every scheduled run
- No network access, elevated privileges, or packaged-file changes

Checked against Omarchy 4.0.6's plugin validator, enablement rules, and theme
background commands, plus the [current plugin documentation](https://omarchy.org/manual/shell-plugins/).
Wallpaper previews cover the image formats supported by the installed background command.

## Install

```bash
omarchy plugin add https://github.com/sthuizen/omarchy-wallpaper-rotation-plugin.git --enable --yes
omarchy bar move thenailedone.wallpaper-rotation --section right
```

The default is an hourly sequential rotation. Open the bar widget to change the interval or select shuffle mode. Middle-click the widget to advance immediately.

Settings are owned by this plugin's panel and saved in its dedicated `config.json`.
The manifest does not advertise separate inline bar settings, which would create
a second, unsynchronized source of preferences.

## Timing and lifecycle

The timer uses systemd's monotonic `OnActiveSec` scheduling and rearms after each
service run finishes. A non-blocking `ExecStopPost` restart avoids waiting on a
timer job ordered before that same service. Using a single timing baseline also
prevents a previous scheduled run from shortening a manual wallpaper reset.
Reloading an unchanged plugin does not restart the timer. Changing the interval
or choosing a wallpaper manually starts a fresh interval. Suspend pauses the
countdown, and starting a new user session after a reboot starts a new interval;
missed rotations are not replayed. `AccuracySec=1min` allows systemd to group
wakeups, so the interval is not a second-precise deadline.
See the [systemd timer reference](https://www.freedesktop.org/software/systemd/man/latest/systemd.timer.html)
for monotonic scheduling and the calendar-only `Persistent` option.

The scheduled helper checks the plugin's ID in Omarchy's `shell.json`, including
bar placement, shelved entries in `plugins[]`, and `disabledPlugins[]`. Disabled
plugins do not change the wallpaper. If the checkout is removed without cleanup,
the service's path condition skips the missing helper instead of repeatedly
failing to execute it. Use the removal procedure below to remove the timer too.

## Update

```bash
omarchy plugin update thenailedone.wallpaper-rotation
```

The service refreshes its unit files when it loads. An unchanged reload keeps
the current due time; the first update from 1.0.x rewrites the unit and restarts
the interval once.

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

Remove the user timer and service before removing the plugin:

```bash
~/.config/omarchy/plugins/thenailedone.wallpaper-rotation/WallpaperRotation.sh uninstall
omarchy plugin remove thenailedone.wallpaper-rotation --yes
```

The configuration and shuffle-state directories are intentionally retained so
reinstalling preserves your preferences. No root access is required.

## Test

```bash
./tests/test-control.sh
omarchy plugin validate .
```

The tests use isolated directories and mocked Omarchy/systemd commands. They
never change the real desktop wallpaper or enable a real timer. Generated unit
files are checked with `systemd-analyze --user verify`.

## License

MIT
