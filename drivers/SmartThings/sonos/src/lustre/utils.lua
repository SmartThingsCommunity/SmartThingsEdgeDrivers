local log = require"quietlog"

local U8_AS_I8 = {
  [0] = 0,
  [1] = 1,
  [2] = 2,
  [3] = 3,
  [4] = 4,
  [5] = 5,
  [6] = 6,
  [7] = 7,
  [8] = 8,
  [9] = 9,
  [10] = 10,
  [11] = 11,
  [12] = 12,
  [13] = 13,
  [14] = 14,
  [15] = 15,
  [16] = 16,
  [17] = 17,
  [18] = 18,
  [19] = 19,
  [20] = 20,
  [21] = 21,
  [22] = 22,
  [23] = 23,
  [24] = 24,
  [25] = 25,
  [26] = 26,
  [27] = 27,
  [28] = 28,
  [29] = 29,
  [30] = 30,
  [31] = 31,
  [32] = 32,
  [33] = 33,
  [34] = 34,
  [35] = 35,
  [36] = 36,
  [37] = 37,
  [38] = 38,
  [39] = 39,
  [40] = 40,
  [41] = 41,
  [42] = 42,
  [43] = 43,
  [44] = 44,
  [45] = 45,
  [46] = 46,
  [47] = 47,
  [48] = 48,
  [49] = 49,
  [50] = 50,
  [51] = 51,
  [52] = 52,
  [53] = 53,
  [54] = 54,
  [55] = 55,
  [56] = 56,
  [57] = 57,
  [58] = 58,
  [59] = 59,
  [60] = 60,
  [61] = 61,
  [62] = 62,
  [63] = 63,
  [64] = 64,
  [65] = 65,
  [66] = 66,
  [67] = 67,
  [68] = 68,
  [69] = 69,
  [70] = 70,
  [71] = 71,
  [72] = 72,
  [73] = 73,
  [74] = 74,
  [75] = 75,
  [76] = 76,
  [77] = 77,
  [78] = 78,
  [79] = 79,
  [80] = 80,
  [81] = 81,
  [82] = 82,
  [83] = 83,
  [84] = 84,
  [85] = 85,
  [86] = 86,
  [87] = 87,
  [88] = 88,
  [89] = 89,
  [90] = 90,
  [91] = 91,
  [92] = 92,
  [93] = 93,
  [94] = 94,
  [95] = 95,
  [96] = 96,
  [97] = 97,
  [98] = 98,
  [99] = 99,
  [100] = 100,
  [101] = 101,
  [102] = 102,
  [103] = 103,
  [104] = 104,
  [105] = 105,
  [106] = 106,
  [107] = 107,
  [108] = 108,
  [109] = 109,
  [110] = 110,
  [111] = 111,
  [112] = 112,
  [113] = 113,
  [114] = 114,
  [115] = 115,
  [116] = 116,
  [117] = 117,
  [118] = 118,
  [119] = 119,
  [120] = 120,
  [121] = 121,
  [122] = 122,
  [123] = 123,
  [124] = 124,
  [125] = 125,
  [126] = 126,
  [127] = 127,
  [128] = -128,
  [129] = -127,
  [130] = -126,
  [131] = -125,
  [132] = -124,
  [133] = -123,
  [134] = -122,
  [135] = -121,
  [136] = -120,
  [137] = -119,
  [138] = -118,
  [139] = -117,
  [140] = -116,
  [141] = -115,
  [142] = -114,
  [143] = -113,
  [144] = -112,
  [145] = -111,
  [146] = -110,
  [147] = -109,
  [148] = -108,
  [149] = -107,
  [150] = -106,
  [151] = -105,
  [152] = -104,
  [153] = -103,
  [154] = -102,
  [155] = -101,
  [156] = -100,
  [157] = -99,
  [158] = -98,
  [159] = -97,
  [160] = -96,
  [161] = -95,
  [162] = -94,
  [163] = -93,
  [164] = -92,
  [165] = -91,
  [166] = -90,
  [167] = -89,
  [168] = -88,
  [169] = -87,
  [170] = -86,
  [171] = -85,
  [172] = -84,
  [173] = -83,
  [174] = -82,
  [175] = -81,
  [176] = -80,
  [177] = -79,
  [178] = -78,
  [179] = -77,
  [180] = -76,
  [181] = -75,
  [182] = -74,
  [183] = -73,
  [184] = -72,
  [185] = -71,
  [186] = -70,
  [187] = -69,
  [188] = -68,
  [189] = -67,
  [190] = -66,
  [191] = -65,
  [192] = -64,
  [193] = -63,
  [194] = -62,
  [195] = -61,
  [196] = -60,
  [197] = -59,
  [198] = -58,
  [199] = -57,
  [200] = -56,
  [201] = -55,
  [202] = -54,
  [203] = -53,
  [204] = -52,
  [205] = -51,
  [206] = -50,
  [207] = -49,
  [208] = -48,
  [209] = -47,
  [210] = -46,
  [211] = -45,
  [212] = -44,
  [213] = -43,
  [214] = -42,
  [215] = -41,
  [216] = -40,
  [217] = -39,
  [218] = -38,
  [219] = -37,
  [220] = -36,
  [221] = -35,
  [222] = -34,
  [223] = -33,
  [224] = -32,
  [225] = -31,
  [226] = -30,
  [227] = -29,
  [228] = -28,
  [229] = -27,
  [230] = -26,
  [231] = -25,
  [232] = -24,
  [233] = -23,
  [234] = -22,
  [235] = -21,
  [236] = -20,
  [237] = -19,
  [238] = -18,
  [239] = -17,
  [240] = -16,
  [241] = -15,
  [242] = -14,
  [243] = -13,
  [244] = -12,
  [245] = -11,
  [246] = -10,
  [247] = -9,
  [248] = -8,
  [249] = -7,
  [250] = -6,
  [251] = -5,
  [252] = -4,
  [253] = -3,
  [254] = -2,
  [255] = -1,
}

