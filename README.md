# DevPorts

A macOS menu bar app for the ports you forgot you left running.

Five projects half-open across terminal tabs, `EADDRINUSE` on port 3000, and no idea which
of them owns it. DevPorts lists every listening port, tells you which project it belongs to,
and gives you a button for each thing you'd otherwise do by hand.

```
┌──────────────────────────────────────────────┐
│  🔍 Filter by port, name or path      ⟳   ⚙  │
│  [ Running 2 ]  [ Favorites 3 ]              │
├──────────────────────────────────────────────┤
│  ●  3000   AI Coach              ⧉  ↻  ■  ★  │
│            ~/Dev/AI Coach · node · pid 32429 │
│  ●  5173   storefront            ⧉  ↻  ■  ★  │
│            ~/Dev/storefront · node · pid 611 │
├──────────────────────────────────────────────┤
│  2 listening · 3 system hidden          Quit │
└──────────────────────────────────────────────┘
```

---

## What it does

**Lists what's listening.** Every TCP port in LISTEN state, refreshed while the panel is
open. System daemons (ControlCenter, rapportd, and friends) are hidden behind a toggle, so
the list is your projects and nothing else.

**Names things the way you do.** A row is called `AI Coach`, not
`/Users/you/Dev/AI Coach/node_modules/.bin/next`. Names come from the project directory,
and you can rename anything — names key off directory + port, so they survive restarts and
new PIDs.

**Recovers the real start command.** This is the part that took the work. Node rewrites its
process title, so the thing on port 3000 reports itself as `next-server (v16.2.6)` — useless
for restarting. DevPorts walks up the process tree to the topmost runtime ancestor, which
still carries `next dev --turbopack`, then rewrites absolute paths relative to the project
directory so a path containing a space doesn't re-split when replayed. When it still can't
produce something trustworthy, it says so and asks you instead of guessing.

**Stops things, showing its work first.** Stop expands inline and lists the exact PIDs it's
about to signal, then offers **Stop Process** or **Stop Tree** — because killing the
listening PID usually leaves the `npm run dev` wrapper alive. SIGTERM first, SIGKILL after a
3 second grace. Tick *Remember* and a favorite stops skipping the prompt.

**Starts things back up.** Favorite a port and DevPorts saves its command and directory.
Node projects are pre-filled from `package.json` and the lockfile present — `pnpm run dev`,
`npm run start`, whichever fits. Started servers are fully detached: quit DevPorts and they
keep running.

**Restart** = stop, wait for the port to actually clear, start again.

**Opens in a browser** with a per-entry `http`/`https` choice.

---

## The port field, and what it can't do

A favorite's port is exported to the command as `PORT` — the convention Next, CRA, Express,
Rails and most dev servers read. But a command with its port hard-coded in config
(`server.port` in `vite.config.js`, an explicit `next dev -p 3000`) overrides the
environment, and no amount of wishing changes that.

So DevPorts watches where the server *actually* lands. If it comes up somewhere else, you
get told:

> "storefront ignored $PORT and started on 5173 instead of 4000."

The row keeps showing `saved :4000` next to the live port, and the `⋯` menu offers **Save
Port 5173** to adopt reality. The server is still matched to its favorite by working
directory, so it never splits into two rows.

---

## Install

```bash
git clone <this repo>
cd Mac-DevPorts
make install          # builds and copies to /Applications
```

Or build in place:

```bash
./build.sh            # produces ./DevPorts.app
make run              # build and launch
```

Needs Swift 6 and the Xcode command line tools. No third-party dependencies — SwiftUI,
AppKit, and `lsof`/`ps`.

**First launch:** the app is ad-hoc signed and not notarized, so Gatekeeper will refuse a
double-click. Right click `DevPorts.app` → **Open** → **Open**. Once only.

There's no Dock icon — DevPorts is an `LSUIElement` agent. Look in the menu bar.

---

## Why it isn't sandboxed

The app shells out to `lsof` and `ps`, sends signals to processes it doesn't own, and spawns
login shells in arbitrary directories. None of that is possible inside the App Sandbox. It
is a local developer tool, and it is unsandboxed by necessity rather than by shortcut.

Everything it stores lives in `~/Library/Application Support/DevPorts/`:

| Path | Contents |
| --- | --- |
| `store.json` | favorites, renames, settings |
| `logs/<favorite-id>.log` | output of servers DevPorts started |

Delete the folder to reset the app completely.

---

## Debugging

```bash
swift run DevPorts --scan
```

Dumps what the scanner sees without opening the UI — port, PID, which ancestor the command
was recovered from, resolved directory, and whether the command is considered replayable:

```
dev 3000	node	pid=58650 src=58649 bind=*
	dir: /Users/you/Dev/AI Coach
	cmd: node node_modules/.bin/next dev --turbopack  [verified: true]
```

Compare against `lsof -nP -iTCP -sTCP:LISTEN` when something looks wrong.

---

## How it's built

| File | Job |
| --- | --- |
| `Service/PortScanner.swift` | parses `lsof -F` field output, collapses IPv4/IPv6 duplicates |
| `Service/ProcessInspector.swift` | process table, ancestor walk, cwd, system classification, `package.json` suggestions |
| `Service/ProcessController.swift` | SIGTERM→SIGKILL escalation, detached launch, port polling |
| `Service/Store.swift` | debounced atomic JSON persistence |
| `ViewModel/PortsViewModel.swift` | scan → row merge, favorites, every action |
| `View/` | menu bar panel, rows, inline stop confirmation, editor window |

A few decisions worth knowing if you go reading:

- **Two `ps` calls, not one.** Each asks for a single space-containing field (`comm`, then
  `command`) in trailing position, which keeps parsing unambiguous for executables under
  paths with spaces.
- **One batched `lsof` for working directories.** `-p` takes a comma list, so enriching
  twenty listeners is still one process spawn.
- **Editing happens in a real window, not a sheet.** A sheet attached to a menu bar panel
  dismisses the panel the moment focus moves.
- **Stop confirmation is inline, not a popover,** for the same reason.

---

## Limits

- `lsof` without root only reports **your own** processes. Ports held by root daemons show up
  only with *Show system processes* on, and can't be stopped from the app — you'll get a
  clear message rather than silence.
- Restarting a process you haven't favorited uses the derived command. Where DevPorts can't
  derive a trustworthy one, it opens the editor pre-filled instead of firing blind.
- Ad-hoc signed, not notarized. Distributing it to other machines means signing it properly.

## License

MIT. See [LICENSE](LICENSE).
