local lazy_require = require "st.utils.lazy_require"

local ClosureControlServerCommands = {
  Stop = lazy_require "ClosureControl.server.commands.Stop",
  MoveTo = lazy_require "ClosureControl.server.commands.MoveTo",
  Calibrate = lazy_require "ClosureControl.server.commands.Calibrate",
}
ClosureControlServerCommands[0x0000] = ClosureControlServerCommands.Stop
ClosureControlServerCommands[0x0001] = ClosureControlServerCommands.MoveTo
ClosureControlServerCommands[0x0002] = ClosureControlServerCommands.Calibrate

ClosureControlServerCommands._cluster = require "ClosureControl"

return ClosureControlServerCommands
