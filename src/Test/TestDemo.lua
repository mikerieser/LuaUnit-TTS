local lu = require("Test.luaunit")

local T = {}

TestBulk = {}
for i = 1, 100 do
    TestBulk["test_bulk_pass_" .. i] = function()
        lu.assertEquals(i, i)
    end
end

function T.test_failed_assertion()
    lu.assertEquals(2, 1 + 3)
end

function T.test_runtime_error()
    local id = getObjectFromGUID("123456")
    id.call("non_existent_object", {})
    lu.assertEquals(2, 1 + 3)
end

function T.test_skipped()
    lu.skip("this test intentionally skipped")
    lu.assertEquals(2, 1 + 3)
end

return T
