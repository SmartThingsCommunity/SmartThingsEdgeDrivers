--TODO remove the usage of these color utils once 0.48.x has been distributed
-- to all hubs.
local color_utils = {}
local utils = require "st.utils"

local function color_gamma_revert(value)
  return value <= 0.0031308 and 12.92 * value or (1.0 + 0.055) * (value ^ (1.0 / 2.4)) - 0.055
end

--- Convert from x/y/Y to Red/Green/Blue
---
--- @param x number x axis non-negative value
--- @param y number y axis non-negative value
--- @param Y number Y tristimulus value
--- @returns number, number, number equivalent red, green, blue vector with each color in the range [0,1]
color_utils.xy_to_rgb = function(x, y, Y)
  local subexpr = y ~= 0 and (Y / y) or 0
  local X = subexpr * x
  local Z = subexpr * (1.0 - x - y)

  local M = {
    {  3.2404542, -1.5371385, -0.4985314 },
    { -0.9692660,  1.8760108,  0.0415560 },
    {  0.0556434, -0.2040259,  1.0572252 }
  }

  local r = X * M[1][1] + Y * M[1][2] + Z * M[1][3]
  local g = X * M[2][1] + Y * M[2][2] + Z * M[2][3]
  local b = X * M[3][1] + Y * M[3][2] + Z * M[3][3]

  r = r < 0 and 0 or r
  r = r > 1 and 1 or r
  g = g < 0 and 0 or g
  g = g > 1 and 1 or g
  b = b < 0 and 0 or b
  b = b > 1 and 1 or b

  local max_rgb = math.max(r, g, b)
  r = color_gamma_revert(r / max_rgb)
  g = color_gamma_revert(g / max_rgb)
  b = color_gamma_revert(b / max_rgb)

  return r, g, b
end

--- Convert from x/y/Y to Hue/Saturation
--- If every value is missing then [x, y, Y] = [0, 0, 1]
---
--- @param x number red in range [0x0000, 0xFFFF]
--- @param y number green in range [0x0000, 0xFFFF]
--- @param Y number blue in range [0x0000, 0xFFFF]
--- @returns number, number equivalent hue, saturation, level each in range [0,100]%
color_utils.safe_xy_to_hsv = function(x, y, Y)
  local safe_x = x ~= nil and x / 65536 or 0
  local safe_y = y ~= nil and y / 65536 or 0
  local safe_Y = Y ~= nil and Y or 1

  local r, g, b = color_utils.xy_to_rgb(safe_x, safe_y, safe_Y)
  local h, s, v = utils.rgb_to_hsv(r, g, b)

  return utils.round(h * 100), utils.round(s * 100), utils.round(v * 100)
end

return color_utils