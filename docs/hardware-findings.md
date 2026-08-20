# Hardware findings — km01 panel

Measured 2026-08-16 on `km01` (`master-11`, 192.168.10.101) with
`tools/probe_hardware.py`. These resolve the three risks in spec section 12.

## 1. DRM master — RESOLVED, no root required

```
DRM OK as uid=1000: 1280x720
pygame 2.5.2 (SDL 2.30.0, Python 3.12.3)
```

`piwi` (uid 1000) acquires DRM master via SDL2's KMSDRM backend **unprivileged**,
because it is already in the `video` and `render` groups. The reported mode is
1280x720, matching the spec.

**Consequence:** `deploy/kw-dashboard.service` keeps `User=piwi` / `Group=piwi`.
The root fallback contemplated in the plan is not needed and should not be used.

## 2. VT contention — RESOLVED

```
console active on: ['ttyS2', 'tty1']
tty users: (none reported)
```

The console occupies `tty1` (plus the `ttyS2` serial console). No process holds
any other VT, so `TTYPath=/dev/tty2` in the unit is free and will not fight
`fbcon` or a getty.

## 3. Touch calibration — DEFERRED to deploy

Capturing `ABS_X`/`ABS_Y` ranges requires a human physically touching the panel's
four corners, so it was not captured from this remote session.

Run at deploy time:

```bash
python3 /tmp/probe_hardware.py --touch
```

Then set `swap_xy` / `invert_x` / `invert_y` in `/etc/kw-dashboard/config.toml`
per plan Task 16 step 5, which already iterates calibration against the live
panel. Defaults assume a 0..4095 range with no swap or inversion.

**This is deferred, not dismissed.** The ILITEK digitiser's orientation is still
unverified, and the calibration knobs exist precisely because it may be wrong.

## Panel reference

| Property           | Value                                                                                                                                     |
| ------------------ | ----------------------------------------------------------------------------------------------------------------------------------------- |
| Connector          | HDMI-A-1, connected                                                                                                                       |
| Mode               | 1280x720 (preferred; 1920x1080 offered but unused)                                                                                        |
| Panel              | Realtek scaler, EDID model `RTK 9Cun` — ~9 inch                                                                                           |
| EDID physical size | Reports 597x336 mm. **Garbage** — generic scaler default, implies 27". Ignore it; the 9" figure comes from the model name (_cun_ = inch). |
| Touch              | ILITEK, USB 222a:0001, `/dev/input/event5` + `mouse0`                                                                                     |
| GPU                | Mali-G610, `panthor` driver, `/dev/dri/card1`                                                                                             |
| Other input        | `gpio_ir_recv` (IR), `adc-keys-0/1` — present but unused                                                                                  |
