# pomodoro_total.koplugin

A Pomodoro focus/break timer for [KOReader](https://koreader.rocks/), with a
full-screen countdown and a running total of time studied — today, this
week, this month, and all-time.

Loosely inspired by [s4m-mo/pomodoro.koplugin](https://github.com/s4m-mo/pomodoro.koplugin),
rebuilt from scratch to add persistent study-time tracking, configurable
session lengths, and a full-screen shrinking-circle timer display.

## Features

- Full-screen timer: big countdown, and a circle that shrinks as the
  session runs down. Tap the screen to pause; Continue/Stop appear while
  paused.
- Configurable session length: 25/5, 45/15, or 60/30 minute focus/break
  presets, from the menu.
- Persistent study stats: today, this week, this month, and all-time
  totals, plus a day-by-day weekly and monthly breakdown — kept in a
  separate "Study stats" menu, off the timer screen itself.
- All state (totals, history, presets) survives restarts.

## Install

1. Download this repo (or a release zip).
2. Copy the `pomodoro_total.koplugin` folder into `koreader/plugins/` on
   your device.
3. Restart KOReader.
4. Open it from the main menu: **More tools → Pomodoro timer**.

## Usage

- **Start timer** — launches the full-screen countdown.
- **Session length** — pick 25/5, 45/15, or 60/30. Only affects the next
  session you start.
- **Study stats** — totals plus weekly/monthly breakdowns.

## Notes

- Only focus time counts toward your studied total, not breaks.
- The daily total resets at midnight (device local time); weekly/monthly
  are computed from a per-day history log, so nothing is lost.

## License

MIT
