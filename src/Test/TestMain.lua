local lu = require("Test.luaunit_tts")

local testClasses = {
    TestDemo = require("Test.TestDemo")
}

for name, class in pairs(testClasses) do
    _G[name] = class
end

function runTests()
    lu.LuaUnit:run()
    --Global.call("runTests", { self.getGUID() })
end

function onDrop()
    Wait.condition(runTests, function() return self.resting end)
end

function onLoad()
    if self.is_face_down then self.flip() end
    printToAll("Drop this checker to run tests.", Color.Orange)
end
