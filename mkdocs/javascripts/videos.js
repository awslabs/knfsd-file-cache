/*
 * Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 *
 * Click-to-play YouTube facades.
 *
 * The cards hook (mkdocs/hooks/cards.py) emits each video as a poster image
 * still wrapped in its original link to YouTube, tagged with data-youtube. An
 * iframe has no poster attribute, so embedding the player up front would always
 * show the uploader's chosen thumbnail; keeping the authored poster and swapping
 * the iframe in on click is the only way to control the holding frame. It also
 * means nothing is requested from YouTube until playback is asked for.
 *
 * Without JavaScript the untouched link still opens the video on YouTube, so
 * this is purely an enhancement.
 */

(function () {
  "use strict";

  // Permissions YouTube's own embed code requests, less the ones a
  // documentation page has no use for.
  var ALLOW =
    "accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope;" +
    " picture-in-picture";

  /* Appended to a claimed poster's accessible name, so the inline playback the
   * badge signals visually is also announced. */
  var PLAY_SUFFIX = " (play video)";

  /* Replace a facade with the real player. autoplay=1 is what makes the single
   * click that swapped the element also start playback. */
  function play(card, videoId) {
    /* The poster is a Markdown image link, so python-markdown wraps it in a
     * paragraph; replace the link inside that paragraph so the frame keeps its
     * 16:9 sizing and the caption below is untouched. */
    var link = card.querySelector("p:first-child > a");
    if (!link) {
      return;
    }

    var frame = document.createElement("iframe");
    frame.src =
      "https://www.youtube-nocookie.com/embed/" +
      encodeURIComponent(videoId) +
      "?autoplay=1&rel=0";
    frame.title = link.querySelector("img")
      ? link.querySelector("img").alt
      : "YouTube video player";
    frame.setAttribute("allow", ALLOW);
    frame.setAttribute("referrerpolicy", "strict-origin-when-cross-origin");
    frame.setAttribute("allowfullscreen", "");
    frame.setAttribute("frameborder", "0");

    link.replaceWith(frame);
    card.classList.remove("video-card--ready");
    frame.focus();
  }

  function init() {
    var cards = document.querySelectorAll("[data-youtube]");

    Array.prototype.forEach.call(cards, function (card) {
      var videoId = card.getAttribute("data-youtube");
      if (!videoId || card.dataset.youtubeReady === "1") {
        return;
      }

      /* The poster link is the accessible control: already focusable and
       * announced, so intercepting it avoids bolting ARIA onto a div. */
      var link = card.querySelector("p:first-child > a");
      if (!link) {
        return;
      }

      /* Guard against double-binding, kept separate from the --ready class so
       * that removing the badge on play cannot re-arm this listener. */
      card.dataset.youtubeReady = "1";

      /* Only now advertise playback, so the badge never appears on a card this
       * script has not wired up. */
      card.classList.add("video-card--ready");

      /* The badge is a CSS pseudo-element, so it is invisible to assistive
       * tech: without this a screen reader would announce a plain link to
       * YouTube while the link in fact plays inline. Extend the name rather
       * than replacing it, so the poster's alt text is still read out.
       *
       * Checked for the suffix first so this is idempotent on its own. The
       * dataset guard above already prevents a second pass, but Material's
       * instant navigation can restore cached markup with the attribute intact,
       * and appending twice would have a screen reader read "(play video) (play
       * video)". */
      var img = link.querySelector("img");
      var label = link.getAttribute("aria-label") || (img && img.alt) || "";
      if (label.slice(-PLAY_SUFFIX.length) !== PLAY_SUFFIX) {
        link.setAttribute("aria-label", (label + PLAY_SUFFIX).trim());
      }

      /* Modified clicks are left alone so "open in new tab" still reaches
       * YouTube. */
      link.addEventListener("click", function (event) {
        if (
          event.metaKey ||
          event.ctrlKey ||
          event.shiftKey ||
          event.altKey ||
          event.button !== 0
        ) {
          return;
        }
        event.preventDefault();
        play(card, videoId);
      });
    });
  }

  /* Material ships instant loading (navigation.instant), which swaps page
   * content without a full reload. document$ re-emits on every such navigation;
   * fall back to DOMContentLoaded when it is unavailable. */
  if (window.document$ && typeof window.document$.subscribe === "function") {
    window.document$.subscribe(init);
  } else if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
