import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { on } from "@ember/modifier";
import icon from "discourse/helpers/d-icon";
import { getOwner } from "@ember/application";
import Composer from "discourse/models/composer";
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

  @tracked isDrawerOpen = false;

  constructor() {
    super(...arguments);

    // Close the drawer on any route change — covers taps on category
    // links rendered by Discourse's own CategoriesSection component (we
    // don't own their click handlers) and normal back/forward navigation.
    this.router.on("routeDidChange", this._closeOnRouteChange);
  }

  willDestroy() {
    super.willDestroy?.(...arguments);
    this.router.off("routeDidChange", this._closeOnRouteChange);
  }

  _closeOnRouteChange = () => {
    if (this.isDrawerOpen) {
      this.isDrawerOpen = false;
    }
  };

  // ── Getters ───────────────────────────────────────────────────────────────

  get navItems() {
    // `settings` is the theme-settings global injected into theme JS.
    const raw = settings.nav_items;
    if (raw) {
      try {
        const parsed = JSON.parse(raw);
        if (Array.isArray(parsed) && parsed.length) {
          return parsed;
        }
      } catch {
        // Malformed JSON in the setting -- fall through to the default
        // so the nav never renders empty.
      }
    }
    return DEFAULT_NAV_ITEMS;
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

  @action
  openUserMenu() {
    // Proxy-click Discourse's user menu button (covered by WBO nav, not hidden).
    const btn =
      document.querySelector(
        ".d-header-icons .header-dropdown-toggle.current-user button"
      ) ||
      document.querySelector(".d-header-icons .current-user button") ||
      document.querySelector(".header-dropdown-toggle.current-user button");
    btn?.click();
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
        <a href="https://worldbeyblade.org" class="wbo-site-nav__logo">
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
            {{! Proxy-clicks the Discourse user menu }}
            <button
              {{on "click" this.openUserMenu}}
              type="button"
              class="wbo-site-nav__user-btn"
              aria-label="User menu"
            >
              <img
                src={{this.userAvatarUrl}}
                class="avatar"
                width="32"
                height="32"
                alt={{this.currentUser.username}}
              />
            </button>
          {{else}}
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
      <nav>
        {{#each this.navItems as |item|}}
          <a
            href={{item.url}}
            class="wbo-nav-drawer__link {{if item.active 'is-active'}}"
            {{on "click" this.closeDrawer}}
          >{{item.label}}</a>

          {{! Expand Community in place with the category list. Tapping
              Community routes to /latest; Unread lives in Discourse's
              own pill row (which shows it only when count > 0). Not an
              accordion — you're already in the section. }}
          {{#if item.isCommunity}}
            <div class="wbo-nav-drawer__community">
              {{! Discourse's category section, restyled by our scss.
                  Reused for counts, permissions, and drift resilience. }}
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
