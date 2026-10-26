-- Copyright 2026 SmartThings, Inc.
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

--- Constants and Specification Scaffolding for Allegion / Schlage Sense Pro UWB Door Lock
---
--- Reference Specifications:
--- 1. Confluence: "Schlage Sense Pro (Aliro) - UWB Configuration and Feature Support" (Page 5350097136)
--- 2. Confluence: "Action plan for Schlage UWB configuration" (Page 5392597723)
---
--- Feature Overview:
--- 1. Field of View (Detection Area):
---    Allowed values per Allegion spec:
---      0: Front + Left + Right (all directions)
---      1: Front + Left
---      2: Front + Right
---      3: Front only
---    SmartThings Capability: lockUwbApproachSettings
---
--- 2. Intent Mode (Unlock Behavior):
---    Allowed values per Allegion spec:
---      0: Unlock on Approach
---      1: Unlock on Arrival
---      2: Unlock on Lock Interaction
---    SmartThings Capability: lockUwbModeSettings
---
--- NOTE FOR ALLEGION ENGINEERS:
--- Update the manufacturer-specific Matter cluster ID, attribute IDs, command IDs,
--- and data types below to match your final Matter cluster specification.

local capabilities = require "st.capabilities"

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

--- Field of View (lockUwbApproachSettings) mappings
--- [PLACEHOLDER / VERIFY]: Update this mapping table if the device's raw attribute values differ from the defaults below.
--- Default per Confluence 5350097136 / 5392597723:
---   0: Front+Left+Right, 1: Front+Left, 2: Front+Right, 3: Front only
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

--- Intent Mode (lockUwbModeSettings) mappings
--- [PLACEHOLDER / VERIFY]: Update this mapping table if the device's raw attribute values differ from the defaults below.
--- Default per Confluence 5350097136 / 5392597723:
---   0: Unlock on Approach, 1: Unlock on Arrival, 2: Unlock on Lock Interaction
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

-------------------------------------------------------------------------------------
-- Fallback Capability Builders (Pre-27R1 Compatibility)
-------------------------------------------------------------------------------------

constants.APPROACH_CAP_JSON = [[{
  "name": "Lock UWB Approach Settings",
  "id": "lockUwbApproachSettings",
  "version": 1,
  "attributes": {
    "approachDirection": {
      "schema": {
        "type": "object",
        "properties": {
          "value": {
            "type": "string",
            "enum": ["frontLeftRight", "frontLeft", "frontRight", "frontOnly"]
          }
        },
        "required": ["value"]
      }
    },
    "supportedApproachDirections": {
      "schema": {
        "type": "object",
        "properties": {
          "value": {
            "type": "array",
            "items": { "type": "string" }
          }
        },
        "required": ["value"]
      }
    }
  },
  "commands": {
    "setApproachDirection": {
      "name": "setApproachDirection",
      "arguments": [
        {
          "name": "approachDirection",
          "schema": {
            "type": "string",
            "enum": ["frontLeftRight", "frontLeft", "frontRight", "frontOnly"]
          },
          "optional": false
        }
      ]
    }
  }
}]]

constants.MODE_CAP_JSON = [[{
  "name": "Lock UWB Mode Settings",
  "id": "lockUwbModeSettings",
  "version": 1,
  "attributes": {
    "intentMode": {
      "schema": {
        "type": "object",
        "properties": {
          "value": {
            "type": "string",
            "enum": ["unlockOnApproach", "unlockOnArrival", "unlockOnInteraction"]
          }
        },
        "required": ["value"]
      }
    },
    "supportedIntentModes": {
      "schema": {
        "type": "object",
        "properties": {
          "value": {
            "type": "array",
            "items": { "type": "string" }
          }
        },
        "required": ["value"]
      }
    }
  },
  "commands": {
    "setIntentMode": {
      "name": "setIntentMode",
      "arguments": [
        {
          "name": "intentMode",
          "schema": {
            "type": "string",
            "enum": ["unlockOnApproach", "unlockOnArrival", "unlockOnInteraction"]
          },
          "optional": false
        }
      ]
    }
  }
}]]

local function load_or_build(cap_id, cap_json)
  local status, cap = pcall(function() return capabilities[cap_id] end)
  if status and cap and pcall(function() return cap.commands end) and cap.commands ~= nil then
    return cap
  end
  return capabilities.build_cap_from_json_string(cap_json)
end

function constants.get_lock_uwb_approach_settings_capability()
  return load_or_build(constants.CAPABILITY_LOCK_UWB_APPROACH_SETTINGS, constants.APPROACH_CAP_JSON)
end

function constants.get_lock_uwb_mode_settings_capability()
  return load_or_build(constants.CAPABILITY_LOCK_UWB_MODE_SETTINGS, constants.MODE_CAP_JSON)
end

return constants
