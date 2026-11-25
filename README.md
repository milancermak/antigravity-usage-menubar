# agy-usage-menubar

Native macOS menu bar app for tracking and projecting your Google Antigravity **Gemini** 5-hour and weekly quota limits.

## Features

- **Color-coded fire icon(s)** in the macOS menu bar:
  - **Green**: on track with comfortable headroom at reset
  - **Amber**: borderline pace or getting low
  - **Red**: on track to run dry before reset or critically low
- **Configurable menu bar**:
  - 1 fire (5-hour *or* weekly) or 2 fires (5-hour + weekly)
  - Optional `%` remaining label beside each flame
- **Clean popover visualization**:
  - Progress bars with a linear-pace marker
  - Remaining-over-time charts plotted against the linear pace line and forward projection
  - Clear reset countdown and depletion/headroom forecast
- **Automatic cleanup**:
  - Polls every 1 minute by default via the official `agy` CLI `statusLine` contract (no prompts sent, zero quota consumed)
  - Stores only Gemini quota readings (no account PII) and automatically deletes expired snapshots after the weekly cycle resets

## Requirements

- macOS 14+ (Apple Silicon or Intel)
- Swift 6+ / Xcode Command Line Tools
- [Antigravity CLI (`agy`)](https://antigravity.google/product/antigravity-cli) installed and authenticated

## Build & Run

```bash
# Run unit tests
swift test

# Build the macOS .app bundle
./scripts/build-app.sh

# Launch the menu bar app
open dist/AgyUsageMenubar.app
```

To install permanently, copy `dist/AgyUsageMenubar.app` into `/Applications`.

## How It Fetches Quota

The app invokes `agy --settings ...` using the documented `statusLine` JSON hook (`antigravity.google/docs/cli/statusline`) inside a local PTY, reads the first `gemini-5h` and `gemini-weekly` quota snapshot (`remaining_fraction`, `reset_time`), discards all other fields, and terminates the process immediately without starting a conversation or spending quota.
