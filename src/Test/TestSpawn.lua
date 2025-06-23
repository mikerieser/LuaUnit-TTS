lu = require("Test.luaunit_tts")

function lu.LuaUnit:runSync()
    lu.LuaUnit:run()
end

function lu.LuaUnit:asyncRun()
    local co = coroutine.create(function() self:runSync() end)

    local function resumeRunner()
        if coroutine.status(co) == "dead" then
            return  -- we’re done
        end

        local ok, yielded = coroutine.resume(co)
        if not ok then
            error("LuaUnit asyncRun error: " .. tostring(yielded))
        end

        -- if the suite/test finished on that resume, stop
        if coroutine.status(co) == "dead" then
            return
        end

        if type(yielded) == "function" then
            -- your test asked us to wait for `yielded()` before continuing
            Wait.condition(resumeRunner, yielded)
        else
            -- no yield → just keep going on the next frame
            Wait.frames(resumeRunner, 1)
        end
    end

    -- kick it off immediately
    resumeRunner()
end

-- function lu.LuaUnit:asyncRun()
--     local co = coroutine.create(function() self:runSync() end)

--     local function resumeRunner(errOrCondition)
--         -- errOrCondition may be an error message (string) or the next conditionFunc
--         if coroutine.status(co) == "dead" then
--             return
--         end
--         local ok, yielded = coroutine.resume(co)
--         if not ok then
--             error("LuaUnit asyncRun error: " .. tostring(yielded))
--         end
--         if yielded == nil then
--             error("yielded is nil: " .. tostring(yielded))
--         end
--         if type(yielded) == "function" then
--             Wait.condition(resumeRunner, yielded)
--         end
--     end

--     -- kick it off
--     resumeRunner()
-- end

-- from your test harness, e.g. in TestMain.lua
function runTests()
    lu.LuaUnit:asyncRun()
end

function onDrop()
    Wait.condition(runTests, function() return self.resting end)
end

function waitFor(conditionFunc)
    -- cause the surrounding test coroutine to yield this function
    return coroutine.yield(conditionFunc)
end

function newObject()
    local params = {
        type = "BlockSquare", -- or use a saved object via `params.json` or a saved object ID
        position = { 0, 2, 0 }, -- spawn above the table
        rotation = { 0, 180, 0 }, -- optional
        scale = { 1, 1, 1 }, -- optional
        sound = false,      -- optional: don't play sound
        snap_to_grid = true, -- optional
        callback_function = function(obj)
            print("Spawned object with GUID:", obj.getGUID())
        end
    }

    return spawnObject(params)
end

TestSpawner = {}

function TestSpawner:setupClass()
    -- 1) spawn
    self.obj = newObject()
    -- 2) wait for physics to settle before any assertions or next steps
    waitFor(function() return self.obj.resting end)
end

function TestSpawner:test_position()
    lu.assertEquals(Vector(0, 2, 0), self.obj.getPosition())
end

function TestSpawner:test_rotation()
    lu.assertEquals(Vector(0, 180, 0), self.obj.getRotation())
end

function TestSpawner:teardownClass()
    if self.obj then
        self.obj.destroy()
        self.obj = nil
    end
end