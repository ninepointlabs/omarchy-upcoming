# Upcoming for Omarchy

A small Omarchy bar widget for the shows you actually watch. Search [TVmaze](https://www.tvmaze.com/api)
to pick the right title (year and network shown so Silo on Apple TV is not Silo on meWATCH), then
see when the next episode is due.

No API key. The list lives in `~/.local/state/omarchy-upcoming/watchlist.json`, not in `shell.json`.

## What it does

- **Bar chip** — the soonest upcoming episode among your list, e.g. `Silo · S4E1 Jul 9 2027`. Empty until you add a show.
- **Click the chip** — search, pick a match, remove shows, refresh air dates.
- **Middle-click the chip** — refresh without opening the panel.

TVmaze tracks listed air dates, not “released on my service in my country”. Ended shows and titles with no date yet still sit on the list as ended / TBA.

## Requirements

- Omarchy (Quickshell bar), 4.0.3 or later.
- `python3` and `curl` are not required at runtime beyond Python 3 (stdlib `urllib`).
- Network access to `https://api.tvmaze.com`.

## Install

Not published to the marketplace yet. From a local checkout:

```sh
~/Projects/omarchy-upcoming/install.sh
omarchy plugin enable ninepointlabs.upcoming
omarchy restart shell
```

`install.sh` copies into `~/.config/omarchy/plugins/ninepointlabs.upcoming` and validates, but does not enable the widget or restart the shell.

## Limits

- Twenty-four shows.
- Refresh is polite: on add, on load, on demand, and every six hours.
- Some streaming calendars land late or as TBA. That is TVmaze, not a bug in the chip.

Show names and episode titles are rendered as plain text.
