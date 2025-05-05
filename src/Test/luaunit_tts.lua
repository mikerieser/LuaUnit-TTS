--[[────────────────────────────────────────────────────────────────────────────
    LuaUnit Bootstrap for TTS
    Thin bootstrap that loads upstream LuaUnit, installs the TTS‑specific
    environment stubs and wires in our multi‑destination output module.
────────────────────────────────────────────────────────────────────────────]] --

local lu = require("Test.luaunit") -- upstream distribution (cached once)
require("Test.luaunit_tts_env")    -- os/print/io stubs for MoonSharp / TTS

-- Automatically run all test entrypoints in a coroutine if hostObject is set
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
        startLuaCoroutine(self.hostObject, "__runLuaUnitCoroutine")
    end
end

lu.LuaUnit.outputType = require("Test.luaunit_tts_output")
lu.LuaUnit.hostObject = self

return lu
