-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local lock_constants = {}

lock_constants.DRIVER_STATE = {
  BUSY = "busy",
  COMMAND_IN_PROGRESS = "commandInProgress",
  CREDENTIAL_ARGS_IN_USE = "currentCredential",
  SLGA_MIGRATED = "slgaMigrated",
}

lock_constants.SYNC = {
  CODES_FROM_LOCK = "syncCodesFromLock",
  CODE_INDEX = "syncCodeIndex",
  CONSECUTIVE_UNOCCUPIED_CODES = "consecutiveUnoccupiedCodes",
}

lock_constants.COMMAND_RESULT = {
  SUCCESS = "success",
  FAILURE = "failure",
  DUPLICATE = "duplicate",
  OCCUPIED = "occupied",
  INVALID_COMMAND = "invalidCommand",
  RESOURCE_EXHAUSTED = "resourceExhausted",
  BUSY = "busy"
}

lock_constants.LOCK_CREDENTIALS = {
  ADD = "addCredential",
  UPDATE = "updateCredential",
  DELETE = "deleteCredential",
  DELETE_ALL = "deleteAllCredentials"
}

lock_constants.LOCK_USERS = {
  ADD = "addUser",
  UPDATE = "updateUser",
  DELETE = "deleteUser",
  DELETE_ALL = "deleteAllUsers"
}

lock_constants.CRED_TYPE_PIN = "pin"
-- STOPGAP: lockUsers has no master code userType yet, so master codes are represented as users with
-- "controlOnlyMember", which is otherwise unused by this driver. Replace this once a dedicated type exists.
lock_constants.USER_TYPE_MASTER = "controlOnlyMember"
-- Yale (and ASSA ABLOY iRevo) locks hold their master code at credential index 0.
lock_constants.YALE_MASTER_CODE_SLOT = 0
lock_constants.MASTER_CODE_NAME = "Master Code"
lock_constants.DELAY_LOCK_EVENT = "_delay_lock_event"
lock_constants.MAX_DELAY = 10

return lock_constants
