-- AdoptMeDeltaBot: GUI prototype only. No Trade Hub automation.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local player = Players.LocalPlayer
assert(player, "AdoptMeDeltaBot must run on the client")
local parent = player:WaitForChild("PlayerGui")
local GUI_NAME = "AdoptMeDeltaBotGUI"
local old = parent:FindFirstChild(GUI_NAME)
if old then old:Destroy() end

local ITEMS = {
    give = {{id = "ribbon_seal", name = "Ribbon Seal"}},
    want = {{id = "ride_potion", name = "Ride Potion"}, {id = "fly_potion", name = "Fly Potion"}},
}
local C = {
    background = Color3.fromRGB(10, 15, 28), panel = Color3.fromRGB(19, 28, 46),
    border = Color3.fromRGB(49, 65, 91), text = Color3.fromRGB(229, 239, 250),
    muted = Color3.fromRGB(137, 157, 181), cyan = Color3.fromRGB(71, 216, 237),
    purple = Color3.fromRGB(151, 119, 246), red = Color3.fromRGB(241, 122, 139),
}
local state = {running = false, give = ITEMS.give[1], want = ITEMS.want[1], giveQuantity = 1, wantQuantity = 1}
local connections, logs, counters, counterLabels = {}, {}, {offersSent = 0, invalid = 0, errors = 0}, {}
local dropdownConnections, collectingDropdown = {}, false
local alive, minimized, openDropdown = true, false, nil
local function connect(signal, callback)
    local connection = signal:Connect(callback)
    table.insert(collectingDropdown and dropdownConnections or connections, connection)
    return connection
end
local function make(class, properties, container)
    local object = Instance.new(class)
    for key, value in pairs(properties) do object[key] = value end
    object.Parent = container
    return object
end
local function round(object, radius)
    make("UICorner", {CornerRadius = UDim.new(0, radius or 8)}, object)
end
local function border(object, color)
    make("UIStroke", {Color = color or C.border, Transparency = 0.3, Thickness = 1}, object)
end
local function tween(object, properties)
    TweenService:Create(object, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), properties):Play()
end
local function label(container, text, x, y, width, height, size, color)
    return make("TextLabel", {BackgroundTransparency = 1, Position = UDim2.fromOffset(x, y),
        Size = UDim2.fromOffset(width, height), Text = text, TextColor3 = color or C.text,
        Font = Enum.Font.GothamMedium, TextSize = size or 12, TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 3}, container)
end
local function button(container, text, x, y, width, height, accent)
    local base = C.panel
    local b = make("TextButton", {Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(width, height),
        BackgroundColor3 = base, AutoButtonColor = false, Text = text, TextColor3 = accent or C.text,
        Font = Enum.Font.GothamBold, TextSize = 12, ZIndex = 4}, container)
    round(b, 7)
    border(b, accent)
    connect(b.MouseEnter, function() tween(b, {BackgroundColor3 = Color3.fromRGB(33, 46, 68)}) end)
    connect(b.MouseLeave, function() tween(b, {BackgroundColor3 = base}) end)
    connect(b.MouseButton1Down, function() tween(b, {BackgroundColor3 = Color3.fromRGB(44, 60, 84)}) end)
    connect(b.MouseButton1Up, function() tween(b, {BackgroundColor3 = base}) end)
    return b
end

local gui = make("ScreenGui", {Name = GUI_NAME, ResetOnSpawn = false, IgnoreGuiInset = true,
    DisplayOrder = 10000, ZIndexBehavior = Enum.ZIndexBehavior.Sibling}, parent)
local window = make("Frame", {Name = "Window", Size = UDim2.fromOffset(420, 486),
    Position = UDim2.new(0.5, -210, 0.5, -243), BackgroundColor3 = C.background,
    BackgroundTransparency = 0.08, ClipsDescendants = true, Active = true, ZIndex = 1}, gui)
round(window, 12)
border(window, C.cyan)
local scale = make("UIScale", {Scale = 1}, window)
local function fit()
    local camera = workspace.CurrentCamera
    if camera then scale.Scale = math.min(1, math.max(0.25, math.min((camera.ViewportSize.X - 20) / 420, (camera.ViewportSize.Y - 20) / 486))) end
end
fit()
local cameraConnection
local function watchCamera()
    if cameraConnection then cameraConnection:Disconnect() end
    local camera = workspace.CurrentCamera
    if camera then cameraConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(fit) end
    fit()
