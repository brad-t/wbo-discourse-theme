import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { on } from "@ember/modifier";
import { concat } from "@ember/helper";
import { htmlSafe } from "@ember/template";
import icon from "discourse/helpers/d-icon";
import { getOwner } from "@ember/application";
import Composer from "discourse/models/composer";

// Inline SVG paths lifted from the WP header.php dropdown so both sides
// use identical iconography. Stroke inherits currentColor, so drawer/
// dropdown CSS can recolor as needed. Kept as SafeString values so
// Glimmer renders them as HTML instead of escaping.
const _svg = (paths) =>
  htmlSafe(
    `<svg width="16" height="16" viewBox="0 0 24 24" fill="none" ` +
      `stroke="currentColor" stroke-width="2" stroke-linecap="round" ` +
      `stroke-linejoin="round">${paths}</svg>`
  );
const ICONS = {
  trophy: _svg(
    '<path d="M6 9H4.5a2.5 2.5 0 0 1 0-5H6"/>' +
      '<path d="M18 9h1.5a2.5 2.5 0 0 0 0-5H18"/>' +
      '<path d="M4 22h16"/>' +
      '<path d="M10 14.66V17c0 .55-.47.98-.97 1.21C7.85 18.75 7 20.24 7 22"/>' +
      '<path d="M14 14.66V17c0 .55.47.98.97 1.21C16.15 18.75 17 20.24 17 22"/>' +
      '<path d="M18 2H6v7a6 6 0 0 0 12 0V2Z"/>'
  ),
  bell: _svg(
    '<path d="M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9"/>' +
      '<path d="M10.3 21a1.94 1.94 0 0 0 3.4 0"/>'
  ),
  envelope: _svg(
    '<rect x="2" y="4" width="20" height="16" rx="2"/>' +
      '<path d="m22 7-8.97 5.7a1.94 1.94 0 0 1-2.06 0L2 7"/>'
  ),
  gear: _svg(
    '<path d="M12.22 2h-.44a2 2 0 0 0-2 2v.18a2 2 0 0 1-1 1.73l-.43.25a2 2 0 0 1-2 0l-.15-.08a2 2 0 0 0-2.73.73l-.22.38a2 2 0 0 0 .73 2.73l.15.1a2 2 0 0 1 1 1.72v.51a2 2 0 0 1-1 1.74l-.15.09a2 2 0 0 0-.73 2.73l.22.38a2 2 0 0 0 2.73.73l.15-.08a2 2 0 0 1 2 0l.43.25a2 2 0 0 1 1 1.73V20a2 2 0 0 0 2 2h.44a2 2 0 0 0 2-2v-.18a2 2 0 0 1 1-1.73l.43-.25a2 2 0 0 1 2 0l.15.08a2 2 0 0 0 2.73-.73l.22-.39a2 2 0 0 0-.73-2.73l-.15-.08a2 2 0 0 1-1-1.74v-.5a2 2 0 0 1 1-1.74l.15-.09a2 2 0 0 0 .73-2.73l-.22-.38a2 2 0 0 0-2.73-.73l-.15.08a2 2 0 0 1-2 0l-.43-.25a2 2 0 0 1-1-1.73V4a2 2 0 0 0-2-2Z"/>' +
      '<circle cx="12" cy="12" r="3"/>'
  ),
  sun: _svg(
    '<circle cx="12" cy="12" r="4"/>' +
      '<path d="M12 2v2M12 20v2M4.93 4.93l1.41 1.41M17.66 17.66l1.41 1.41M2 12h2M20 12h2M6.34 17.66l-1.41 1.41M19.07 4.93l-1.41 1.41"/>'
  ),
  moon: _svg('<path d="M12 3a6 6 0 0 0 9 9 9 9 0 1 1-9-9Z"/>'),
  logout: _svg(
    '<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/>' +
      '<polyline points="16 17 21 12 16 7"/>' +
      '<line x1="21" y1="12" x2="9" y2="12"/>'
  ),
};
// Reuse Discourse's own categories section so we get:
//   - unread/new counts wired to TopicTrackingState (live)
//   - the user's own sidebar category picks (or top-N fallback)
//   - category permissions (private categories omitted)
//   - "All categories" link
//   - resilience to categories being added/renamed
// NOTE: these are internal component paths, not a public plugin API. They
// are re-verified for each Discourse upgrade. Currently reads the running
// instance at 2026.4.0-latest.
import UserCategoriesSection from "discourse/components/sidebar/user/categories-section";
import AnonymousCategoriesSection from "discourse/components/sidebar/anonymous/categories-section";

