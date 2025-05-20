# LuaUnit for Tabletop Simulator (TTS)

A port of LuaUnit to Tabletop Simulator, featuring XML UI integration and multi-channel test output (chat, log, GUI).

A drop-in extension of [LuaUnit](https://github.com/bluebird75/luaunit) for Tabletop Simulator, supporting output to
chat, system log, and a grid UI.
This is a custom port of [LuaUnit](https://github.com/bluebird75/luaunit) adapted for use inside **Tabletop Simulator
** (TTS), which uses the **MoonSharp** Lua interpreter.

The goal is to provide a fast, visual, developer-friendly test framework for mods, while staying unobtrusive and
compatible with upstream LuaUnit.

---

## Features

- ✅ **1-line require()** for easy drop-in: `require("Test.luaunit_tts")`
- 🎨 GUI **visual test grid** using XML Grid Layout + scripting object
- 📦 Works with [LuaBundler](https://github.com/Benjamin-Dobell/luabundler)
- 🔁 Supports most of the standard LuaUnit assertions: `assertEquals()`, `assertTrue()`, etc.
- ⚠️ Supports skipping tests: `lu.skip("reason")`
- 🔍 Detects any global table whose name starts with `Test`
- 🔊 Verbosity modes for output: `QUIET`, `LOW`, `DEFAULT`, `VERBOSE`

---

## Installation

All the Lua files and this document assume the following folder structure under `Test/`.

```
Test/                                # Top-level test directory
├── luaunit.lua                      # Core LuaUnit framework, 1-line require() for test files
├── luaunit_tts_env.lua              # TTS/MoonSharp sandbox stubs for os/io/print (needed by TTS runner)
├── luaunit_tts_output.lua           # TTS output handlers (needed by TTS runner)
├── luaunit_tts.lua                  # TTS runner, 1-line require(), includes everthing above
└── TestMain.lua                     # Example test runner
```

---

## Quick Start & Demo

Assuming support for static `require()` statements.
e.g. rolandostar's **Tabletop Simulator Lua** VSCode plugin.

1. Spawn an object to host your test runner.
   (e.g. a Checker from *Objects → Components → Checkers → White*).
1. Add this Lua script to the object:
   ```lua
   require("Test.TestMain")
   ```
1. Save this game.
1. Load the saved game.
1. Drop the object to run tests and see results in **chat**, **log**, and gui **grid**.
1. Click on a grid square result to see the corresponding test name and result.

---

## Writing Tests

Here is an minimal complete example for defining and running a test.

* Include **`Test.luaunit_tts`**, a 1-line require for the TTS runner code, which also includes LuaUnit.
* Define a **Test Class** (table), in Global scope with a name that begins with 'Test'.
* Define a **Test Case** (function).
    * Every Test Case should have an Assertion **`assertEquals()`** in this case.
* Invoke the **Test Runner**, the LuaUnit runner auto-discovers Test Classes (tables), and runs each Test Case (
  function).

**Simplistic Example:**

```Lua
local lu = require("Test.luaunit_tts")  -- 1-line require for the TTS runner code

TestChecker = {}                        -- table in Global scope with a name that begins with 'Test'

function TestChecker:test_subtraction()
    -- test function in the test table with a name that also begins with 'test'
    lu.assertEquals(2, 3 - 1)           -- LuaUnit assertion, the first value is what is expected,
end                                     --                    the second is the actual computed value

lu.LuaUnit:run()                        -- the LuaUnit runner which auto-discovers test files and runs the test functions.
```

The above really gives no control over when the LuaUnit `run()` is invoked.

A more practical example would allow you to run the tests repeatedly under your control.
An object to kick off the tests is far more convenient. Hence the `runTests()` method and `onDrop()` method to invoke
it.

**Improved Example:**

```Lua
local lu = require("Test.luaunit_tts")

TestChecker = {}

function TestChecker:test_subtraction()
    lu.assertEquals(2, 3 - 1)
end

function runTests()
    lu.LuaUnit:run()
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
    printToAll("Drop this checker to run tests.", { 1, 1, 1 })
end
```

---

### Which 1-line to `require()`

You'll only ever need 1 `require`. The original `luaunit.lua` had to be modified to run in Tabletop Simulator. It won't
run tests as-is, but it is all you need for defining tests.

* **`require("Test.luaunit")`** can be used in a Test Class or Module to provide the assertions where you want to define
  Tests, but it won't be able to run them unaided.
* **`require("Test.luaunit_tts")`** provides everything from `luaunit.lua`, but also provides the environment for the
  test runner to work in the TTS sandbox. For simplicity and the cost of some unnecessary Lua code while testing, you
  can just use this everywhere.

**Note:** It's not recommended to ship your Mod with all the unnecessary baggage of your Test Code and LuaUnit.

---

### Names and Scope

LuaUnit discovers tests automatically using a naming convention:

* **Tables**: Named `Test*` in global scope (case-insensitive).
* **Test Functions**: Methods starting with `test*` (also case-insensitive).

LuaUnit automatically discovers all **global tables** whose names begin
with `Test`. For discovery to work, your test suite must be assigned to
a global variable (e.g., `TestMath = {}`), not a local one.

- ✅ **Global test table:** `TestMath = {}` — discovered
- ❌ **Local table:** `local TestMath = {}` — *not* discovered

- ✅ `TestMath = require("Test.TTS_lib.TestMath")` — works
- ❌ `local TestMath = require(...)` — ignored, again the issue is not with `require`, but with `local`, which prevents
  the table from being added to `_G`

The following also works if it's used as follows. Assume the following is in a file named `Add.lua`.

```lua
-- File: Add.lua
local lu = require("Test.luaunit")  -- Note: this works as we only need the assertions from luaunit, not the runner

local T = {}
function T:test_addition()
    -- the function needs to begin with 'test'
    lu.assertEquals(4, 2 + 2)
end

return T
```

Now before we invoke the runner, we set this up:

```Lua
local lu = require("Test.luaunit_tts")  -- Note: we need the runner, so we require the `_tts` file.

_G.TestAdd = require("Add")             -- assign the table to a global scoped key

lu.LuaUnit.run()
```

The variable assigned in `_G` **doesn’t need to match** the returned table name. What matters is the **key**:
This is valid because `_G.TestAdd` begins with `Test` and is in global scope even though the file returns a `local`
table named `T`.

### Useful Pattern for `TestMain.lua`

This pattern is bundler-friendly and auto-discoverable:

```lua
local testClasses = {
    TestMath = require("Test.TTS_lib.TestMath"),
    TestString = require("Test.TTS_lib.TestString"),
    TestVector = require("Test.TTS_lib.TestVector"),
}

for name, class in pairs(testClasses) do
    _G[name] = class
end
```

---

### Common Assertions

LuaUnit had a *default* which was contrary to the original xUnit pattern for assertions.
This port has the convention for assertions of listing the **expected value** first, that is the correct answer that you
should expect, and
the **actual value** second, that is the value computed or returned as a result of a call to your code under test.
**`lu.assertEquals(expected, actual)`** — *as God and Kent Beck intended!*
e.g. `lu.assertEquals(4, Math.add(2,2))`

LuaUnit supports expressive, self-documenting assertions:

- `lu.assertEquals(expected, actual)`
- `lu.assertAlmostEquals(expected, actual, delta)`
- `lu.assertStrContains(haystack, needle)`
- `lu.assertError(function, ...)`
- `lu.assertTrue(actual)` / `lu.assertFalse(actual)`

> You can also use `lu.assert(value)` as a truthiness check — similar to Lua’s native `assert()`, but integrated into
> the test framework.

For more, see [LuaUnit’s assertion list](https://github.com/bluebird75/luaunit#assertions).

---

### Skipping Tests

It's occasionally helpful to remove a test from the test run, but turning into a comment isn't always desirable as it
will
no longer be treated as code by an IDE. The LuaUnit supported way to skip a test is with the `lu.skip("message")`
method.

```lua
function TestExample:test_skipFeature()
    lu.skip("Feature not yet implemented")
    -- ... the rest of the test case
end
```

---
## Customizing Output

Each output channel can be turned on or off, and configured.

### Output Channels

LuaUnit defined output formats that could go to the console or to an XML file.
TTS will not allow creating a file and writing to it. So, file-based output is unavailable.

Two of the output formats provided by LuaUnit: **`TEXT`** and **`TAP`** are available in the TTS port.

* **TEXT** is a compact text format which is the default for LuaUnit and at its lowest verbosity it just outputs single
  character results: `.`, `F`, `E`, or `S` for passed, failed, error, or skipped.
* **TAP** is the [Test Anything Protocol](https://testanything.org/), which seems easy to read and understand though a
  tad verbose in TTS.

Both of these text-based output formats (TEXT or TAP) are available and can be configured to be sent to either the TTS
Chat window with color, or to the TTS Console Log, or both.

Each LuaUnit output format can be further configured with a **verbosity** setting. Available settings are:
`lu.VERBOSITY_QUIET, lu.VERBOSITY_LOW, lu.VERBOSITY_DEFAULT, lu.VERBOSITY_VERBOSE.`

Because having a lot of text scroll past in a window isn't particularly helpful, a GUI GridLayout is also available with
clickable cells to give information on the results of the test run.
This is referred to as **Grid** output.

All three possible output channels are enabled by default and have the following configurations:

* **Chat** { `TAP` format, verbose }
* **Log**  { `TEXT` format, low verbosity }
* **Grid** { enabled with default `gridOwner` as `self` }

### Verbosity Modes

Set verbosity to control the amount of output:

```lua
lu.LuaUnit.verbosity = lu.VERBOSITY_QUIET    -- Mostly
lu.LuaUnit.verbosity = lu.VERBOSITY_LOW      -- Only summary
lu.LuaUnit.verbosity = lu.VERBOSITY_DEFAULT  -- Summary + test names
lu.LuaUnit.verbosity = lu.VERBOSITY_VERBOSE  -- Full: classes, tests, details
```
> **Tip:** `/clear` will clear the chat window.
---
## Output Configuration

Each output channel can be set to `false` to disable them (as shown above), or to a `table` with configuration settings.

### Disabling an output channel

Disabling what you don't use should improve performance.

```lua
lu.LuaUnit.outputType.chat = false
lu.LuaUnit.outputType.log = false
lu.LuaUnit.outputType.grid = false
```

---
### Yield Frequency

When running tests in TTS, the framework will occupy the CPU and
delay all output until all the processing is finished unless
it's told to yield. 
The `yieldFrequency` setting is the
number of tests the test runner will process between each 
`coroutine.yield(0)`.

**Default Yield Setting**
```Lua
yieldFrequency = 10
```

Larger values will increase performance at the cost of seeing visual progress.

---
### OutputType Table Structure

In LuaUnit the `outputType` is one of `nil`, `TEXT`, `TAP`, or `JUnit XML`.
In TTS, the `outputType` is replaced with a configurable composite called `TTSOutput`.
You'll never use `TTSOutput` directly, but you will be configuring it through its reference: `lu.LuaUnit.outputType`.
LuaUnit calls `new()` on the `outputType` and assigns the instance to the test runner's `output`.

`TTSOutput` is used to configure the three output channels: `chat`,
`log`, and `grid`, the table of colors shared by both `grid` and `chat` output,
and it configures the frequency of updates to the screen.

**Default Configuration:**
```lua
lu.LuaUnit.outputType.chat = { format = "TAP", verbosity = lu.VERBOSITY_VERBOSE }
lu.LuaUnit.outputType.log = { format = "TEXT", verbosity = lu.VERBOSITY_LOW }
lu.LuaUnit.outputType.gridOwner = self
```

Any changes in configuration must be made **before** calling `:run()`.

```lua
-- To change just one property:
lu.LuaUnit.outputType.chat.format = "TEXT"
```

---
### Customizing Colors

The following colors are used by `chat` and `grid` outputs.

**Default Table of Colors**:
```lua
lu.LuaUnit.outputType.colors = {
    SUCCESS = "#00FF00",    -- bright green (test passed)
    FAIL    = "#FF0000",    -- bright red   (test failed)
    ERROR   = "#FF6600",    -- dark orange  (test had a runtime error)
    SKIP    = "#FFFF00",    -- yellow       (test skipped)
    INFO    = "#FFFDD0",    -- cream        (generic info)
    UNKNOWN = "#FF00FF",    -- magenta      (something unexpected)
}
```

You can override the entire table or just one key.

**Example: Overriding the ERROR color**
```lua
lu.LuaUnit.outputType.colors.ERROR = "#FFA500"
```

---
### GUI Grid Output

The grid output gives visual test progress, and helps with investigating test failures.

By default, the script runner (identified by `self`) is also set as the `gridOwner`:
```Lua
lu.LuaUnit.outputType.gridOwner = self
```

If the script runner (and therefore `gridOwner`) is `Global`, the grid will show up on-screen. Which can be awkward.

>It's possible to trigger the running of scripts in `Global`, but also have the grid output to be anchored by an object.

**Example: `TestMain.lua`** in anchor object
```Lua
function runTests()
    Global.call("runTests", { self.getGUID() })
end

function onDrop()
    Wait.condition(runTests, function() return self.resting end)
end
```

**Example: `Global.lua`**
```Lua
function runTests(arg)
    local guid = type(arg) == "table" and arg[1] or arg
    local host = getObjectFromGUID(guid)
    if not host then
        error("runTests: invalid GUID " .. tostring(guid))
    end

    lu.LuaUnit.outputType.gridOwner = host
    lu.LuaUnit:run()
end
```
The grid shows test status and allows clicking for details.

---
## Differences from Native LuaUnit

* **No JUnit XML Output**: file output is unsupported in TTS.
* **MoonSharp Sandbox**: No `io.open()`, `os.exit()` or real environment `os.getenv()` access.
* **Coroutine Execution**: the test framework needs to yield to TTS coroutines to do UI updates.
* **assert(expected, actual):** LuaUnit sets `lu.ORDER_ACTUAL_EXPECTED = true` which is opposite of the original xUnit convention of: expected, actual.

### `error()` handling

Moonsharp's `error()` handling internally converts error objects to `strings`. This means
`lu.assertError()` will work, if you try to use `lu.assertErrorMsgContains()`
Moonsharp will have already converted the `table` to a `string` and you'll get the meaningless `"table: 000204A1"` as
the error message.

### Command Line Features

LuaUnit goes to great pains to provide rich command-line features like selecting tests by patterns or certain instances
etc. This isn't easily reproduced within TTS.
So instead you'll control what goes into `_G` global scope and then gets auto-discovered.

```lua
local testClasses = {
    TestVector = require("Test.TTS_lib.TestVector"),
    TestMath   = require("Test.TTS_lib.TestMath"),
    TestString = require("Test.TTS_lib.TestString"),
    TestTable  = require("Test.TTS_lib.TestTable")
}

for name, class in pairs(testClasses) do
    _G[name] = class
end

lu.LuaUnit:run()
```
---

Happy testing 🎲

---
## Credits

- LuaUnit by [Philippe Fremy](https://github.com/bluebird75/luaunit)
- TTS port and multi-output by [Mike Rieser](https://github.com/mikerieser/LuaUnit-TTS)

## License

* Original **LuaUnit** by [Philippe Fremy](https://github.com/bluebird75/luaunit)
* **LuaUnit-TTS** port by [Mike Rieser](https://github.com/mikerieser/LuaUnit-TTS)

Distributed under the **BSD 3-Clause License**.
