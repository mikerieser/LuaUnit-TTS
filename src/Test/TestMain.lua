local lu = require("Test.luaunit_tts")

local testClasses = {
    TestDemo = require("Test.TestDemo"),
    TestSpawn = require("Test.TestSpawn"),
}

for name, class in pairs(testClasses) do
    _G[name] = class
end

function runTests()
    lu.LuaUnit:run() -- runs the tests configured here.
    -- Global.call("runTests", { self.getGUID() }) -- runs the tests configured in the global script.
end

function onDrop()
    Wait.condition(runTests, function()
        return self.resting
    end)
end

function onLoad()
    if self.is_face_down then
        self.flip()
    end
    printToAll("Drop this checker to run tests.", Color.Orange)
end

function onChat(msg, _player)
    if msg:lower() == "!runtests" then
        runTests()
    end
end
