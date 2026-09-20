# AirPods on Sailfish OS

Working battery reporting, noise-control switching and per-device settings for
AirPods, Beats and Galaxy Buds on Sailfish OS, by porting
[MagicPodsCore](https://github.com/steam3d/MagicPodsCore) and adding a native
Silica front end.

This repository is both a set of sources and a step-by-step record of how the
port was done, including the dead ends. Everything here was carried out and
verified on a real device.

## Result

| Feature | Status |
| --- | --- |
| Battery level per earbud and case | Working |
| Noise control switching (off / transparency / adaptive / ANC) | Working |
| Adaptive-mode noise intensity | Working |
| Per-device settings (press speed, conversation awareness, tone volume, ...) | Working |
| Bluetooth profile switching | Working |
| Silica application with cover page | Working |
| Case-open animation (BLE proximity) | Untested |
| RPM package | Not done |

## Test environment

| Component | Version |
| --- | --- |
| Device | Jolla Phone (2026), MediaTek mt6858, aarch64 |
| OS | Sailfish OS 5.2.0.17 "Finlayson" |
| Headphones | AirPods Pro 2 (model `0x2014`, firmware 90.3431000025000000.6807) |
| BlueZ | 5.87 |
| PulseAudio | 17.0 |
| systemd | 238 |
| GCC | 13.4.0 |
| CMake | 3.31.8 |
| OpenSSL | 3.5.7 |
| Qt (for QtWebSockets QML) | 5.5.1 |

Sailfish OS 5.2 ships a surprisingly complete toolchain. The whole daemon was
built natively on the phone; the Sailfish SDK was never needed.

## Architecture: what actually needs porting

The obvious starting point is
[MagicPodsDecky](https://github.com/steam3d/MagicPodsDecky), the Steam Deck
plugin. That is the wrong target. The Decky plugin is a React front end and
nothing more; all the value lives in a git submodule:

```
backend/src/MagicPodsCore -> github.com/steam3d/MagicPodsCore (GPL-3.0)
```

`MagicPodsCore` is a standalone C++20 daemon that:

- talks to BlueZ over D-Bus (`sdbus-c++`) to enumerate and connect devices;
- opens a raw L2CAP socket to PSM `0x1001` — Apple's AAP channel;
- decodes battery, ANC state and roughly a dozen settings;
- exposes all of it as a JSON API over a WebSocket on `127.0.0.1:2020`.

Nothing in it is Steam Deck specific. Porting means packaging this daemon and
writing a front end, not porting a Decky plugin.

The upstream project already ships two front ends, a Decky plugin and a KDE
plasmoid. The plasmoid's `Backend.qml` is 149 lines of plain QtQuick +
QtWebSockets, so it is a far better starting point than the React code. Only
its Plasma/Kirigami UI needs rewriting in Silica.

## Step 0: prove the transport works before anything else

Do not build anything until you know the phone can open Apple's AAP channel.
If `connect()` on PSM `0x1001` fails, the whole project is dead and no amount
of packaging will help.

Pair and connect the headphones first, then find their address:

```sh
busctl --system tree org.bluez
```

Classic BR/EDR devices such as AirPods appear as a bare `dev_XX_XX_...` node
with no GATT services under it. BLE devices (a smartwatch, for example) carry
a large tree of `serviceXXXX/charXXXX` children. AAP runs on the classic link.

Confirm the device:

```sh
dbus-send --system --print-reply --dest=org.bluez \
  /org/bluez/hci1/dev_XX_XX_XX_XX_XX_XX \
  org.freedesktop.DBus.Properties.GetAll string:org.bluez.Device1
```

You want `Connected: true`, `AddressType: public`, and
`0000110b-0000-1000-8000-00805f9b34fb` (A2DP Sink) among the UUIDs. The
`Modalias` field gives vendor and product IDs, for example
`bluetooth:v004Cp2014d215C` — vendor `0x004C` is Apple, product `0x2014` is
AirPods Pro 2.

Then run [`tools/aapconsole.c`](tools/aapconsole.c). It has no dependencies at
all — not even libbluetooth, the `sockaddr_l2` struct is redeclared inline:

```sh
gcc -O2 -Wall -o aapconsole aapconsole.c
./aapconsole 20:15:82:D3:15:DB
```

It opens the L2CAP socket, sends the AAP handshake, decodes battery and
settings frames, and lets you type raw hex frames or shortcuts
(`off`, `anc`, `transparency`, `adaptive`).

Note: Python is a dead end here. Sailfish's `python3` is built without
Bluetooth support, so `socket.BTPROTO_L2CAP` does not exist.

### The AAP handshake

| Purpose | Bytes |
| --- | --- |
| Init | `00 00 04 00 01 00 02 00 00 00 00 00 00 00 00 00` |
| Enable notifications (1) | `04 00 04 00 0f 00 ff ff ef ff` |
| Enable notifications (2) | `04 00 04 00 0f 00 ff ff ff ff` |
| Extended init (Pro 2 / Pro 3 / Pro USB-C / AirPods 4 ANC / Max 2) | `04 00 04 00 4d 00 0e 00 00 00 00 00 00 00` |

The extended init is required on models that support adaptive mode. Without
it, some noise-control values are silently refused.

Byte 4 of an incoming frame is the message type: `0x04` battery, `0x09`
settings, `0x0f` notifications, `0x4b` conversation awareness.

## Prerequisites

Install these on the phone, in this order. Package names follow RPM
convention (`-devel`, not `-dev`):

```sh
devel-su pkcon install cmake
devel-su pkcon install git
devel-su pkcon install make
devel-su pkcon install gcc-c++
devel-su pkcon install systemd-devel
devel-su pkcon install bluez5-libs-devel
devel-su pkcon install pulseaudio-devel
devel-su pkcon install openssl
devel-su pkcon install openssl-devel
devel-su pkcon install qt5-qtdeclarative-import-websockets
```

Three traps worth knowing about:

- **`gcc` and `gcc-c++` are separate packages.** Installing only `gcc` gets you
  through CMake's C compiler check and then fails on the C++ one.
- **`make` is not installed by default.** CMake fails with
  `CMAKE_MAKE_PROGRAM is not set` and, confusingly, also reports the compilers
  as missing.
- **`openssl-devel` will not install until `openssl` is installed.** PackageKit
  reports `Package not found: openssl-devel` rather than naming the unmet
  dependency. The `-devel` package exists in the official Jolla repository;
  the error message is simply misleading.

`pkcon what-provides <file>` does not search repositories on Sailfish, only
installed packages. Use `pkcon search name <term>` instead.

If CMake caches a failed configure, delete the whole `build` directory before
retrying — a stale cache reproduces the original error.

## Building the daemon

```sh
git clone https://github.com/steam3d/MagicPodsCore.git
cd MagicPodsCore
```

Apply the adapter patch (see below), then:

```sh
mkdir build && cd build
cmake -DCMAKE_BUILD_TYPE=Release ..
cmake --build . -j4
```

Configure takes about 25 seconds and requires network access: sdbus-c++ 1.6.0,
uWebSockets 20.58.0, uSockets 0.8.7, nlohmann/json 3.11.3 and toml++ 3.4.0 are
all pulled with `FetchContent` rather than vendored. Compilation takes roughly
fifteen minutes on-device, most of it in sdbus-c++ and uWebSockets.

This `FetchContent` dependency is the main obstacle to RPM packaging: OBS
builds run without network access, so the dependencies must be vendored or
supplied as source tarballs.

### Patch: hardcoded `hci0`

`src/dbus/DBusService.cpp` hardcodes the adapter path:

```cpp
DBusService::DBusService()
    : _rootProxy{sdbus::createProxy("org.bluez", "/")},
      _defaultBluetoothAdapterProxy{sdbus::createProxy("org.bluez", "/org/bluez/hci0")} {
```

On the Jolla Phone 2026 there is no `hci0` at all — the working controller is
`hci1`. The constructor then calls `getProperty("Powered")` on a nonexistent
object, throws, and the process dies before it ever enumerates a device.

[`patches/0001-adapter-discovery.patch`](patches/0001-adapter-discovery.patch)
replaces this with runtime discovery:

- enumerate `GetManagedObjects` and pick the first object exposing
  `org.bluez.Adapter1` with `Powered` true;
- fall back to the first adapter found if none is powered;
- allow an override through `MAGICPODS_ADAPTER=hci1` (or a full object path);
- start without an adapter instead of crashing, with the adapter-dependent
  features disabled;
- add the missing null checks on `EnableBluetoothAdapter`,
  `DisableBluetoothAdapter`, `StopDiscovery` and the four async variants —
  only `SetDiscoveryFilter` and `StartDiscovery` had them.

```sh
git apply 0001-adapter-discovery.patch
```

This is not Sailfish specific. Any machine with two controllers, or where the
first one fails to initialise, hits the same wall. It is a good candidate for
an upstream pull request.

For a quick first build you can instead do
`sed -i 's|/org/bluez/hci0|/org/bluez/hci1|' src/dbus/DBusService.cpp`, but
that only works on your own device.

### Building without OpenSSL

If `openssl-devel` is unavailable, OpenSSL is only used by
`src/sdk/aap/Aes.cpp`, which decrypts BLE advertisements for the case-open
animation. Replace that file with stubs returning `false` and empty vectors,
then delete the `find_package(OpenSSL REQUIRED)` and `OpenSSL::Crypto` lines
from `CMakeLists.txt`. Do not remove the file from the build: other
translation units link against it. Everything except the case-open animation
keeps working.

## Running the daemon as a user service

```sh
mkdir -p ~/.local/bin
cp build/magicpodscore ~/.local/bin/
mkdir -p ~/.config/systemd/user
cp scripts/magicpodscore.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now magicpodscore.service
systemctl --user status magicpodscore.service
```

A **user** service, deliberately: it touches no system file, survives reboot,
and is removed with a single `systemctl --user disable --now`.

The daemon binds port 2020 exclusively and calls `exit(1)` if the bind fails,
so a manually launched instance will keep the service in a restart loop. Check
with `pgrep -a magicpodscore` before blaming anything else.

Reading its journal needs group membership:

```sh
devel-su usermod -a -G systemd-journal $USER
# log out and back in, then
journalctl --user -u magicpodscore -f
```

## The WebSocket API

The daemon speaks JSON over `ws://127.0.0.1:2020`. Full reference in
`api-reference.md` upstream. Sailfish ships neither `websocat` nor `wscat`, so
this repository includes [`tools/wsclient.c`](tools/wsclient.c), a dependency-free
client:

```sh
gcc -O2 -Wall -o wsclient wsclient.c
./wsclient
```

Shortcuts: `all`, `devices`, `info`, `adapter`, `quit`. Anything else is sent
verbatim, so you can paste raw JSON.

**The server pings and closes idle connections after 16 seconds.** A client
that ignores ping frames gets disconnected mid-session, which looks exactly
like a command being silently dropped. `wsclient` answers with pong frames;
any front end must do the same.

Reading state:

```json
{"method":"GetAll"}
```

Writing:

```json
{"method":"SetCapabilities","arguments":{"address":"20:15:82:D3:15:DB","capabilities":{"anc":{"selected":16}}}}
```

`SetCapabilities` returns nothing. Confirmation arrives as an asynchronous
`onCapabilityChanged` broadcast, and **only if the state actually changed**.
Silence means either "already in that mode" or "the device refused". This is
easy to misread as a failure.

### Noise-control values

The `selected` and `options` fields use the daemon's universal flags
(`DeviceAncModes`), not Apple's wire protocol numbering. This tripped us up
for a while:

| Flag | Mode |
| --- | --- |
| 1 | Off |
| 2 | Transparency |
| 4 | Adaptive |
| 8 | Wind cancellation |
| 16 | Noise cancellation |

`options` is a bitmask of the available modes. AirPods Pro 2 report `23`
(1 + 2 + 4 + 16). Build the UI from this mask so other models get the right
buttons.

On this firmware, mode 1 (off) is refused: the earbuds play an error tone and
keep their previous state. That appears to be an Apple restriction, not a port
problem.

### Battery status values

| Value | Meaning |
| --- | --- |
| 0 | Not available — hide |
| 1 | Disconnected — hide |
| 2 | Connected — show |
| 3 | Cached — show as stale |

Show an entry only when `status >= 2`. A single-battery headset reports
`single` and leaves `left`/`right`/`case` at 0.

## The AVRCP volume bug

**This is the part that makes the whole project worth installing.**

Out of the box on Sailfish, AirPods connect, PulseAudio creates the card and
the A2DP sink, streams are routed to it correctly, the sink reaches `RUNNING`
— and no sound comes out. Everything in the stack looks healthy:

```
$ LC_ALL=C pactl list sinks short
5  bluez_sink.20_15_82_D3_15_DB.a2dp_sink  module-bluez5-device.c  s16le 2ch 44100Hz  RUNNING
```

The culprit is the AVRCP absolute volume held by the headphones, which is a
different value from the PulseAudio sink volume:

```sh
dbus-send --system --print-reply --dest=org.bluez \
  /org/bluez/hci1/dev_20_15_82_D3_15_DB/sep1/fd0 \
  org.freedesktop.DBus.Properties.GetAll string:org.bluez.MediaTransport1
```

```
State: "active"
Volume: uint16 0
```

Sailfish's audio policy is built around the handset's own speaker and earpiece
and never pushes an initial AVRCP volume to a Bluetooth sink, so the
headphones stay at their default of zero. The hardware volume keys act on the
PulseAudio sink, which is already at 100 %, so nothing the user can do from
the UI fixes it.

Fix:

```sh
dbus-send --system --print-reply --dest=org.bluez \
  /org/bluez/hci1/dev_20_15_82_D3_15_DB/sep1/fd0 \
  org.freedesktop.DBus.Properties.Set string:org.bluez.MediaTransport1 \
  string:Volume variant:uint16:100
```

The scale is 0 to 127. Once set, the volume keys control it normally.

Find the transport object with `busctl --system tree org.bluez | grep fd`; the
`sepN` index varies.

Automating this — watch for `org.bluez.MediaTransport1` appearing, and raise
the volume if it is zero — is the single most useful thing this application
can do that upstream does not. It is not yet implemented here.

## The Silica application

A pure-QML application: no compilation, no RPM needed to iterate. Install with

```sh
devel-su sh scripts/install-magicpods.sh
sailfish-qml harbour-magicpods
```

Launch from the terminal the first time; QML errors are printed there and are
invisible when launching from the app grid. Expect a lot of unrelated hybris
noise about `libGLES_mali` and `libselinux` — that is normal.

Files land in `/usr/share/harbour-magicpods`, `/usr/share/applications` and
`/usr/share/icons/hicolor`. Removal:

```sh
devel-su rm -rf /usr/share/harbour-magicpods \
  /usr/share/applications/harbour-magicpods.desktop \
  /usr/share/icons/hicolor/*/apps/harbour-magicpods.png
```

The UI is built entirely from the JSON, with no assumptions about any
particular model: battery rows appear only for entries reporting
`status >= 2`, noise-control buttons are generated from the `options` bitmask,
and each advanced setting is hidden when its capability is absent. Galaxy Buds
or a single-battery headset therefore get a correct UI without code changes.

Two QML notes specific to this target:

- Qt is 5.5.1, so `import QtWebSockets 1.0`. The `1.1` import used by the KDE
  plasmoid does not exist here.
- `visible: someVar && someVar.field` evaluates to `undefined` rather than
  `false` while the daemon has not replied yet, and QML rejects it with
  `Unable to assign [undefined] to bool`. Write
  `someVar !== undefined && someVar.field`.

## Repository layout

```
tools/aapconsole.c    Raw AAP console over L2CAP, no dependencies
tools/wsclient.c      WebSocket client for the daemon API, no dependencies
patches/              Adapter discovery patch for MagicPodsCore
scripts/              systemd user unit, application installer
app/                  Silica application sources and icons
```

## Remaining work

- Automate the AVRCP volume fix.
- Vendor the CMake dependencies and build an RPM for Chum.
- Verify service ordering after boot: the unit declares
  `After=bluetooth.target`, which may not exist in a user session.
- Translations; the UI strings are wrapped in `qsTr` but no catalogue exists.
- The icon does not follow Sailfish's icon guidelines.
- Submit the adapter-discovery patch upstream.

## Credits and licence

`MagicPodsCore` and `MagicPodsDecky` are by Aleksandr Maslov and Andrei
Litvintsev, released under GPL-3.0. This work is a port and a front end for
their daemon; all protocol knowledge comes from their code. The upstream
project deliberately separates its core from its front ends, so contributions
belong there where possible.

Everything in this repository is GPL-3.0, to match.
