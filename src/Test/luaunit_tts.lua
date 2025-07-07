--- @module luaunit_tts
-- Bootstrap for the TTS LuaUnit port: loads core runner, env shim, multi-output,
-- auto-inits on require, and wraps all entry points in coroutines by name.

local lu        = require("Test.luaunit")
require("Test.luaunit_tts_env")
local TTSOutput = require("Test.luaunit_tts_output")
TTSOutput.currentRunner = nil

--- Initialize the TTS LuaUnit port.
--- @param scriptOwner :LuaGameObjectScript  drives coroutines & chat/log output
--- @param gridOwner   :LuaGameObjectScript? where the Grid UI attaches
function lu.init(scriptOwner, gridOwner)
    assert(scriptOwner, "luaunit_tts.init: scriptOwner is required")
    lu.LuaUnit.scriptOwner = scriptOwner
    TTSOutput.gridOwner   = gridOwner or scriptOwner
    lu.LuaUnit.outputType = TTSOutput
end

-- Auto‐initialize when required inside a TTS object script
local _self = rawget(_G, "self")
if _self then lu.init(_self) end

-- Wrap all core runner methods so they execute inside a named TTS coroutine.
local methods = { "run", "runSuite", "runSuiteByNames", "runSuiteByInstances" }
for _, m in ipairs(methods) do
    local orig = lu.LuaUnit[m]
    lu.LuaUnit[m] = function(self, ...)
        assert(self.scriptOwner,
               "luaunit_tts: call luaunit_tts.init(self[, gridOwner]) in onLoad")
        local args     = { ... }
        local coroName = "__luaunit_" .. m .. "_coro"
        TTSOutput.currentRunner = self


        -- register a global function for TTS to find by name
        _G[coroName] = function()
            orig(self, table.unpack(args))
            return 1
        end

        -- start it by name per the TTS API
        startLuaCoroutine(self.scriptOwner, coroName)
    end
end

--- Yield the test coroutine until a condition is met or for N frames.
--- @param condOrFrames function():boolean | number
function lu.await(condOrFrames)
    return coroutine.yield(condOrFrames)
end

return lu
