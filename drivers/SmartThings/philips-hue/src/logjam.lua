local log = require "log"

local logjam = {}
function logjam.log(opts, level, ...)
  if opts.on == true then
    log.log(opts, level, ...)
  end
end

for field_key, level_key in pairs(log) do
  if
      string.find(field_key, "LOG_LEVEL_") and
      type(level_key) == "string" and
      type(log[level_key]) == "function"
  then
    local level_with_key = string.format("%s_with", level_key)
    logjam[level_key] = function(...)
      local first_arg = select(1, ...)
      if first_arg == true or (type(first_arg) == "table" and first_arg.on == true) then
        log[level_key](select(2, ...))
      end
    end

    logjam[level_with_key] = function(opts, ...)
      opts = opts or {}
      if opts.on == true then
        log[level_with_key](...)
      end
    end
  end
end

return logjam
