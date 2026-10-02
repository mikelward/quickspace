// Knowing that a screen share is live (SPEC.md §12), as pure functions the
// QML binds to. The QML passes Quickshell's PipeWire objects and its
// PwLinkState.Active in, so this file names no Quickshell type.

// xdph names each screencast's PipeWire node xdph-streaming-<id>.
export function isShareNode(node) {
    return typeof node?.name === "string" && node.name.startsWith("xdph-streaming");
}

// The link groups out of share nodes: the ones the shell binds (with a
// PwObjectTracker), since a link group's state is only valid while bound,
// and only these, rather than every audio link.
export function shareLinks(linkGroups) {
    return linkGroups.filter(g => isShareNode(g.source));
}

// The share nodes something is consuming: an xdph stream with an active
// link out of it. A stream nobody reads yet (the picker is still open, or
// Chrome hasn't started) isn't a share.
export function liveShares(nodes, linkGroups, ACTIVE) {
    const consumed = new Set(linkGroups
        .filter(g => g.state === ACTIVE && g.source)
        .map(g => g.source.id));
    return nodes.filter(n => isShareNode(n) && consumed.has(n.id));
}

// Whether popups are held for the shares that are live. Only a screen or
// region share holds them; a window share can't show them (§9). Nothing
// says which kind a stream is until the picker records its choice (§12),
// so for now every live share counts as a screen share: the safe way to be
// wrong, since a popup then waits rather than leaking into a stream.
export function holdsPopups(shares) {
    return shares.length > 0;
}

// The bar's red Sharing pill (§7.4) shows while any share is live, and takes
// no room otherwise. Unlike holding popups, a window share counts.
export function sharingPill(shares) {
    return shares.length > 0;
}
