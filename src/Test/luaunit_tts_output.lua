--[[────────────────────────────────────────────────────────────────────────────
    LuaUnit Multi-Output Handler for TTS
    Drop-in replacement to route LuaUnit output to multiple destinations
    (chat, system log, grid GUI) while reusing LuaUnit formatters.
────────────────────────────────────────────────────────────────────────────]] --

local M = require("Test.luaunit")

--[[
    TTSOutput: These are the defaults for the TTSOutput object:
    * chat: ChatOutput (default: enabled) uses verbose output in TAP format to the chat window.
    * log: LogOutput (default: enabled) uses low verbosity output in TEXT format to the system console.
    * grid: GridOutput (default: enabled if gridOwner exists) uses a clickable GUI grid to show test results.
    * colors: color scheme for all outputs (default: see below) can easily be overridden by the user.
    * yieldFrequency: (default: 10) number of tests between each coroutine.yield
]]
--- @class TTSOutput: genericOutput
TTSOutput = {
    chat = { format = "TAP", verbosity = M.VERBOSITY_VERBOSE },
    log = { format = "TEXT", verbosity = M.VERBOSITY_LOW },
    grid = true,
    gridOwner = nil,     -- set to the object that owns the UI (usually self)
    yieldFrequency = 10, -- number of tests between each coroutine.yield

    -- Colors used by all outputs
    colors = {
        [M.NodeStatus.SUCCESS] = "#00FF00", -- bright green (test passed)
        [M.NodeStatus.FAIL] = "#FF0000",    -- bright red (test failed)
        [M.NodeStatus.ERROR] = "#FF6600",   -- dark orange (test had runtime error)
        [M.NodeStatus.SKIP] = "#FFFF00",    -- yellow (test skipped)
        INFO = "#FFFDD0",                   -- cream (generic info)
        UNKNOWN = "#FF00FF",                -- magenta
    },

    -- Factory method for LuaUnit's outputType.new() call
    new = function(runner)
        return buildTTSOutput(runner, TTSOutput)
    end
}

--[[────────────────────────────────────────────────────────────────────────────
    TTSMultiOutput: Composite root that delegates to child outputs
────────────────────────────────────────────────────────────────────────────]] --
--- @class TTSMultiOutput: genericOutput
local TTSMultiOutput = {}
TTSMultiOutput.__index = TTSMultiOutput
setmetatable(TTSMultiOutput, { __index = M.genericOutput })
TTSMultiOutput.__class__ = "TTSMultiOutput"

function TTSMultiOutput.new(runner)
    local t = M.genericOutput.new(runner)
    t.children = {}
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
    ├── DIRECT OUTPUTS (special destinations)
    │   └── GridOutput (visual GUI grid, subclasses genericOutput directly)
    │
    └── YieldOutput (controls coroutine yieldFrequency)
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
        return self.colors[status] or self.colors.INFO
    end
}

--[[────────────────────────────────────────────────────────────────────────────
    ChatOutput: Colored chat window output wrapping TextOutput or TapOutput formatting
────────────────────────────────────────────────────────────────────────────]] --
--- @class ChatOutput wraps either TextOutput or TapOutput
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
        __index = function(_, key)
            return ChatOutput[key] or baseClass[key]
        end
    })
end

function ChatOutput:flush(line)
    self.flushFunc(line, Color.fromHex(self:getColorForNode(self.result.currentNode)))
end

--[[────────────────────────────────────────────────────────────────────────────
    LogOutput: System console output wrapping TextOutput or TapOutput formatting
────────────────────────────────────────────────────────────────────────────]] --
--- @class LogOutput wraps either TextOutput or TapOutput
local LogOutput = {}
LogOutput.__index = LogOutput
LogOutput.__class__ = "LogOutput"

