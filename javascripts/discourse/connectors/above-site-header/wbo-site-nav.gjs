import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { on } from "@ember/modifier";
import icon from "discourse/helpers/d-icon";
import { getOwner } from "@ember/application";
import Composer from "discourse/models/composer";

const NAV_ITEMS = [
  { label: "Tournaments", url: "https://worldbeyblade.org/tournaments/" },
  { label: "Leagues", url: "https://leaderboard.fighting-spirits.org/" },
  {
    label: "Rules & Resources",
    url: "https://worldbeyblade.org/rules/beyblade-x-rules/",
  },
  { label: "Forums", url: "/", active: true },
  { label: "About WBO", url: "#" },
];

export default class WboSiteNav extends Component {
  @service router;
  @service currentUser;
  @service siteSettings;
  @service composer;

  @tracked isDrawerOpen = false;
  @tracked isDiscourseSidebarOpen = false;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  constructor() {
    super(...arguments);
    // Watch for Discourse's mobile sidebar dropdown mounting/unmounting so
    // we can render a click-blocking backdrop while it's open.
    this._sidebarObserver = new MutationObserver(() => {
      this.isDiscourseSidebarOpen = !!document.querySelector(
        ".sidebar-hamburger-dropdown"
      );
    });
    this._sidebarObserver.observe(document.body, {
      childList: true,
      subtree: true,
    });
  }

  willDestroy() {
    super.willDestroy?.(...arguments);
    this._sidebarObserver?.disconnect();
  }

  // ── Getters ───────────────────────────────────────────────────────────────

  get bodyElement() {
    return document.body;
  }

  get logoUrl() {
    // Discourse stores the logo as a site setting; fall back to DOM if needed
    return (
      this.siteSettings.logo_url ||
      this.siteSettings.logo ||
      document.querySelector(".d-header .logo img")?.src ||
      null
    );
  }

  get userAvatarUrl() {
    return this.currentUser?.avatar_template?.replace("{size}", "45") ?? null;
  }

  get activeNavLabel() {
    const route = this.router.currentRouteName || "";

    // Topic page — show the topic's category as context
    if (route.startsWith("topic.")) {
      const attrs = this.router.currentRoute?.attributes;
      return attrs?.topic?.category?.name ?? attrs?.category?.name ?? "Topic";
    }

    // User-area top-level sidebar sections (collapse all sub-routes)
    if (route.startsWith("userPrivateMessages")) return "My messages";
    if (route.startsWith("userActivity")) return "Activity";
    if (route.startsWith("userNotifications")) return "Notifications";
    if (route.startsWith("userInvited")) return "Invites";
    if (route.startsWith("preferences")) return "Preferences";
    if (route.startsWith("user.summary")) return "Summary";
    if (route.startsWith("user.")) return "Profile";

    // Other top-level sidebar destinations
    if (route.startsWith("review")) return "Review";
    if (route.startsWith("badges")) return "Badges";
    if (route.startsWith("groups")) return "Groups";
    if (route.startsWith("admin")) return "Admin";
    if (route.startsWith("full-page-search") || route === "search") {
      return "Search";
    }

    // Tag pages
    if (route.startsWith("tag.") || route.startsWith("tags.")) {
      const tag = this.router.currentRoute?.params?.tag_id;
      return tag ? `#${tag}` : "Tags";
    }

    // Category-scoped discovery
    if (route.startsWith("discovery.category")) {
      return this.router.currentRoute?.attributes?.category?.name ?? "Category";
    }

    // Discovery filters (latest/hot/top/new/unread/read/posted/bookmarks)
    if (route.startsWith("discovery.")) {
      const tail = route.slice("discovery.".length).toLowerCase();
      if (tail.startsWith("latest")) return "Latest";
      if (tail.startsWith("hot")) return "Hot";
      if (tail.startsWith("top")) return "Top";
      if (tail.startsWith("unread")) return "Unread";
      if (tail.startsWith("new")) return "New";
      if (tail.startsWith("read")) return "Read";
      if (tail.startsWith("posted")) return "My posts";
      if (tail.startsWith("bookmarks")) return "Bookmarks";
      if (tail.startsWith("categories")) return "Categories";
    }

    return "Topics";
  }

  // ── Create / reply context ────────────────────────────────────────────────

  get currentTopic() {
    const route = this.router.currentRouteName || "";
    if (!route.startsWith("topic.")) {
      return null;
    }
    // The topic controller's model is the live topic with `details` populated.
    // Falls back to router attributes for early renders.
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
    // throttling, post limits, group restrictions, etc. Be conservative:
    // if we can't determine the flag, hide the button rather than show a
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
  toggleSidebar() {
    // Desktop uses .header-sidebar-toggle; mobile uses the hamburger dropdown
    // in .d-header-icons. Try each in order.
    const btn =
      document.querySelector(".header-sidebar-toggle button") ||
      document.querySelector(
        ".d-header-icons .header-dropdown-toggle.hamburger-dropdown button"
      ) ||
      document.querySelector(".hamburger-dropdown button") ||
      document.querySelector(".hamburger-dropdown");
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
    <nav class="wbo-site-nav" aria-label="WBO site navigation">
      <a href="https://worldbeyblade.org" class="wbo-site-nav__logo">
        {{#if this.logoUrl}}
          <img src={{this.logoUrl}} alt="WBO" height="36" />
        {{else}}
          <span class="wbo-site-nav__logo-text">WBO</span>
        {{/if}}
      </a>

      <div class="wbo-site-nav__links">
        {{#each NAV_ITEMS as |item|}}
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
        {{#each NAV_ITEMS as |item|}}
          <a
            href={{item.url}}
            class="wbo-nav-drawer__link {{if item.active 'is-active'}}"
            {{on "click" this.closeDrawer}}
          >{{item.label}}</a>
        {{/each}}
      </nav>
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

    {{! ── Mobile: backdrop for Discourse's sidebar dropdown ────────────── }}
    {{! Portalled to <body> so it isn't trapped in any wrapper's stacking
        context and reliably sits at the global z-index we want. }}
    {{#if this.isDiscourseSidebarOpen}}
      {{#in-element this.bodyElement}}
        {{! template-lint-disable no-invalid-interactive }}
        <div
          {{on "click" this.toggleSidebar}}
          class="wbo-discourse-sidebar-backdrop"
          role="presentation"
        ></div>
      {{/in-element}}
    {{/if}}

    {{! ── Mobile: sticky bottom bar ────────────────────────────────────── }}
    <div class="wbo-bottom-bar">
      <button
        {{on "click" this.toggleSidebar}}
        type="button"
        class="wbo-bottom-bar__nav"
        aria-label="Open sidebar"
      >
        {{icon "angles-right"}}
        <span class="wbo-bottom-bar__label">{{this.activeNavLabel}}</span>
      </button>

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
