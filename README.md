# WinShuffle

WinShuffle is a small macOS app that grabs the currently open windows you can move through Accessibility and shuffles them across the screen like a deck of cards.

## What it does

- Prompts for Accessibility access the first time it runs.
- Lists movable standard windows from running apps.
- Animates those windows into shuffled positions with stagger and lift so the motion reads like cards being dealt.

## Run

```bash
swift run
```

Grant Accessibility permission to the built app when macOS prompts you.

## Notes

- Full-screen and minimized windows are skipped.
- The app only moves windows macOS exposes through the Accessibility API.
