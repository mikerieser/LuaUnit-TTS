local lu = require("Test.luaunit_tts")

function newObject()
    local params = {
        type = "BlockSquare",     -- or use a saved object via `params.json` or a saved object ID
        position = { 0, 2, 0 },   -- spawn above the table
        rotation = { 0, 180, 0 }, -- optional
        scale = { 1, 1, 1 },      -- optional
        sound = false,            -- optional: don't play sound
        snap_to_grid = true,      -- optional
        callback_function = function(obj)
            print("Spawned object with GUID:", obj.getGUID())
        end
    }

    return spawnObject(params)
end

TestSpawner = {}

function TestSpawner:setUp()
    -- 1) spawn
    self.obj = newObject()
    -- 2) wait for the object to settle before any assertions or next steps
    lu.await(function() return self.obj.resting end)
end

function TestSpawner:test_position()
    lu.assertEquals(Vector(0, 2, 0), self.obj.getPosition())
end

function TestSpawner:test_rotation()
    lu.assertEquals(Vector(0, 180, 0), self.obj.getRotation())
end

function TestSpawner:tearDown()
    if self.obj then
        self.obj.destroy()
        self.obj = nil
    end
end
