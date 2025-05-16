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
    gridOwner = nil, -- set to the object that owns the UI (usually self)
    yieldFrequency = 10, -- number of tests between each coroutine.yield
    
    -- Colors used by all outputs
    colors = {
        [M.NodeStatus.SUCCESS] = "#00FF00", -- bright green (test passed)
        [M.NodeStatus.FAIL] = "#FF0000", -- bright red (test failed)
        [M.NodeStatus.ERROR] = "#FF6600", -- dark orange (test had runtime error)
        [M.NodeStatus.SKIP] = "#FFFF00", -- yellow (test skipped)
        INFO = "#FFFDD0", -- cream (generic info)
        UNKNOWN = "#FF00FF", -- magenta
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
local TTSMultiOutput = { __class__ = "TTSMultiOutput" }
TTSMultiOutput.__index = TTSMultiOutput
setmetatable(TTSMultiOutput, { __index = M.genericOutput })

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
    ├── TTSMultiOutput (TTS port - composite, delegates to children)
    │
    ├── OUTPUT FORMATTERS (LuaUnit base - what to output)
    │   ├── M.TextOutput (human readable format)
    │   └── M.TapOutput (human/machine readable format)
    │
    ├── OUTPUT DECORATORS (TTS port - where to output)
    │   ├── ChatOutput (decorates any formatter with colored output to chat window)
    │   └── LogOutput (decorates any formatter with output to system console)
    │
    ├── DIRECT OUTPUTS (TTS port - special destinations)
    │   └── GridOutput (visual GUI grid, subclasses genericOutput directly)
    │
    └── YieldOutput (TTS port - controls coroutine yieldFrequency)
────────────────────────────────────────────────────────────────────────────]] --

local FormatterDecorator = {}
function FormatterDecorator._init(decorator, runner, colors, config)
    local formatter = (config.format == "TAP") and M.TapOutput or M.TextOutput
    local self = formatter.new(runner)
    
    self.colors = colors or TTSOutput.colors
    self.verbosity = config.verbosity or M.VERBOSITY_DEFAULT
    for k, v in pairs(_G.Emitter) do
        self[k] = v
    end
    self:init()
    
    return setmetatable(self, { __index = function(_, k)
        return decorator[k] or formatter[k]
    end })
end

local _colorCache = {}
local function colorFromHex(hex)
    local c = _colorCache[hex]
    if not c then
        c = Color.fromHex(hex)
        _colorCache[hex] = c
    end
    return c
end

local function statusColor(colors, status)
    return colors[status] or colors.INFO
end

--[[────────────────────────────────────────────────────────────────────────────
    ChatOutput: Colored chat window output wrapping TextOutput or TapOutput formatting
────────────────────────────────────────────────────────────────────────────]] --
--- @class ChatOutput wraps either TextOutput or TapOutput
local ChatOutput = { __class__ = "ChatOutput" }
ChatOutput.__index = ChatOutput

function ChatOutput.new(runner, colors, cfg)
    return FormatterDecorator._init(ChatOutput, runner, colors, cfg)
end

function ChatOutput:flush(line)
    local node = self.result.currentNode
    local hex = statusColor(self.colors, node and node.status or "INFO")
    printToAll(line, colorFromHex(hex))
end

--[[────────────────────────────────────────────────────────────────────────────
    LogOutput: System console output wrapping TextOutput or TapOutput formatting
────────────────────────────────────────────────────────────────────────────]] --
--- @class LogOutput wraps either TextOutput or TapOutput
local LogOutput = { __class__ = "LogOutput" }
LogOutput.__index = LogOutput

function LogOutput.new(runner, colors, cfg)
    return FormatterDecorator._init(LogOutput, runner, colors, cfg)
end

function LogOutput:flush(line)
    log(line)
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
    local testGrid = {
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
        },
        children = {}
    }
    local ui = {
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
                                                testGrid,
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
    
    return ui, testGrid
end

--- @class GridOutput: genericOutput
GridOutput = { __class__ = "GridOutput" }
setmetatable(GridOutput, { __index = M.genericOutput })

function onTestSquareClick(_player, _value, id)
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
    return setmetatable(t, { __index = GridOutput })
end

function GridOutput:startSuite()
    local clickFunc = "onTestSquareClick"
    
    if M.LuaUnit.outputType.scriptOwner == Global then
        clickFunc = "Global" .. "/" .. clickFunc
    end
    
    local uiTable, testGrid = buildGridUI()
    
    local totalTests = self:totalTests()
    for i = 1, totalTests do
        local id = tostring(i)
        table.insert(testGrid.children, {
            tag = "Button",
            attributes = {
                id = id,
                onClick = clickFunc,
                width = "50",
                height = "50",
                color = self.colors.INFO,
            }
        })
    end
    
    self.gridOwner.UI.setXmlTable(uiTable)
end

function GridOutput:endTest(node)
    local id = tostring(node.number)
    local hex = statusColor(self.colors, node.status)
    self.gridOwner.UI.setAttribute(id, "color", hex)
    if self:totalTests() > 100 then
        local completedTests = node.number
        local percent = 1 - (completedTests / self:totalTests())
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
local YieldOutput = { __class__ = "YieldOutput" }
YieldOutput.__index = YieldOutput

--- @param runner table LuaUnit runner instance
--- @param freq   number of tests between each coroutine.yield
function YieldOutput.new(_, freq)
    return setmetatable({ freq = freq, n = 0 }, YieldOutput)
end

function YieldOutput:startSuite(_)
    coroutine.yield(0)
end

function YieldOutput:endSuite(_)
    coroutine.yield(0)
end

function YieldOutput:endTest(_)
    self.n = self.n + 1
    if self.n % self.freq == 0 then
        coroutine.yield(0)
    end
end

---------------------------------------------------------------
-- Factory method to build the complete output graph
---------------------------------------------------------------
function buildTTSOutput(runner, cfg)
    local root = TTSMultiOutput.new(runner)
    
    -- ChatOutput (enabled unless explicitly disabled)
    if cfg.chat ~= false then
        root:add(ChatOutput.new(runner, cfg.colors, cfg.chat))
    end
    
    -- LogOutput (enabled unless explicitly disabled)
    if cfg.log ~= false then
        root:add(LogOutput.new(runner, cfg.colors, cfg.log))
    end
    
    -- GridOutput (enabled by default if gridOwner exists)
    if cfg.grid ~= false and cfg.gridOwner then
        root:add(GridOutput.new(runner, cfg))
    end
    
    if cfg.yieldFrequency then
        root:add(YieldOutput.new(runner, cfg.yieldFrequency))
    end
    
    return root
end

return TTSOutput