// Fallback used when the `nav_items` theme setting is empty or malformed.
// The setting (settings.yml) holds the same shape as JSON and is the
// source of truth in normal operation -- edit the menu there, no deploy
// needed. Kept in sync as the safety net.
const DEFAULT_NAV_ITEMS = [
  { label: "Tournaments", url: "https://worldbeyblade.org/tournaments/" },
  { label: "Leagues", url: "https://leaderboard.fighting-spirits.org/" },
  { label: "Community", url: "/", active: true, isCommunity: true },
  {
    label: "Rules & Resources",
    url: "https://worldbeyblade.org/rules/beyblade-x-rules/",
  },
  { label: "About WBO", url: "#" },
];

export default class WboSiteNav extends Component {
  @service router;
  @service currentUser;
  @service siteSettings;
  @service composer;
  @service topicTrackingState;

  @tracked isDrawerOpen = false;
  @tracked isUserDropdownOpen = false;
  @tracked totalUnread = 0;
  @tracked totalNew = 0;

  constructor() {
    super(...arguments);

    this._refreshCounts();
    this._trackingCallbackId = this.topicTrackingState?.onStateChange(() =>
      this._refreshCounts()
    );

    // Close the drawer on any route change — covers taps on category
    // links rendered by Discourse's own CategoriesSection component (we
    // don't own their click handlers) and normal back/forward navigation.
    this.router.on("routeDidChange", this._closeOnRouteChange);

    // Custom user-menu dropdown: close on any click outside the pill, and
    // on Escape. Kept in one place so it's easy to remove if the mount
    // point ever changes. Listeners run in capture phase so we win the
    // race against any other outside-click handler on the page.
    document.addEventListener("click", this._closeUserDropdownOnOutside, true);
    document.addEventListener("keydown", this._closeUserDropdownOnEscape);
  }

  willDestroy() {
    super.willDestroy?.(...arguments);
    if (this._trackingCallbackId) {
      this.topicTrackingState?.offStateChange(this._trackingCallbackId);
    }
    this.router.off("routeDidChange", this._closeOnRouteChange);
    document.removeEventListener(
      "click",
      this._closeUserDropdownOnOutside,
      true
    );
    document.removeEventListener("keydown", this._closeUserDropdownOnEscape);
  }

  _closeUserDropdownOnOutside = (event) => {
    if (!this.isUserDropdownOpen) return;
    const target = event.target;
    if (!target || target.closest?.(".wbo-user-menu-wrap")) return;
    this.isUserDropdownOpen = false;
  };

  _closeUserDropdownOnEscape = (event) => {
    if (event.key === "Escape" && this.isUserDropdownOpen) {
      this.isUserDropdownOpen = false;
    }
  };

  _closeOnRouteChange = () => {
    if (this.isDrawerOpen) {
      this.isDrawerOpen = false;
    }
  };

  _refreshCounts() {
    if (!this.currentUser) {
      this.totalUnread = 0;
      this.totalNew = 0;
      return;
    }
    this.totalUnread = this.topicTrackingState?.countUnread?.() ?? 0;
    this.totalNew = this.topicTrackingState?.countNew?.() ?? 0;
  }

  // Latest routes to /latest, which surfaces both unread and new topics.
  // Its badge is unread+new so a single indicator covers everything users
  // would want to see under "Latest".
  get latestBadge() {
    return this.totalUnread + this.totalNew;
  }

