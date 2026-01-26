local lazy_require = require "st.utils.lazy_require"

local ClosureControlServerAttributes = {
  CountdownTime = lazy_require "ClosureControl.server.attributes.CountdownTime",
  MainState = lazy_require "ClosureControl.server.attributes.MainState",
  CurrentErrorList = lazy_require "ClosureControl.server.attributes.CurrentErrorList",
  OverallCurrentState = lazy_require "ClosureControl.server.attributes.OverallCurrentState",
  OverallTargetState = lazy_require "ClosureControl.server.attributes.OverallTargetState",
  LatchControlModes = lazy_require "ClosureControl.server.attributes.LatchControlModes",
  AcceptedCommandList = lazy_require "ClosureControl.server.attributes.AcceptedCommandList",
  AttributeList = lazy_require "ClosureControl.server.attributes.AttributeList",
}
ClosureControlServerAttributes[0x0000] = ClosureControlServerAttributes.CountdownTime
ClosureControlServerAttributes[0x0001] = ClosureControlServerAttributes.MainState
ClosureControlServerAttributes[0x0002] = ClosureControlServerAttributes.CurrentErrorList
ClosureControlServerAttributes[0x0003] = ClosureControlServerAttributes.OverallCurrentState
ClosureControlServerAttributes[0x0004] = ClosureControlServerAttributes.OverallTargetState
ClosureControlServerAttributes[0x0005] = ClosureControlServerAttributes.LatchControlModes
ClosureControlServerAttributes[0xFFF9] = ClosureControlServerAttributes.AcceptedCommandList
ClosureControlServerAttributes[0xFFFB] = ClosureControlServerAttributes.AttributeList

ClosureControlServerAttributes._cluster = require "ClosureControl"

return ClosureControlServerAttributes
