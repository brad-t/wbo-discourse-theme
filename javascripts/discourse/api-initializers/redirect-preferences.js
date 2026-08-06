import { apiInitializer } from "discourse/lib/api";

// Bounce anyone who lands on Discourse's /u/{username}/preferences* pages
// to the WordPress-side settings page instead. Discourse's own prefs UI
// is mostly hidden from the nav in this theme, but users can still arrive
// via pasted URLs, bookmarks, or emails Discourse sends with these links.
//
// The redirect maps Discourse's sub-page slugs onto the WBO section slugs
// where the equivalent controls live — so a user aiming at
// /preferences/security lands on /settings/?section=security rather than
// the front page. Unknown sub-pages fall back to the WBO settings root.

const SECTION_MAP = {
  account: "account",
  profile: "profile",
  emails: "emails",
  notifications: "notifications",
  tracking: "tracking",
  users: "users",
  security: "security",
  interface: "wbo",
  "second-factor": "security",
};

export default apiInitializer("1.0", (api) => {
  const base = (settings.wbo_settings_url || "").trim();
  if (!base) return;

  api.onPageChange((url) => {
    const m = url.match(/^\/u\/[^/]+\/preferences(?:\/([^/?#]+))?/);
    if (!m) return;

    const sub = m[1];
    const section = sub ? SECTION_MAP[sub] : null;
    const target = section
      ? `${base}${base.includes("?") ? "&" : "?"}section=${section}`
      : base;

    // replace() so the Discourse preferences URL doesn't sit in browser
    // history — otherwise Back returns them here and bounces again.
    window.location.replace(target);
  });
});
