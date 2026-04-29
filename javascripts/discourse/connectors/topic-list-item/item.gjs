import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { get } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { service } from "@ember/service";
import ShareTopicModal from "discourse/components/modal/share-topic";
import PluginOutlet from "discourse/components/plugin-outlet";
import TopicExcerpt from "discourse/components/topic-list/topic-excerpt";
import TopicLink from "discourse/components/topic-list/topic-link";
import UnreadIndicator from "discourse/components/topic-list/unread-indicator";
import TopicPostBadges from "discourse/components/topic-post-badges";
import TopicStatus from "discourse/components/topic-status";
import categoryLink from "discourse/helpers/category-link";
import icon from "discourse/helpers/d-icon";
import discourseTags from "discourse/helpers/discourse-tags";
import formatDate from "discourse/helpers/format-date";
import lazyHash from "discourse/helpers/lazy-hash";
import topicFeaturedLink from "discourse/helpers/topic-featured-link";
import { wantsNewWindow } from "discourse/lib/intercept-click";
import { i18n } from "discourse-i18n";

const YOUTUBE_RE =
  /(?:youtube\.com\/watch\?(?:.*&)?v=|youtu\.be\/)([a-zA-Z0-9_-]{11})/;

export default class Item extends Component {
  @service currentUser;
  @service modal;
  @tracked isPlayingVideo = false;

  get youtubeVideoId() {
    const link = this.args.outletArgs.topic.featured_link;
    if (!link) return null;
    const match = link.match(YOUTUBE_RE);
    return match ? match[1] : null;
  }

  get youtubeEmbedUrl() {
    return this.youtubeVideoId
      ? `https://www.youtube.com/embed/${this.youtubeVideoId}?autoplay=1&rel=0`
      : null;
  }

  get newDotText() {
    return this.currentUser?.trust_level > 0
      ? ""
      : i18n("filters.new.lower_title");
  }

  @action
  onTitleFocus(event) {
    event.target.closest(".topic-list-item").classList.add("selected");
  }

  @action
  onTitleBlur(event) {
    event.target.closest(".topic-list-item").classList.remove("selected");
  }

  @action
  openTopic(event) {
    if (
      (event.target.nodeName === "A" && !event.target.closest(".raw-link")) ||
      event.target.closest(".badge-wrapper")
    ) {
      return;
    }

    const { navigateToTopic, topic } = this.args.outletArgs;

    if (wantsNewWindow(event)) {
      window.open(topic.lastUnreadUrl, "_blank");
    } else {
      navigateToTopic(topic, topic.lastUnreadUrl);
    }
  }

  @action
  share(event) {
    event.stopPropagation();
    this.modal.show(ShareTopicModal, {
      model: { topic: this.args.outletArgs.topic },
    });
  }

  @action
  playVideo(event) {
    event.stopPropagation();
    this.isPlayingVideo = true;
  }

