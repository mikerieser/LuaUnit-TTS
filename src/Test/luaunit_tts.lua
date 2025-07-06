--[[────────────────────────────────────────────────────────────────────────────
    LuaUnit Bootstrap for TTS
    Thin bootstrap that loads upstream LuaUnit, installs the TTS‑specific
    environment stubs and wires in the multi‑destination output module.
────────────────────────────────────────────────────────────────────────────]] --

local lu = require("Test.luaunit")
require("Test.luaunit_tts_env")

local scriptSelf = self

_G.__luaunit_runner_instance = nil
_G.__luaunit_runner_method = nil
_G.__luaunit_runner_args = nil

function __runLuaUnitCoroutine()
    local instance = _G.__luaunit_runner_instance
    local method = _G.__luaunit_runner_method
    local args = _G.__luaunit_runner_args or {}
    method(instance, table.unpack(args))
    return 1
end

for _, methodName in ipairs({ "run", "runSuite", "runSuiteByNames", "runSuiteByInstances" }) do
    local orig = lu.LuaUnit[methodName]
    lu.LuaUnit[methodName] = function(self, ...)
        _G.__luaunit_runner_instance = self
        _G.__luaunit_runner_method = orig
        _G.__luaunit_runner_args = { ... }
        startLuaCoroutine(scriptSelf, "__runLuaUnitCoroutine")
    end
end

lu.LuaUnit.outputType = require("Test.luaunit_tts_output")
lu.LuaUnit.outputType.gridOwner = self
lu.LuaUnit.outputType.scriptOwner = scriptSelf

--- @section Async/Await Support

local origRun = lu.LuaUnit.run
--- Kick off an asynchronous test run.  Tests can call `await(condFn)` to yield until `condFn()` is true.
--- @param ... any  Command-line style args (patterns, flags), just like `:run(...)`
function lu.LuaUnit:asyncRun(...)
    local args = {...}
    local co = coroutine.create(function() origRun(self, table.unpack(args)) end)
    local function resumeLoop(lastYield)
        if coroutine.status(co) == "dead" then return end
        local ok, yielded = coroutine.resume(co, lastYield)
        if not ok then error("LuaUnit asyncRun error: "..tostring(yielded)) end
        if coroutine.status(co) == "dead" then return end
        if type(yielded) == "function" then
            Wait.condition(resumeLoop, yielded)
        else
            Wait.frames(resumeLoop, 1)
        end
    end
    
    -- start immediately
    resumeLoop()
end

--- Yield the surrounding test coroutine until `conditionFn()` returns true.
--- @param conditionFn function():boolean
function lu.await(conditionFn)
    return coroutine.yield(conditionFn)
end

return lu
