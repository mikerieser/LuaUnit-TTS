--[[────────────────────────────────────────────────────────────────────────────
    LuaUnit Multi-Output Handler for TTS
    Drop-in replacement to route LuaUnit output to multiple destinations
    (chat, system log, grid GUI) while reusing LuaUnit formatters.
────────────────────────────────────────────────────────────────────────────]] --

local M = require("Test.luaunit")

---------------------------------------------------------------
-- Defaults: color scheme, chat, system log, gui
---------------------------------------------------------------

--[[
    TTSOutput: These are the defaults for the TTSOutput object. The defaults are:
    - chat: ChatOutput (default: enabled) uses verbose output in TAP format to the chat window.
    - log: LogOutput (default: enabled) uses low verbosity output in TEXT format to the system console.
    - grid: GridOutput (default: enabled if hostObject exists) uses a clickable GUI grid to show test results.
    - colors: color scheme for all outputs (default: see below) can easily be overridden by the user.
    - yieldFrequency: (default: 10) number of tests between each coroutine.yield
]]
TTSOutput = {
    chat = { format = "TAP", verbosity = M.VERBOSITY_VERBOSE },
    log = { format = "TEXT", verbosity = M.VERBOSITY_LOW },
    grid = true,
    yieldFrequency = 10, -- number of tests between each coroutine.yield

    -- Colors used by all outputs
    colors = {
        [M.NodeStatus.SUCCESS] = "#00FF00", -- bright green (test passed)
        [M.NodeStatus.FAIL]    = "#FF0000", -- bright red (test failed)
        [M.NodeStatus.ERROR]   = "#FF6600", -- dark orange (test had runtime error)
        [M.NodeStatus.SKIP]    = "#FFFF00", -- yellow (test skipped)
        INFO                   = "#FFFDD0", -- cream (generic info)
        START                  = "#FFFF99", -- light yellow (suite start)
        FINISH                 = "#FFFF99", -- light yellow (suite end)
        NEUTRAL                = "#FFFFFF", -- white (grid squares before status)
        UNKNOWN                = "#FF00FF", -- magenta
    },

    -- Factory method for LuaUnit's outputType.new() call
    new = function(runner)
        return buildTTSOutput(runner, TTSOutput)
    end
}

--[[────────────────────────────────────────────────────────────────────────────
    TTSMultiOutput: Composite root that delegates to child outputs
────────────────────────────────────────────────────────────────────────────]] --
local TTSMultiOutput = {}
TTSMultiOutput.__index = TTSMultiOutput -- Ensure methods are accessible in TTSMultiOutput
setmetatable(TTSMultiOutput, { __index = M.genericOutput }) -- Inherit from genericOutput
TTSMultiOutput.__class__ = "TTSMultiOutput"

function TTSMultiOutput.new(runner)
    local t = M.genericOutput.new(runner)
    t.children = {} -- Initialize an empty list of children
    return setmetatable(t, TTSMultiOutput)
end

function TTSMultiOutput:add(child)
    table.insert(self.children, child)
end

-- Delegate all lifecycle methods to child outputs
setmetatable(TTSMultiOutput, {
    __index = function(_, method)
        return function(self, ...)
            for _, child in ipairs(self.children) do
                if child[method] then
                    child[method](child, ...)
                end
            end
        end
    end
})

--[[────────────────────────────────────────────────────────────────────────────
    Output Class Hierarchy:

    M.genericOutput (LuaUnit base)
    ├── TTSMultiOutput (composite root, delegates to children)
    │
    ├── OUTPUT FORMATTERS (what to output)
    │   ├── M.TextOutput (human readable format)
    │   └── M.TapOutput (human/machine readable format)
    │
    ├── OUTPUT DECORATORS (where to output)
    │   ├── ChatOutput (decorates any formatter with colored output to chat window)
    │   └── LogOutput (decorates any formatter with output to system console)
    │
    └── DIRECT OUTPUTS (special destinations)
        └── GridOutput (visual GUI grid, subclasses genericOutput directly)
────────────────────────────────────────────────────────────────────────────]] --

-- createOutput for the text-based formatters (TextOutput/TapOutput)
local function createOutput(runner, colors, cfg, flushFunc)
    local baseFormatter = (cfg.format == "TAP") and M.TapOutput or M.TextOutput
    local t = baseFormatter.new(runner)
    t.colors = colors or TTSOutput.colors
    t.verbosity = cfg.verbosity
    t.flushFunc = flushFunc

    for k, v in pairs(_G.Emitter) do
        t[k] = v
    end
    t:init()

    return t, baseFormatter
end

-- Add ColoredOutput mixin
local ColoredOutput = {
    getColorForNode = function(self, node)
        local status = node and node.status or "INFO"
        return self.colors[status] or self.colors.NEUTRAL
    end
}

--[[────────────────────────────────────────────────────────────────────────────
    ChatOutput: Colored chat window output using TextOutput/TapOutput formatting
────────────────────────────────────────────────────────────────────────────]] --
local ChatOutput = {}
ChatOutput.__index = ChatOutput
ChatOutput.__class__ = "ChatOutput"

function ChatOutput.new(runner, colors, cfg)
    local t, baseClass = createOutput(runner, colors, cfg, function(line, color)
        printToAll(line, color)
    end)
    for k, v in pairs(ColoredOutput) do
        t[k] = v
    end

    return setmetatable(t, {
        __index = function(instance, key)
            return ChatOutput[key] or baseClass[key]
        end
    })
end

function ChatOutput:flush(line)
    self.flushFunc(line, Color.fromHex(self:getColorForNode(self.result.currentNode)))
end

