# Teleport — running it on a physical iPhone

How to build the app onto a real iPhone and override the GPS location that **every**
app on the device sees — Apple Maps, Google Maps, Waze, anything.

Verified against iPhone 15 Pro on iOS 26.5, Xcode 26.6, macOS 26.

---

## Why there are two pieces

An iOS app cannot change its own device's system location. There is no public or
private API for it, and Developer Mode doesn't grant one — only a jailbreak-level
tweak could, and none exists for iOS 26.5.

What Developer Mode *does* unlock is Apple's location-simulation developer service
(`DTSimulateLocation`). A coordinate pushed through that service applies system-wide.
It has to come from a trusted computer, so this project is split in two:

| Piece | Where it runs | Job |
| --- | --- | --- |
| Teleport app | your iPhone | pick a place; show what the device reports |
| `agent/teleportd.py` | your Mac | hold the location channel open and apply the coordinate |

The app finds the agent over Bonjour on your Wi-Fi and sends it the coordinate.

**The consequence to understand up front:** the simulated location lasts only while the
agent is running and the phone is connected. `pymobiledevice3`'s own CLI blocks on a
"press Enter" prompt after setting a location for exactly this reason — closing the
channel ends the simulation. The agent is therefore a resident process that holds the
channel open and re-asserts the coordinate every 25 seconds. Quit it, unplug, or reboot
the phone and the real GPS comes straight back. You cannot walk around town as a
Berliner without the Mac.

---

## One-time setup

### 1. Python tooling

Already installed at `~/.fake-location-venv`. To recreate it:

```bash
python3 -m venv ~/.fake-location-venv
~/.fake-location-venv/bin/pip install pymobiledevice3
```

Use an **x86_64** Python if you have both Homebrews. `zeroconf` compiles its C
extension for the native arch and fails to load in an Intel venv, which is why the
agent uses macOS's own `dns-sd` for Bonjour and needs no extra packages.

### 2. Signing

The project ships with no signing team, so this is required even for personal use.

1. Xcode → **Settings → Accounts → + → Apple ID**. A free account is enough; nothing
   here needs a paid membership.
2. Open `fake-location.xcodeproj`, select the **fake-location** target →
   **Signing & Capabilities** → set **Team** to your Personal Team.

Bundle identifier is `com.amirrezajamali.teleport`. If Xcode says it's already taken,
change it to anything else unique.

### 3. Phone preparation

- Developer Mode on: **Settings → Privacy & Security → Developer Mode**.
- Connect by USB, unlock, and tap **Trust This Computer**.

---

## Install the app

1. Pick your iPhone in Xcode's destination menu and press **⌘R**.
2. On a free account the first launch fails with an untrusted-developer error. On the
   phone: **Settings → General → VPN & Device Management** → your Apple ID → **Trust**.
   Then run again.
3. Approve both first-launch prompts:
   - **Local Network** — mandatory. Without it the app can never find your Mac, and
     there is no second prompt; you'd have to re-enable it under Settings → Teleport.
   - **Location** — optional, but it's how you see your own dot land in Berlin.

---

## Teleport

### 1. Start the agent

Leave this running in a Terminal window:

```bash
cd /Volumes/NVME/iOS-apps/fake-location/fake-location
./agent/start.sh
```

It brings up the developer tunnel (asking for your password, since creating the tunnel
interface needs root), waits for it to answer, then starts the agent:

```
The developer tunnel needs administrator rights to start.
Password:
Waiting for the tunnel..... — up.

Plug in your iPhone, unlock it, and open Teleport.
Both devices must be on the same Wi-Fi for the app to find this Mac.

12:19:02  listening on port 52518, advertised as 'Teleport Agent'
12:19:02  ready
```

That last line is the one that matters: `ready` means the phone is attached and the
location channel is open. `tunnelOffline` or `noDevice` instead means see the
troubleshooting table below.

### 2. Check both connections are live

This is the step that trips people up. You need **two** links at the same time:

- **USB cable** — carries the developer tunnel to the device. Required for the first
  pairing only; after that it can go entirely (see [going fully
  wireless](#going-fully-wireless)).
- **Same Wi-Fi network** — how the app discovers the agent, and how the tunnel keeps
  working once the cable is out. This one is never optional.

### 3. Go

1. Open Teleport. Wait for the status pill to turn green and read **Ready**.
2. Pick a city from the carousel, search for anywhere, or just drag the map — the
   crosshair is what you're aiming at.
3. Tap **Teleport**. The pill changes to **In Berlin**.

### 4. Verify

Open Apple Maps or Google Maps and tap its locate button. You should be in Berlin.

### 5. Go back

Either tap the pin-slash button in the app, or press `Ctrl-C` in the agent's terminal.
Both restore the real GPS.

---

## When something doesn't work

Tap the status pill in the app — it expands to name which of the four links is broken.

| Pill says | What's wrong | Fix |
| --- | --- | --- |
| Looking for your Mac | App can't see the agent | Start `./agent/start.sh`; check both are on the same Wi-Fi; confirm Local Network permission is on under Settings → Teleport |
| Connecting (stuck) | Agent is advertised but not answering | The agent was killed with `SIGKILL`, leaving a stale advertisement. Restart it — it clears stale records on startup |
| Tunnel offline | `tunneld` isn't running | `sudo ~/.fake-location-venv/bin/pymobiledevice3 remote tunneld`, or just use `start.sh` |
| No device | Tunnel is up, no phone on it | Unlock the phone. On USB, re-trust the Mac. On Wi-Fi, check `pymobiledevice3 bonjour remotepairing` lists it |
| Agent error | Device dropped mid-session | Check the agent's terminal for the reason; it retries automatically |
| Teleport button greyed out | Chain isn't complete | The expanded pill shows which row is failing |

Tunnel log: `/tmp/teleport-tunneld.log`.

---

## Going fully wireless

You can get rid of the cable for everything — Xcode builds included — at the cost of
**one** USB connection to bootstrap it. Pairing is the only thing that genuinely
requires the cable.

### The one-time cable step

1. Connect by USB, unlock, trust the Mac.
2. Xcode → **Window → Devices and Simulators** (⇧⌘2) → select your iPhone → tick
   **Connect via Network**.
3. Wait for the globe icon to appear next to the device name, then unplug.

That checkbox is the key to both halves of this. It makes the phone advertise a
`_remotepairing._tcp` service on your network, which is what Xcode uses to deploy
wirelessly — and it's exactly the service `tunneld` browses for to build the tunnel.
One setting, both problems solved.

### After that

- **Building:** your iPhone stays in Xcode's destination menu with a network icon.
  ⌘R deploys over Wi-Fi.
- **The tunnel:** `tunneld` finds the phone over Wi-Fi on its own — `--wifi` monitoring
  is on by default, so `start.sh` needs no changes.
- **The app→agent link:** already Wi-Fi only; it never used the cable.

Confirm the phone is visible before starting the agent:

```bash
~/.fake-location-venv/bin/pymobiledevice3 bonjour remotepairing
```

If your iPhone is listed, the wireless path is working. If nothing appears, the cable
step above hasn't taken effect.

### What has to be true

- Both devices on the **same** Wi-Fi network.
- Not a guest network. AP/client isolation blocks the mDNS discovery that all three
  links depend on, and it fails silently.
- Phone unlocked and awake; Mac awake and not asleep.

Wireless is slower and less reliable than USB for both deployment and the tunnel. Keep
a cable within reach — plugging back in is always the fix.

---

## Can the fake location survive disconnecting?

**The cable can go. The Mac cannot.**

`tunneld` monitors Wi-Fi as well as USB, so once the phone has been paired over USB you
can unplug the cable and the tunnel re-forms over the network. The agent notices the
channel dropped, reconnects within a few seconds, and re-asserts the pinned coordinate.
So you can put the phone in your pocket and walk around the house with Berlin still in
effect.

What you cannot do is make it outlive the Mac. All of these snap you back to real GPS:

- Quitting the agent, or the Mac sleeping.
- The phone leaving the Wi-Fi network the Mac is on.
- Rebooting the phone.

This is not a shortcoming of this project — it's the design of the service. The
simulated location lives for exactly as long as the `DTSimulateLocation` channel is
open, and only a trusted computer can hold that channel. Making a fake location
persist standalone on the device needs a jailbreak-level tweak, and there is nothing
of that kind for iOS 26.5.

A VPN is the only thing that survives full disconnection, and it doesn't do what you
want: it changes your IP-based location, which some websites use, but it leaves the GPS
sensor untouched. Apple Maps, Google Maps, and Waze read CoreLocation and would still
show where you really are.

> Wi-Fi tunnelling is untested here — no device was attached when this was built. USB
> is the reliable transport; if the wireless tunnel misbehaves, plug the cable back in.

---

## Limitations

- **The Mac has to stay running.** See the section above for what does and doesn't
  survive a disconnect.
- **Reboot clears it.** So does quitting the agent or losing the tunnel.
- **A fixed point, not a route.** The agent pins one coordinate; it doesn't simulate
  movement along a path. `pymobiledevice3` can replay a GPX route if you want that.
- **Free accounts expire.** The app stops opening after 7 days — re-run it from Xcode.
- **Personal use.** Spoofing your location breaks the terms of service of plenty of
  apps, and some detect it.