end
watchCamera()
connect(workspace:GetPropertyChangedSignal("CurrentCamera"), watchCamera)
local header = make("Frame", {Size = UDim2.new(1, 0, 0, 66), BackgroundTransparency = 1, Active = true, ZIndex = 2}, window)
label(header, "ADOPT ME TRADE BOT", 16, 11, 300, 22, 15)
local status = label(header, "Status: IDLE", 16, 36, 285, 17, 11, C.muted)
local minimize = button(header, "−", 344, 14, 26, 26, C.cyan)
local close = button(header, "×", 378, 14, 26, 26, C.muted)
local content = make("Frame", {Position = UDim2.fromOffset(0, 66), Size = UDim2.fromOffset(420, 420), BackgroundTransparency = 1, ZIndex = 2}, window)
local preview
local logScroll = make("ScrollingFrame", {Position = UDim2.fromOffset(16, 304), Size = UDim2.fromOffset(388, 99),
    BackgroundColor3 = C.panel, BackgroundTransparency = 0.25, BorderSizePixel = 0, ScrollBarThickness = 3,
    ScrollBarImageColor3 = C.cyan, CanvasSize = UDim2.fromOffset(0, 0), ZIndex = 3}, content)
round(logScroll, 7)
local function addLog(category, message)
    if not alive then return end
    local entry = label(logScroll, "[" .. category .. "] " .. message, 8, 0, 364, 18, 10, C.muted)
    entry.TextTruncate = Enum.TextTruncate.AtEnd
    table.insert(logs, entry)
    if #logs > 80 then table.remove(logs, 1):Destroy() end
    for i, line in ipairs(logs) do line.Position = UDim2.fromOffset(8, 5 + (i - 1) * 18) end
    local height = #logs * 18 + 10
    logScroll.CanvasSize = UDim2.fromOffset(0, height)
    logScroll.CanvasPosition = Vector2.new(0, math.max(0, height - logScroll.AbsoluteWindowSize.Y))
end
local function tradeText()
    return state.give.name .. " x" .. state.giveQuantity .. "  →  " .. state.want.name .. " x" .. state.wantQuantity
end
local function updateTrade()
    if preview then preview.Text = tradeText() end
    addLog("Trade", tradeText())
end
local function dismissDropdown()
    for _, connection in ipairs(dropdownConnections) do connection:Disconnect() end
    table.clear(dropdownConnections)
    if openDropdown then openDropdown:Destroy(); openDropdown = nil end
