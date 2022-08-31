-- Copyright 2022 SmartThings
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

local presence_utils = {}

-- used when presence events are based on battery reports
presence_utils.LAST_CHECKIN_TIMESTAMP = "lastCheckinTimestamp"

presence_utils.PRESENCE_CALLBACK_CREATE_FN = "presenceCallbackCreateFn"

-- events are based on battery reports
presence_utils.PRESENCE_CALLBACK_TIMER = "presenceCallbackTimer"

-- events are based on recurring poll of Basic cluster's attribute
presence_utils.RECURRING_POLL_TIMER = "recurringPollTimer"

return presence_utils
