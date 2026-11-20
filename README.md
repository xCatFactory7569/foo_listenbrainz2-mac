# foo_listenbrainz2 (macOS port)

Submits the music you play in foobar2000 for Mac to [ListenBrainz](https://listenbrainz.org)
(or a ListenBrainz-compatible server). Based on
[phw/foo_listenbrainz2](https://github.com/phw/foo_listenbrainz2) (MIT).

* Intel Mac, macOS 13 (Ventura) or newer, foobar2000 v2 for Mac.
* Settings: **Settings > Tools > ListenBrainz 2** (token, API URL, options).
* Toggle: **Playback > Submit to ListenBrainz**.
* Listens are sent after half the track or 4 minutes; failed ones are cached and retried.

Differences from the Windows version: settings live in macOS user defaults (not in the foobar2000 profile), the
"skip tracks matching a query" option is not included yet.

Build: run the "Build macOS component" workflow in the Actions tab.
