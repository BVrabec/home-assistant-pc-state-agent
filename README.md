# PC state agent (MQTT) → Home Assistant

A tiny Python program that tells **Home Assistant what a Linux computer is doing** — off, locked,
idle or in use — so an automation or an assistant can tell *"the PC is on"* from *"he is sitting at
the PC"*.

The PC connects **outward** to an MQTT broker on the Home Assistant machine and publishes one word.
Home Assistant turns that word into a sensor by itself; nothing in Home Assistant needs editing.

```
Linux PC  ──MQTT──▶  broker (on the Home Assistant host)  ──▶  Home Assistant sensor  ──▶  automations
```

- No AI, no cloud, no internet.
- It reads **two things only**: whether the session is locked, and how long the screen has been
  untouched. No files, no screen, no keyboard, no microphone.
- It runs as **your own user**, in your own login session, as a systemd *user* service. No root, no
  second account, no system-wide changes.

## Why this repo exists

Home Assistant could already see whether the PC was **on** — a ping sensor does that. It could not
tell *"the PC is on"* from *"he is sitting at it"*, and a great many automations want exactly that
difference: ring or stay quiet, is he at the computer or away, has he stepped out of the room.

This agent closes that gap. It runs on the PC itself, publishes one of four words over MQTT, and
Home Assistant turns it into a sensor that an automation — or an assistant — can read.

**What is in here:** the program, the systemd user unit, an install script, a settings example, and a
guide in two halves — *install it on the Linux PC*, then *connect it to Home Assistant*. Enough to
rebuild the whole thing from scratch, on this machine or any other.

## What it reports

| State    | Meaning                                                          |
|----------|------------------------------------------------------------------|
| `active` | On, unlocked, being used                                         |
| `idle`   | On, unlocked, untouched for `idle_seconds` (default 10 minutes)  |
| `locked` | On, screen locked                                                |
| `off`    | PC off — set by the broker's *last will* if the program stops     |

`locked` wins over `idle`, so `idle` appears only when the screen is unlocked **and** untouched —
watching a film, for example. A history showing only `locked` and `active` is not a fault.

---

## Requirements

- A Linux PC with a **graphical login session** (tested on Fedora 42 / KDE Plasma 6).
- `systemd` (for the user service) and `loginctl`.
- One of `busctl`, `qdbus6` or `qdbus` for the idle reading (`busctl` is part of systemd, so it is
  almost always present).
- Python 3.8+ and the `paho-mqtt` library.
- Home Assistant with the **Mosquitto broker** add-on (or any MQTT broker) and the **MQTT**
  integration enabled.

---

# Part 1 — Install it on the computer

## 1.1 Install the MQTT library

Fedora / RHEL:

```bash
sudo dnf install -y python3-paho-mqtt
```

Debian / Ubuntu:

```bash
sudo apt install -y python3-paho-mqtt
```

Arch:

```bash
sudo pacman -S --needed python-paho-mqtt
```

(Any route works, including `pip install --user paho-mqtt` — but the distribution package keeps
Python from being mixed between two installs.)

## 1.2 Put the files in place

Download or clone this repository, then either run the helper or do it by hand.

**With the helper:**

```bash
./install.sh
```

It copies the program to `~/.local/bin/jarvis-pc-agent`, creates
`~/.config/jarvis-pc-agent/`, and installs the user service unit. It never overwrites an existing
settings file.

**By hand:**

```bash
mkdir -p ~/.local/bin ~/.config/jarvis-pc-agent ~/.config/systemd/user
cp jarvis-pc-agent              ~/.local/bin/jarvis-pc-agent
cp jarvis-pc-agent.service      ~/.config/systemd/user/jarvis-pc-agent.service
chmod +x ~/.local/bin/jarvis-pc-agent
```

> **`~/.local/bin` must be in your `PATH`** for the plain `jarvis-pc-agent` command to work. The
> service unit uses the full path, so the service works regardless.

## 1.3 Write the settings file

Copy the example and fill it in:

```bash
cp config.example.json ~/.config/jarvis-pc-agent/config.json
chmod 600 ~/.config/jarvis-pc-agent/config.json
```

`~/.config/jarvis-pc-agent/config.json` — the two lines that matter are `broker` and the
`username`/`password` pair you will create in **Part 2, step 2.2**:

```json
{
  "broker": "192.168.1.50",
  "port": 1883,
  "username": "jarvis-pc",
  "password": "the password you made up",
  "topic": "jarvis/pc/state",
  "discovery_prefix": "homeassistant",
  "device_id": "jarvis_desktop",
  "device_name": "Personal Desktop",
  "idle_seconds": 600,
  "poll_seconds": 15,
  "heartbeat_seconds": 120,
  "client_id": "jarvis-pc-agent"
}
```