function LogOutput.new(runner, colors, cfg)
    local flushFunc = function(line)
        log(line)
    end
    local t, baseClass = createOutput(runner, colors, cfg, flushFunc)

    return setmetatable(t, {
        __index = function(_, key)
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

local function buildGridUI()
    return
    {
        {
            tag = "Defaults",
            attributes = {},
            children = {
                {
                    tag = "Text",
                    attributes = {
                        alignment = "MiddleCenter",
                        class = "title",
                        color = "White",
                        fontStyle = "Bold",
                        resizeTextForBestFit = "true"
                    },
                    children = {},
                }
            },
        },
        {
            tag = "Panel",
            attributes = {
                id = "TestStatus",
                width = "650",
                height = "700",
                position = "0 350 -50",
                color = "#666666",
                active = "true"
            },
            children = {
                {
                    tag = "VerticalLayout",
                    attributes = {
                        spacing = "10",
                        padding = "10 10 10 10"
                    },
                    children = {
                        {
                            tag = "Text",
                            attributes = {
                                class = "title",
                                preferredHeight = "80",
                                text = "Test Progress"
                            }
                        },
                        {
                            tag = "Panel",
                            attributes = {
                                preferredWidth = "580",
                                flexibleHeight = "1",
                                color = "#333333",
                                padding = "10 10 0 10",
                                alignment = "MiddleCenter"
                            },
                            children = {
                                {
                                    tag = "VerticalScrollView",
                                    attributes = {
                                        id = "TestScroll",
                                        preferredHeight = "580",
                                        contentSizeFitter = "vertical",
                                        color = "#222222"
                                    },
                                    children = {
                                        {
                                            tag = "VerticalLayout",
                                            attributes = {
                                                preferredHeight = "580",
                                                contentSizeFitter = "vertical"
                                            },
                                            children = {
                                                {
                                                    tag = "GridLayout",
                                                    attributes = {
                                                        id = "TestGrid",
                                                        cellSize = "50 50",
                                                        spacing = "6 6",
                                                        padding = "10 10 10 10",
                                                        constraint = "FixedColumnCount",
                                                        constraintCount = "10",
                                                        color = "#222222",
                                                        alignment = "UpperCenter"
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
end

--- @class GridOutput: genericOutput
GridOutput = {
    __class__ = "GridOutput"
}
setmetatable(GridOutput, { __index = M.genericOutput })

function onTestSquareClick(player, value, id)
    local runner = _G.__luaunit_runner_instance

    local node = runner.result.allTests[tonumber(id)]
    if not node then
        printToAll("No data for test #" .. id, { 1, 0, 0 })
        return
    end

    printToAll(M.prettystr(node), Color.fromHex(TTSOutput.colors[node.status] or TTSOutput.colors.UNKNOWN))
end

function GridOutput.new(runner, config)
    local t = M.genericOutput.new(runner)
    t.gridOwner = config.gridOwner
    t.colors = config.colors or TTSOutput.colors
    t.testOutputs = {}

    -- Add color handling
    for k, v in pairs(ColoredOutput) do
        t[k] = v
    end

    return setmetatable(t, { __index = GridOutput })
end

function GridOutput:startSuite()
    local clickFunc = "onTestSquareClick"

    if M.LuaUnit.outputType.scriptOwner == Global then
        clickFunc = "Global" .. "/" .. clickFunc
    end

    local uiTable = buildGridUI()

    -- create one Button per test square, using GUID/functionName syntax
    local panels = {}
    local totalTests = self.runner.result.selectedCount
    for i = 1, totalTests do
        local id = tostring(i) -- just "1", "2", "3", …
        table.insert(panels, {
            tag = "Button",
            attributes = {
                id      = id,
                onClick = clickFunc,
                width   = "50",
                height  = "50",
                color   = self.colors.INFO,
                text    = ""
            }
        })
    end

    -- attach the buttons into the GridLayout
    local testGrid = findElementById(uiTable, "TestGrid")
    if not testGrid then
        printToAll(self.__class__ .. ": TestGrid not found", Color.fromHex(self.colors.ERROR))
        return
    end
    testGrid.children = panels

    -- render the assembled UI
    self.gridOwner.UI.setXmlTable(uiTable)
end

function GridOutput:endTest(node)
    local colorHex = self:getColorForNode(node)
    local id = tostring(node.number)
    self.testOutputs[id] = node

    printToAll("GridOutput: " .. id .. " → " .. M.prettystr(node), Color.Orange)

    self.gridOwner.UI.setAttribute(id, "color", colorHex)
    self.gridOwner.UI.setAttribute(id, "value", colorHex)
    if self.runner.result.selectedCount > 100 then
        local completedTests = node.number
        local percent = 1 - (completedTests / self.runner.result.selectedCount)
        self.gridOwner.UI.setAttribute("TestScroll", "verticalNormalizedPosition", tostring(percent))
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
local YieldOutput = {}
YieldOutput.__index = YieldOutput
YieldOutput.__class__ = "YieldOutput"

--- @param runner table LuaUnit runner instance
--- @param freq   number of tests between each coroutine.yield
function YieldOutput.new(runner, freq)
    -- inherit no-op lifecycle methods & emit/emitLine from genericOutput
    local t = M.genericOutput.new(runner) -- :contentReference[oaicite:0]{index=0}:contentReference[oaicite:1]{index=1}
    t.count = 0
    t.freq = freq or 10
    return setmetatable(t, YieldOutput)
end

function YieldOutput:startSuite(_)
    coroutine.yield(0)
end

function YieldOutput:endSuite(_)
    coroutine.yield(0)
end

--- Called after each test; yields every self.freq tests.
function YieldOutput:endTest(_)
    self.count = self.count + 1
    if self.count % self.freq == 0 then
        coroutine.yield(0)
    end
end

function YieldOutput:endClass(_)
    coroutine.yield(0)
end

---------------------------------------------------------------
-- Factory method to build the complete output graph
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

    -- GridOutput (enabled by default if gridOwner exists)
    if config.grid ~= false and config.gridOwner then
        root:add(GridOutput.new(runner, config))
    end

    if config.yieldFrequency then
        root:add(YieldOutput.new(runner, config.yieldFrequency))
    end

    return root
end

return TTSOutput
