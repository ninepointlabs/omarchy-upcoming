# Upcoming for Omarchy

A small Omarchy bar widget for the shows you actually watch. Search [TVmaze](https://www.tvmaze.com/api)
to pick the right title (year and network shown so Silo on Apple TV is not Silo on meWATCH), then
see when the next episode is due.

No API key. The list lives in `~/.local/state/omarchy-upcoming/watchlist.json` (mode 0600), not in `shell.json`.

![Upcoming panel](preview.png)

## What it does

- **Bar chip** — the soonest upcoming episode among your list, e.g. `Silo · S4E1 Jul 9 2027`. Empty until you add a show.
- **Click the chip** — search, pick a match, remove shows, refresh air dates.
- **Middle-click the chip** — refresh without opening the panel.

TVmaze tracks listed air dates, not “released on my service in my country”. Ended shows and titles with no date yet still sit on the list as ended / TBA.

## Requirements

- Omarchy (Quickshell bar), 4.0.3 or later.
- Python 3 (stdlib `urllib` only).
- Network access to `https://api.tvmaze.com`.

## Install

```sh
omarchy plugin add https://github.com/ninepointlabs/omarchy-upcoming.git --enable
```

That clones into `~/.config/omarchy/plugins/ninepointlabs.upcoming` and turns it on. To update later:

```sh
omarchy plugin update ninepointlabs.upcoming
```

### From a local checkout

```sh
~/Projects/omarchy-upcoming/install.sh
omarchy plugin enable ninepointlabs.upcoming
omarchy restart shell
```

`install.sh` copies into the plugin directory and validates. It does not enable the widget or restart the shell.

## Remove

```sh
omarchy plugin remove ninepointlabs.upcoming
```

Your watchlist in `~/.local/state/omarchy-upcoming/` is left in place.

## Limits

- Twenty-four shows.
- Refresh is polite: on add, on load, on demand, and every six hours.
- Some streaming calendars land late or as TBA. That is TVmaze, not a bug in the chip.

## Security notes

- No API key, no credentials, nothing in `shell.json` or process argv besides the helper paths.
- **Nothing runs through your `PATH`.** The widget starts exactly one program: Python 3 from a fixed absolute path (`/usr/bin/python3`, then `/bin/python3`, then `/run/current-system/sw/bin/python3`), probed in that order at load. If none exists it shows an error and runs nothing. There is no shell, and no `mkdir`, `head`, `wc`, `kill` or `sleep` process.
- **Closed environment.** Every process is started with the session environment cleared and replaced by `PATH=/usr/bin:/bin:/run/current-system/sw/bin` and `LC_ALL=C.UTF-8`. Python runs with `-I -S -B` (ignores `PYTHON*` variables, user site-packages and the script directory). The supervisor also strips `BASH_ENV`, `ENV`, `BASH_FUNC_*` and `LD_*` hooks before anything starts.
- **Bounded jobs.** Every job runs under `bin/bounded-run`, a Python stdlib supervisor: output caps enforced as bytes arrive (256 KiB stdout / 64 KiB stderr for TVmaze calls), a deadline (60 s search, 300 s refresh, 15 s watchlist I/O), and TERM→KILL of the job's process group. The supervisor stays the direct parent of the job and does not reap it until every signal is sent, and it is a child subreaper, so it never signals a PID or process group that could have been reused.
- Search queries, show ids and the watchlist go to `bin/upcoming-ops` over stdin. HTTPS calls are only to `api.tvmaze.com`; redirects off that host are refused, proxies from the environment are not used, and response bodies are capped while they are read.
- **Watchlist I/O is descriptor-based.** The helper opens the home directory from the password database, then `~/.local`, `~/.local/state` and `~/.local/state/omarchy-upcoming` one component at a time with `O_NOFOLLOW`, checking ownership and that none is writable by others (the last is kept at 0700). `watchlist.json` is read through that held directory with `O_NOFOLLOW|O_NONBLOCK`, must be a regular, singly-linked file you own, and is capped at 64 KiB. Saves create a random-named 0600 temp file with `O_EXCL|O_NOFOLLOW` in the same held directory, `fsync`, and `rename` it into place; if something other than your own regular file sits at `watchlist.json`, the save is refused.
- Show names and episode titles are stripped of tags in the parser and rendered as `Text.PlainText`.

## Tests

```sh
node tests/model.test.cjs              # model, process boundary, PATH-shadow checks, live TVmaze
/usr/bin/python3 -I -B tests/store_test.py   # watchlist store: symlinks, FIFOs, modes, sizes
tests/bounded-run.test.sh bin/bounded-run    # supervisor: caps, deadline, process-group cleanup
```