--[[────────────────────────────────────────────────────────────────────────────
    LogOutput: System console output using TapOutput formatting
────────────────────────────────────────────────────────────────────────────]] --
local LogOutput = {}
LogOutput.__index = LogOutput
LogOutput.__class__ = "LogOutput"

function LogOutput.new(runner, colors, cfg)
    local flushFunc = function(line)
        log(line)
    end
    local t, baseClass = createOutput(runner, colors, cfg, flushFunc) -- Default to TEXT for experts

    return setmetatable(t, {
        __index = function(instance, key)
            return LogOutput[key] or baseClass[key]
        end
    })
end

function LogOutput:flush(line)
    self.flushFunc(line)
end

--[[────────────────────────────────────────────────────────────────────────────
    GridOutput: Grid-based UI output for TTS
────────────────────────────────────────────────────────────────────────────]] --
-- Utility function to recursively find an element by its ID
local function findElementById(elements, id)
    for _, element in ipairs(elements or {}) do
        if element.attributes and element.attributes.id == id then
            return element
        end
        if element.children then
            local found = findElementById(element.children, id)
            if found then
                return found
            end
        end
    end
    return nil
end

GridOutput = {
    __class__ = "GridOutput"
}
setmetatable(GridOutput, { __index = M.genericOutput })

function GridOutput.new(runner, colors)
    local t = M.genericOutput.new(runner)
    t.hostObject = runner.hostObject
    t.colors = colors or TTSOutput.colors
    t.squareIds = {}
    t.testOutputs = {}

    -- Add color handling
    for k, v in pairs(ColoredOutput) do
        t[k] = v
    end

    runner.hostObject.UI.setAttribute("TestStatus", "active", "true")
    return setmetatable(t, { __index = GridOutput })
end

function GridOutput:startSuite()
    local uiTable = self.hostObject.UI.getXmlTable()
    if not uiTable or #uiTable == 0 then
        printToAll(self.__class__ .. ": Failed to get UI table", Color.fromHex(self.colors.ERROR))
        return
    end

    function onClick(player, value, id)
        local testResult = M.prettystr(self.testOutputs[id])
        local colorHex = self.hostObject.UI.getAttribute(id, "color")
        printToAll(testResult, Color.fromHex(colorHex))
    end

    local panels = {}
    local totalTests = self.runner.result.selectedCount
    for i = 1, totalTests do
        local id = "TestSquare" .. i
        self.squareIds[i] = id
        table.insert(panels, {
            tag = "Panel",
            attributes = {
                id = id,
                color = self.colors.NEUTRAL,
                onClick = "onClick"
            }
        })
    end

    local testGrid = findElementById(uiTable, "TestGrid")
    if not testGrid then
        printToAll(self.__class__ .. ": TestGrid not found", Color.fromHex(self.colors.ERROR))
        return
    end
    testGrid.children = panels
    self.hostObject.UI.setXmlTable(uiTable)
end

function GridOutput:endTest(node)
    local completedTests = node.number
    local colorHex = self:getColorForNode(node) -- Use the mixin's method

    local id = "TestSquare" .. node.number
    self.testOutputs[id] = node

    local squareId = self.squareIds[completedTests]
    self.hostObject.UI.setAttribute(squareId, "color", colorHex)
    if self.runner.result.selectedCount > 100 then
        local percent = 1 - (completedTests / self.runner.result.selectedCount)
        self.hostObject.UI.setAttribute("TestScroll", "verticalNormalizedPosition", tostring(percent))
    end
end

function GridOutput:totalTests()
    return self.runner.result.selectedCount
end

--[[────────────────────────────────────────────────────────────────────────────
    YieldOutput: Isn't really an Output. It's a counter to yield control
    from LuaUnit code to TTS to allow the various outputs to show up.
    It's configurable, as the yield actually introduces a significant performance
    hit when used with the GridOutput. So, if you don't need it, set it to 0.
────────────────────────────────────────────────────────────────────────────]] --
--- @class YieldOutput: genericOutput
local YieldOutput     = {}
YieldOutput.__index   = YieldOutput
YieldOutput.__class__ = "YieldOutput"

--- @param runner LuaUnit runner instance
--- @param freq   number of tests between each coroutine.yield
function YieldOutput.new(runner, freq)
    -- inherit no-op lifecycle methods & emit/emitLine from genericOutput
    local t = M.genericOutput.new(runner) -- :contentReference[oaicite:0]{index=0}:contentReference[oaicite:1]{index=1}
    t.count = 0
    t.freq  = freq or 10
    return setmetatable(t, YieldOutput)
end

function YieldOutput:startSuite(node)
    coroutine.yield(0)
end

function YieldOutput:endSuite(node)
    coroutine.yield(0)
end

--- Called after each test; yields every self.freq tests.
function YieldOutput:endTest(node)
    self.count = self.count + 1
    if self.count % self.freq == 0 then
        coroutine.yield(0)
    end
end

function YieldOutput:endClass(node)
    coroutine.yield(0)
end

---------------------------------------------------------------
-- Factory method to build a complete output graph
---------------------------------------------------------------
function buildTTSOutput(runner, config)
    local root = TTSMultiOutput.new(runner)

    -- ChatOutput (enabled unless explicitly disabled)
    if config.chat ~= false then
        root:add(ChatOutput.new(runner, config.colors, config.chat))
    end

    -- LogOutput (enabled unless explicitly disabled)
    if config.log ~= false then
        root:add(LogOutput.new(runner, config.colors, config.log))
    end

    -- GridOutput (enabled by default if hostObject exists)
    if config.grid ~= false and runner.hostObject then
        root:add(GridOutput.new(runner, config.colors))
    end

    if config.yieldFrequency then
        root:add(YieldOutput.new(runner, config.yieldFrequency))
    end

    return root
end

return TTSOutput