  // ── Getters ───────────────────────────────────────────────────────────────

  get navItems() {
    // `settings` is the theme-settings global injected into theme JS.
    const raw = settings.nav_items;
    let items = DEFAULT_NAV_ITEMS;
    if (raw) {
      try {
        const parsed = JSON.parse(raw);
        if (Array.isArray(parsed) && parsed.length) {
          items = parsed;
        }
      } catch {
        // Malformed JSON in the setting -- fall through to the default
        // so the nav never renders empty.
      }
    }

    // Community is baked as active in the setting, but auth/account flows
    // ({login, signup, password-reset, email-login, invites, ...}) live in
    // Discourse without being part of the Community section — active state
    // should follow the intent (browsing the forum), not the fact that
    // the URL is on the Discourse origin.
    const communityActive = this._isCommunityActiveRoute();
    return items.map((item) =>
      item.isCommunity ? { ...item, active: communityActive } : item
    );
  }

  _isCommunityActiveRoute() {
    const route = this.router.currentRouteName || "";
    // Prefix match — Ember route names dot-delimit sub-routes (e.g.
    // `password-reset.token`, `invites.show`), so `startsWith` catches
    // the whole subtree with one entry.
    const NON_COMMUNITY_ROUTE_PREFIXES = [
      "login",
      "signup",
      "password-reset",
      "email-login",
      "invites",
      "account-created",
      "associate-account",
    ];
    return !NON_COMMUNITY_ROUTE_PREFIXES.some(
      (prefix) => route === prefix || route.startsWith(prefix + ".")
    );
  }

  get logoUrl() {
    return this.siteSettings.logo_url || this.siteSettings.logo || null;
  }

  get userAvatarUrl() {
    return this.currentUser?.avatar_template?.replace("{size}", "45") ?? null;
  }

  get CategoriesSection() {
    return this.currentUser
      ? UserCategoriesSection
      : AnonymousCategoriesSection;
  }

  // ── Create / reply context ────────────────────────────────────────────────

  get currentTopic() {
    const route = this.router.currentRouteName || "";
    if (!route.startsWith("topic.")) {
      return null;
    }
    const owner = getOwner(this);
    const topicController = owner?.lookup?.("controller:topic");
    return (
      topicController?.model ??
      this.router.currentRoute?.attributes?.topic ??
      this.router.currentRoute?.attributes ??
      null
    );
  }

  get currentCategory() {
    return this.router.currentRoute?.attributes?.category ?? null;
  }

  get isOnTopic() {
    return !!this.currentTopic;
  }

  get canReplyToTopic() {
    const t = this.currentTopic;
    if (!t || !this.currentUser) return false;
    if (t.archived || t.closed) return false;

    // Discourse's canonical check — covers permissions, consecutive-reply
    // throttling, post limits, group restrictions, etc. Conservative: if
    // we can't determine the flag, hide the button rather than show a
    // broken one.
    const details = t.details ?? t.get?.("details");
    const flag =
      details?.can_create_post ??
      details?.get?.("can_create_post") ??
      t.can_create_post ??
      t.get?.("can_create_post");

    return flag === true;
  }

  get canCreateTopic() {
    if (!this.currentUser) return false;
    const route = this.router.currentRouteName || "";
    return [
      "discovery.",
      "tag.",
      "tags.",
      "categories",
    ].some((prefix) => route.startsWith(prefix));
  }

  get showCreateButton() {
    return this.isOnTopic ? this.canReplyToTopic : this.canCreateTopic;
  }

  get createButtonIcon() {
    return this.isOnTopic ? "reply" : "plus";
  }

