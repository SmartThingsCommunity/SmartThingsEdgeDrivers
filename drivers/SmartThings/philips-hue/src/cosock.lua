local socket = require "cosock.socket"
local nativesocket = require "socket"
local channel = require "cosock.channel"
local timer = require "cosock.timer"
local ssl = require "cosock.ssl"

local weaktable = { __mode = "kv" } -- mark table as having weak refs to keys and values
local weakkeys = { __mode = "k" } -- mark table as having weak refs to keys

local threads = {} --TODO: use set instead of list
local threadnames = setmetatable({}, weakkeys)
local threadswaitingfor = {} -- what each thread is waiting for
local readythreads = {} -- like wakethreads, but for next loop (can be modified while looping wakethreads)
local socketwrappermap = setmetatable({}, weaktable) -- from native socket to async socket
local threaderrorhandler = nil -- TODO: allow setting error handler
local last_wakes = setmetatable({}, weakkeys)

-- save print for when we actually need to print
local alwaysprint = print

-- count elements in non-array table
local function tablecount(t)
    local count = 0
    for _, _ in pairs(t) do count = count + 1 end
    return count
end

local function generate_thread_metadata(thread)
  local tb = debug and debug.traceback or function() alwaysprint("debug.traceback not avaliable") end
  return {
    name = threadnames[thread],
    traceback = tb(thread),
    recvt = #((threadswaitingfor[thread] or {}).recvr or {}),
    sendt = #((threadswaitingfor[thread] or {}).sendr or {}),
    timeout = (threadswaitingfor[thread] or {}).timeout,
    last_wake = last_wakes[thread] or "unknown",
    status = coroutine.status(thread),
  }
end

