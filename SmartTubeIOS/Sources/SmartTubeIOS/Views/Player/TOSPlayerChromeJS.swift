#if !os(tvOS)
import Foundation

// MARK: - TOSPlayerChromeJS
//
// Hides YouTube's in-page chrome inside the TOS embed so only the video is
// visible. Uses the same class-agnostic technique as ShortsEmbedJS: hide every
// body descendant with `visibility`, then re-show the `<video>` (and captions)
// with `visibility:visible !important`. This survives YouTube renames and
// stacking-context changes.
//
// Ad safety: when `#movie_player` has the `ad-showing` class, the hider is
// disabled entirely so YouTube's ad UI and Skip Ad button remain usable. The
// native overlay observes the same flag through the tick payload and yields.
enum TOSPlayerChromeJS {
    static let hiderJS: String = """
        (function() {
            if (window === window.top) return;

            var _lastAd = null;

            function ensureStyle() {
                var el = document.getElementById('st-tos-chrome-style');
                if (!el) {
                    var parent = document.head || document.documentElement;
                    if (!parent) return null;
                    el = document.createElement('style');
                    el.id = 'st-tos-chrome-style';
                    parent.appendChild(el);
                }
                return el;
            }

            function apply() {
                var style = ensureStyle();
                if (!style) return;
                var root = document.documentElement;
                if (!root) return;
                var ad = root.classList.contains('st-ad');
                if (_lastAd === ad && style.isConnected) return;
                _lastAd = ad;
                style.textContent = ad ? '' :
                    'html,body{background:#000!important;margin:0!important;padding:0!important}' +
                    'body *{visibility:hidden!important}' +
                    'video{visibility:visible!important;position:fixed!important;top:0!important;left:0!important;' +
                    'width:100%!important;height:100%!important;object-fit:contain!important;background:#000!important}' +
                    // Captions are rendered natively from InnerTube caption
                    // tracks; keep YouTube's own caption container hidden so
                    // the two never double-render.
                    '#movie_player,video{pointer-events:none!important}';
            }

            function syncAd() {
                var root = document.documentElement;
                if (!root) return;
                var p = document.getElementById('movie_player');
                var ad = !!(p && p.classList.contains('ad-showing'));
                if (root.classList.contains('st-ad') !== ad) {
                    root.classList.toggle('st-ad', ad);
                    _lastAd = null;
                    apply();
                }
            }

            function start() {
                apply();
                syncAd();
                var root = document.documentElement;
                if (root) {
                    new MutationObserver(function() {
                        apply();
                        syncAd();
                    }).observe(root, {
                        childList: true,
                        subtree: true,
                        attributes: true,
                        attributeFilter: ['class']
                    });
                }
                setInterval(syncAd, 500);
            }

            if (document.readyState === 'loading') {
                document.addEventListener('DOMContentLoaded', start);
            } else {
                start();
            }
        })();
        """
}
#endif
