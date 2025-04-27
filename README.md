# LuaUnit for Tabletop Simulator (TTS)
A port of LuaUnit to Tabletop Simulator, featuring XML UI integration and multi-channel test output (chat, log, GUI).

A drop-in extension of [LuaUnit](https://github.com/bluebird75/luaunit) for Tabletop Simulator, supporting output to chat, system log, and a grid UI.
This is a custom port of [LuaUnit](https://github.com/bluebird75/luaunit) adapted for use inside **Tabletop Simulator** (TTS), which uses the **MoonSharp** Lua interpreter.

The goal is to provide a fast, visual, developer-friendly test framework for mods, while staying unobtrusive and
compatible with upstream LuaUnit.

---

## Features

- ✅ **1-line require()** for easy drop-in: `require("Test.luaunit_tts")`
- 🎨 GUI **visual test grid** using XML Grid Layout + scripting object
- 📦 Works with [LuaBundler](https://github.com/Spellcaster/lua-bundler)
- 🔁 Supports all standard LuaUnit assertions: `assertEquals()`, `assertTrue()`, etc.
- ⚠️ Supports skipping tests: `lu.skip("reason")`
- 🔍 Detects any global table whose name starts with `Test`
- 🔊 Verbosity modes for output: `QUIET`, `LOW`, `DEFAULT`, `VERBOSE`

---

## File Overview

All examples in this README.md assume the following folder structure.

```
Test/                                # Top-level test directory
├── luaunit.lua                      # Core LuaUnit framework
├── luaunit_tts.lua                  # TTS-compatible test runner (what you require)
├── luaunit_tts_env.lua              # MoonSharp stubs for os/io/print
├── luaunit_tts_output.lua           # Grid + chat output handler
├── luaunit_tts_output.xml           # Grid layout (include this in your object)
└── TestMain.lua                     # Main test entry point for all test files
```

---

## Quick Start & Demo

This guide assumes support for static `require()` and `<Include>` statements.
e.g. Rolandostar's TTS Lua VSCode plugin.

1. Spawn an object to host your test runner.</br>
   (e.g. a Checker from *Objects → Components → Checkers → White*).
1. Add the XML layout to that object’s scripting panel.
   ```xml
   <Include src="Test/luaunit_tts_output.xml"/>
   ```
1. Add this Lua script to the object:
   ```lua
   require("Test.TestMain")
   ```
1. Save this game.
1. Load the saved game.
1. Save & Play
   Drop the object to run tests and see results in chat, log, and grid.
1. Pickup and Drop the Checker
1. Click on a grid square result to see the corresponding test name.

✅ You now have a working grid-based test runner.

---

## Writing Tests

To be discovered automatically, test function names **must** begin with `test`.

```lua
local lu = require("Test.luaunit_tts")

local T = {}
function T:test_addition()
    lu.assertEquals(2 + 2, 4)
end

return T
```

### Common Assertions

By default, this port sets `lu.ORDER_ACTUAL_EXPECTED = false`
which supports the original xUnit convention of `lu.assertEquals(expected, actual)` — *this is the way*.

LuaUnit supports expressive, self-documenting assertions:

- `lu.assertEquals(expected, actual)`
- `lu.assertAlmostEquals(a, b, delta)`
- `lu.assertStrContains(haystack, needle)`
- `lu.assertError(function, ...)`
- `lu.assertTrue(value)` / `lu.assertFalse(value)`


> You can also use `lu.assert(value)` as a truthiness check — similar to Lua’s native `assert()`, but integrated into
> the test framework.

For more, see [LuaUnit’s assertion list](https://github.com/bluebird75/luaunit#assertions).

---

## Global Namespace Requirement

LuaUnit automatically collects all test tables in `_G` whose name begins with `Test`.

- ✅ `TestMath = {}` — discovered
- ❌ `local TestMath = {}` — ignored
- ✅ `TestMath = require("Test.TTS_lib.TestMath")` — works
- ❌ `local TestMath = require(...)` — ignored

The variable assigned in `_G` **doesn’t need to match** the returned table name. What matters is the key:
`_G.TestFoo = require(...)` is valid even if the file returns a table named `T`.

### Pattern for `TestMain.lua`

This pattern is bundler-friendly and discoverable:

```lua
local testSuites = {
    TestVector = require("Test.TTS_lib.TestVector"),
    TestMath   = require("Test.TTS_lib.TestMath"),
}

for name, suite in pairs(testSuites) do
    _G[name] = suite
end
```

---

## Verbosity Modes

Set verbosity to control the amount of output:

```lua
lu.LuaUnit.verbosity = lu.VERBOSITY_LOW      -- Only summary
lu.LuaUnit.verbosity = lu.VERBOSITY_DEFAULT  -- Summary + test names
lu.LuaUnit.verbosity = lu.VERBOSITY_VERBOSE  -- Full: classes, tests, details
```

---

## Output Configuration
## Enabling Chat Output

You can enable, disable, or configure each output type before calling `:run()`:
Enable this to see test results in the TTS chat window:

```lua
-- Enable/disable outputs:
lu.LuaUnit.outputType.chat = { format = "TAP", verbosity = lu.VERBOSITY_VERBOSE }
lu.LuaUnit.outputType.log = { format = "TEXT", verbosity = lu.VERBOSITY_LOW }
lu.LuaUnit.outputType.grid = true -- or false to disable

-- Disable log output:
lu.LuaUnit.outputType.log = false
Must be set **before** running tests. Useful even when the grid UI is disabled or unavailable.

-- Change just one property:
lu.LuaUnit.outputType.chat.format = "TEXT"
## GUI Output Grid

To show visual test progress:

- Include the grid layout XML in your object:
  ```xml
  <Include src="Test/luaunit_tts_output.xml"/>
```
- In Lua, set:
  ```lua
  lu.LuaUnit.hostObject = self
  ```

> The `hostObject` becomes the anchor for grid placement and attribute updates.

---

## Customizing Colors

Override all or individual colors (applies to all outputs):
You can override visual output colors like so:

```lua
lu.LuaUnit.outputType.colors = {
    SUCCESS = "#00FF00",
    FAIL    = "#FF3333",
    ERROR   = "#FFA500",  -- Orange
    SKIP    = "#FFFF00",
    NEUTRAL = "#FFFFFF",
    START   = "#FFFF99",
    FINISH  = "#FFFF99",
    INFO    = "#9999FF",
    UNKNOWN = "#FF00FF",
}
```

Or override individual entries:

```lua
lu.LuaUnit.outputType.colors.ERROR = "#FFA500"
```

---

## Manual Runner (Advanced)

In most cases, you'll just call:

```lua
lu.LuaUnit.outputType.colors.ERROR = "#FFA500" -- Orange for errors
lu.LuaUnit.outputType.colors.SUCCESS = "#00FF00"
lu.LuaUnit:run()
```
However, for full control — such as explicitly specifying which test suites to run, bypassing automatic discovery, or managing multiple contexts — you can create and run your own LuaUnit instance:

---

## Grid Output

- The grid UI is enabled by default if `lu.LuaUnit.hostObject = self` and `outputType.grid` is not `false`.
- The grid shows test status and allows clicking for details.

---

## Troubleshooting

- **No output in chat or grid?**  
  Make sure you set `lu.LuaUnit.hostObject = self` before calling `:run()`.

- **Want only chat or only grid?**  
  Set `lu.LuaUnit.outputType.grid = false` or `lu.LuaUnit.outputType.chat = false`.

- **Changing colors or verbosity has no effect?**  
  Set options before calling `:run()`.

---

## Example: Minimal Test Suite

```lua
local lu = require("Test.luaunit_tts")

TestMath = {}

function TestMath:test_add()
    lu.assertEquals(1 + 1, 2)
end

function runTests()
    lu.LuaUnit.hostObject = self
    lu.LuaUnit:run()
end

function onDrop()
    runTests()
    local runner = lu.LuaUnit.new()
    runner.hostObject = self
    runner.testClasses = { TestExample }
    runner:runSuite()
end
```

---

## Advanced: OutputType Table Structure

- `chat`, `log`, and `grid` are the main outputs.
- Each can be set to `false` to disable, or to a table to configure.
- `colors` is a table of status-to-color mappings (hex strings).


---

Happy testing 🎲

---

## Credits

- LuaUnit by [Philippe Fremy](https://github.com/bluebird75/luaunit)
- TTS port and multi-output by [Mike Rieser](https://github.com/mikerieser/LuaUnit-TTS)


## License

This software is distributed under the **BSD 3-Clause License**.

It includes [LuaUnit](https://github.com/bluebird75/luaunit), originally
created by [Philippe Fremy](https://github.com/bluebird75),
and adapted for Tabletop Simulator (TTS) by [Mike
Rieser](https://github.com/mikerieser).

Original LuaUnit [LICENSE.txt](https://raw.githubusercontent.com/bluebird75/luaunit/refs/heads/master/LICENSE.txt),
and 
LuaUnit-TTS port [LICENSE.txt](https://github.com/mikerieser/LuaUnit-TTS/blob/af963ecafb6c5dfbc941ca07a5178a2b7b3bd950/LICENSE)

