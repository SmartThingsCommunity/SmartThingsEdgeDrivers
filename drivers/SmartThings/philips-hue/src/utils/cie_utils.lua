local st_utils = require "st.utils"
-- trick to fix the VS Code Lua Language Server typechecking
---@type fun(val: any?, name: string?, multi_line: boolean?): string
st_utils.stringify_table = st_utils.stringify_table

local CieUtils = {}

local DefaultGamut = {
  red = {x = 0.6915, y = 0.3083},
  green = {x = 0.17, y = 0.7},
  blue = {x = 0.1532, y = 0.0475}
}

---@param val number
---@return number
local function _apply_gamma_correct(val)
  if val > 0.04045 then
    return ((val + 0.055) / (1.0 + 0.055)) ^ (2.4)
  else
    return val / 12.92
  end
end

---@param val number
---@return number
local function _invert_gamma_correct(val)
  if val <= 0.0031308 then
    return val * 12.92
  else
    return (1.055) * (val ^ (1/2.4)) - 0.055
  end
end

---@param a HueColorCoords
---@param b HueColorCoords
---@return number
local function _vec_cross_product(a, b)
  return (a.x * b.y) - (b.x * a.y)
end

---@param xy HueColorCoords
---@param gamut HueGamut
---@return boolean is_in_triangle
local function _xy_in_gamut_triangle(xy, gamut)
  local red = gamut.red
  local green = gamut.green
  local blue = gamut.blue

  local v1 = {}
  local v2 = {}
  local q = {}

  v1.x = green.x - red.x;
  v1.y = green.y - red.y;
  v2.x = blue.x - red.x;
  v2.y = blue.y - red.y;

  q.x = xy.x - red.x;
  q.y = xy.y - red.y;

  local s = _vec_cross_product(q, v2) / _vec_cross_product(v1, v2);
  local t = _vec_cross_product(v1, q) / _vec_cross_product(v1, v2);

  return (s >= 0) and (t >= 0) and (s + t < 1)
end

---@param point HueColorCoords
---@param line_segment_start HueColorCoords
---@param line_segment_end HueColorCoords
---@return HueColorCoords
local function _closest_point_on_line(point, line_segment_start, line_segment_end)
  local AP = {}
  local AB = {}
  AP.x = point.x - line_segment_start.x
  AP.y = point.y - line_segment_start.y
  AB.x = line_segment_end.x - line_segment_start.x
  AB.y = line_segment_end.y - line_segment_start.y

  local ab2 = AB.x * AB.x + AB.y * AB.y
  local ap_ab = AP.x * AB.x + AP.y * AB.y
  local t = st_utils.clamp_value(ap_ab / ab2, 0, 1)

  return {
    x = line_segment_start.x + AB.x * t,
    y = line_segment_start.y + AB.y * t
  }
end

---@param a HueColorCoords
---@param b HueColorCoords
---@return number
local function _distance_between_points(a, b)
  local dx = a.x - b.x
  local dy = a.y - b.y
  return math.sqrt(dx * dx + dy * dy)
end

---@param xy HueColorCoords
---@param gamut HueGamut
---@return HueColorCoords
local function _closest_point_in_gamut_triangle(xy, gamut)
  local red_green_corner = _closest_point_on_line(xy, gamut.red, gamut.green)
  local blue_red_corner = _closest_point_on_line(xy, gamut.blue, gamut.red)
  local green_blue_corner = _closest_point_on_line(xy, gamut.green, gamut.blue)

  local distance_to_red_green = _distance_between_points(xy, red_green_corner)
  local distance_to_blue_red = _distance_between_points(xy, blue_red_corner)
  local distance_to_green_blue = _distance_between_points(xy, green_blue_corner)

  local smallest_distance = distance_to_red_green
  local closest_point = red_green_corner
  if distance_to_blue_red < smallest_distance then
    smallest_distance = distance_to_blue_red
    closest_point = blue_red_corner
  end

  if distance_to_green_blue < smallest_distance then
    closest_point = green_blue_corner
  end

  return closest_point
end

---@param red number
---@param green number
---@param blue number
---@param gamut HueGamut
---@return HueColorCoords
function CieUtils.safe_rgb_to_xy(red, green, blue, gamut)
  if gamut == nil then gamut = DefaultGamut end
  red = _apply_gamma_correct(red)
  green = _apply_gamma_correct(green)
  blue = _apply_gamma_correct(blue)

  local x = red * 0.664511 + green * 0.154324 + blue * 0.162028;
  local y = red * 0.283881 + green * 0.668433 + blue * 0.047685;
  local z = red * 0.000088 + green * 0.072310 + blue * 0.986039;

  local xy = {}
  xy.x = (x / (x + y + z))
  xy.y = (y / (x + y + z))

  -- Portable way to detect NaN in Lua: https://stackoverflow.com/a/37759548/411216
  -- Leverages the fact that NaN is not equal to any value, including itself.
  if xy.x ~= xy.x then xy.x = 0 end
  if xy.y ~= xy.y then xy.y = 0 end

  if not _xy_in_gamut_triangle(xy, gamut) then
    xy = _closest_point_in_gamut_triangle(xy, gamut)
  end

  return xy
end

---@param xy HueColorCoords
---@param gamut HueGamut
---@return number red
---@return number green
---@return number blue
function CieUtils.safe_xy_to_rgb(xy, gamut)
  if gamut == nil then gamut = DefaultGamut end
  if not _xy_in_gamut_triangle(xy, gamut) then
    xy = _closest_point_in_gamut_triangle(xy, gamut)
  end

  local x = xy.x
  local y = xy.y
  local z = 1.0 - x - y
  local y2 = 1.0
  local x2 = (y2 / y) * x
  local z2 = (y2 / y) * z
  -- sRGB D65 conversion
  local r = x2 * 1.656492 - y2 * 0.354851 - z2 * 0.255038
  local g = -x2 * 0.707196 + y2 * 1.655397 + z2 * 0.036152
  local b = x2 * 0.051713 - y2 * 0.121364 + z2 * 1.011530

  if (r > b) and (r > g) and (r > 1) then
    g = g / r
    b = b / r
    r = 1
  elseif (g > b) and (g > r) and (g > 1) then
    r = r / g
    b = b / g
    g = 1
  elseif (b > r) and (b > g) and (b > 1) then
    r = r / b
    g = g / b
    b = 1
  end

  -- apply gamma correction
  r = _invert_gamma_correct(r)
  g = _invert_gamma_correct(g)
  b = _invert_gamma_correct(b)

  if (r > b) and (r > g) then
    if r > 1 then
      g = g / r
      b = b / r
      r = 1.0
    end
  elseif (g > b) and (g > r) then
    if g > 1 then
      r = r / g
      b = b / g
      g = 1.0
    end
  elseif (b > r) and (b > g) then
    if b > 1 then
      r = r / b
      g = g / b
      b = 1.0
    end
  end

  r = st_utils.clamp_value(r, 0, 1)
  g = st_utils.clamp_value(g, 0, 1)
  b = st_utils.clamp_value(b, 0, 1)

  return r, g, b
end

return CieUtils
