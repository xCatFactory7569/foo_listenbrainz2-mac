# foo_listenbrainz2 (macOS port)

A foobar2000 for Mac component that submits the music you listen to
[ListenBrainz](https://listenbrainz.org) (or a ListenBrainz-compatible server).

## Credits and transparency

This is **not an original design**. It is a macOS port of
[foo_listenbrainz2](https://github.com/phw/foo_listenbrainz2) for Windows:

* The original component was written by **[marc2003](https://github.com/marc2003/)**.
* It is maintained and extended by **[phw](https://github.com/phw)** (Philipp Wolfer).

Their behaviour is what this port reproduces (when a listen is submitted, which tags
and MusicBrainz IDs are sent, the offline cache, the options), and the original
MIT license and copyright notice are kept in `LICENSE.txt`. Many thanks to them for
the excellent Windows component.

**How this port was made:** the macOS code was written by **Claude (an AI assistant made by
Anthropic)** for the repository owner's personal use, not by the original authors and not
by a professional macOS developer. The Windows user interface and networking code could not be
reused, so those parts were rewritten from scratch for macOS (Cocoa preferences page,
Apple networking). For the macOS build setup, the official foobar2000 SDK sample project was
followed, and the open-source Mac Last.fm scrobblers
[zfoxer/foo_scrobbler_mac](https://github.com/zfoxer/foo_scrobbler_mac) and
[JendaT/fb2k-components-mac-suite](https://github.com/JendaT/fb2k-components-mac-suite)
were consulted as references for how Mac components are structured (no code copied).

It comes with no warranty. Please don't report problems with it to the original authors.

## Requirements

Intel Mac, macOS 13 (Ventura) or newer, foobar2000 v2 for Mac.

## Use

* Settings: **Settings > Tools > ListenBrainz 2** (token, API URL, options). Changes save immediately.
* Toggle: **Playback > Submit to ListenBrainz**.
* A listen is sent after half the track or 4 minutes; failed ones are cached and retried.

Differences from the Windows version: settings are stored in macOS user defaults (not in the
foobar2000 profile), and the "skip tracks matching a query" option is not included.

## Build

Run the "Build macOS component" workflow in the Actions tab. The foobar2000 SDK is downloaded
during the build and is not part of this repository.
