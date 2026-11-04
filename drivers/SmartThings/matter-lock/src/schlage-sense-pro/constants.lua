-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

--- Constants for the Schlage Sense Pro UWB door lock.
---
--- Field of view values: 0 front+left+right, 1 front+left, 2 front+right, 3 front only.
--- Intent mode values: 0 unlock on approach, 1 unlock on arrival, 2 unlock on lock interaction.
--- Cluster and attribute IDs below are provisional until the manufacturer cluster is finalized.

local constants = {}

-- Device Identification
constants.SCHLAGE_VENDOR_ID = 0x1236             -- Allegion / Schlage Vendor ID
constants.SCHLAGE_SENSE_PRO_PRODUCT_ID = 0x3800  -- Schlage Sense Pro Product ID

-------------------------------------------------------------------------------------
-- Matter Manufacturer-Specific Cluster Definitions
-- [PLACEHOLDER - ACTION REQUIRED BY ALLEGION]
-------------------------------------------------------------------------------------

--- [PLACEHOLDER - ACTION REQUIRED BY ALLEGION]
--- Manufacturer-specific cluster ID for Schlage UWB Configuration.
--- Allegion engineers MUST replace this placeholder with the official cluster ID
--- allocated for the Schlage Sense Pro UWB configuration cluster.
--- (Typically formatted as (VendorID << 16) | MEI, e.g. 0x1236FC01).
constants.SCHLAGE_UWB_CUSTOM_CLUSTER_ID = 0x1236FC01

--- [PLACEHOLDER - ACTION REQUIRED BY ALLEGION]
--- Attribute ID for Field of View / Approach Direction.
--- Allegion engineers MUST replace this placeholder with the actual attribute ID
--- defined in the custom cluster specification.
constants.ATTR_FIELD_OF_VIEW_ID = 0x0001

--- [PLACEHOLDER - ACTION REQUIRED BY ALLEGION]
--- Attribute ID for Intent Mode / Unlock Behavior.
--- Allegion engineers MUST replace this placeholder with the actual attribute ID
--- defined in the custom cluster specification.
constants.ATTR_INTENT_MODE_ID = 0x0002

--- [PLACEHOLDER - ACTION REQUIRED BY ALLEGION]
--- Command IDs (used only if interaction requires Matter Invoke Commands instead of Attribute Writes).
--- If commands are used, Allegion engineers MUST replace these placeholders with the actual command IDs.
constants.CMD_SET_FIELD_OF_VIEW_ID = 0x0001
constants.CMD_SET_INTENT_MODE_ID = 0x0002

-------------------------------------------------------------------------------------
-- Capability Definitions and Value Mappings
-- [VERIFICATION REQUIRED BY ALLEGION]
-------------------------------------------------------------------------------------

constants.CAPABILITY_LOCK_UWB_APPROACH_SETTINGS = "lockUwbApproachSettings"
constants.CAPABILITY_LOCK_UWB_MODE_SETTINGS = "lockUwbModeSettings"

--- Field of view (lockUwbApproachSettings) mappings.
--- 0: front+left+right, 1: front+left, 2: front+right, 3: front only.
constants.APPROACH_DIRECTION = {
  FRONT_LEFT_RIGHT = "frontLeftRight",
  FRONT_LEFT = "frontLeft",
  FRONT_RIGHT = "frontRight",
  FRONT_ONLY = "frontOnly",
}

constants.RAW_TO_APPROACH_DIRECTION = {
  [0] = constants.APPROACH_DIRECTION.FRONT_LEFT_RIGHT,
  [1] = constants.APPROACH_DIRECTION.FRONT_LEFT,
  [2] = constants.APPROACH_DIRECTION.FRONT_RIGHT,
  [3] = constants.APPROACH_DIRECTION.FRONT_ONLY,
}

constants.APPROACH_DIRECTION_TO_RAW = {
  [constants.APPROACH_DIRECTION.FRONT_LEFT_RIGHT] = 0,
  [constants.APPROACH_DIRECTION.FRONT_LEFT] = 1,
  [constants.APPROACH_DIRECTION.FRONT_RIGHT] = 2,
  [constants.APPROACH_DIRECTION.FRONT_ONLY] = 3,
}

constants.SUPPORTED_APPROACH_DIRECTIONS = {
  constants.APPROACH_DIRECTION.FRONT_LEFT_RIGHT,
  constants.APPROACH_DIRECTION.FRONT_LEFT,
  constants.APPROACH_DIRECTION.FRONT_RIGHT,
  constants.APPROACH_DIRECTION.FRONT_ONLY,
}

--- Intent mode (lockUwbModeSettings) mappings.
--- 0: unlock on approach, 1: unlock on arrival, 2: unlock on lock interaction.
constants.INTENT_MODE = {
  UNLOCK_ON_APPROACH = "unlockOnApproach",
  UNLOCK_ON_ARRIVAL = "unlockOnArrival",
  UNLOCK_ON_INTERACTION = "unlockOnInteraction",
}

constants.RAW_TO_INTENT_MODE = {
  [0] = constants.INTENT_MODE.UNLOCK_ON_APPROACH,
  [1] = constants.INTENT_MODE.UNLOCK_ON_ARRIVAL,
  [2] = constants.INTENT_MODE.UNLOCK_ON_INTERACTION,
}

constants.INTENT_MODE_TO_RAW = {
  [constants.INTENT_MODE.UNLOCK_ON_APPROACH] = 0,
  [constants.INTENT_MODE.UNLOCK_ON_ARRIVAL] = 1,
  [constants.INTENT_MODE.UNLOCK_ON_INTERACTION] = 2,
}

constants.SUPPORTED_INTENT_MODES = {
  constants.INTENT_MODE.UNLOCK_ON_APPROACH,
  constants.INTENT_MODE.UNLOCK_ON_ARRIVAL,
  constants.INTENT_MODE.UNLOCK_ON_INTERACTION,
}

return constants
