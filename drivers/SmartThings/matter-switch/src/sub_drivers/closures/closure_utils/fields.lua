-- Copyright © 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local ClosureFields = {}

ClosureFields.CURRENT_LIFT = "__current_lift"
ClosureFields.CURRENT_TILT = "__current_tilt"
ClosureFields.DEFAULT_PRESET_LEVEL = 50
ClosureFields.PRESET_LEVEL_KEY = "__preset_level_key"
ClosureFields.REVERSE_POLARITY = "__reverse_polarity"
-- Endpoint-scoped ClosureControl state cache key. A table is stored for each endpoint:
-- { main = <MainStateEnum>, current = <CurrentPositionEnum>, target = <TargetPositionEnum> }
ClosureFields.CLOSURE_CONTROL_STATE_CACHE = "__closure_control_state_cache"

return ClosureFields
