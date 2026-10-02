// The tray (SPEC.md §7.4): third-party StatusNotifierItem icons, as pure
// functions the QML binds to.

// The items to show, in the order they registered. A passive item says
// it's idle and can be hidden, as waybar's tray hides it by default.
export function shownItems(items, passive) {
    return items.filter(i => i.status !== passive);
}

// What a click with `button` ("left", "middle" or "right") does to `item`
// (SPEC.md §7.4: a click opens the app's menu):
//   - "menu", its menu (DBusMenu), for a left or right click;
//   - "activate", the app's own action, usually showing its window: a
//     middle click, or a left click on an item without a menu;
//   - "secondary", its secondary action: a right click without a menu;
//   - null, nothing.
export function clickAction(button, item) {
    switch (button) {
    case "left":
        return item.hasMenu ? "menu" : "activate";
    case "middle":
        return "activate";
    case "right":
        return item.hasMenu ? "menu" : "secondary";
    default:
        return null;
    }
}