  get createButtonLabel() {
    return this.isOnTopic ? "Reply" : "New topic";
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  @action
  toggleDrawer() {
    this.isDrawerOpen = !this.isDrawerOpen;
  }

  @action
  closeDrawer() {
    this.isDrawerOpen = false;
  }

  // Discourse's outside-close listens on the document at mousedown /
  // pointerdown / touchstart, all of which fire BEFORE `click`. Any of
  // those bubbling from the bell would close an open user menu, and then
  // our click-time proxy would reopen it. Snapshot the panel's open state
  // at pointerdown and stop those events from bubbling to Discourse's
  // outside-close listener. `click` then reads the snapshot to decide
  // whether to toggle (menu was closed → open it) or stay quiet (menu was
  // open → the tap counts as the close).
  _wasMenuOpenAtPointerDown = false;

  @action
  bellPointerDown(event) {
    this._wasMenuOpenAtPointerDown = !!document.querySelector(
      ".user-menu.revamped, .hamburger-panel .user-menu"
    );
    event?.stopPropagation();
  }

  @action
  openDiscourseUserMenu(event) {
    event?.stopPropagation();
    if (this._wasMenuOpenAtPointerDown) {
      // The user tapped the bell to close an open panel. Close it by
      // clicking the native trigger; without the pointerdown short-
      // circuit above, this same click would have re-opened it after
      // outside-close already fired.
      this._wasMenuOpenAtPointerDown = false;
    }
    const btn =
      document.querySelector(
        ".d-header-icons .header-dropdown-toggle.current-user button"
      ) ||
      document.querySelector(".d-header-icons .current-user button") ||
      document.querySelector(".header-dropdown-toggle.current-user button");
    btn?.click();
  }

  @action
  toggleUserDropdown(event) {
    // Stop the click from immediately reaching the outside-click closer.
    event?.stopPropagation();
    this.isUserDropdownOpen = !this.isUserDropdownOpen;
  }

  @action
  closeUserDropdown() {
    this.isUserDropdownOpen = false;
  }

  @action
  toggleTheme() {
    // Mirrors the WP theme's flip: data-theme on <html>, remembered in
    // localStorage. Discourse has its own colour-scheme system that this
    // does NOT touch — kept for visual parity with the WP dropdown and
    // as a stub the theme-parity work can wire into later.
    const root = document.documentElement;
    const next = root.getAttribute("data-theme") === "light" ? "dark" : "light";
    root.setAttribute("data-theme", next);
    try {
      localStorage.setItem("wbo-theme", next);
    } catch {
      // Storage may be blocked (private mode, quota); the DOM flip already
      // gave the click its feedback, so nothing else to do.
    }
  }

  // Base URL for cross-side links back into WordPress. Same TODO as the
  // logo href — swap to https://worldbeyblade.org before deploying.
  get wpBase() {
    return "http://wbo.local";
  }

  // Live counts from Discourse for the pill's activity dot and the
  // dropdown row badges. Names track the fields Discourse exposes on
  // currentUser today; guard everything with `?.` because upgrades have
  // renamed these before.
  get unreadNotifications() {
    const u = this.currentUser;
    return (
      u?.all_unread_notifications_count ??
      u?.unread_notifications ??
      0
    );
  }

  get unreadMessages() {
    return this.currentUser?.unread_private_messages ?? 0;
  }

  get unreadReviewables() {
    return this.currentUser?.reviewable_count ?? 0;
  }

  get hasUserActivity() {
    return (
      this.unreadNotifications > 0 ||
      this.unreadMessages > 0 ||
      this.unreadReviewables > 0
    );
  }

  // Dropdown items, mirroring the WP header's user-menu-dropdown. Order,
  // labels, icons, and the WP/Discourse-side split match WP one-for-one.
  // "Preferences (forum)" was removed from both sides.
  get userDropdownItems() {
    const u = this.currentUser;
    if (!u) return [];
    const username = u.username;
    return [
      {
        key: "tournaments",
        label: "My Tournaments",
        href: `${this.wpBase}/tournaments/?going=1`,
        icon: ICONS.trophy,
        // Tournament count is a WP-side value; skipping for now per plan.
      },
      {
        key: "notifications",
        label: "Notifications",
        href: `/u/${username}/notifications`,
        icon: ICONS.bell,
        count: this.unreadNotifications,
        countVariant: "activity",
      },
      {
        key: "messages",
        label: "Messages",
        href: `/u/${username}/messages`,
        icon: ICONS.envelope,
        count: this.unreadMessages,
        countVariant: "activity",
      },
      {
        key: "settings",
        label: "Settings",
        href: `${this.wpBase}/settings/`,
        icon: ICONS.gear,
      },
    ];
  }

  // Expose the theme-toggle + log-out icons to the template.
  get iconSun() {
    return ICONS.sun;
  }
  get iconMoon() {
    return ICONS.moon;
  }
  get iconLogout() {
    return ICONS.logout;
  }

  @action
  createOrReply() {
    if (this.isOnTopic) {
      const topic = this.currentTopic;
      if (!topic) return;
      this.composer.open({
        action: Composer.REPLY,
        topic,
        draftKey: topic.draft_key,
        draftSequence: topic.draft_sequence,
      });
    } else {
      this.composer.openNewTopic({
        category: this.currentCategory,
      });
    }
  }

  <template>
    {{! ── Desktop nav bar (covers .d-header at same z-level) ──────────── }}
    {{! .wbo-site-nav is the full-bleed fixed bar; .wbo-site-nav__inner
        is the 1200px-max centred content, mirroring WordPress's
        .site-header / .site-header-inner split. }}
    <nav class="wbo-site-nav" aria-label="WBO site navigation">
      <div class="wbo-site-nav__inner">
        {{! TODO: swap back to https://worldbeyblade.org before deploying. }}
        <a href="http://wbo.local" class="wbo-site-nav__logo">
          {{#if this.logoUrl}}
            {{! width/height are intrinsic (natural 512x166) so the browser
                reserves the correct space before the image decodes -- without
                them, the nav links reflow ~89px on every page load. }}
            <img
              src={{this.logoUrl}}
              alt="WBO"
              width="108"
              height="35"
            />
          {{else}}
            <span class="wbo-site-nav__logo-text">WBO</span>
          {{/if}}
        </a>

        <div class="wbo-site-nav__links">
          {{#each this.navItems as |item|}}
            <a
              href={{item.url}}
              class="wbo-site-nav__link {{if item.active 'is-active'}}"
            >{{item.label}}</a>
          {{/each}}
        </div>

        <div class="wbo-site-nav__right">
          {{#if this.currentUser}}
            {{! Pill + custom dropdown — mirrors the WP .user-menu-wrap
                markup so both sides share the same visual language. The
                dropdown links out to WP for tournaments/settings and
                stays on Discourse for notifications/messages/prefs. }}
            <div class="wbo-user-menu-wrap">
              <button
                {{on "click" this.toggleUserDropdown}}
                type="button"
                class="wbo-user-menu-link
                  wbo-user-menu-trigger
                  {{if this.isUserDropdownOpen 'is-open'}}"
                aria-haspopup="true"
                aria-expanded={{if this.isUserDropdownOpen "true" "false"}}
                aria-controls="wbo-user-menu-dropdown"
              >
                <span class="avatar">
                  <img
                    src={{this.userAvatarUrl}}
                    width="32"
                    height="32"
                    alt={{this.currentUser.username}}
                  />
                </span>
                <span
                  class="wbo-user-menu-name"
                >{{this.currentUser.username}}</span>
                <span class="wbo-user-menu-caret" aria-hidden="true">
                  <svg width="10" height="10" viewBox="0 0 10 10" fill="none">
                    <path
                      d="M2 4l3 3 3-3"
                      stroke="currentColor"
                      stroke-width="1.5"
                      stroke-linecap="round"
                      stroke-linejoin="round"
                    />
                  </svg>
                </span>
                {{#if this.hasUserActivity}}
                  <span
                    class="wbo-user-menu-dot"
                    aria-label="You have unread activity"
                  ></span>
                {{/if}}
              </button>

              {{#if this.isUserDropdownOpen}}
                <div
                  class="wbo-user-menu-dropdown"
                  id="wbo-user-menu-dropdown"
                  role="menu"
                >
                  {{#each this.userDropdownItems as |item|}}
                    <a
                      class="wbo-user-menu-item"
                      role="menuitem"
                      href={{item.href}}
                    >
                      <span class="wbo-user-menu-item-icon">{{item.icon}}</span>
                      <span class="wbo-user-menu-item-label">{{item.label}}</span>
                      {{#if item.count}}
                        <span
                          class="wbo-user-menu-item-count
                            {{if item.countVariant (concat 'wbo-user-menu-item-count--' item.countVariant)}}"
                        >{{item.count}}</span>
                      {{/if}}
                    </a>
                  {{/each}}

                  <div class="wbo-user-menu-divider" role="separator"></div>

                  {{! Theme toggle — WP-parity stub; see toggleTheme. Two
                      icons ship (sun/moon); CSS shows the one that names
                      the action a click takes. }}
                  <button
                    {{on "click" this.toggleTheme}}
                    type="button"
                    class="wbo-user-menu-item wbo-user-menu-theme"
                    role="menuitem"
                  >
                    <span class="wbo-user-menu-item-icon">
                      <span class="when-dark">{{this.iconSun}}</span>
                      <span class="when-light">{{this.iconMoon}}</span>
                    </span>
                    <span class="wbo-user-menu-item-label when-dark"
                    >Light mode</span>
                    <span class="wbo-user-menu-item-label when-light"
                    >Dark mode</span>
                  </button>

                  <a
                    class="wbo-user-menu-item wbo-user-menu-item-secondary"
                    role="menuitem"
                    href="/logout"
                  >
                    <span class="wbo-user-menu-item-icon">{{this.iconLogout}}</span>
                    <span class="wbo-user-menu-item-label">Log out</span>
                  </a>
                </div>
              {{/if}}
            </div>

            {{! Bell — always visible; opens Discourse's own user menu
                (notifications tab by default). Sits to the RIGHT of the
                pill per design. pointerdown/mousedown/touchstart are
                intercepted at capture-style timing so Discourse's own
                outside-close (which runs on those events) never fires
                on a bell tap; click alone drives the toggle. }}
            <button
              {{on "pointerdown" this.bellPointerDown}}
              {{on "mousedown" this.bellPointerDown}}
              {{on "touchstart" this.bellPointerDown}}
              {{on "click" this.openDiscourseUserMenu}}
              type="button"
              class="wbo-bell"
              aria-label="Notifications"
            >
              {{icon "bell"}}
            </button>
          {{else}}
            {{! Two-button pair on desktop, matching the WP header. Log in
                is hidden on mobile via SCSS; the drawer carries the pair. }}
            <a href="/signup" class="wbo-site-nav__join">Join Now</a>
            <a href="/login" class="wbo-site-nav__login">Log in</a>
          {{/if}}
        </div>
      </div>
    </nav>

    {{! ── Mobile: hamburger (fixed, overlays Discourse header) ────────── }}
    {{! template-lint-disable no-invalid-interactive }}
    <button
      {{on "click" this.toggleDrawer}}
      type="button"
      class="wbo-hamburger {{if this.isDrawerOpen 'is-open'}}"
      aria-label="Open site navigation"
      aria-expanded={{if this.isDrawerOpen "true" "false"}}
    >
      <span></span><span></span><span></span>
    </button>

    {{! ── Mobile: slide-in drawer ──────────────────────────────────────── }}
    <div
      class="wbo-nav-drawer {{if this.isDrawerOpen 'is-open'}}"
      aria-hidden={{if this.isDrawerOpen "false" "true"}}
    >
      {{! Logo pinned in the drawer's top strip. The WBO nav-bar logo
          sits behind the drawer (z-index 1002 vs 1009) so it's hidden
          when the drawer is open; this fills that empty top strip. }}
      {{! TODO: swap back to https://worldbeyblade.org before deploying. }}
      <a href="http://wbo.local" class="wbo-nav-drawer__logo">
        {{#if this.logoUrl}}
          <img src={{this.logoUrl}} alt="WBO" height="36" />
        {{else}}
          <span class="wbo-nav-drawer__logo-text">WBO</span>
        {{/if}}
      </a>

      <nav>
        {{#each this.navItems as |item|}}
          <a
            href={{item.url}}
            class="wbo-nav-drawer__link {{if item.active 'is-active'}}"
            {{on "click" this.closeDrawer}}
          >{{item.label}}</a>

          {{! Expand Community in place with Latest / Unread / categories.
              Not an accordion — you're already in the section. }}
          {{#if item.isCommunity}}
            <div class="wbo-nav-drawer__community">
              <a
                href="/latest"
                class="wbo-nav-drawer__sublink"
                {{on "click" this.closeDrawer}}
              >
                <span class="wbo-nav-drawer__sublink-label">Latest</span>
                {{! Reuses Discourse's own sidebar dot indicator (same
                    class + icon as the category rows). Existing SCSS
                    override colours it WBO orange. }}
                {{#if this.latestBadge}}
                  <span class="sidebar-section-link-suffix icon unread">
                    {{icon "circle"}}
                  </span>
                {{/if}}
              </a>

              {{#if this.currentUser}}
                <a
                  href="/unread"
                  class="wbo-nav-drawer__sublink"
                  {{on "click" this.closeDrawer}}
                >
                  <span class="wbo-nav-drawer__sublink-label">Unread</span>
                  {{#if this.totalUnread}}
                    <span class="sidebar-section-link-suffix icon unread">
                      {{icon "circle"}}
                    </span>
                  {{/if}}
                </a>
              {{/if}}

              {{! Discourse's category section, restyled by our scss.
                  Reused for counts, permissions, and drift resilience.
                  "All categories" hidden via scss since the sidebar list
                  already surfaces every browseable top-level. }}
              <div class="wbo-nav-drawer__categories">
                <this.CategoriesSection @collapsable={{false}} />
              </div>
            </div>
          {{/if}}
        {{/each}}
      </nav>

      {{#if this.currentUser.admin}}
        {{! Admin isn't in Discourse's mobile user menu, so give staff a
            reachable footer link now that the second toggle is gone. }}
        <a
          href="/admin"
          class="wbo-nav-drawer__admin"
          {{on "click" this.closeDrawer}}
        >Admin</a>
      {{/if}}

      {{#if this.currentUser}}
        <a
          href="/logout"
          class="wbo-nav-drawer__logout"
          {{on "click" this.closeDrawer}}
        >Log out</a>
      {{else}}
        {{! Anonymous drawer footer — Join Now + Log in side by side,
            mirroring the WP drawer's two-button auth row. Sits directly
            after the nav items (no margin-top:auto). }}
        <div class="wbo-nav-drawer__auth">
          <a
            href="/signup"
            class="wbo-nav-drawer__auth-btn wbo-nav-drawer__auth-btn--primary"
            {{on "click" this.closeDrawer}}
          >Join Now</a>
          <a
            href="/login"
            class="wbo-nav-drawer__auth-btn wbo-nav-drawer__auth-btn--secondary"
            {{on "click" this.closeDrawer}}
          >Log in</a>
        </div>
      {{/if}}
    </div>

    {{! ── Mobile: backdrop ─────────────────────────────────────────────── }}
    {{#if this.isDrawerOpen}}
      {{! template-lint-disable no-invalid-interactive }}
      <div
        {{on "click" this.closeDrawer}}
        class="wbo-nav-backdrop"
        role="presentation"
      ></div>
    {{/if}}

    {{! ── Mobile: sticky create/reply button ─────────────────────────── }}
    <div class="wbo-bottom-bar">
      {{#if this.showCreateButton}}
        <button
          {{on "click" this.createOrReply}}
          type="button"
          class="wbo-bottom-bar__create"
          aria-label={{this.createButtonLabel}}
        >
          {{icon this.createButtonIcon}}
        </button>
      {{/if}}
    </div>
  </template>
}
