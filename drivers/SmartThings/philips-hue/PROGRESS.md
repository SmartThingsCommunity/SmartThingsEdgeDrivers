# Refactor Progress

Tracking TODOs for this refactor in this file; this is mostly to allow for creating the draft/WIP PR that the other main PR's will land on. This will will be dropped from history when the refactor is done.

## Sections

### Discovery

#### Tasks

- [x] Convert supported resources map to a map of handlers instead of boolean ✅ 2024-04-16
- [x] Move handlers to their own file ✅ 2024-04-16
- [x] Rename the "light_state_disco_cache" key to be service type agnostic ✅ 2024-04-16
- [x] Update the `discovered_device_callback` function to allow for other device types ✅ 2024-04-16

### Capability Handlers

#### Tasks

- [x] Create a table of handlers for dispatching refreshes by device type ✅ 2024-04-17
- [x] Fix `refresh_all_for_bridge` to remove assumptions that all child devices are lights ✅ 2024-04-17

### Driver (init.lua) Refactors

#### Tasks

- [ ] Extract lifecycle handlers to their own module(s)
  - [x] 2024-04-18 Update: Initial code review missed that `is_*_bridge` and `is_*_light` calls in `utils` were implemented such that the check for light was based on failing the check for bridge. So those need to be fixed as well.  ✅ 2024-04-22
- [x] Extract attribute event emitters to their own module(s) ✅ 2024-04-17
- [ ] Refactor Stray Light Handler to be a general Stray Device Handler
- [ ] Refactor SSE `onmessage` callback to remove light-specific assumptions
  - [ ] `update` messages are hard coded to emit light events with no checks
  - [ ] `add` message handling rejects non-light devices instead of being written to be extensible

### Miscellaneous/Custodial

#### Tasks

- [ ] Update all doc strings that claim we only support bridges and lights
- [ ] Update any dangling utility methods/variables/symbols that use "light" when they should use "device"
