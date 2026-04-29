import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { on } from "@ember/modifier";
import icon from "discourse/helpers/d-icon";

const NAV_ITEMS = [
  { label: "Tournaments", url: "https://worldbeyblade.org/tournaments/" },
  {
    label: "Leagues",
    url: "https://leaderboard.fighting-spirits.org/",
  },
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

  @tracked isDrawerOpen = false;

  get activeNavLabel() {
    const route = this.router.currentRouteName || "";

    if (route.startsWith("topic.")) {
      const attrs = this.router.currentRoute?.attributes;
      return (
        attrs?.topic?.category?.name || attrs?.category?.name || "Topic"
      );
    }

    if (route.includes("category")) {
      const attrs = this.router.currentRoute?.attributes;
      return attrs?.category?.name || "Category";
    }

    if (route.includes("tag")) {
      const params = this.router.currentRoute?.params;
      return params?.tag_id ? `#${params.tag_id}` : "Tag";
    }

    if (route.includes("latest")) return "Latest";
    if (route.includes("hot")) return "Hot";
    if (route.includes("top")) return "Top";
    if (route.includes("unread")) return "Unread";
    if (route.includes("new")) return "New";

    return "Topics";
  }

  @action
  toggleDrawer() {
    this.isDrawerOpen = !this.isDrawerOpen;
  }

  @action
  closeDrawer() {
    this.isDrawerOpen = false;
  }

  @action
  toggleSidebar() {
    document.querySelector(".btn.header-sidebar-toggle")?.click();
  }

  @action
  createTopic() {
    document.querySelector("#create-topic")?.click();
  }

  <template>
    {{! ── Desktop nav bar ──────────────────────────────────────────────── }}
    <nav class="wbo-site-nav" aria-label="WBO site navigation">
      {{#each NAV_ITEMS as |item|}}
        <a
          href={{item.url}}
          class="wbo-site-nav__link {{if item.active 'is-active'}}"
        >{{item.label}}</a>
      {{/each}}
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

    {{! ── Mobile: sticky bottom bar ────────────────────────────────────── }}
    <div class="wbo-bottom-bar">
      <button
        {{on "click" this.toggleSidebar}}
        type="button"
        class="wbo-bottom-bar__nav"
        aria-label="Open sidebar"
      >
        {{icon "bars"}}
        <span class="wbo-bottom-bar__label">{{this.activeNavLabel}}</span>
        {{icon "chevron-up"}}
      </button>

      {{#if this.currentUser}}
        <button
          {{on "click" this.createTopic}}
          type="button"
          class="wbo-bottom-bar__create"
          aria-label="New topic"
        >
          {{icon "pencil-alt"}}
        </button>
      {{/if}}
    </div>
  </template>
}
