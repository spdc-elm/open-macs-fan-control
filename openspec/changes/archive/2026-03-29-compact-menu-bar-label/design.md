## Summary

This change stays within the existing single `MenuBarExtra` structure and only adjusts the label view.

## Design Decisions

- Keep one menu bar item instead of introducing multiple independent status items.
- Replace the current single long text row with a compact grouped label that still shows CPU, GPU, and fan summary values.
- Treat the indicator dot as an automatic-control state badge:
  - gray when control is idle
  - green when control is running
  - orange when control is starting or stopping
  - red when control has failed or a controller error is present

## Notes

- This uses the existing `AutomaticControlStatusSnapshot.phase` model and does not require runtime or controller protocol changes.
- The implementation should prefer a simple SwiftUI layout change over any lower-level AppKit status-item rewrite.
