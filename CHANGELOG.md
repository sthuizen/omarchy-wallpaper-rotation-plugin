# Changelog

## 1.1.0 — 2026-10-26 — Timer lifecycle and recovery

- Preserve the rotation deadline when the shell restarts or plugin code reloads.
- Avoid redundant `systemctl enable --now` calls: bare-metal testing on systemd
  262 showed that its implicit manager reload postpones an active deadline.
- Rearm a single-baseline timer after each service run so a manual wallpaper
  selection really starts a full new interval, including after earlier rotations.
- Skip scheduled rotations while the plugin is disabled in Omarchy, including
  explicit `disabledPlugins` entries and widgets moved into `plugins[]`.
- Skip a removed helper using a systemd path condition and add an `uninstall`
  command that removes both user units while preserving preferences.
- Recover from settings of the wrong JSON type and corrupt shuffle queues.
- Avoid immediately repeating a queued wallpaper selected through another picker.
- Serialize manual selection with scheduled rotation and accept leading-zero
  interval input as decimal.
- Quote helper paths for systemd, including spaces and literal percent signs.
- Remove unused inline manifest settings and document the actual monotonic timer
  behavior, including suspend and reboot, without claiming calendar persistence.
- Use `omarchy bar move` in installation instructions and add regression coverage
  for the updated behavior. Checked against Omarchy 4.0.6.
- Qualify the Omarchy colour singleton in the panel to avoid Qt Quick Controls'
  conflicting `Color` type and undefined colour bindings.
- Add the real popup screenshot and bare-metal validation report. Native timer,
  enablement, shuffle, manual-reset, and reload checks passed on a Framework
  Laptop 13; suspend and reboot remain untested.

## 1.0.1 — Omarchy 4.0.4 compatibility

- Verified the plugin against Omarchy 4.0.4's manifest schema and native
  background commands. No runtime code changes were required.
- Ran the isolated control tests and validated the generated user systemd units.
  A live shell session is still needed to exercise the bar UI and actual timer.
