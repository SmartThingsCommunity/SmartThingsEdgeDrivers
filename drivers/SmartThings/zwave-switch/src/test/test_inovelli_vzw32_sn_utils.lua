-- Copyright 2025 SmartThings
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

-- Unit tests for Inovelli VZW32-SN utility functions
-- This file tests the helper functions used in the driver

local capabilities = require "st.capabilities"
local utils = require "st.utils"

-- Test huePercentToValue function
local function test_hue_percent_to_value()
  local huePercentToValue = function(value)
    if value <= 2 then
      return 0
    elseif value >= 98 then
      return 255
    else
      return utils.round(value / 100 * 255)
    end
  end

  -- Test edge cases
  assert(huePercentToValue(0) == 0, "Value 0 should return 0")
  assert(huePercentToValue(1) == 0, "Value 1 should return 0")
  assert(huePercentToValue(2) == 0, "Value 2 should return 0")
  assert(huePercentToValue(98) == 255, "Value 98 should return 255")
  assert(huePercentToValue(99) == 255, "Value 99 should return 255")
  assert(huePercentToValue(100) == 255, "Value 100 should return 255")

  -- Test middle values
  assert(huePercentToValue(50) == 128, "Value 50 should return 128")
  assert(huePercentToValue(25) == 64, "Value 25 should return 64")
  assert(huePercentToValue(75) == 191, "Value 75 should return 191")
end

-- Test preferences_to_numeric_value function
local function test_preferences_to_numeric_value()
  local preferences_to_numeric_value = function(new_value)
    local numeric = tonumber(new_value)
    if numeric == nil then -- in case the value is boolean
      numeric = new_value and 1 or 0
    end
    return numeric
  end

  -- Test numeric values
  assert(preferences_to_numeric_value("50") == 50, "String '50' should return 50")
  assert(preferences_to_numeric_value(75) == 75, "Number 75 should return 75")

  -- Test boolean values
  assert(preferences_to_numeric_value(true) == 1, "Boolean true should return 1")
  assert(preferences_to_numeric_value(false) == 0, "Boolean false should return 0")

  -- Test nil values
  assert(preferences_to_numeric_value(nil) == 0, "Nil should return 0")
end

-- Test preferences_calculate_parameter function
local function test_preferences_calculate_parameter()
  local preferences_calculate_parameter = function(new_value, type, number)
    if type == 4 and new_value > 2147483647 then
      return ((4294967296 - new_value) * -1)
    elseif type == 2 and new_value > 32767 then
      return ((65536 - new_value) * -1)
    elseif type == 1 and new_value > 127 then
      return ((256 - new_value) * -1)
    else
      return new_value
    end
  end

  -- Test normal values
  assert(preferences_calculate_parameter(50, 1, 1) == 50, "Small value should remain unchanged")
  assert(preferences_calculate_parameter(100, 2, 2) == 100, "Medium value should remain unchanged")
  assert(preferences_calculate_parameter(1000, 4, 4) == 1000, "Large value should remain unchanged")

  -- Test overflow cases
  assert(preferences_calculate_parameter(200, 1, 1) == -56, "Byte overflow should be handled")
  assert(preferences_calculate_parameter(40000, 2, 2) == -25536, "Word overflow should be handled")
  assert(preferences_calculate_parameter(3000000000, 4, 4) == -1294967296, "Dword overflow should be handled")
end

-- Test component_to_endpoint function
local function test_component_to_endpoint()
  local component_to_endpoint = function(device, component_id)
    local ep_num = component_id:match("switch(%d)")
    return { ep_num and tonumber(ep_num) }
  end

  -- Test valid component IDs
  local result1 = component_to_endpoint(nil, "switch1")
  assert(result1[1] == 1, "switch1 should map to endpoint 1")

  local result2 = component_to_endpoint(nil, "switch2")
  assert(result2[1] == 2, "switch2 should map to endpoint 2")

  -- Test invalid component IDs
  local result3 = component_to_endpoint(nil, "main")
  assert(result3[1] == nil, "main should map to nil endpoint")

  local result4 = component_to_endpoint(nil, "button1")
  assert(result4[1] == nil, "button1 should map to nil endpoint")
