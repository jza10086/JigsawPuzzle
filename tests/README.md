# Automated checks

Run with a Godot 4.x binary from the project root:

```sh
godot --headless --path . --script res://tests/state_test.gd
godot --headless --path . --script res://tests/ui_test.gd
```

The script exits `0` on success and `1` on any recorded failure. No addons, test frameworks, network requests, or scene rendering are required.

Coverage:

- 1,000 deterministic shuffle seeds: all nine unique pieces preserved, turns in `0..3`, both positions and orientations shuffled, never initially solved.
- Two rare regression seeds exercise the identity-permutation and all-upright shuffle safety guards on Godot 4.7.2.
- Four clockwise rotations return a piece to its original orientation; rotation stays with its identity when swapped.
- Left-click pickup, same-slot placement, two-piece swap, source selection release, exact move counting.
- Right click without selection, invalid slots, phase locks, and 100 repeated inputs during each animation type.
- Restart from reveal/shuffling/playing/completed, with and without an active selection or animation lock; late transition calls cannot bypass reveal.
- Winning requires correct locations, all upright orientations, and placing the held piece. Completed state is locked.
- 1,000 deterministic full solves with exact operation accounting.
- 50,000 seeded mixed actions, including rapid clicks, rotation, settling, and restart, checking invariants throughout.

`ui_test.gd` instantiates the actual main scene and additionally checks:

- The five-second reveal boundary and solve timer exclusion during reveal/shuffle.
- Real rotation, placement, and swap tweens with repeated input while animating.
- Actual right-click event handler, pointer following, lifted state, and source selection.
- Restart during reveal, shuffle, pickup, rotation, and swapping; killed tween callbacks cannot corrupt the fresh round.
- A complete solution through the real controller, final image reassembly, locked input, and frozen completion time.
- Board, panel, hit-testing, visible widget bounds, and text-content overlap at 1280×900, 1600×900, 720×900, and 900×1200 logical sizes.

These tests inspect real scene state but do not compare pixels. Native visual QA remains necessary for artwork quality, actual glyph appearance, mouse ergonomics, and animation feel.