| Key                 | What it is                                                                 |
|---------------------|-----------------------------------------------------------------------------|
| `broker`            | IP address or hostname of the machine running the MQTT broker (your Home Assistant host). |
| `port`              | `1883` for plain MQTT. If you enabled TLS on the broker, use `8883` and see *TLS* below. |
| `username`/`password` | The MQTT login — created in Home Assistant, **Part 2**.                    |
| `topic`             | The topic the state is published to. Only change it if it clashes.          |
| `discovery_prefix`  | Leave as `homeassistant` unless your Home Assistant MQTT integration uses another one. |
| `device_id`         | Internal id of the device in Home Assistant.                                |
| `device_name`       | The name you will see in Home Assistant.                                    |
| `idle_seconds`      | Untouched this long ⇒ `idle`. 600 = 10 minutes.                             |
| `poll_seconds`      | How often the state is checked.                                             |
| `heartbeat_seconds` | Re-publish even when nothing changed, so the broker never thinks it is stale. |

Keep the file readable by you only (`chmod 600`) — it holds the MQTT password. **Never commit it.**
The `.gitignore` in this repo already excludes it.

## 1.4 Test it by hand, before installing anything as a service

```bash
~/.local/bin/jarvis-pc-agent --check
```

Expected output — it prints the readings and the state it *would* send, and connects to nothing:

```
config        : /home/you/.config/jarvis-pc-agent/config.json
broker        : 192.168.1.50:1883  user=jarvis-pc
topic         : jarvis/pc/state
session id    : 3
locked        : False
idle seconds  : 12.0
state now     : active
```

If `locked` or `idle seconds` reads `None`, run the diagnostic, which shows every way of reading
them, raw:

```bash
~/.local/bin/jarvis-pc-agent --probe
```

It also lists which helper tools (`busctl`, `qdbus6`, `qdbus`, `loginctl`) exist on the machine.
Paste its output when asking for help — it says more than any description.

## 1.5 Start it, and make it start at every login

```bash
systemctl --user daemon-reload
systemctl --user enable --now jarvis-pc-agent
```

`enable` means *start automatically at every login*; `--now` means *start it right now as well*.

> **Why a *user* service and not a system one:** the lock and idle readings belong to your login
> session. A system service running as root, or as another account, cannot see your screen and would
> report nothing useful.

For the service to keep running when you are not logged in graphically it must not be killed at
logout — by default `systemd --user` stops your services when your last session ends, which is
correct here: no session, no state to report. The broker marks the PC `off` in the meantime.

## 1.6 Check that it is running

```bash
systemctl --user status jarvis-pc-agent
journalctl --user -u jarvis-pc-agent -n 20 --no-pager
```

What you want to see in the journal:

```
jarvis-pc-agent: connected to 192.168.1.50:1883 as jarvis-pc
jarvis-pc-agent: state -> active
```

`connected` means the broker accepted the login. If instead you see
`(Not authorized)` or `refused: not authorised`, the login is wrong or missing — go to
**Part 2, step 2.2**, that is almost always the cause.

---

# Part 2 — Connect it to Home Assistant

## 2.1 Find the broker address

The broker is the **Mosquitto broker** add-on (or any MQTT broker) running on the Home Assistant
machine.

