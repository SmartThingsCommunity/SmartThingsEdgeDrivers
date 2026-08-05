local OperationalStateTypes = require "OperationalState.types"

local OperationalState = {}

OperationalState.ID = 0x0060
OperationalState.NAME = "OperationalState"
OperationalState.server = {}
OperationalState.client = {}
OperationalState.types = OperationalStateTypes

return OperationalState