-- dump debugging info to stdout
local function dump_thread_state(wokenthreads)
  wokenthreads = wokenthreads or {}
  alwaysprint("vvvvvvvvvvvvvvvvvvvvvvvv DUMP STATE vvvvvvvvvvvvvvvvvvvvvvvv")
  local tb = debug and debug.traceback or function() alwaysprint("debug.traceback not avaliable") end
  alwaysprint("threads woken in last turn ("..tostring(tablecount(wokenthreads))..")")
  alwaysprint("=========================================================")
  for thread, _ in pairs(wokenthreads) do
    alwaysprint(thread, threadnames[thread])
    alwaysprint(tb(thread))
    alwaysprint("recvt:", #((threadswaitingfor[thread] or {}).recvr or {}))
    alwaysprint("sendt:", #((threadswaitingfor[thread] or {}).sendr or {}))
    alwaysprint("timeout:", (threadswaitingfor[thread] or {}).timeout)
    alwaysprint("last wake:", last_wakes[thread] or "unknown")
    alwaysprint("---------------------------------------------------------")
  end
  alwaysprint("threads not woken in last turn ("..tostring(tablecount(threads) - tablecount(wokenthreads))..")")
  alwaysprint("=========================================================")
  for thread, _ in pairs(threads) do
    if not wokenthreads[thread] then
      alwaysprint(thread, threadnames[thread])
      alwaysprint(tb(thread))
      alwaysprint("recvt:", #((threadswaitingfor[thread] or {}).recvr or {}))
      alwaysprint("sendt:", #((threadswaitingfor[thread] or {}).sendr or {}))
      alwaysprint("timeout:", (threadswaitingfor[thread] or {}).timeout)
      alwaysprint("last wake:", last_wakes[thread] or "unknown")
      alwaysprint("---------------------------------------------------------")
    end
  end

  alwaysprint("^^^^^^^^^^^^^^^^^^^^^^^^ DUMP STATE ^^^^^^^^^^^^^^^^^^^^^^^^")
end

-- silence print statements in this file
local print = function() end

local m = {}

m._VERSION = "0.2.0"
m.socket = socket
m.channel = channel
m.timer = timer
m.ssl = ssl

local timers = {}
do
  local timeouts = {}
  local refs = {}
  -- takes a relative timeout, a callback that is called with no params,
  -- and an optional reference object for cancellation
  timers.set = function(timeout, callback, ref)
    print("timer set: %s,%s", timeout, ref)
    local now = nativesocket.gettime()
    local timeoutat = timeout + now
    print(timeoutat, timeout, now)
    local timeoutinfo = {timeoutat = timeoutat, callback = callback, ref = ref}
    table.insert(timeouts, timeoutinfo)
    if ref then refs[ref] = timeoutinfo end
  end

  timers.cancel = function(ref)
    local timeoutinfo = refs[ref]
    if timeoutinfo then
      -- mark as canceled, actual object will fall out at originally scheduled time
      timeoutinfo.callback = nil
      timeoutinfo.ref = nil
    end
    refs[ref] = nil
  end

  -- run expired timers, returns time to next timeout expiration
  timers.run = function()
    -- this seems exceptionally inefficient, but it works
    -- TODO: I dunno, maybe use a timerwheel, after benchmarks
    table.sort(
      timeouts,
      function(a,b)
        -- bubble nil timeouts to the top to be dropped
        return
          not a.timeoutat or
          (a.timeoutat and b.timeoutat and a.timeoutat < b.timeoutat)
      end
    )

    local now = nativesocket.gettime()

    -- process timeout callback and remove
    while timeouts[1] and (timeouts[1].timeoutat == nil or timeouts[1].timeoutat < now) do
      local timeoutinfo = table.remove(timeouts, 1)
      if timeoutinfo.callback then timeoutinfo.callback() end
      if timeoutinfo.ref then refs[timeoutinfo.ref] = nil end
    end

    local timeoutat = (timeouts[1] or {}).timeoutat
    print("timeout time", timeoutat)
    if timeoutat then
      local timeout = timeoutat - now
      print("earliest timeout", timeout)
      return timeout
    else
      return nil
    end
  end
end

-- asyncify
do
  local realrequire = require
  local asyncify_loaded = {}
  local function wrappedrequire(name)
    --[[ Our API is incomplete, just choose a few specific modules for now
    if string.sub(name, 1, 6) == "socket" then
      name = "cosock."..name
    end
    ]]
    local subbed
    if name == "socket" then
      subbed = "cosock.socket"
    elseif name == "ssl" then
      subbed = "cosock.ssl"
    end
    return subbed and realrequire(subbed) or m.asyncify(name)
  end

  local fakeenv = {
    require = wrappedrequire
  }
  setmetatable(fakeenv, {__index = _ENV })

  function m.asyncify(name)
    local err
    if name == "socket" then name = "cosock.socket" end
    if name == "ssl" then name = "cosock.ssl" end

    if asyncify_loaded[name] then
      return asyncify_loaded[name]
    end
    for _,searcher in ipairs(package.searchers) do
      local loader, loc = searcher(name)
      if type(loader) == "function" then
        -- figure out which upvalue is env
        local upvalueidx = 0
        repeat
          upvalueidx = upvalueidx + 1
          local uvname, _ = debug.getupvalue(loader, upvalueidx)
          if not uvname then upvalueidx = nil; break end
        until uvname == "_ENV"

        -- set loader env to fake env to override calls to `require`
        if upvalueidx then
          debug.setupvalue(loader, upvalueidx, fakeenv)
        end

        -- load module with loader
        local module = loader(name, loc)
        asyncify_loaded[name] = module
        return module
      -- If the last searcher returns nil we need to check the
      -- package.loaded or we may miss some std lib packages
      elseif loader == nil and package.loaded[name] then
        asyncify_loaded[name] = package.loaded[name]
        return package.loaded[name]
      else
        -- non-function values mean error, keep last non-nil value
        err = loader or err
      end
    end

    return err
  end
end

function m.spawn(fn, name)
  local thread = coroutine.create(fn)
  print("socket spawn", name or thread)
  threadnames[thread] = name
  threads[thread] = thread
  readythreads[thread] = {}
end

local function wake_thread(wakelist, thread, kind, skt)
  print("wake thread", thread, kind, skt)
  wakelist[thread] = wakelist[thread] or {}
  wakelist[thread][kind] = wakelist[thread][kind] or {}
  table.insert(wakelist[thread][kind], skt)
end

local function wake_thread_err(wakelist, thread, err)
  print("wake thread err", thread, err)
  wakelist[thread] = wakelist[thread] or {}
  wakelist[thread].err = err
end

-- Implementaion Notes:
-- This run loop is where all the magic happens
--
-- Threads' calls to coroutine.yield function exactly like socket.select. They take: a list of
-- receive-test sockets, a list of write-test sockets, and a timeout. Then, that thread is resumed
-- with: a list of recieve-ready sockets, a list of write-ready sockets, and/or a timeout error.
--
-- This function then combines these lists for a single call to the real socket.select. Once that
-- returns it filters the list of ready sockets out each thread that was waiting on each or
-- determines which has a timeout that has ellapsed.
function m.run()
  local runstarttime = nativesocket.gettime()
  while true do
    print(string.format("================= %s ======================", nativesocket.gettime() - runstarttime))
    local wakethreads = {} -- map of thread => named resume params (rdy skts, timeout, etc)
    local sendt, recvt, timeout = {}, {} -- cumulative values across all threads

    -- add threads that have become ready since last loop to threads to be woken
    for thread, reasons in pairs(readythreads) do
      wakethreads[thread] = reasons

      -- drain copied table (note: the `readythreads` table must not be replaced with a new
      -- table, callbacks hold a reference to this specific instance)
      -- also this operation is actually valid, values can be modified or removed, just not added
      readythreads[thread] = nil

      -- cancel thread timeout (if any)
      timers.cancel(thread)

      -- cancel other timers before any threads are resumed
      for kind, sockets in pairs(threadswaitingfor[thread] or {}) do
        if kind ~= "timeout" then
          for _, skt in pairs(sockets) do
            assert(skt.setwaker, "non-wakeable socket")
            print("unset waker", threadnames[thread] or thread, kind)
            skt:setwaker(kind, nil)
          end
        end
      end
    end

    -- run all threads
    for thread, params in pairs(wakethreads) do
      print("waking", threadnames[thread] or thread, params.recvr, params.sendr, params.err)
      if coroutine.status(thread) == "suspended" then
        last_wakes[thread] = os.time()
        -- resume thread
        local status, threadrecvt_or_err, threadsendt, threadtimeout =
          coroutine.resume(thread, params.recvr, params.sendr, params.err)

        if status and coroutine.status(thread) == "suspended" then
          local threadrecvt = threadrecvt_or_err
          print("suspending", threadnames[thread] or thread, threadrecvt, threadsendt, threadtimeout)
          -- note which sockets this thread is now waiting on
          threadswaitingfor[thread] = {recvr = threadrecvt, sendr = threadsendt, timeout = threadtimeout}

          -- setup wakers for all sockets
          for kind, sockets in pairs(threadswaitingfor[thread]) do
            if kind ~= "timeout" then
              for _, skt in pairs(sockets) do
                assert(skt.setwaker, "non-wakeable socket")
                print("set waker", kind)
                skt:setwaker(kind, function()
                  -- unset waker so we can't double wake
                  skt:setwaker(kind, nil)
                  wake_thread(readythreads, thread, kind, skt)
                end)
              end
            end
          end

          -- setup waker for timeout
          if threadtimeout then
            timers.set(threadtimeout, function() wake_thread_err(readythreads, thread, "timeout") end, thread)
          end
        elseif coroutine.status(thread) == "dead" then
          if not status and not threaderrorhandler then
            local err = threadrecvt_or_err
            if debug and debug.traceback then
              error(debug.traceback(thread, err))
            else
              error(err)
            end
            os.exit(-1)
          end
          print("dead", threadnames[thread] or thread, status, threadrecvt_or_err)
          threads[thread] = nil
          threadswaitingfor[thread] = nil
        end
      else
        print("non-suspended thread encountered", coroutine.status(thread))
      end
    end

    -- check if all threads have completed so that the runtime should exit
    local running = false
    for _, thread in pairs(threads) do
      print("thread", threadnames[thread] or thread, coroutine.status(thread))
      if coroutine.status(thread) ~= "dead" then running = true end
    end
    if not running and not next(readythreads) then break end

    -- pull out threads' recieve-test & send-test sockets into each cumulative list
    for thread, params in pairs(threadswaitingfor) do
      if params.recvr then
        for _, skt in pairs(params.recvr) do
          if skt.inner_sock then
            print("thread for recvt:", threadnames[thread] or thread)
            table.insert(recvt, skt.inner_sock)
            socketwrappermap[skt.inner_sock] = skt;
          end
        end
      end
      if params.sendr then
        for _, skt in pairs(params.sendr) do
          if skt.inner_sock then
            print("thread for sendt:", threadnames[thread] or thread)
            table.insert(sendt, skt.inner_sock)
            socketwrappermap[skt.inner_sock] = skt;
          end
        end
      end
    end

    -- run timeouts (will push to `readythreads`)
    timeout = timers.run()

    if next(readythreads) then
      print("thread woken during execution of other threads, no timeout")
      timeout = 0
    end

    if not timeout and #recvt == 0 and #sendt == 0 then
      -- in case of bugs
      dump_thread_state(wakethreads)
      error("cosock tried to call socket.select with no sockets and no timeout. "
            .."this is a bug, please report it, including the above dump state")
    end

    print("start select", #recvt, #sendt, timeout)
    --for k,v in pairs(recvt) do print("r", k, v) end
    --for k,v in pairs(sendt) do print("s", k, v) end
    local recvr, sendr, err = nativesocket.select(recvt, sendt, timeout)
    print("return select", #(recvr or {}), #(sendr or {}))

    if err and err ~= "timeout" then error(err) end

    -- call waker on recieve-ready sockets
    for _,lskt in ipairs(recvr or {}) do
      local skt = socketwrappermap[lskt]
      assert(skt, "unknown socket")
      assert(skt._wake, "unwakeable socket")
      skt:_wake("recvr")
    end

    -- call waker on send-ready sockets
    for _,lskt in ipairs(sendr or {}) do
      local skt = socketwrappermap[lskt]
      assert(skt, "unknown socket")
      assert(skt._wake, "unwakeable socket")
      skt:_wake("sendr")
    end
  end

  print("run exit")
end

-- reset state for tests, not for external use
function m.reset()
  threads = {}
  threadnames = setmetatable({}, weakkeys)
  threadswaitingfor = {}
  readythreads = {}
  socketwrappermap = setmetatable({}, weaktable)
  threaderrorhandler = nil
end

-- handle to get the metadata for all cosock owned threads
function m.get_thread_metadata()
  local ret = {}
  for th, _ in pairs(threads) do
    table.insert(ret, generate_thread_metadata(th))
  end
  return ret
end

return m
