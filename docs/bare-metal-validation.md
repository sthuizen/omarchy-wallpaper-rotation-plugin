# Wallpaper Rotation: bare-metal validation

Tested: 26 October 2026, 23:35 GMT

Framework Laptop 13 (AMD Ryzen 7040 Series); Omarchy 4.0.6; systemd 262.1. The laptop reported no virtual-machine environment.

Installed plugin: `thenailedone.wallpaper-rotation`, version 1.1.0. Runtime checks passed at commit `5e3defe216b0e1effb82661030b624cb500ba5d2`; the release also adds this report, its screenshot, and documentation updates.

## Passed

- Live catalogue contains all 20 Quattro Sunset wallpapers
- IPC next changes the real desktop wallpaper
- Helper init and live QML reload preserve the exact timer deadline
- Automatic-off blocks a real scheduled service run
- Disabling the Omarchy plugin blocks a real scheduled service run
- Three real shuffle changes do not repeat an image
- Manual selection applies a catalogue wallpaper
- The actual systemd timer changes the wallpaper and rearms itself
- Manual selection waits a full interval and the next automatic run succeeds
- The real popup opened with all 20 wallpaper previews and correct theme colours.

## Test scope

These checks used the installed plugin, live desktop IPC, actual wallpaper files, and the native systemd user manager. Timer checks used a temporary 10-second drop-in; no scheduler or wallpaper commands were mocked. The drop-in was removed afterward. Suspend, reboot, and physical pointer clicks on each popup control were not tested.

## Final state

Plugin installed and enabled. Automatic rotation enabled, sequential order, 60-minute interval. Original Creation wallpaper restored.

## Fix found on hardware

A redundant `systemctl enable --now` implicitly reloaded the manager and postponed an active deadline. Initialization now checks enablement and activity first, leaving an unchanged active timer untouched. The same live deadline checks then passed.

[Review and code changes](https://github.com/sthuizen/omarchy-wallpaper-rotation-plugin/pull/1)
