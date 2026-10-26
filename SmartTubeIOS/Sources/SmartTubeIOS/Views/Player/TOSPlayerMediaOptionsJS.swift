#if !os(tvOS)
import Foundation

// MARK: - TOSPlayerMediaOptionsJS
//
// Injected into the YouTube embed iframe at document end. Exposes a small,
// JSON-serialisable facade over the player's internal media-option methods.
//
// The TV-UA embed does not expose the web player's documented IFrame API, so
// these are the same internal `movie_player` methods the web player uses. The
// helper is deliberately defensive: every call is wrapped in try/catch and
// returns `{ supported: false }`/`false` when the TV player does not implement
// the corresponding method. The native overlay then hides/disables that
// picker instead of shipping a silent no-op.
enum TOSPlayerMediaOptionsJS {
    static let helperJS: String = """
        (function() {
            if (window === window.top) return;

            var QUALITY_LABEL = {
                highres: '4320p', hd2160: '2160p', hd1440: '1440p',
                hd1080: '1080p', hd720: '720p', large: '480p',
                medium: '360p', small: '240p', tiny: '144p'
            };
            var QUALITY_HEIGHT = {
                highres: 4320, hd2160: 2160, hd1440: 1440,
                hd1080: 1080, hd720: 720, large: 480,
                medium: 360, small: 240, tiny: 144
            };

            function player() {
                return document.getElementById('movie_player');
            }

            function qualityLabel(id) {
                return QUALITY_LABEL[id] || id;
            }

            function qualityHeight(id) {
                return QUALITY_HEIGHT[id] || 0;
            }

            function safeJSON(value) {
                try { return JSON.stringify(value); } catch (e) { return String(value); }
            }

            // Some YouTube objects expose display names as `{simpleText: "…"}`
            // or `{runs: [{text: "…"}]}` instead of a plain string. Normalise
            // every shape the player uses.
            function textOf(value) {
                if (value === null || value === undefined) return '';
                if (typeof value === 'string') return value;
                if (typeof value === 'number' || typeof value === 'boolean') return String(value);
                if (Array.isArray(value.runs)) {
                    return value.runs.map(function(r) { return textOf(r && r.text); }).join('');
                }
                if (typeof value === 'object') return value.simpleText || value.text || value.name || '';
                return String(value);
            }

            // `getAvailableAudioTracks()` returns `PlayerAudioTrack` objects whose
            // localized label and BCP-47-ish id ("en.4", "de-DE.2") are only
            // reachable through `getLanguageInfo()`. The plain track object often
            // carries just an opaque content id, which is why labels used to fall
            // back to "Audio N" with a cryptic subtitle.
            function languageInfoOf(track) {
                try {
                    if (track && typeof track.getLanguageInfo === 'function') {
                        var info = track.getLanguageInfo();
                        if (info) {
                            return {
                                id: textOf(info.id) || '',
                                name: textOf(info.name) || '',
                                isDefault: !!(info.isDefault || info.default)
                            };
                        }
                    }
                } catch (e) {}
                return null;
            }

            // The TV embed's getAvailableAudioTracks() sometimes omits
            // languageName/displayName. The player response's adaptiveFormats
            // carry an audioTrack object with the localized displayName; build a
            // lookup keyed by every id that might match a track ("en.4") plus its
            // language prefix ("en") as a last resort.
            function audioDisplayNames(p) {
                var names = {};
                try {
                    var pr = p.getPlayerResponse ? p.getPlayerResponse() : null;
                    var formats = (pr && pr.streamingData && pr.streamingData.adaptiveFormats) || [];
                    for (var i = 0; i < formats.length; i++) {
                        var at = formats[i].audioTrack;
                        if (at && at.id) {
                            var display = textOf(at.displayName) || textOf(at.languageName);
                            if (display) {
                                names[at.id] = display;
                                var base = String(at.id).split('.')[0];
                                if (base && !names[base]) { names[base] = display; }
                            }
                        }
                    }
                } catch (e) {}
                return names;
            }

            // Authoritative live state. `video.duration === Infinity` is NOT a
            // reliable signal in the TV embed, so read the player response:
            //   videoDetails.isLive            → true only while live
            //   liveBroadcastDetails.isLiveNow → true only while live
            //   isLiveContent                  → true for any broadcast (sticky)
            // Returns true/false, or null when neither the player response nor
            // getVideoData() exposes a live flag (caller falls back to duration).
            function getLive() {
                var p = player();
                if (!p) return null;
                try {
                    var pr = (typeof p.getPlayerResponse === 'function') ? p.getPlayerResponse() : null;
                    if (pr) {
                        var d = pr.videoDetails || {};
                        if (typeof d.isLive === 'boolean') return d.isLive;
                        var mf = pr.microformat && pr.microformat.playerMicroformatRenderer;
                        var lb = mf && mf.liveBroadcastDetails;
                        if (lb && typeof lb.isLiveNow === 'boolean') return lb.isLiveNow;
                        if (typeof d.isLiveContent === 'boolean') {
                            return d.isLiveContent && String(d.lengthSeconds || '0') === '0';
                        }
                    }
                } catch (e) {}
                try {
                    if (typeof p.getVideoData === 'function') {
                        var vd = p.getVideoData();
                        if (vd && typeof vd.isLive === 'boolean') return vd.isLive;
                    }
                } catch (e) {}
                return null;
            }

            window.__stPlayerAPI = {
                getLive: getLive,
                getOptions: function() {
                    var p = player();
                    if (!p) return { supported: false };

                    var out = {
                        supported: true,
                        quality: null,
                        qualities: [],
                        captions: [],
                        caption: null,
                        audioTracks: [],
                        audioTrack: null
                    };

                    try {
                        if (p.getAvailableQualityLevels) {
                            var levels = p.getAvailableQualityLevels() || [];
                            out.qualities = levels.map(function(q) {
                                return { id: q, label: qualityLabel(q), height: qualityHeight(q) };
                            });
                        }
                        if (p.getPlaybackQuality) {
                            out.quality = p.getPlaybackQuality() || null;
                        }
                    } catch (e) {
                        out.qualities = [];
                    }

                    try {
                        if (p.loadModule) { p.loadModule('captions'); }
                        var tracks = (p.getOption ? p.getOption('captions', 'tracklist') : null) || [];
                        // The TV embed often does not populate the captions
                        // module's tracklist, but the current audio track does
                        // carry its captionTracks. Fall back to those so the
                        // picker still works when InnerTube is unavailable.
                        if (tracks.length === 0 && typeof p.getAudioTrack === 'function') {
                            try {
                                var currentAudio = p.getAudioTrack();
                                if (currentAudio && currentAudio.captionTracks
                                    && currentAudio.captionTracks.length > 0) {
                                    tracks = currentAudio.captionTracks;
                                }
                            } catch (e) {}
                        }
                        window.__stCaptionTracks = tracks;
                        // The player response carries the signed timedtext URL
                        // (baseUrl) for each caption track. The getOption list
                        // only has language metadata, so merge by vssId/lang.
                        var prTracks = [];
                        try {
                            var pr = p.getPlayerResponse ? p.getPlayerResponse() : null;
                            prTracks = (pr && pr.captions && pr.captions.playerCaptionsTracklistRenderer
                                && pr.captions.playerCaptionsTracklistRenderer.captionTracks) || [];
                        } catch (e) {}
                        function baseUrlFor(t) {
                            var vss = t.vssId || '';
                            var lang = t.languageCode || '';
                            for (var j = 0; j < prTracks.length; j++) {
                                var pt = prTracks[j];
                                if ((vss && pt.vssId === vss) || (!vss && lang && pt.languageCode === lang)) {
                                    return pt.baseUrl || pt.baseURL || '';
                                }
                            }
                            return '';
                        }
                        out.captions = tracks.map(function(t, i) {
                            var vss = t.vssId || '';
                            return {
                                index: i,
                                id: vss || t.languageCode || String(i),
                                name: textOf(t.displayName) || textOf(t.languageName)
                                    || textOf(t.name) || textOf(t.trackName)
                                    || textOf(t.languageCode) || ('Track ' + (i + 1)),
                                languageCode: textOf(t.languageCode),
                                isAutoGenerated: (vss.indexOf('a.') === 0) || t.kind === 'asr',
                                baseUrl: baseUrlFor(t) || t.url || ''
                            };
                        });
                        var current = p.getOption ? p.getOption('captions', 'track') : null;
                        out.caption = (current && current.vssId) ? current.vssId : null;
                    } catch (e) {
                        window.__stCaptionTracks = [];
                        out.captions = [];
                    }

                    try {
                        var audio = (p.getAvailableAudioTracks ? p.getAvailableAudioTracks() : null) || [];
                        window.__stAudioTracks = audio;
                        var audioNames = audioDisplayNames(p);
                        out.audioTracks = audio.map(function(t, i) {
                            var info = languageInfoOf(t);
                            var id = (info && info.id) || t.audioTrackId || t.id || String(i);
                            var display = (info && info.name)
                                || textOf(t.displayName) || textOf(t.languageName)
                                || textOf(t.name) || textOf(t.label) || textOf(t.title)
                                || audioNames[id] || audioNames[t.audioTrackId] || audioNames[t.id]
                                || textOf(t.languageCode) || '';
                            return {
                                index: i,
                                id: id,
                                name: display,
                                languageCode: textOf(t.languageCode) || textOf(t.lang) || '',
                                isOriginal: !!(t.isDefault || t.default
                                    || t.audioIsDefault || (info && info.isDefault))
                            };
                        });
                        // Raw shape for diagnostics — the TV embed's track
                        // objects differ from the web player's, so log them
                        // when labels fall back to "Audio N".
                        out.rawAudio = safeJSON(audio);
                        var currentAudio = p.getAudioTrack ? p.getAudioTrack() : null;
                        out.audioTrack = (currentAudio && (currentAudio.id || currentAudio.audioTrackId)) || null;
                        out.rawCurrentAudio = safeJSON(currentAudio);
                    } catch (e) {
                        window.__stAudioTracks = [];
                        out.audioTracks = [];
                    }

                    return out;
                },

                setQuality: function(id) {
                    var p = player();
                    if (!p) return false;
                    try {
                        if (id === 'auto' || id === 'default') {
                            if (p.setPlaybackQualityRange) {
                                p.setPlaybackQualityRange('default');
                            } else if (p.setPlaybackQuality) {
                                p.setPlaybackQuality('default');
                            }
                        } else {
                            if (p.setPlaybackQualityRange) {
                                p.setPlaybackQualityRange(id, id);
                            } else if (p.setPlaybackQuality) {
                                p.setPlaybackQuality(id);
                            }
                        }
                        return true;
                    } catch (e) {
                        return false;
                    }
                },

                setCaption: function(index) {
                    var p = player();
                    if (!p) return false;
                    try {
                        if (p.loadModule) { p.loadModule('captions'); }
                        if (index < 0) {
                            if (p.setOption) {
                                p.setOption('captions', 'track', {});
                            } else if (p.toggleCaptions) {
                                var current = p.getOption ? p.getOption('captions', 'track') : null;
                                if (current) { p.toggleCaptions(); }
                            }
                        } else {
                            var track = (window.__stCaptionTracks || [])[index];
                            if (!track) return false;
                            if (p.setOption) {
                                p.setOption('captions', 'track', track);
                            } else if (p.toggleCaptions) {
                                p.toggleCaptions();
                            }
                        }
                        return true;
                    } catch (e) {
                        return false;
                    }
                },

                setAudioTrack: function(index) {
                    var p = player();
                    if (!p) return false;
                    try {
                        var track = (window.__stAudioTracks || [])[index];
                        if (!track || !p.setAudioTrack) return false;
                        p.setAudioTrack(track);
                        return true;
                    } catch (e) {
                        return false;
                    }
                }
            };
        })();
        """
}
#endif
