<p align="left">
  <img src="http://i.imgur.com/76RElTT.png" alt="Popcorn Time" title="Popcorn Time">
</p>

# Popcorn Time for tvOS · iOS · macOS

[![CI](https://github.com/Ioan-Popovici/PopcornTimeTV/actions/workflows/build.yml/badge.svg)](https://github.com/Ioan-Popovici/PopcornTimeTV/actions/workflows/build.yml)
[![Platform](https://img.shields.io/badge/platform-iOS%2026%20%7C%20tvOS%2026%20%7C%20macOS%2026-lightgrey.svg?style=flat)](#)
[![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg?style=flat)](#)
[![License](https://img.shields.io/badge/license-GPL_v3-373737.svg?style=flat)](LICENSE.md)

PopcornTimeTV is an Apple TV, iPhone, iPad, and Mac application to torrent
movies and TV shows for streaming, written in SwiftUI.

## Requirements

- **Xcode 26** (Swift 6.3 toolchain).
- Deployment targets: **tvOS 26 · iOS 26 · macOS 26**.
- VLCKit binaries fetched on first build (`make vlc-mac` / `vlc-ios` / `vlc-tv`).

## Build & run

The shortest path is the `Makefile`:

```bash
make build-release       # Release macOS .app into ./build/
make run                 # Build and launch
make build-ios           # Debug build for iOS Simulator
make build-tvos          # Debug build for tvOS Simulator
make compare             # Build current + upstream side-by-side
make clean               # Remove ./build and DerivedData
make help                # List every target
```

Or open the project in Xcode and run as usual:

```bash
open PopcornTime.xcodeproj
```

Pick the **PopcornTime (tvOS)**, **PopcornTime (iOS)**, or **PopcornTime (macOS)**
scheme, set your signing team in *Signing & Capabilities*, and hit **Run**.

### Apple TV deployment

1. Pair the device: **Settings → Remotes and Devices → Remote App and Devices**
   on the Apple TV, then add it via **Window → Devices and Simulators** in Xcode.
2. Register the device in [Apple Developer → Certificates, Identifiers &
   Profiles → Devices](https://developer.apple.com/account/resources/devices/list).
3. Change the bundle identifier on **PopcornTime (tvOS)** *and* **TopShelf**
   targets to something unique (e.g. `com.<you>.PopcornTime`).
4. Build & run — the app installs over the network.

To bump VLCKit, edit the version constant in
[`VLCKit/get-vlc-frameworks.sh`](VLCKit/get-vlc-frameworks.sh).

## Architecture (short version)

- **PopcornKit** — Swift Package: REST clients (TMDB, Trakt, OpenSubtitles,
  Fanart, Popcorn, OMDb, DHT) and shared models. Builds in **Swift 6 strict
  concurrency** mode.
- **PopcornTime** — SwiftUI app target with three schemes (one per platform).
  iOS 26 Liquid Glass on player controls, action-button rows, and the macOS
  blur surface.
- **TopShelf** — tvOS extension that surfaces continue-watching content.
- **PopcornTorrent + VLCKit** — torrent streaming + media playback, vendored
  via SwiftPM and a binary drop respectively.

## Continuous integration

[`.github/workflows/build.yml`](.github/workflows/build.yml) builds all three
platforms on every push, every pull request, and on the first of each month.
On a tag push it attaches the `.ipa` (tvOS, iOS) and `.zip` (macOS) artifacts
to the GitHub release. Run the same matrix locally with `make ci-local`.

## License

This program is free software: you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation, either version 3 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but **without
any warranty**; without even the implied warranty of merchantability or
fitness for a particular purpose. See the GNU General Public License for more
details. You should have received a copy of the GPL v3 along with this program;
if not, see <http://www.gnu.org/licenses/>.

External dependencies are governed by their own licenses, listed in
[NOTICE.md](NOTICE.md).

> **This project and the distribution of this project is not illegal, nor does
> it violate _any_ DMCA laws. The use of this project, however, may be illegal
> in your area. Check your local laws and regulations regarding the use of
> torrents to watch potentially copyrighted content. The maintainers of this
> project do not condone the use of this project for anything illegal, in any
> state, region, country, or planet. Please use at your own risk.**

---

Copyright © Popcorn Time Foundation — released under the [GPL V3](LICENSE.md).
