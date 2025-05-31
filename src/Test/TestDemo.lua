local lu = require("Test.luaunit")

local T = {}

TestBulk = {}
for i = 1, 100 do
    TestBulk["test_bulk_pass_" .. i] = function()
        lu.assertEquals(i, i)
    end
end

function T:test_length()
    local len = Vector(1, 2, 3):magnitude()
    lu.assertAlmostEquals(3.7417, len, 0.0001)
end

function T:test_table_equality()
    local A = { 121221, 122211, 121221, 122211 }
    local B = { 121221, 212211, 121221, 122211 }
    lu.assertEquals(A, B)
end

function T.test_runtime_error()
    local id = getObjectFromGUID("123456")
    id.getPosition() -- This will cause a runtime error since the GUID is invalid
    lu.assertIsNil(id)
end

function T.test_skipped()
    lu.skip("this test intentionally skipped")
    lu.assertEquals(2, 1 + 3)
end

return T