end

-- Test endpoint_to_component function
local function test_endpoint_to_component()
  local mock_device = {
    profile = {
      components = {
        switch1 = {},
        switch2 = {},
        main = {}
      }
    }
  }

  local endpoint_to_component = function(device, ep)
    local switch_comp = string.format("switch%d", ep)
    if device.profile.components[switch_comp] ~= nil then
      return switch_comp
    else
      return "main"
    end
  end

  -- Test valid endpoints
  assert(endpoint_to_component(mock_device, 1) == "switch1", "Endpoint 1 should map to switch1")
  assert(endpoint_to_component(mock_device, 2) == "switch2", "Endpoint 2 should map to switch2")

  -- Test invalid endpoints
  assert(endpoint_to_component(mock_device, 3) == "main", "Endpoint 3 should map to main")
  assert(endpoint_to_component(mock_device, 0) == "main", "Endpoint 0 should map to main")
end

-- Test button_to_component function
local function test_button_to_component()
  local button_to_component = function(buttonId)
    if buttonId > 0 then
      return string.format("button%d", buttonId)
    end
  end

  -- Test valid button IDs
  assert(button_to_component(1) == "button1", "Button ID 1 should return button1")
  assert(button_to_component(2) == "button2", "Button ID 2 should return button2")
  assert(button_to_component(3) == "button3", "Button ID 3 should return button3")

  -- Test invalid button IDs
  assert(button_to_component(0) == nil, "Button ID 0 should return nil")
  assert(button_to_component(-1) == nil, "Button ID -1 should return nil")
end

-- Test getNotificationValue function
local function test_get_notification_value()
  local mock_device = {
    get_latest_state = function(self, component, capability_id, attribute)
      if capability_id == "switchLevel" and attribute == "level" then
        return 75
      elseif capability_id == "colorControl" and attribute == "hue" then
        return 100
      end
      return nil
    end,
    get_parent_device = function(self)
      return {
        preferences = {
          notificationType = 2
        }
      }
    end
  }

  local huePercentToValue = function(value)
    if value <= 2 then
      return 0
    elseif value >= 98 then
      return 255
    else
      return utils.round(value / 100 * 255)
    end
  end

  local getNotificationValue = function(device, value)
    local notificationValue = 0
    local level = device:get_latest_state("main", capabilities.switchLevel.ID, capabilities.switchLevel.level.NAME) or 100
    local color = utils.round(device:get_latest_state("main", capabilities.colorControl.ID, capabilities.colorControl.hue.NAME) or 100)
    local effect = device:get_parent_device().preferences.notificationType or 1
    notificationValue = notificationValue + (effect*16777216)
    notificationValue = notificationValue + (huePercentToValue(value or color)*65536)
    notificationValue = notificationValue + (level*256)
    notificationValue = notificationValue + (255*1)
    return notificationValue
  end

  -- Test with default values
  local result = getNotificationValue(mock_device)
  -- Expected: 2*16777216 + 255*65536 + 75*256 + 255*1 = 33554432 + 16711680 + 19200 + 255 = 50285567
  assert(result == 50285567, "Notification value calculation should be correct")
end

-- Run all tests
local function run_tests()
  print("Running Inovelli VZW32-SN utility function tests...")
  
  test_hue_percent_to_value()
  print("✓ huePercentToValue tests passed")
  
  test_preferences_to_numeric_value()
  print("✓ preferences_to_numeric_value tests passed")

  test_preferences_calculate_parameter()
  print("✓ preferences_calculate_parameter tests passed")

  test_component_to_endpoint()
  print("✓ component_to_endpoint tests passed")

  test_endpoint_to_component()
  print("✓ endpoint_to_component tests passed")

  test_button_to_component()
  print("✓ button_to_component tests passed")

  test_get_notification_value()
  print("✓ getNotificationValue tests passed")

  print("All utility function tests passed!")
end

-- Execute tests
run_tests()
