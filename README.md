# Vitals for Omarchy

A compact system monitor for several machines at once. Vitals shows CPU, memory
and network for this machine and for any other machine you can reach over SSH.
It sits in a narrow sidebar docked to a screen edge, or in its own window. The
remote side needs nothing installed: a small shell script is streamed over SSH
and runs with the tools every Linux and macOS system already has.

The readouts follow [OmaStats](https://github.com/crmne/omastats): stacked
letter labels, thin bar-history graphs, and colors taken from your Omarchy
theme, so Vitals looks at home beside OmaStats in the bar.

![The Vitals sidebar docked on the right, with the machine list and the add-machine form](preview.png)

## What it shows

Each machine gets a compact card:

- **Header.** A status dot, the machine's name, its core count and an OS glyph.
- **CPU.** Usage history (user and system stacked) and the current percentage.
- **MEM.** Used memory history, the percentage, and used/total.
- **NET.** Upload above the midline and download below it, with current rates.

The status dot uses the theme's colors: online, connecting or stale, offline.
A machine that can't be reached shows **offline · reconnecting**, the reason
(for example "Host not found" or "SSH key not accepted"), and a countdown to
the next try. Vitals never shows numbers it doesn't have.

The cards stay legible at 180 to 220 pixels wide. With more machines than fit,
the sidebar scrolls.

## Requirements

- Omarchy with the Quickshell-based `omarchy-shell`.
- For remote machines: `ssh` on this machine, and key-based login to each remote
  that already works without a prompt (see [Remote machines](#remote-machines)).

Nothing else. No packages, agents or daemons on either side.

## Install

```sh
omarchy plugin add https://github.com/SuperCleanse/omarchy-vitals.git --enable
```

This puts the Vitals pulse icon in the right section of your bar. Click it to
open the sidebar. Move the icon with
`omarchy bar move supercleanse.vitals --section right`, or drag it.

Update later with `omarchy plugin update supercleanse.vitals`, then run
`omarchy-restart-shell`. Vitals keeps its service and SSH sessions running
across the shell's hot reloads, so new code takes effect on a restart.

### Manual install

```sh
git clone https://github.com/SuperCleanse/omarchy-vitals.git ~/.config/omarchy/plugins/supercleanse.vitals
omarchy-shell shell rescanPlugins
omarchy plugin enable supercleanse.vitals
```

### Remove

```sh
omarchy plugin remove supercleanse.vitals
rm -rf ~/.config/vitals ~/.local/state/vitals   # machine list and open/closed state
```

## Using it

| Action | Result |
|:--|:--|
| Click the bar icon | Show or hide Vitals |
| Middle-click the bar icon | Reconnect any offline machine now |
| Right-click the bar icon | Open Vitals in edit mode |
| Refresh button in the sidebar | Reconnect any offline machine now |
| Pencil button | Edit the machine list |

In edit mode each machine has a checkbox to switch it on or off, buttons to
move it up or down, edit it or remove it, and an **Add machine** button below
the list. The local machine can be renamed and switched off but not removed.
Its name defaults to the short hostname.

### IPC and keybinding

```sh
omarchy-shell supercleanse.vitals toggle    # show or hide
omarchy-shell supercleanse.vitals open
omarchy-shell supercleanse.vitals close
omarchy-shell supercleanse.vitals dock      # switch to the docked sidebar and show it
omarchy-shell supercleanse.vitals window    # switch to window mode and show it
omarchy-shell supercleanse.vitals refresh   # reconnect anything offline, reread machines.json
omarchy-shell supercleanse.vitals edit      # show in edit mode
omarchy-shell supercleanse.vitals status    # JSON: every machine, its state and latest figures
```

`dock` and `window` save the choice as the widget's `mode` setting in
`shell.json`, so it sticks. To bind a key, add this to
`~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + SHIFT + M", "Vitals", "omarchy-shell supercleanse.vitals toggle")
```

## Display modes

- **dock** (default). A layer-shell panel pinned to the left or right edge,
  below the bar. It reserves its width as an exclusive zone, so Hyprland tiles
  your windows beside it instead of under it. Like the bar, it is on every
  workspace. It only takes keyboard focus while the add/edit form is open.
- **window.** The same content in an ordinary window, which Hyprland tiles like
  any app. Its class is Quickshell's, `org.quickshell`, and its title is
  `Vitals`, for window rules:

  ```lua
  o.window({ class = "^org.quickshell$", title = "^Vitals$" }, { float = true })
  ```

  Closing the window hides Vitals.

## Settings

Set these in the shell's settings for the Vitals bar widget, or inline on its
entry in `~/.config/omarchy/shell.json`.

| Key | Default | Meaning |
|:--|:--|:--|
| `mode` | `dock` | `dock` or `window` |
| `edge` | `right` | Dock edge: `right` or `left` |
| `width` | `200` | Sidebar and window width in pixels (160 to 360) |
| `screen` | `""` | Output for the dock, such as `DP-1` (see `hyprctl monitors`). Empty lets the compositor choose, usually the focused screen |
| `refreshSeconds` | `"2"` | Sample interval: 1, 2, 3, 5 or 10 seconds |
| `historySeconds` | `120` | How much history the graphs keep (30 to 900) |
| `sampleWhileHidden` | `false` | Keep sampling while Vitals is hidden. Graphs then have history when you open it, and the bar icon turns the theme's danger color when a machine drops off |
| `barReadout` | `icon` | `icon`, or `count` to add online/total beside the icon while sampling |

By default Vitals only samples while it is visible. Hiding it closes every SSH
session.

## The machine list

Vitals keeps the list in `~/.config/vitals/machines.json` (it honors
`XDG_CONFIG_HOME`). The file is created on first run with just this machine.
The edit mode writes it for you, but it is plain JSON and safe to edit by hand.
Vitals rereads it when it changes.

```json
{
  "version": 1,
  "machines": [
    { "id": "local", "alias": "", "host": "", "enabled": true },
    { "id": "studio-mini", "alias": "studio-mini", "host": "studio-mini", "enabled": true },
    { "id": "build-box", "alias": "build-box", "host": "builder@100.101.102.103", "enabled": true },
    { "id": "nas", "alias": "nas", "host": "nas.example-tailnet.ts.net", "enabled": false }
  ]
}
```

- `id` is a stable key. Leave it out of a new entry and Vitals makes one up.
- `alias` is the name shown on the card. For the local machine, empty means the
  short hostname.
- `host` is any SSH destination. Empty means this machine, and there is always
  exactly one local entry.
- `enabled: false` keeps a machine in the list without showing or sampling it.
- The order of the list is the order of the cards.

If the file stops being valid JSON, Vitals shows only this machine and a note
asking you to fix it. It never overwrites a file it couldn't read.

Whether Vitals is open is remembered in `~/.local/state/vitals/state.json`.

## Remote machines

Vitals runs your own `ssh` client like this, once per machine, and keeps the
session open:

```sh
ssh -T -o BatchMode=yes -o ConnectTimeout=8 -o ServerAliveInterval=10 \
    -o ServerAliveCountMax=2 -- <host> sh -s -- <interval>  < vitals-sampler.sh
```

So anything that works for `ssh <host>` works in Vitals: `~/.ssh/config`
aliases, `ProxyJump`, `ProxyCommand` (Cloudflare Tunnel's
`cloudflared access ssh`, for example), ports and identity files. Because of
`BatchMode=yes`, ssh never prompts. That means:

- **Key login must already work.** Test with `ssh -o BatchMode=yes <host> true`.
  Load your key into `ssh-agent` if it has a passphrase.
- **The host key must already be known.** Connect once by hand to accept it.
  Vitals shows "Host key not trusted yet" until you do.

An alias in `~/.ssh/config` keeps the destination short:

```
Host studio-mini
  HostName studio-mini.example-tailnet.ts.net
  User me
```

**Tailscale.** A MagicDNS name (`studio-mini` or
`studio-mini.example-tailnet.ts.net`) or a `100.x.y.z` address works directly
as the destination. Tailscale SSH works too, as long as it doesn't ask for
browser approval on each connection; check mode is a prompt, and Vitals can't
answer prompts.

When a connection drops, Vitals marks the machine offline and retries after 2,
4, 8 and 16 seconds, then every 30 seconds. ssh's keepalive notices a dead link
within about 30 seconds. A machine that goes quiet without disconnecting is
marked **stale** after three missed samples.

### macOS remotes

- Tested on macOS 26 (Apple silicon).
- Turn on **System Settings › General › Sharing › Remote Login**.
- Vitals uses only built-in tools: `iostat`, `vm_stat`, `netstat`, `sysctl`,
  `sw_vers` and `scutil`.
- Memory "used" is App Memory plus Wired plus Compressed, the same figure
  Activity Monitor shows as Memory Used. It leaves out file cache, which
  `top`'s PhysMem counts.
- CPU is reported in whole percents, and the interval rounds to whole seconds.
- Network counts the `en*` interfaces, so Tailscale's `utun` traffic isn't
  counted twice.

### Linux remotes

- Tested on Arch Linux. The script uses only POSIX `sh`, `/proc` and `/sys`, so
  other distributions, including busybox-based ones, should work too.
- Network sums the interfaces backed by a real device in
  `/sys/class/net/*/device`, which leaves out loopback, bridges, veths, Docker
  and Tailscale. Inside a container, where nothing qualifies, it falls back to
  every non-loopback interface.
- Memory "used" is `MemTotal - MemAvailable`.

## How it works

- **One process per machine.** The local machine runs
  `sh sampler/vitals-sampler.sh <interval>`. A remote one runs the ssh command
  above, with the same script streamed over stdin. Nothing is copied to or left
  on the remote machine. When Vitals stops a session, the remote loop exits on
  its next write.
- **The sampler** is about 230 lines of POSIX sh. It detects the OS with
  `uname`, prints a `hello` line (OS, hostname, core count), then one JSON line
  per interval:

  ```json
  {"type":"sample","cpu":12.3,"user":8.1,"sys":4.2,"memUsed":13404160000,"memTotal":34359738368,"rx":5120,"tx":2048,"load":0.42}
  ```

- **Cost.** On Linux, each sample reads `/proc` with shell builtins, and `sleep`
  is the only process it starts: about 13 ms of CPU per sample. On macOS, each
  sample runs `iostat` (which also does the waiting), `vm_stat`, `netstat` and
  one `awk`: about 40 ms of CPU, or 2% of one core at the default 2 seconds.
- **The service** (`VitalsService.qml`) owns the list, one connection per
  enabled machine, the sidebar or window, and the IPC target. It reconnects
  with backoff and keeps each machine's history in memory.
- **Colors** come from the active theme through `Commons.Color`. The graphs use
  the theme accent plus a second hue picked from the theme's `colors.toml`, the
  way OmaStats does, and follow theme changes live.

Vitals never stores passwords and never runs anything with elevated privileges.

## Development

Validate the manifest:

```sh
omarchy plugin validate .
```

Run the checks. None of them opens a window on your desktop.

```sh
dev/test-model.sh                     # unit tests for Model.js (needs node)
dev/test-sampler.sh                   # run the sampler here and check its output
dev/test-sampler.sh studio-mini       # ...and stream it to a remote too (read-only)
dev/render.sh --fake-data             # render every view to dev/renders/*.png
dev/render.sh --fake-data --theme tokyo-night
dev/load-check.sh /tmp/vitals-check studio-mini   # load the real plugin and sample for a few seconds
```

`dev/render.sh` runs a private Quickshell instance with
`QT_QPA_PLATFORM=offscreen`, its own runtime directory and no Wayland, Hyprland
or D-Bus connection, and saves each scene with `grabToImage`. It refuses to run
without `--fake-data`. Every number it draws comes from
`dev/harness/fixtures.js`. The plugin itself has no fake-data path: an
unreachable machine is shown as offline, never with made-up figures.

`dev/load-check.sh` loads the real service and widget with a scratch `HOME`,
lets the real samplers run, calls each IPC method on that private instance,
and saves one PNG of the live view to the scratch directory. That PNG holds
real host data, so the script refuses to write inside the repository.

The docked sidebar's layer-shell behavior (the exclusive zone and tiling beside
it) needs a running compositor. Offscreen rendering can't show it, so check it
on a live session.

## Credits

The look and several pieces are adapted from
[OmaStats](https://github.com/crmne/omastats) by Carmine Paolino (MIT): the
stacked letter label, the bar-history and mirrored graphs, the byte and rate
formatting, and the way it picks a second graph hue from the theme. See
`LICENSE` for both notices.

## License

MIT