1. Home Assistant → **Settings → Add-ons → Mosquitto broker**.
2. Open the **Info** tab and note the port — normally `1883`.
3. The address is the **IP address of the Home Assistant machine** on your network. That is what goes
   in `"broker"` on the PC. (If Home Assistant runs on a separate VM or container, use *that*
   machine's address, not the Home Assistant URL.)

Sanity check from the PC before going further:

```bash
nc -zv 192.168.1.50 1883
```

Expect `succeeded` or `open`. If it fails, the PC cannot reach the broker — fix the network (or the
firewall on the Home Assistant host) before anything else.

## 2.2 Create the MQTT login — in Home Assistant, as a **user**

This is the step that trips nearly everyone up, so read it twice.

The Mosquitto add-on authenticates against **Home Assistant's own user system**. A login that exists
only inside the add-on's Configuration tab may be refused with `Not authorized` — the PC connects,
and every publish is rejected. Create it as a Home Assistant user:

1. Home Assistant → **Settings → People → Users → Add user**.
2. Username: e.g. `jarvis-pc`.
3. Password: something long and random. Make it up here; do not reuse a real password.
4. Leave *Allow this user to log in* on, *Administrator* **off**.
5. **Create**.

Then, so the broker knows the login too:

6. **Settings → Add-ons → Mosquitto broker → Configuration**, and add the same pair under `logins`:

   ```yaml
   logins:
     - username: jarvis-pc
       password: the same password
   ```

7. **Save**, then **Restart** the add-on.

The username and password have nothing to do with your Linux account. They exist in exactly two
places: Home Assistant and the settings file on the PC.

## 2.3 Put the credentials on the PC

Back at the PC, edit `~/.config/jarvis-pc-agent/config.json` and set `broker`, `username` and
`password`. Then restart the agent so it picks them up:

```bash
systemctl --user restart jarvis-pc-agent
journalctl --user -u jarvis-pc-agent -n 20 --no-pager
```

You want `connected to … as jarvis-pc` and then a `state -> …` line.

## 2.4 The sensor appears by itself

On connecting, the agent publishes a **Home Assistant MQTT discovery** record once, to:

```
homeassistant/sensor/jarvis_desktop/state/config
```

Home Assistant's MQTT integration reads that and creates the device and its entity with **no manual
configuration at all**.

1. Home Assistant → **Settings → Devices & Services → MQTT**. The device `Personal Desktop` (or
   whatever you set as `device_name`) is listed there.
2. Open it — one entity: **PC state** (`sensor.<device_name>_pc_state`, e.g.
   `sensor.personal_desktop_pc_state`).
3. Its state is one of `active`, `idle`, `locked`, `off`.

The entity id is derived from the device name, so renaming the device in Home Assistant renames the
entity. Renaming the device *from the agent* (`device_name` in the settings) is cleaner, because the
name then comes from the PC itself.

## 2.5 Verify that the state is actually arriving

Two ways, both read-only:

- **Developer Tools → States** → filter for `pc_state` → the state should change within
  `poll_seconds` (15 s by default) of you locking or using the PC.
- **Settings → Devices & Services → MQTT → Configure → Listen to a topic** → topic
  `jarvis/pc/state` → **Start listening**. Every published word appears live.

## 2.6 The walk-through test

Do this once, and the whole chain is proven end to end:

| Do this on the PC                                  | Expect in Home Assistant      |
|----------------------------------------------------|-------------------------------|
| Use the PC normally                                | `active`                      |
| Lock the screen (`Meta`+`L` on KDE/GNOME)           | `locked` within ~15 s         |
| Unlock, then leave it untouched for 10 minutes      | `idle`                        |
| Touch the mouse                                     | `active`                      |
| `systemctl --user stop jarvis-pc-agent`             | `off` after a moment          |

`off` when the service stops is deliberate: the agent registers a **last will** with the broker, so a
PC that dies, sleeps or has its agent stopped cannot be left looking `active` forever.

---

# Troubleshooting

**`connected … (Not authorized)` / `refused: not authorised`**
The login was refused. It is almost always step **2.2**: create the login as a Home Assistant
**user** (Settings → People → Users), then restart the Mosquitto add-on. Check the password matches
exactly — the settings file is JSON, so quotes and no trailing commas.

**The journal says `connected` but no device appears in Home Assistant**
- Is the **MQTT integration** installed and connected to the same broker? *Settings → Devices &
  Services* should list **MQTT**.
- Is `discovery_prefix` still `homeassistant`? Discovery is off if your MQTT integration was set up
  with a different prefix.
- MQTT discovery may be disabled in the integration: *MQTT → Configure → Enable discovery*.

**`idle seconds: None`, so `idle` never appears**
Run `jarvis-pc-agent --probe`. It tries, in order: `org.freedesktop.ScreenSaver` via `busctl`, KDE's
own `org.kde.screensaver` via `busctl`/`qdbus6`/`qdbus`, and finally `logind`'s idle hint. If all
fail, install the D-Bus tools (`sudo dnf install -y qt6-qttools` provides `qdbus6`) or check that the
program is running inside the graphical session — a service started outside your session cannot see
the screen saver.

**`locked` is always `False`**
`loginctl` is not reporting the lock hint for your session. Check by hand:

```bash
loginctl show-session $XDG_SESSION_ID -p LockedHint --value
```

Lock the screen and run it again — it should say `yes`. If your desktop does not set the hint, the
agent cannot know either.

**The state never leaves `active`**
The idle threshold has not been reached: `idle_seconds` defaults to 600. Lower it for testing.

**The state is `off` while the PC is on**
The agent is not running, or it lost the broker. `systemctl --user status jarvis-pc-agent` and the
journal will say which.

---

# Files in this repository

| File                       | What it is                                                     |
|----------------------------|----------------------------------------------------------------|
| `jarvis-pc-agent`          | The program. No secret inside it.                              |
| `config.example.json`      | The shape of the settings file. The real one is made on the PC. |
| `jarvis-pc-agent.service`  | The systemd **user** unit — start at every login.              |
| `install.sh`               | Copies the above into place. Does not touch the settings file. |
| `.gitignore`               | Keeps `config.json` (with the password) out of git.            |

Useful flags:

```bash
jarvis-pc-agent --check    # what it would send; connects to nothing
jarvis-pc-agent --probe    # every reading, raw; use when one comes back empty
```

The settings file can also be pointed elsewhere with the environment variable
`JARVIS_PC_AGENT_CONFIG=/path/to/config.json`.

# Uninstall

```bash
systemctl --user disable --now jarvis-pc-agent
rm ~/.local/bin/jarvis-pc-agent \
   ~/.config/systemd/user/jarvis-pc-agent.service
systemctl --user daemon-reload
```

The broker then marks the PC `off` by itself, so nothing stale is left in Home Assistant. The device
can be deleted there, and the MQTT login removed from Home Assistant at any time.

# Security notes

- The agent makes an **outbound** connection only. Nothing needs to reach the PC, no port is opened
  on it, and it works fine behind NAT.
- It reads the session lock state and the screen-saver idle counter, and publishes one of four words.
  It does not read files, the screen, the keyboard, the clipboard or the network.
- Give the MQTT login a password of its own, keep it out of git, and keep the settings file at
  `chmod 600`. If the broker is reachable from outside your network, enable TLS on it and set the
  port to `8883`.

# Licence

MIT — see `LICENSE`.