-- https://tools.ietf.org/html/rfc3629
-- LuaFormatter off
local UTF8_CHAR_WIDTH = {
      -- 1  2  3  4  5  6  7  8  9  A  B  C  D  E  F
[0] = 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, -- 0
      1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, -- 1
      1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, -- 2
      1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, -- 3
      1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, -- 4
      1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, -- 5
      1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, -- 6
      1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, -- 7
      0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, -- 8
      0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, -- 9
      0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, -- A
      0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, -- B
      0, 0, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, -- C
      2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, -- D
      3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, -- E
      4, 4, 4, 4, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, -- F
}
-- LuaFormatter on

local function get_print_safe_string(str, limit)
  local ret
  if str:match("^[%g ]+$") ~= nil then
    if limit and #str > limit then
      ret = string.format("%s", string.sub(str, 1,
        limit) .. "...")
    else
      ret = string.format("%s", str)
    end
  else
    local fmt, len
    if limit and #str > limit then
      fmt = string.rep("\\x%02X", limit)
      len = limit
    else
      fmt = string.rep("\\x%02X", #str)
      len = #str
    end
    ret = string.format(fmt,
      string.byte(str, 1, len))
  end
  return ret
end

local key_order_cmp = function(key1, key2)
  local type1 = type(key1)
  local type2 = type(key2)
  if type1 ~= type2 then
    return type1 < type2
  elseif type1 == "number" or type1 == "string" then -- comparable types
    return key1 < key2
  elseif type1 == "boolean" then
    return key1 == true
  else
    return tostring(key1) < tostring(key2)
  end
end

local stringify_table_helper

stringify_table_helper = function(val, name,
  multi_line, indent, previously_printed,
  str_limit)
  local tabStr = multi_line
                   and string.rep(" ", indent)
                   or ""

  if name then
    tabStr = tabStr .. tostring(name) .. "="
  end

  local multi_line_str = ""
  if multi_line then
    multi_line_str = "\n"
  end

  if type(val) == "table" then
    if not previously_printed[val] then
      tabStr = tabStr .. "{" .. multi_line_str
      -- sort keys for repeatability of print
      local tkeys = {}
      for k in pairs(val) do
        table.insert(tkeys, k)
      end
      table.sort(tkeys, key_order_cmp)

      for _, k in ipairs(tkeys) do
        local v = val[k]
        previously_printed[val] = name
        if #val > 0 and type(k) == "number" then
          tabStr = tabStr
                     .. stringify_table_helper(v,
              nil, multi_line, indent + 2,
              previously_printed, str_limit)
                     .. ", " .. multi_line_str
        else
          tabStr = tabStr
                     .. stringify_table_helper(v,
              k, multi_line, indent + 2,
              previously_printed, str_limit)
                     .. ", " .. multi_line_str
        end
      end
      if tabStr:sub(#tabStr, #tabStr) == "\n"
        and tabStr:sub(#tabStr - 1, #tabStr - 1)
        == "{" then
        tabStr = tabStr:sub(1, -2) .. "}"
      elseif tabStr:sub(#tabStr - 1, #tabStr - 1)
        == "," then
        tabStr = tabStr:sub(1, -3)
                   .. (multi_line
                     and string.rep(" ", indent)
                     or "") .. "}"
      else
        tabStr = tabStr
                   .. (multi_line
                     and string.rep(" ", indent)
                     or "") .. "}"
      end
    else
      tabStr = tabStr .. "RecursiveTable: "
                 .. previously_printed[val]
    end
  elseif type(val) == "number" then
    tabStr = tabStr .. tostring(val)
  elseif type(val) == "string" then
    tabStr = tabStr .. "\""
               .. get_print_safe_string(val,
        str_limit) .. "\""
  elseif type(val) == "boolean" then
    tabStr = tabStr .. (val and "true" or "false")
  elseif type(val) == "function" then
    tabStr = tabStr .. tostring(val)
  else
    tabStr = tabStr .. "\"[unknown datatype:"
               .. type(val) .. "]\""
  end

  return tabStr
end

--- Convert value to string
---@param val table Value to stringify
---@param name string Print a name along with value [Optional]
---@param multi_line boolean use newlines to provide a more easily human readable string [Optional]
---@returns string String representation of `val`
local function table_string(val, name, multi_line,
  str_limit)
  return stringify_table_helper(val, name,
    multi_line, 0, {}, str_limit)
end

local function trailer_is_in_range(byte)
  local as_i8 = U8_AS_I8[byte]
  if not as_i8 then
    error("byte too large: ", byte)
  end
  log.trace("trailer_is_in_range", byte, as_i8,
    as_i8 < -64)
  return as_i8 < -64
end

local function valid_3_byte_set(one, two, three)
  -- 0xE0, 0xA0..=0xBF)
  if one == 0xE0 then
    if two >= 0xA0 and two <= 0xBF
      and trailer_is_in_range(three) then
      return true
    end
    return false, "Invalid UTF-8 Continue"
  end
  -- | (0xE1..=0xEC, 0x80..=0xBF)
  if one >= 0xE1 and one <= 0xEC then
    if two >= 0x80 and two <= 0xBF
      and trailer_is_in_range(three) then
      return true
    end
    return false, "Invalid UTF-8 Continue"
  end
  -- | (0xED, 0x80..=0x9F)
  if one == 0xED then
    if two >= 0x80 and two <= 0x9F
      and trailer_is_in_range(three) then
      return true
    end
    return false, "Invalid UTF-8 Continue"
  end
  -- | (0xEE..=0xEF, 0x80..=0xBF) => {}
  if one >= 0xEE and one <= 0xEF then
    if two >= 0x80 and two <= 0xBF
      and trailer_is_in_range(three) then
      return true
    end
    return false, "Invalid UTF-8 Continue"
  end
  if trailer_is_in_range(three) then
    return true
  end
  return false, "Invalid UTF-8 Continue"
end

local function valid_4_byte_set(one, two, three,
  four)
  -- (0xF0, 0x90..=0xBF) 
  if one == 0xF0 then
    return two >= 0x90 and two <= 0xBF
             and trailer_is_in_range(three)
             and trailer_is_in_range(four)
  end
  -- | (0xF1..=0xF3, 0x80..=0xBF)
  -- | (0xF4, 0x80..=0x8F)
  if one == 0xF4 then
    log.trace("found 0xf4",
      string.format("%x", two))
    if two >= 0x80 and two <= 0x8F
      and trailer_is_in_range(three)
      and trailer_is_in_range(four) then
      return true
    end
  end
  if (one >= 0xF1 and one <= 0xF3) then
    if two >= 0x80 and two <= 0xBF
      and trailer_is_in_range(three)
      and trailer_is_in_range(four) then
      return true
    end
  end
  return false, "Invalid UTF-8 Continue"
end

local function check_for_range(len, one, two,
  three, four)
  log.trace("check_for_range", len, one, two,
    three, four)
  if len == 4 then
    if not (two and three and four) then
      local count = (four and 1 or 0)
                      + (three and 1 or 0)
                      + (two and 1 or 0) + 1
      return nil, "Invalid UTF-8 too short",
        -count
    end
    log.trace("four byte check")
    return valid_4_byte_set(one, two, three, four)
  end
  if len == 3 then
    log.trace("three byte check")
    if not (two and three) then
      local count = (three and 1 or 0)
                      + (two and 1 or 0) + 1
      return nil, "Invalid UTF-8 too short",
        -count
    end
    return valid_3_byte_set(one, two, three)
  end
  if len == 2 then
    log.trace("two byte check")
    if not two then
      return nil, "Invalid UTF-8 too short", -1
    end
    if trailer_is_in_range(two) then
      return true
    end
    return false, "Invalid UTF-8 Continue"
  end
  if len > 4 then
    return nil, "Sequence too long"
  end
  log.trace("one byte check")
  if (one & 0x80) == 0 then
    return true
  else
    return false, "Invalid UTF-8 Start"
  end
end

local function validate_utf8(s)
  if type(s) ~= "string" then
    log.error("can't validate non string",
      debug.traceback())
    return nil,
      "Type Error, expected string found "
        .. type(s)
  end
  local i = 1
  for _ in string.gmatch(s, "["
    .. string.char(0xFF, 0xFE) .. "]") do
    return nil, "Invalid UTF-8 Byte"
  end

  while i <= #s do
    local first = s:byte(i)
    -- log.trace(i, 'first', first)
    if first < 128 then
      if first & 0x80 ~= 0 then
        -- log.trace("1 byte character can't have 128 set")
        return nil, "Invalid UTF-8 Sequence Start"
      end
      return 1
    end
    local width = UTF8_CHAR_WIDTH[first]
    if width < 2 or width > 4 then
      return nil, "Invalid UTF-8 Length"
    end
    log.trace("checking for range", first, width)
    local suc, e, idx = check_for_range(width,
      string.byte(s, i, i + width - 1))
    if not suc then
      return nil, e, idx
    end
    i = i + width
  end
  return 1
end

return {
  table_string = table_string,
  validate_utf8 = validate_utf8,
}