  <template>
    {{! template-lint-disable no-invalid-interactive }}
    <div {{on "click" this.openTopic}} class="custom-topic-layout">
      <div class="custom-topic-layout_meta">
        {{#unless @outletArgs.hideCategory}}
          {{#unless @outletArgs.topic.isPinnedUncategorized}}
            <PluginOutlet
              @name="topic-list-before-category"
              @outletArgs={{lazyHash topic=@outletArgs.topic}}
            />
            {{categoryLink @outletArgs.topic.category}}
            <span class="bullet-separator">&bull;</span>
          {{/unless}}
        {{/unless}}

        <span class="custom-topic-layout_meta-posted">
          <span class="custom-topic-layout_meta-posted-by">
            {{i18n (themePrefix "posted_by")}}
          </span>

          <a
            data-user-card={{get @outletArgs "topic.posters.0.user.username"}}
            href="/u/{{get @outletArgs 'topic.posters.0.user.username'}}"
          >@{{get @outletArgs "topic.posters.0.user.username"}}</a>

          {{formatDate
            @outletArgs.topic.createdAt
            format="medium"
            noTitle="true"
            leaveAgo="true"
          }}
        </span>
      </div>

      <h2 class="link-top-line">
        <TopicStatus @topic={{@outletArgs.topic}} />

        <TopicLink
          {{on "focus" this.onTitleFocus}}
          {{on "blur" this.onTitleBlur}}
          @topic={{@outletArgs.topic}}
          class="raw-link raw-topic-link"
        />

        {{#if @outletArgs.topic.featured_link}}
          {{topicFeaturedLink @outletArgs.topic}}
        {{/if}}

        <PluginOutlet
          @name="topic-list-after-title"
          @outletArgs={{lazyHash topic=@outletArgs.topic}}
        />

        <UnreadIndicator @topic={{@outletArgs.topic}} />

        {{#if @outletArgs.showTopicPostBadges}}
          <TopicPostBadges
            @unreadPosts={{@outletArgs.topic.unread_posts}}
            @unseen={{@outletArgs.topic.unseen}}
            @newDotText={{this.newDotText}}
            @url={{@outletArgs.topic.lastUnreadUrl}}
          />
        {{/if}}
      </h2>

      <div class="link-bottom-line">
        {{discourseTags
          @outletArgs.topic
          mode="list"
          tagsForUser=@outletArgs.tagsForUser
        }}
      </div>

      {{#if @outletArgs.topic.thumbnails}}
        <div class="custom-topic-layout_image">
          {{#if this.isPlayingVideo}}
            <div class="youtube-embed">
              <iframe
                src={{this.youtubeEmbedUrl}}
                allow="autoplay; encrypted-media; picture-in-picture"
                allowfullscreen={{true}}
                title="YouTube video"
              ></iframe>
            </div>
          {{else if this.youtubeVideoId}}
            {{! template-lint-disable no-invalid-interactive }}
            <div
              {{on "click" this.playVideo}}
              class="youtube-thumbnail"
              role="button"
              aria-label="Play video"
            >
              <img
                height={{get @outletArgs "topic.thumbnails.0.height"}}
                width={{get @outletArgs "topic.thumbnails.0.width"}}
                src={{get @outletArgs "topic.thumbnails.0.url"}}
                alt=""
              />
              <div class="youtube-play-btn" aria-hidden="true">
                <svg viewBox="0 0 68 48" xmlns="http://www.w3.org/2000/svg">
                  <path
                    d="M66.52 7.74c-.78-2.93-2.49-5.41-5.42-6.19C55.79.13 34 0 34 0S12.21.13 6.9 1.55c-2.93.78-4.63 3.26-5.42 6.19C.06 13.05 0 24 0 24s.06 10.95 1.48 16.26c.78 2.93 2.49 5.41 5.42 6.19C12.21 47.87 34 48 34 48s21.79-.13 27.1-1.55c2.93-.78 4.64-3.26 5.42-6.19C67.94 34.95 68 24 68 24s-.06-10.95-1.48-16.26z"
                    fill="#f00"
                  />
                  <path d="M45 24 27 14v20z" fill="#fff" />
                </svg>
              </div>
            </div>
          {{else}}
            <img
              height={{get @outletArgs "topic.thumbnails.0.height"}}
              width={{get @outletArgs "topic.thumbnails.0.width"}}
              src={{get @outletArgs "topic.thumbnails.0.url"}}
              alt=""
            />
          {{/if}}
        </div>
      {{/if}}

      {{#unless @outletArgs.topic.thumbnails}}
        <div class="custom-topic-layout_excerpt">
          <TopicExcerpt @topic={{@outletArgs.topic}} />
        </div>
      {{/unless}}

      <div class="custom-topic-layout_bottom-bar">
        <span class="reply-count">
          {{icon "reply"}}
          {{@outletArgs.topic.replyCount}}
          {{i18n "replies"}}
        </span>

        {{! template-lint-disable no-invalid-interactive }}
        <span {{on "click" this.share}} class="share-toggle">
          {{icon "link"}}
          {{i18n "post.quote_share"}}
        </span>
      </div>
    </div>
  </template>
}