end
local function selector(side, title, x, accent)
    local card = make("Frame", {Position = UDim2.fromOffset(x, 0), Size = UDim2.fromOffset(188, 131), BackgroundColor3 = C.panel,
        BackgroundTransparency = 0.2, ZIndex = 3}, content)
    round(card, 9); border(card)
    label(card, title, 12, 9, 164, 20, 12, accent)
    label(card, "Item", 12, 32, 164, 17, 10, C.muted)
    local select = button(card, state[side].name .. "  ▾", 12, 51, 164, 29)
    select.TextSize = 11
    label(card, "Quantity", 12, 91, 71, 22, 10, C.muted)
    local minus = button(card, "−", 84, 90, 26, 26)
    local quantity = label(card, "1", 112, 90, 35, 26, 12)
    quantity.TextXAlignment = Enum.TextXAlignment.Center
    local plus = button(card, "+", 150, 90, 26, 26, accent)
    local key = side .. "Quantity"
    connect(minus.Activated, function()
        if state[key] > 1 then state[key] -= 1; quantity.Text = tostring(state[key]); updateTrade() end
    end)
    connect(plus.Activated, function()
        if state[key] < 9999 then state[key] += 1; quantity.Text = tostring(state[key]); updateTrade() end
    end)
    connect(select.Activated, function()
        local same = openDropdown and openDropdown.Name == side
        dismissDropdown()
        if same then return end
        local menu = make("Frame", {Name = side, Position = UDim2.fromOffset(x + 12, 82), Size = UDim2.fromOffset(164, 0),
            BackgroundColor3 = C.background, ClipsDescendants = true, ZIndex = 20}, content)
        round(menu, 7); border(menu, accent)
        openDropdown = menu
        collectingDropdown = true
        for i, item in ipairs(ITEMS[side]) do
            local option = button(menu, item.name, 4, 4 + (i - 1) * 30, 156, 26, accent)
            option.ZIndex = 21
            connect(option.Activated, function()
                state[side] = item; select.Text = item.name .. "  ▾"; dismissDropdown(); updateTrade()
            end)
        end
        collectingDropdown = false
        tween(menu, {Size = UDim2.fromOffset(164, #ITEMS[side] * 30 + 8)})
    end)
end
selector("give", "YOU GIVE", 16, C.cyan)
selector("want", "YOU WANT", 216, C.purple)
label(content, "SELECTED TRADE", 16, 141, 388, 17, 10, C.muted)
preview = label(content, tradeText(), 16, 160, 388, 24, 12)
preview.TextXAlignment = Enum.TextXAlignment.Center
preview.TextTruncate = Enum.TextTruncate.AtEnd
local start = button(content, "START", 16, 195, 188, 34, C.cyan)
local stop = button(content, "STOP", 216, 195, 188, 34, C.purple)
local function setStatus(value, color)
    status.Text = "Status: " .. value
    tween(status, {TextColor3 = color})
    start.Active = not state.running
    start.TextTransparency = state.running and 0.55 or 0
end
-- Future Trader integration: keep callbacks local and implement only after real inspection.
local Trader = {}
function Trader.start(config)
    -- GUI prototype. No offers are sent.
end
function Trader.stop()
    -- Future cancellation should be synchronous and idempotent.
end
local function setCounter(name, value)
    assert(counters[name] ~= nil, "Unknown counter: " .. tostring(name))
    assert(type(value) == "number" and value >= 0 and value < math.huge, "Invalid counter value")
    counters[name] = math.floor(value)
    counterLabels[name].Text = tostring(counters[name])
end
local function incrementCounter(name, amount)
    setCounter(name, counters[name] + (amount or 1))
end
-- Future Trader can call setCounter/incrementCounter and addLog in this file.
for i, definition in ipairs({{"offersSent", "Offers Sent"}, {"invalid", "Invalid"}, {"errors", "Errors"}}) do
    local x = 16 + (i - 1) * 132
    label(content, definition[2], x, 244, 120, 15, 10, C.muted)
    counterLabels[definition[1]] = label(content, "0", x, 260, 120, 21, 15, i == 3 and C.purple or C.cyan)
end
label(content, "ACTIVITY LOG", 16, 285, 388, 16, 10, C.muted)
connect(start.Activated, function()
    if state.running then return end
    dismissDropdown()
    if not state.give or not state.want or state.giveQuantity < 1 or state.wantQuantity < 1 then
        incrementCounter("errors"); addLog("Error", "Invalid trade configuration"); return
    end
    state.running = true
    setStatus("RUNNING", C.cyan)
    addLog("Trade", tradeText())
    addLog("Bot", "Started (GUI only; no offers sent)")
    local ok, err = pcall(Trader.start, {give = state.give.id, want = state.want.id,
        giveQuantity = state.giveQuantity, wantQuantity = state.wantQuantity})
    if not ok then
        state.running = false; setStatus("STOPPED", C.red)
        incrementCounter("errors"); addLog("Error", tostring(err))
    end
end)
connect(stop.Activated, function()
    state.running = false
    setStatus("STOPPED", C.purple)
    local ok, err = pcall(Trader.stop)
    addLog("Bot", "Stopped")
    if not ok then incrementCounter("errors"); addLog("Error", tostring(err)) end
end)
connect(minimize.Activated, function()
    dismissDropdown()
    minimized = not minimized
    content.Visible = not minimized
    minimize.Text = minimized and "+" or "−"
    tween(window, {Size = UDim2.fromOffset(420, minimized and 66 or 486)})
end)
local dragging, dragOrigin, windowOrigin
connect(header.InputBegan, function(input)
    if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
    local point = input.Position
    if point.X >= minimize.AbsolutePosition.X then return end
    dismissDropdown()
    dragging = input
    dragOrigin = input.Position
    windowOrigin = window.Position
end)
connect(UserInputService.InputChanged, function(input)
    if not dragging then return end
    if input.UserInputType == Enum.UserInputType.MouseMovement or input == dragging then
        local delta = input.Position - dragOrigin
        window.Position = UDim2.new(windowOrigin.X.Scale, windowOrigin.X.Offset + delta.X,
            windowOrigin.Y.Scale, windowOrigin.Y.Offset + delta.Y)
    end
end)
connect(UserInputService.InputEnded, function(input)
    if input == dragging or input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = nil end
end)
local function cleanup()
    if not alive then return end
    alive = false; state.running = false
    dismissDropdown()
    pcall(Trader.stop)
    if cameraConnection then cameraConnection:Disconnect() end
    for _, connection in ipairs(connections) do connection:Disconnect() end
    table.clear(connections)
    table.clear(logs)
end
connect(gui.Destroying, cleanup)
connect(close.Activated, function() gui:Destroy() end)
addLog("GUI", "Loaded")
addLog("Trade", tradeText())
