# AlbumFlow for Lyrion Music Server (beta)

A touch-friendly web interface for [Lyrion Music Server](https://lyrion.org) (LMS) built around a 3D album flow: swipe through your covers, tap one to flip it and see the tracks, play with one tap.

![AlbumFlow](docs/flow.png)

> **Beta.** This is the first public test version. Feedback, bug reports and ideas are very welcome: join the discussion in the **[Lyrion forum thread](https://forums.lyrion.org/forum/user-forums/3rd-party-software/1843884-announce-beta-albumflow-%E2%80%93-touch-web-interface-with-a-3d-album-flow)** or open a GitHub issue.

## Features

- 3D album flow with reflections, A–Z jump bar and position slider; swipe, mouse wheel or arrow keys
- Tap the centre cover to flip it and see the tracks; play, add or insert the whole album; the ⋯ button on a track plays it next or adds it to the queue
- Collections: albums, **artists** (one tile per artist: tap it and their albums slide into the flow, tap beside them to go back; artists with a single album open it right away), albums by artist, recently added, playlists
- Search by album, artist or **song title** (albums containing the song appear in the flow, the track is highlighted when you flip the cover)
- Player selection, volume, play/pause/skip, power, large now-playing view with the queue (tap the cover or title in the bottom bar; optional screensaver)
- **Any source in the flow:** *My Music* (your local files), every music service plugin you have installed (Qobuz, Spotify via Spotty, Deezer, YouTube, …) and *All* (the whole library). For a service its top folders appear under *Collection*; folders open in the flow, albums and playlists flip and play like albums. A *Back* tile at both ends (or the browser/Android back button) goes up one level
- **Radio** as a source: browse TuneIn and your radio plugins in the flow, with flags for countries and languages and cover mosaics for genres and regions
- Opens from Lyrion: an *AlbumFlow* entry in the Material menu (under Settings) and under *Extras* in the classic web interface; the house button in AlbumFlow takes you back to Lyrion
- **TIDAL extras** (with the official TIDAL plugin, nothing patched): favourite tracks in date-added order, your playlists, mixes, suggestions, full TIDAL search, track radio, heart button to add/remove favourites
- Light, dark or automatic look; the accent colour follows the cover of the playing track
- English and German interface (follows the browser language)
- Embeddable: a transparent look made for dashboards such as Home Assistant (see below)
- Single self-contained page, no build step, no extra dependencies

## Installation

AlbumFlow is a normal LMS plugin.

1. In Lyrion open **Settings → Plugins** and scroll to the bottom.
2. Add this repository URL under *Additional repositories*:
   ```
   https://raw.githubusercontent.com/trufy/AlbumFlow/main/repo.xml
   ```
3. Click *Apply*. **AlbumFlow (beta)** now appears in the plugin list. Enable it and restart Lyrion when asked.
4. Open `http://<your-server>:9000/AlbumFlow/` in a browser or on a tablet.

Updates arrive through the normal plugin update mechanism.

## Settings

**Settings → Advanced → AlbumFlow** (or the gear icon in the header):

| Setting | Meaning |
|---|---|
| Library | Which library *My Music* and *All* show, e.g. a virtual library without online duplicates (default: all tracks) |
| Theme | Automatic (follows the device's light/dark mode, default), Light, Dark, or For Home Assistant (transparent, mini player at the top; meant for embedding) |
| Colours from the cover | Light/dark: the accent colour follows the cover of the playing track |
| Colour (Home Assistant theme) | Fixed accent and background colour for the Home Assistant theme: violet, blue, teal, green, orange, red, pink |
| Language | Same as the browser, English or German |
| Screensaver | Seconds without touch before the large now-playing view opens while music plays (0 = off; empty = 30 for Home Assistant, otherwise off) |

The URL parameters below override these per device.

## URL parameters

| Parameter | Example | Meaning |
|---|---|---|
| `player` | `?player=Kitchen` | Preselect a player by name |
| `theme` | `?theme=ha` | `ha` = the Home Assistant / embedded look, `light`, `dark`, empty = automatic |
| `color` | `?color=teal` | Colour of the Home Assistant theme |
| `colors` | `?colors=0` | Colours from the cover off (`1` = on) |
| `lang` | `?lang=en` | Interface language, `en` or `de` (default: browser language) |
| `idle` | `?idle=60` | Seconds without touch before the now-playing screensaver opens (`0` = off; default 30 with `theme=ha`, otherwise off) |

## Home Assistant

AlbumFlow works nicely on a wall tablet as part of a Home Assistant dashboard, embedded with an iframe card and `?theme=ha` (Home Assistant and Lyrion must both be reached over http, or both over https, or the browser blocks the frame):

![AlbumFlow in Home Assistant on a wall tablet](docs/home-assistant.png)

```yaml
type: iframe
url: http://<your-server>:9000/AlbumFlow/index.html?theme=ha&player=<player name>
allow: autoplay
grid_options:
  columns: full
  rows: 9
```

Happy to share the complete dashboard setup (theme, tablet layout): just ask in the forum thread or open an issue.

## Known limitations

- Generic service browsing has been tested with TIDAL, YouTube and Radio (TuneIn) only. Reports for Qobuz, Spotty, Deezer and others are especially welcome.
- Service search fields are not used yet; the search box filters what is shown in the flow (plus the full TIDAL catalogue for TIDAL).
- Other languages than English and German are welcome as contributions.
- Tested with Lyrion 9.x on Windows, TIDAL plugin 1.10, Chrome/Safari/Android WebView.

## Feedback

- [Lyrion forum thread](https://forums.lyrion.org/forum/user-forums/3rd-party-software/1843884-announce-beta-albumflow-%E2%80%93-touch-web-interface-with-a-3d-album-flow)
- [GitHub issues](https://github.com/trufy/AlbumFlow/issues): please include your Lyrion version, browser/device and, for TIDAL issues, the TIDAL plugin version.

## Licence

GPL-2.0, like Lyrion Music Server. See [LICENSE](LICENSE).

Country flags: [flag-icons](https://github.com/lipis/flag-icons) by Panayiotis Lipiridis, MIT licence (see `HTML/AlbumFlow/html/flags/LICENSE.txt`).
