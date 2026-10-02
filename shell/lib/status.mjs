// The bar's battery and volume icons (SPEC.md §7.4), as pure functions the
// QML binds to. Icons are the desktop icon theme's symbolic names, which
// Adwaita has; the QML tints them to the bar's palette.

// Below this charge the battery shows red, unless it's charging.
export const LOW_BATTERY = 0.15;
// One scroll notch over the volume icon changes it by this much.
export const VOLUME_STEP = 0.05;

const CHARGING = 1;
const FULLY_CHARGED = 4;
const PENDING_CHARGE = 5;

// What the battery icon shows, from UPower's display device: `percentage`
// 0-1 and `state` as UPowerDeviceState numbers. `present` false (a desktop,
// or a removed battery) hides it.
export function batteryView({ present, percentage, state }) {
    if (!present || !Number.isFinite(percentage)) {
        return { visible: false, text: "", icon: "", low: false };
    }
    const pct = Math.round(Math.min(1, Math.max(0, percentage)) * 100);
    const charging = state === CHARGING || state === PENDING_CHARGE;
    // Adwaita has battery-level-0 to -100 in tens, and -100-charged.
    const level = Math.round(pct / 10) * 10;
    const icon = state === FULLY_CHARGED ? "battery-level-100-charged-symbolic"
        : `battery-level-${level}${charging ? "-charging" : ""}-symbolic`;
    return {
        visible: true,
        text: `${pct}%`,
        icon,
        low: !charging && state !== FULLY_CHARGED && percentage < LOW_BATTERY,
    };
}

// What the volume icon shows for the default output: muted, or a level by
// thirds. No output (`volume` not a number) shows it muted.
export function volumeIcon({ muted, volume }) {
    if (muted || !Number.isFinite(volume) || volume <= 0) {
        return "audio-volume-muted-symbolic";
    }
    if (volume < 1 / 3) {
        return "audio-volume-low-symbolic";
    }
    return volume < 2 / 3 ? "audio-volume-medium-symbolic" : "audio-volume-high-symbolic";
}

// The volume after `notches` of scrolling (positive is up), VOLUME_STEP a
// notch from wherever it is, within 0 to 1. A volume already above 1,
// which some apps set, isn't pulled down by scrolling up.
export function scrolledVolume(volume, notches) {
    const from = Number.isFinite(volume) ? volume : 0;
    const to = from + Math.trunc(notches) * VOLUME_STEP;
    if (notches > 0 && from >= 1) {
        return from;
    }
    // Rounded to 0.01%, enough to drop float error without moving the level.
    return Math.min(1, Math.max(0, Math.round(to * 10000) / 10000));
}
