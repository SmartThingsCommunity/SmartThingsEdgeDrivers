# Refactor Progress

Tracking TODOs for this refactor in this file; this is mostly to allow for creating the draft/WIP PR that the other main PR's will land on. This will will be dropped from history when the refactor is done.

## Sections

### Discovery

#### Tasks

- [x] Convert supported resources map to a map of handlers instead of boolean
- [x] Move handlers to their own file
- [x] Rename the "light_state_disco_cache" key to be service type agnostic
- [x] Update the `discovered_device_callback` function to allow for other device types

### Capability Handlers

#### Tasks

- [x] Create a table of handlers for dispatching refreshes by device type
- [x] Fix `refresh_all_for_bridge` to remove assumptions that all child devices are lights

### Driver (init.lua) Refactors

#### Tasks

- [x] Extract lifecycle handlers to their own module(s)
  - [x] 2024-04-18 Update: Initial code review missed that `is_*_bridge` and `is_*_light` calls in `utils` were implemented such that the check for light was based on failing the check for bridge. So those need to be fixed as well.
- [x] Extract attribute event emitters to their own module(s)
- [x] Refactor Stray Light Handler to be a general Stray Device Handler
- [x] Refactor SSE `onmessage` callback to remove light-specific assumptions
  - [x] `update` messages are hard coded to emit light events with no checks
  - [x] `add` message handling rejects non-light devices instead of being written to be extensible

### Miscellaneous/Custodial

#### Tasks

- [ ] Refactor fresh handlers to be a single generic refresh handler, which is only possible once all of the above is complete.
- [x] Update all doc strings that claim we only support bridges and lights
- [x] Update any dangling utility methods/variables/symbols that use "light" when they should use "device"
- [x] Normalize modules to all use `<dir>/init.lua` instead of `<mod>.lua` as a sibling to `<dir>`.
