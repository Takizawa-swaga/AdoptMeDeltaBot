-- Takizawa_swaga / AdoptMeDeltaBot. Resolver-driven client GUI Auto Trade; Dry Run by default.
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ANIME_IMAGE_URL = "https://raw.githubusercontent.com/Takizawa-swaga/AdoptMeDeltaBot/main/assets/anime.png"
local ANIME_LOCAL_PATH = "Takizawa_anime.png"
local function loadAnimeAsset()
    local saveFile, registerAsset = writefile, getcustomasset
    if type(saveFile) ~= "function" or type(registerAsset) ~= "function" then
        warn("[AnimeBackground] writefile or getcustomasset unavailable")
        return nil
    end
    local ok, data = pcall(function() return game:HttpGet(ANIME_IMAGE_URL) end)
    if not ok then
        warn("[AnimeBackground] Download failed: " .. tostring(data):sub(1, 180))
        return nil
    end
    if type(data) ~= "string" or #data < 33 or #data > 20 * 1024 * 1024 then
        warn("[AnimeBackground] Invalid download type or size")
        return nil
    end
    if data:sub(1, 8) ~= "\137PNG\r\n\26\n" then
        warn("[AnimeBackground] Download is not a PNG")
        return nil
    end
    -- Preserve the binary response exactly; no text decoding or cache APIs.
    local saved, saveError = pcall(saveFile, ANIME_LOCAL_PATH, data)
    if not saved or saveError == false then
        warn("[AnimeBackground] Save failed: " .. tostring(saveError):sub(1, 180))
        return nil
    end
    local registered, uri = pcall(registerAsset, ANIME_LOCAL_PATH)
    if not registered or type(uri) ~= "string" or uri == "" then
        warn("[AnimeBackground] Registration failed: " .. tostring(uri):sub(1, 180))
        return nil
    end
    return uri
end
local ANIME_IMAGE_ID = loadAnimeAsset()
-- Sibling subtrees: art < lighting < petals < glass < controls < popups.
local Z = {background = 1, lighting = 2, petals = 3, glass = 5, decoration = 6, control = 7, header = 8, popup = 50}
local GUI_NAME = "TakizawaAdoptMeGUI"
local ITEMS = {
    {id = "ribbon_seal", name = "Ribbon Seal"},
    {id = "ride_potion", name = "Ride Potion"},
    {id = "fly_potion", name = "Fly Potion"},
}
local C = {
    bg = Color3.fromRGB(12, 10, 20), glass = Color3.fromRGB(34, 19, 31),
    pink = Color3.fromRGB(194, 119, 151), magenta = Color3.fromRGB(104, 47, 74),
    pale = Color3.fromRGB(218, 194, 209), text = Color3.fromRGB(246, 235, 247),
    muted = Color3.fromRGB(173, 149, 178), line = Color3.fromRGB(91, 62, 91),
    green = Color3.fromRGB(73, 221, 117), red = Color3.fromRGB(255, 101, 129),
}
-- Live submit requires BOTH DryRun=false and the existing mode selector set to Auto.
local LIVE_TEST = true -- START opens one real listing, verifies its window, then stops.
local TradeConfig = {
    DryRun = true, Debug = false, MinConfidence = 0.80, AmbiguityMargin = 0.06,
    ScanInterval = 1.5, ActionDelay = 0.12, PollInterval = 0.15,
    DialogTimeout = 4, InventoryTimeout = 4, ResultTimeout = 6, ListingCooldown = 120,
    MaxNodes = 2500, MaxCards = 80, MaxAncestors = 8, MaxDumpLines = 180, MaxOfferQuantity = 9, MaxProcessed = 500,
    -- Verified image URI -> item name mapping, populated only from known game evidence.
    ItemImages = {},
}
local TradeBackend = {}
local state = {running = false, give = ITEMS[1], want = ITEMS[2], giveQuantity = 1,
    wantQuantity = 1, delay = 3, mode = "Обычный", repeatTrades = true, elapsed = 0,
    schemes = {}, selected = nil, generation = 0}
local alive, minimized = true, false
local connections, tweens, pages, navButtons = {}, {}, {}, {}
local stats = {sent = 0, success = 0, invalid = 0, errors = 0}
local statLabels, tradeViews, settingViews, statusViews, timerViews = {}, {}, {}, {}, {}
local logs, logLabels = {}, {}
local schemeSummaries = {}
local gui, window, body, header, sidebar, anime, pageHost, uiScale, contentScale, popupLayer
-- Composition coordinates refer to the unchanged 1890x832 assets/anime.png.
local ART_ASPECT = 1890 / 832
local LANDSCAPE_HEIGHT = 600
local WORK = {left = 0.60, top = 0.15, width = 0.365, height = 0.71}
local RAIL = {width = 52, button = 46, gap = 6, height = 306}
-- Optional Roblox/custom asset URI for a full-canvas transparent hair layer.
-- No downloads or effect are enabled until a separate clean layer exists.
-- Placeholder file: assets/hair_overlay.png (transparent 1890x832 canvas).
-- Supply a registered Roblox/custom asset URI here once that layer exists.
local HAIR_OVERLAY_IMAGE = ""
local W, H, portrait = LANDSCAPE_HEIGHT * ART_ASPECT, LANDSCAPE_HEIGHT, false
local navLayout
local activePage = "home"
local cameraConnection, dropdownClose, dropdownAnchor, listRefresh
local backgroundImage, backgroundShade, shadeGradient, petalLayer, hairOverlay, hairTween
local ambientTweens, activePetals = {}, {}
local navPulseTween, navPulseValue, navPulseEntry
local navPulseConnections = {}
local particleThread, petalCount = nil, 0
local random = Random.new()
local function connect(signal, callback, scope)
    local c = signal:Connect(callback)
    table.insert(scope or connections, c)
    return c
end
local function disconnect(scope)
    for _, c in ipairs(scope) do c:Disconnect() end
    table.clear(scope)
end
local function make(class, parent, props)
    local object = Instance.new(class)
    for key, value in pairs(props or {}) do object[key] = value end
    if object:IsA("GuiObject") and (not props or props.ZIndex == nil) then object.ZIndex = Z.glass end
    object.Parent = parent
    return object
end
local function corners(object, radius)
    make("UICorner", object, {CornerRadius = UDim.new(0, radius or 9)})
end
local function stroke(object, color, transparency, thickness)
    return make("UIStroke", object, {Color = color or C.line, Transparency = transparency or 0.2,
        Thickness = thickness or 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border})
end
local function gradient(object, first, last, rotation)
    return make("UIGradient", object, {Color = ColorSequence.new(first, last), Rotation = rotation or 0})
end
local function animate(object, props, duration)
    if tweens[object] then tweens[object]:Cancel() end
    local t = TweenService:Create(object, TweenInfo.new(duration or 0.14, Enum.EasingStyle.Quad), props)
    tweens[object] = t
    t.Completed:Once(function()
        if tweens[object] == t then tweens[object] = nil end
    end)
    t:Play()
    return t
end
local function frame(parent, x, y, width, height, color, transparency)
    return make("Frame", parent, {Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(width, height),
        BackgroundColor3 = color or C.glass, BackgroundTransparency = transparency or 0,
        BorderSizePixel = 0, Active = false})
end
local function text(parent, value, x, y, width, height, size, color)
    return make("TextLabel", parent, {Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(width, height),
        BackgroundTransparency = 1, Text = value, TextSize = size or 15, TextColor3 = color or C.text,
        Font = Enum.Font.GothamMedium, TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd, Active = false, ZIndex = Z.control})
end
local function createButton(parent, value, x, y, width, height, bright, scope)
    local base = bright and C.magenta or C.glass
    local transparency = bright and 0.38 or 0.48
    local b = make("TextButton", parent, {Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(width, height),
        BackgroundColor3 = base, BackgroundTransparency = transparency, AutoButtonColor = false,
        Text = value, TextColor3 = bright and C.text or C.pale, TextSize = 15, Font = Enum.Font.GothamMedium, ZIndex = Z.control})
    corners(b, 8); stroke(b, C.pink, bright and 0.2 or 0.58)
    if bright then gradient(b, C.pink, C.magenta, 25) end
    local function appearance(hover, pressed)
        local selected = b:GetAttribute("GlassSelected") == true
        local resting = b:GetAttribute("CompactNavigation") and 0.86 or transparency
        local opacity = selected and (b:GetAttribute("CompactNavigation") and 0.64 or 0.32) or resting
        animate(b, {BackgroundColor3 = (bright or selected) and C.magenta or (hover and Color3.fromRGB(43, 20, 37) or base),
            BackgroundTransparency = opacity - (pressed and 0.08 or hover and 0.04 or 0),
            TextTransparency = pressed and 0.12 or 0})
    end
    connect(b.MouseEnter, function() appearance(true, false) end, scope)
    connect(b.MouseLeave, function() appearance(false, false) end, scope)
    connect(b.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
            appearance(true, true)
        end
    end, scope)
    connect(b.InputEnded, function(input)
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then appearance(false, false) end
    end, scope)
    return b
end
local function createCard(parent, title, x, y, width, height)
    local card = frame(parent, x, y, width, height, C.glass, 0.40)
    card.Name = title
    corners(card); stroke(card, C.pink, 0.78)
    -- UIGradient multiplies the surface colour: use light tint stops rather
    -- than multiplying dark glass by another near-black gradient.
    gradient(card, Color3.fromRGB(246, 210, 232), Color3.fromRGB(188, 172, 198), 70)
    text(card, title, 12, 8, width - 24, 22, 13, C.pale)
    frame(card, 10, 28, width - 20, 1, C.line, 0.4).ZIndex = Z.decoration
    return card
end
local function closeDropdown()
    if dropdownClose then dropdownClose(); dropdownClose = nil end
    dropdownAnchor = nil
end
local function addLog(category, message)
    if not alive then return end
    table.insert(logs, "[" .. category .. "] " .. message)
    if #logs > 80 then table.remove(logs, 1) end
    for _, view in ipairs(logLabels) do
        view.label.Text = table.concat(logs, "\n")
        local height = #logs * 22 + 16
        view.label.Size = UDim2.new(1, -20, 0, height)
        view.scroll.CanvasSize = UDim2.fromOffset(0, height)
        view.scroll.CanvasPosition = Vector2.new(0, math.max(0, height - view.scroll.AbsoluteWindowSize.Y))
    end
end
local function tradeText()
    return state.give.name .. " x" .. state.giveQuantity .. "  →  " .. state.want.name .. " x" .. state.wantQuantity
end
local function updateTrade(logChange)
    for _, view in ipairs(tradeViews) do
        view.give.Text = state.give.name .. "  ▾"; view.want.Text = state.want.name .. "  ▾"
        view.giveQuantity.Text = tostring(state.giveQuantity); view.wantQuantity.Text = tostring(state.wantQuantity)
        view.preview.Text = tradeText()
    end
    if logChange then addLog("Trade", tradeText()) end
end
local function increment(name)
    stats[name] += 1
    statLabels[name].Text = tostring(stats[name])
end
local function incrementSent() increment("sent") end
local function incrementSuccess() increment("success") end
local function incrementInvalid() increment("invalid") end
local function incrementErrors() increment("errors") end
-- Backend result handlers update these existing counters.
local function setStatus(value, color)
    for _, view in ipairs(statusViews) do
        view.label.Text = value; animate(view.label, {TextColor3 = color})
        animate(view.dot, {BackgroundColor3 = color})
    end
end
local startButtons = {}
local setRunning
setRunning = function(running)
    if running and state.running then return end
    closeDropdown()
    if running and LIVE_TEST then print("[LIVE] START pressed"); addLog("LIVE", "START pressed"); setStatus("SEARCHING TRADE HUB", C.green) end
    if running and not LIVE_TEST and (not state.give or not state.want or state.giveQuantity < 1 or state.wantQuantity < 1) then
        incrementErrors(); setStatus("Ошибка", C.red); addLog("Error", "Некорректное предложение"); return
    end
    state.running = running
    state.generation += 1 -- Backend actions must check this cancellation token.
    for _, b in ipairs(startButtons) do
        b.Active = not running
        animate(b, {TextTransparency = running and 0.5 or 0, BackgroundTransparency = running and 0.22 or 0.15})
    end
    if running then
        if not TradeBackend.startTradeBot() then setRunning(false) end
    else
        TradeBackend.stopTradeBot()
        setStatus("STOPPED", C.red)
        addLog("BOT", "Stopped; pending trade actions cancelled")
    end
end
local function createDropdown(anchor, options, selected, onSelect)
    dropdownAnchor = anchor
    local scope = {}
    local menu = frame(popupLayer, 0, 0, 200, 0, C.bg, 0.02)
    corners(menu); stroke(menu, C.pink)
    menu.ClipsDescendants = true
    menu.ZIndex = 51
    local scroller = make("ScrollingFrame", menu, {Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
        BorderSizePixel = 0, ScrollBarThickness = 3, ScrollBarImageColor3 = C.pink,
        CanvasSize = UDim2.fromOffset(0, #options * 40 + 8), ZIndex = 52})
    local s = uiScale.Scale
    local x = (anchor.AbsolutePosition.X - window.AbsolutePosition.X) / s
    local y = (anchor.AbsolutePosition.Y - window.AbsolutePosition.Y) / s + anchor.AbsoluteSize.Y / s + 4
    local width = anchor.AbsoluteSize.X / s
    local height = math.min(#options * 40 + 8, 208)
    if y + height > H - 12 then y = y - height - anchor.AbsoluteSize.Y / s - 8 end
    menu.Position = UDim2.fromOffset(math.clamp(x, 8, W - width - 8), math.max(70, y))
    menu.Size = UDim2.fromOffset(width, 0)
    for i, option in ipairs(options) do
        local b = createButton(scroller, option.name, 4, 4 + (i - 1) * 40, width - 8, 36, option.id == selected, scope)
        b.ZIndex = 53
        connect(b.Activated, function() onSelect(option); closeDropdown() end, scope)
    end
    dropdownClose = function()
        disconnect(scope)
        if tweens[menu] then tweens[menu]:Cancel(); tweens[menu] = nil end
        for _, obj in ipairs(menu:GetDescendants()) do
            if tweens[obj] then tweens[obj]:Cancel(); tweens[obj] = nil end
        end
        if not alive then menu:Destroy(); return end
        animate(menu, {Size = UDim2.fromOffset(width, 0)}, 0.1).Completed:Once(function()
            menu:Destroy()
            if not dropdownClose then popupLayer.Visible = false end
        end)
    end
    popupLayer.Visible = true
    animate(menu, {Size = UDim2.fromOffset(width, height)})
end
local function bindDropdown(button, options, selected, callback)
    connect(button.Activated, function()
        local wasOpen = dropdownAnchor == button
        closeDropdown()
        if not wasOpen then createDropdown(button, options, selected(), callback) end
    end)
end
local function createProposal(parent, y)
    local card = createCard(parent, "ПРЕДЛОЖЕНИЕ", 0, y, 500, 140)
    text(card, "Я отдаю", 12, 30, 210, 20, 13, C.muted)
    text(card, "Я получаю", 278, 30, 210, 20, 13, C.muted)
    local give = createButton(card, "", 12, 52, 210, 30)
    local want = createButton(card, "", 278, 52, 210, 30)
    local arrow = text(card, "⇄", 226, 50, 48, 34, 30, C.pink)
    arrow.TextXAlignment = Enum.TextXAlignment.Center
    local view = {give = give, want = want}
    for _, side in ipairs({"give", "want"}) do
        local x = side == "give" and 12 or 278
        local minus = createButton(card, "−", x, 88, 54, 28)
        view[side .. "Quantity"] = text(card, "1", x + 60, 88, 90, 28, 16)
        view[side .. "Quantity"].TextXAlignment = Enum.TextXAlignment.Center
        local plus = createButton(card, "+", x + 156, 88, 54, 28)
        connect(minus.Activated, function()
            state[side .. "Quantity"] = math.max(1, state[side .. "Quantity"] - 1); updateTrade(true)
        end)
        connect(plus.Activated, function()
            state[side .. "Quantity"] = math.min(9999, state[side .. "Quantity"] + 1); updateTrade(true)
        end)
        bindDropdown(view[side], ITEMS, function() return state[side].id end,
            function(item) state[side] = item; updateTrade(true) end)
    end
    view.preview = text(card, tradeText(), 8, 119, 484, 18, 11, C.pale)
    view.preview.TextXAlignment = Enum.TextXAlignment.Center
    table.insert(tradeViews, view)
    return card
end
local sliderInput, sliderTrack
local function updateSettings()
    for _, view in ipairs(settingViews) do
        view.value.Text = state.delay .. " сек"
        view.fill.Size = UDim2.fromScale((state.delay - 1) / 9, 1)
        view.knob.Position = UDim2.new((state.delay - 1) / 9, -8, 0.5, -8)
        view.repeatButton.Text = (state.repeatTrades and "☑" or "□") .. " Повторять по кругу"
        view.mode.Text = state.mode .. "  ▾"
    end
end
local function createSettingsControls(parent, y)
    local row = frame(parent, 0, y, 500, 78, C.bg, 1)
    row.Name = "SettingsRow"
    local delay = createCard(row, "ЗАДЕРЖКА МЕЖДУ ТРЕЙДАМИ", 0, 0, 260, 78)
    local track = frame(delay, 16, 53, 170, 5, C.line)
    corners(track, 4)
    local fill = frame(track, 0, 0, 0, 5, C.pink); corners(fill, 4)
    local knob = frame(track, 0, -5, 16, 16, C.pink); corners(knob, 16)
    local hit = make("TextButton", track, {Position = UDim2.fromOffset(-8, -17), Size = UDim2.new(1, 16, 0, 40),
        BackgroundTransparency = 1, Text = "", AutoButtonColor = false})
    local value = text(delay, "", 200, 39, 55, 32, 14, C.pink)
    local mode = createCard(row, "РЕЖИМ", 272, 0, 228, 78)
    local modeButton = createButton(mode, "", 10, 37, 90, 32)
    modeButton.TextSize = 11
    local repeatButton = createButton(mode, "", 106, 37, 114, 32)
    repeatButton.TextSize = 10
    table.insert(settingViews, {fill = fill, knob = knob, value = value, mode = modeButton, repeatButton = repeatButton})
    local function slide(input)
        local fraction = math.clamp((input.Position.X - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
        state.delay = math.floor(1 + fraction * 9 + 0.5); updateSettings()
    end
    connect(hit.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
            sliderInput = input; sliderTrack = slide; slide(input)
        end
    end)
    connect(repeatButton.Activated, function() state.repeatTrades = not state.repeatTrades; updateSettings() end)
    bindDropdown(modeButton, {{id = "normal", name = "Обычный"}, {id = "dry", name = "Dry Run"}, {id = "manual", name = "Manual"}, {id = "auto", name = "Auto"}}, function() return ({["Обычный"] = "normal", ["Dry Run"] = "dry", ["Manual"] = "manual", ["Auto"] = "auto"})[state.mode] end,
        function(option) state.mode = option.name; updateSettings() end)
    return row
end
local function createActions(parent, y)
    local row = frame(parent, 0, y, 500, 44, C.bg, 1)
    row.Name = "ActionsRow"
    make("UIListLayout", row, {FillDirection = Enum.FillDirection.Horizontal,
        SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0.024, 0)})
    local start = createButton(row, "▶  ЗАПУСТИТЬ", 0, 0, 244, 44, true)
    local stop = createButton(row, "■  ОСТАНОВИТЬ", 256, 0, 244, 44)
    start.Size = UDim2.fromScale(0.488, 1); stop.Size = UDim2.fromScale(0.488, 1)
    start.LayoutOrder = 1; stop.LayoutOrder = 2
    stroke(stop, C.red, 0.5)
    table.insert(startButtons, start)
    connect(start.Activated, function() setRunning(true) end)
    connect(stop.Activated, function() setRunning(false) end)
    return row
end
local function createStatus(parent, y)
    local card = createCard(parent, "СТАТУС", 0, y, 500, 52)
    local dot = frame(card, 14, 36, 8, 8, C.green); corners(dot, 10)
    local value = text(card, "Готов к работе", 32, 29, 320, 22, 14, C.green)
    local timer = text(card, "00:00:00", 388, 29, 100, 22, 13, C.pink)
    table.insert(statusViews, {label = value, dot = dot}); table.insert(timerViews, timer)
    return card
end
local function createPage(id)
    local page = make("ScrollingFrame", pageHost, {Name = id, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
        BorderSizePixel = 0, ScrollBarThickness = 3, ScrollBarImageColor3 = C.pink,
        CanvasSize = UDim2.fromOffset(0, 438), Visible = false})
    pages[id] = page
    return page
end
local function createHomePage()
    local page = createPage("home")
    page.CanvasSize = UDim2.fromOffset(0, 0)
    page.ScrollingEnabled = false; page.ScrollBarThickness = 0
    make("UIPadding", page, {PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 8)})
    make("UIListLayout", page, {SortOrder = Enum.SortOrder.LayoutOrder,
        FillDirection = Enum.FillDirection.Vertical, Padding = UDim.new(0, 6)})
    createStatus(page, 0).LayoutOrder = 1
    createProposal(page, 58).LayoutOrder = 2
    local card = createCard(page, "СПИСОК ПЕТОВ", 0, 200, 500, 76)
    card.LayoutOrder = 3
    local summary = text(card, "", 12, 32, 242, 36, 12, C.pale)
    summary.TextTruncate = Enum.TextTruncate.None
    table.insert(schemeSummaries, summary)
    local add = createButton(card, "+", 276, 35, 62, 30)
    local remove = createButton(card, "−", 348, 35, 62, 30)
    local clear = createButton(card, "Очистить", 420, 35, 68, 30)
    clear.TextSize = 11
    connect(add.Activated, function()
        if #state.schemes >= 100 then return end
        table.insert(state.schemes, {give = state.give, want = state.want,
            giveQuantity = state.giveQuantity, wantQuantity = state.wantQuantity})
        state.selected = #state.schemes; listRefresh(); addLog("GUI", "Схема добавлена")
    end)
    connect(remove.Activated, function()
        if state.selected then table.remove(state.schemes, state.selected); state.selected = nil; listRefresh() end
    end)
    connect(clear.Activated, function() table.clear(state.schemes); state.selected = nil; listRefresh() end)
    createSettingsControls(page, 282).LayoutOrder = 4
    createActions(page, 366).LayoutOrder = 5
end
local function createAutoTradePage()
    local page = createPage("trade")
    createStatus(page, 0); createProposal(page, 76); createActions(page, 274)
    local card = createCard(page, "AUTO TRADE", 0, 330, 500, 94)
    local note = text(card, "Dry Run включён по умолчанию: финальная отправка заблокирована.\nБот использует только доступный GUI и проверяет каждое действие.", 12, 43, 476, 42, 13, C.muted)
    note.TextWrapped = true; note.TextTruncate = Enum.TextTruncate.None
end
local rowScope, rowObjects = {}, {}
local function createItemsPage()
    local page = createPage("items")
    local card = createCard(page, "СПИСОК ПЕТОВ / СХЕМ", 0, 0, 500, 350)
    local add = createButton(card, "Добавить", 12, 45, 150, 36, true)
    local remove = createButton(card, "Удалить", 174, 45, 150, 36)
    local clear = createButton(card, "Очистить", 336, 45, 150, 36)
    local list = make("ScrollingFrame", card, {Position = UDim2.fromOffset(12, 92), Size = UDim2.fromOffset(476, 246),
        BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3,
        ScrollBarImageColor3 = C.pink, CanvasSize = UDim2.fromOffset(0, 0)})
    listRefresh = function()
        local summary = {}
        for i = 1, math.min(2, #state.schemes) do
            table.insert(summary, i .. "  " .. state.schemes[i].give.name .. " x" .. state.schemes[i].giveQuantity)
        end
        for _, view in ipairs(schemeSummaries) do view.Text = #summary > 0 and table.concat(summary, "\n") or "Список пуст" end
        disconnect(rowScope)
        for _, row in ipairs(rowObjects) do
            for _, object in ipairs(row:GetDescendants()) do if tweens[object] then tweens[object]:Cancel(); tweens[object] = nil end end
            if tweens[row] then tweens[row]:Cancel(); tweens[row] = nil end
            row:Destroy()
        end
        table.clear(rowObjects)
        for i, scheme in ipairs(state.schemes) do
            local row = frame(list, 0, (i - 1) * 46, 470, 40, C.glass, 0.42)
            table.insert(rowObjects, row); corners(row); stroke(row, state.selected == i and C.pink or C.line)
            local select = createButton(row, i .. "  " .. scheme.give.name .. " x" .. scheme.giveQuantity .. " → " .. scheme.want.name .. " x" .. scheme.wantQuantity,
                0, 0, 420, 40, state.selected == i, rowScope)
            select.TextSize = 12
            local delete = createButton(row, "×", 428, 3, 36, 34, false, rowScope)
            connect(select.Activated, function()
                state.selected = i
                state.give = scheme.give; state.want = scheme.want
                state.giveQuantity = scheme.giveQuantity; state.wantQuantity = scheme.wantQuantity
                updateTrade(true); listRefresh()
            end, rowScope)
            connect(delete.Activated, function() table.remove(state.schemes, i); state.selected = nil; listRefresh() end, rowScope)
        end
        list.CanvasSize = UDim2.fromOffset(0, #state.schemes * 46)
    end
    connect(add.Activated, function()
        if #state.schemes >= 100 then addLog("GUI", "Лимит: 100 схем"); return end
        table.insert(state.schemes, {give = state.give, want = state.want, giveQuantity = state.giveQuantity, wantQuantity = state.wantQuantity})
        state.selected = #state.schemes; listRefresh(); addLog("GUI", "Схема добавлена")
    end)
    connect(remove.Activated, function()
        if state.selected then table.remove(state.schemes, state.selected); state.selected = nil; listRefresh() end
    end)
    connect(clear.Activated, function() table.clear(state.schemes); state.selected = nil; listRefresh() end)
    text(page, "Добавить сохраняет текущее предложение. Нажмите строку, чтобы загрузить его.", 8, 360, 484, 56, 13, C.muted).TextWrapped = true
    table.insert(state.schemes, {give = state.give, want = state.want, giveQuantity = 1, wantQuantity = 1})
    listRefresh()
end
local function createSettingsPage()
    local page = createPage("settings")
    createSettingsControls(page, 0)
    local card = createCard(page, "НАСТРОЙКИ ИНТЕРФЕЙСА", 0, 106, 500, 130)
    local note = text(card, "Перетаскивайте окно за верхнюю панель.\nМасштаб автоматически подстраивается под экран.\nLive: config DryRun=false + режим Auto. Обычный = Dry Run.", 12, 44, 476, 72, 14, C.muted)
    note.TextWrapped = true; note.TextTruncate = Enum.TextTruncate.None
end
local function createStatsPage()
    local page = createPage("stats")
    local definitions = {{"sent", "Отправлено предложений"}, {"success", "Успешно"}, {"invalid", "Invalid"}, {"errors", "Ошибок"}}
    for i, entry in ipairs(definitions) do
        local x, y = ((i - 1) % 2) * 256, math.floor((i - 1) / 2) * 116
        local card = createCard(page, entry[2], x, y, 244, 102)
        statLabels[entry[1]] = text(card, "0", 14, 44, 216, 44, 30, C.pink)
    end
    local card = createCard(page, "ВРЕМЯ РАБОТЫ", 0, 242, 500, 102)
    table.insert(timerViews, text(card, "00:00:00", 14, 44, 472, 44, 28, C.pale))
    text(page, "Счётчики изменятся только после подключения настоящей автоматизации.", 8, 357, 484, 50, 13, C.muted).TextWrapped = true
end
local function createInfoPage()
    local page = createPage("info")
    local card = createCard(page, "TAKIZAWA_SWAGA • ADOPT ME", 0, 0, 500, 130)
    local note = text(card, "Resolver-driven Auto Trade\nSTART / STOP управляют торговым контроллером.\nDry Run включён по умолчанию.\nПри неизвестном GUI отправка блокируется; доступен diagnostic dump.", 12, 42, 476, 78, 13, C.muted)
    note.TextWrapped = true; note.TextTruncate = Enum.TextTruncate.None
    local logCard = createCard(page, "ЖУРНАЛ • ПОСЛЕДНИЕ 80 СТРОК", 0, 144, 500, 280)
    local scroll = make("ScrollingFrame", logCard, {Position = UDim2.fromOffset(8, 42), Size = UDim2.fromOffset(484, 228),
        BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3, ScrollBarImageColor3 = C.pink,
        CanvasSize = UDim2.fromOffset(0, 0)})
    local log = text(scroll, "", 8, 4, 460, 0, 12, C.muted)
    log.TextYAlignment = Enum.TextYAlignment.Top; log.TextTruncate = Enum.TextTruncate.None
    table.insert(logLabels, {label = log, scroll = scroll})
end
-- One tiny scalar tween drives only the selected button. No frame loop.
local function stopNavPulse()
    disconnect(navPulseConnections)
    if navPulseTween then navPulseTween:Cancel(); navPulseTween = nil end
    if navPulseValue then navPulseValue:Destroy(); navPulseValue = nil end
    if navPulseEntry then
        navPulseEntry.stroke.Transparency = 0.48
        for _, primitive in ipairs(navPulseEntry.iconParts) do primitive.BackgroundTransparency = 0 end
        for _, outline in ipairs(navPulseEntry.iconStrokes) do outline.Transparency = 0.08 end
        navPulseEntry = nil
    end
end
local function startNavPulse(entry)
    navPulseEntry = entry
    navPulseValue = make("NumberValue", gui, {Name = "ActiveNavigationPulse", Value = 0})
    connect(navPulseValue:GetPropertyChangedSignal("Value"), function()
        if not alive or minimized then return end
        local amount = navPulseValue.Value * 0.06
        entry.stroke.Transparency = 0.48 + amount
        for _, primitive in ipairs(entry.iconParts) do primitive.BackgroundTransparency = amount end
        for _, outline in ipairs(entry.iconStrokes) do outline.Transparency = 0.08 + amount end
    end, navPulseConnections)
    navPulseTween = TweenService:Create(navPulseValue,
        TweenInfo.new(1.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {Value = 1})
    if not minimized then navPulseTween:Play() end
end
local function switchPage(id)
    stopNavPulse()
    closeDropdown(); sliderInput = nil; sliderTrack = nil
    activePage = id
    for name, page in pairs(pages) do page.Visible = name == id end
    for name, entry in pairs(navButtons) do
        local selected = name == id
        entry.stroke.Color = selected and C.pink or C.line
        entry.stroke.Transparency = selected and 0.48 or 0.88
        for _, primitive in ipairs(entry.iconParts) do
            animate(primitive, {BackgroundColor3 = selected and C.pale or C.muted})
        end
        for _, outline in ipairs(entry.iconStrokes) do
            animate(outline, {Color = selected and C.pale or C.muted})
        end
        entry.button:SetAttribute("GlassSelected", selected)
        animate(entry.button, {BackgroundColor3 = selected and C.magenta or C.glass,
            BackgroundTransparency = selected and 0.64 or 0.86})
    end
    startNavPulse(navButtons[id])
    local page = pages[id]
    page.CanvasPosition = Vector2.zero
    page.Position = UDim2.fromOffset(6, 0)
    animate(page, {Position = UDim2.fromOffset(0, 0), ScrollBarImageTransparency = 0.1})
end
local function createAnimePanel()
    -- Keep the new composition static: no crop, global zoom or text drift.
    -- Breathing is a local shoulder-light pulse; hair is a separate optional layer.
    anime = make("Frame", window, {Name = "AnimeBackground", Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1, BorderSizePixel = 0, ClipsDescendants = true,
        Active = false, ZIndex = Z.background})
    backgroundImage = make("ImageLabel", anime, {Name = "AnimeArt", AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1, Image = ANIME_IMAGE_ID or "", ImageTransparency = 0,
        Visible = ANIME_IMAGE_ID ~= nil,
        ScaleType = Enum.ScaleType.Fit, Active = false, Selectable = false, ZIndex = Z.background})
    make("UIAspectRatioConstraint", backgroundImage, {AspectRatio = ART_ASPECT,
        AspectType = Enum.AspectType.FitWithinMaxSize})
    backgroundShade = make("Frame", window, {Name = "RightShade", Position = UDim2.fromScale(0.33, 0),
        Size = UDim2.fromScale(0.67, 1), BackgroundColor3 = C.bg, BorderSizePixel = 0,
        Active = false, ZIndex = Z.lighting})
    shadeGradient = gradient(backgroundShade, C.bg, C.bg)
    local glow = make("Frame", window, {Name = "CharacterLight", Position = UDim2.fromScale(0.23, 0.49),
        Size = UDim2.fromScale(0.16, 0.36), BackgroundColor3 = C.magenta,
        BackgroundTransparency = 0.992, BorderSizePixel = 0, Active = false, ZIndex = Z.lighting})
    corners(glow, 120)
    local lightGradient = gradient(glow, C.magenta, C.pink, 35)
    lightGradient.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 1),
        NumberSequenceKeypoint.new(0.5, 0.4), NumberSequenceKeypoint.new(1, 1)})
    petalLayer = make("Frame", window, {Name = "SakuraLayer", Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1, BorderSizePixel = 0, ClipsDescendants = true, Active = false, ZIndex = Z.petals})
    table.insert(ambientTweens, TweenService:Create(glow,
        TweenInfo.new(2.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
        {BackgroundTransparency = 0.983, Size = UDim2.fromScale(0.16064, 0.36144),
            Position = UDim2.new(0.23, 0, 0.49, 2)}))
    hairOverlay = make("ImageLabel", anime, {Name = "HairOverlay", AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1, Image = HAIR_OVERLAY_IMAGE, ImageTransparency = 0.25,
        Visible = HAIR_OVERLAY_IMAGE ~= "", ScaleType = Enum.ScaleType.Fit,
        Active = false, Selectable = false, ZIndex = Z.lighting})
    make("UIAspectRatioConstraint", hairOverlay, {AspectRatio = ART_ASPECT,
        AspectType = Enum.AspectType.FitWithinMaxSize})
    -- The prepared hair tween is intentionally not played without an asset.
    -- 7.6-second hair cycle drifts out of phase with the 5-second breathing.
    -- fit() caps displacement at 1.5 screen pixels and 2 logical pixels.
    hairTween = TweenService:Create(hairOverlay,
        TweenInfo.new(3.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
        {Position = UDim2.new(0.5, 1.5, 0.5, 0.5)})
    table.insert(ambientTweens, hairTween)
    for _, t in ipairs(ambientTweens) do
        if t ~= hairTween or hairOverlay.Visible then t:Play() end
    end
end
local function removePetal(object)
    local entry = activePetals[object]
    if not entry then return end
    activePetals[object] = nil; petalCount -= 1
    disconnect(entry.connections)
    if entry.tween then entry.tween:Cancel() end
    object:Destroy()
end
local function spawnPetal()
    if not alive or minimized or petalCount >= 8 then return end
    local startX = random:NextNumber() < 0.25 and random:NextNumber(0.04, 0.20) or -0.025
    local startY = random:NextNumber(0.02, 0.90)
    local endY = startY + random:NextNumber(0.04, 0.15)
    local width, height = random:NextInteger(2, 3), random:NextInteger(5, 8)
    local object = make("Frame", petalLayer, {Name = "SakuraPetal", AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(startX, startY), Size = UDim2.fromOffset(width, height),
        BackgroundColor3 = C.pale:Lerp(C.pink, random:NextNumber(0.05, 0.45)),
        BackgroundTransparency = random:NextNumber(0.80, 0.92), Rotation = random:NextNumber(-100, 100),
        BorderSizePixel = 0, Active = false, ZIndex = Z.petals})
    make("UICorner", object, {CornerRadius = UDim.new(0.7, 0)})
    local entry = {connections = {}}
    activePetals[object] = entry; petalCount += 1
    local duration = random:NextNumber(12, 17)
    local rotation = object.Rotation + random:NextNumber(30, 70)
    local function segment(position, angle, second)
        if not alive or not activePetals[object] then return end
        entry.tween = TweenService:Create(object,
            TweenInfo.new(duration / 2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
            {Position = position, Rotation = angle})
        table.insert(entry.connections, entry.tween.Completed:Once(function(playback)
            if playback ~= Enum.PlaybackState.Completed or not alive or not activePetals[object] then return end
            if second then removePetal(object)
            else segment(UDim2.fromScale(1.035, endY), rotation, true) end
        end))
        entry.tween:Play()
        if minimized then entry.tween:Pause() end
    end
    segment(UDim2.fromScale((startX + 1.035) / 2, (startY + endY) / 2 + random:NextNumber(-0.025, 0.025)),
        (object.Rotation + rotation) / 2, false)
end
local function schedulePetal()
    if not alive or minimized or particleThread then return end
    -- One cancellable scheduled task for the whole system, no per-frame loops.
    particleThread = task.delay(random:NextNumber(2.0, 3.2), function()
        particleThread = nil
        if not alive or minimized then return end
        spawnPetal(); schedulePetal()
    end)
end
local function setAtmospherePaused(paused)
    anime.Visible = not paused; backgroundShade.Visible = not paused; petalLayer.Visible = not paused
    local lighting = window:FindFirstChild("CharacterLight")
    if lighting then lighting.Visible = not paused end
    if particleThread then task.cancel(particleThread); particleThread = nil end
    for _, t in ipairs(ambientTweens) do
        if paused then t:Pause()
        elseif t ~= hairTween or hairOverlay.Visible then t:Play() end
    end
    for _, entry in pairs(activePetals) do if paused then entry.tween:Pause() else entry.tween:Play() end end
    if navPulseTween then
        if paused then navPulseTween:Pause() else navPulseTween:Play() end
    end
    if not paused then schedulePetal() end
end
-- Resolution-independent line icons made from passive UI primitives, not
-- emoji or external icon assets (so they also work in executor environments).
local function createNavigationIcon(button, id)
    local icon = make("Frame", button, {Name = "Icon", AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(24, 24),
        BackgroundTransparency = 1, Active = false, ZIndex = Z.control})
    local parts, outlines = {}, {}
    local function line(x1, y1, x2, y2)
        local dx, dy = x2 - x1, y2 - y1
        local object = make("Frame", icon, {AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromOffset((x1 + x2) / 2, (y1 + y2) / 2),
            Size = UDim2.fromOffset(math.sqrt(dx * dx + dy * dy), 1.6),
            Rotation = math.deg(math.atan2(dy, dx)), BackgroundColor3 = C.muted,
            BorderSizePixel = 0, Active = false, ZIndex = Z.control})
        corners(object, 1); table.insert(parts, object)
    end
    local function ring(x, y, diameter)
        local object = make("Frame", icon, {Position = UDim2.fromOffset(x, y),
            Size = UDim2.fromOffset(diameter, diameter), BackgroundTransparency = 1,
            BorderSizePixel = 0, Active = false, ZIndex = Z.control})
        corners(object, diameter / 2)
        table.insert(outlines, stroke(object, C.muted, 0.08, 1.6))
    end
    if id == "home" then
        line(3, 11, 12, 3); line(12, 3, 21, 11)
        line(5, 10, 5, 21); line(19, 10, 19, 21)
        line(5, 21, 9, 21); line(15, 21, 19, 21)
        line(9, 21, 9, 15); line(9, 15, 15, 15); line(15, 15, 15, 21)
    elseif id == "trade" then
        line(3, 7, 21, 7); line(17, 3, 21, 7); line(21, 7, 17, 11)
        line(21, 17, 3, 17); line(7, 13, 3, 17); line(3, 17, 7, 21)
    elseif id == "items" then
        line(12, 2, 21, 7); line(21, 7, 21, 17); line(21, 17, 12, 22)
        line(12, 22, 3, 17); line(3, 17, 3, 7); line(3, 7, 12, 2)
        line(3, 7, 12, 12); line(12, 12, 21, 7); line(12, 12, 12, 22)
    elseif id == "settings" then
        ring(5, 5, 14); ring(10, 10, 4)
        for i = 0, 7 do
            local angle = i * math.pi / 4
            line(12 + math.cos(angle) * 7, 12 + math.sin(angle) * 7,
                12 + math.cos(angle) * 10, 12 + math.sin(angle) * 10)
        end
    elseif id == "stats" then
        line(3, 21, 21, 21)
        for i, height in ipairs({7, 12, 17}) do
            local x = 4 + (i - 1) * 6
            line(x, 19, x, 19 - height); line(x, 19 - height, x + 3, 19 - height)
            line(x + 3, 19 - height, x + 3, 19)
        end
    else
        ring(2, 2, 20); line(12, 11, 12, 18); line(11.5, 7, 12.5, 7)
    end
    return parts, outlines
end
local function createSidebar()
    sidebar = frame(body, 0, 0, RAIL.width, RAIL.height, C.bg, 1)
    sidebar.Name = "IconRail"
    make("UISizeConstraint", sidebar, {MinSize = Vector2.new(RAIL.width, RAIL.height),
        MaxSize = Vector2.new(RAIL.width, RAIL.height)})
    make("UIPadding", sidebar, {PaddingLeft = UDim.new(0, 3), PaddingRight = UDim.new(0, 3)})
    navLayout = make("UIGridLayout", sidebar, {SortOrder = Enum.SortOrder.LayoutOrder,
        CellPadding = UDim2.fromOffset(0, RAIL.gap), CellSize = UDim2.fromOffset(RAIL.button, RAIL.button),
        FillDirectionMaxCells = 1})
    for i, id in ipairs({"home", "trade", "items", "settings", "stats", "info"}) do
        local b = createButton(sidebar, "", 0, (i - 1) * (RAIL.button + RAIL.gap), RAIL.button, RAIL.button)
        b.Name = id; b.LayoutOrder = i; b.BackgroundTransparency = 0.86
        b:SetAttribute("CompactNavigation", true)
        b:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(0, 9)
        local parts, outlines = createNavigationIcon(b, id)
        navButtons[id] = {button = b, iconParts = parts, iconStrokes = outlines,
            stroke = b:FindFirstChildOfClass("UIStroke")}
        connect(b.Activated, function() switchPage(id) end)
    end
end
local viewport = Vector2.new(900, 530)
local function clampWindow(position)
    local size = Vector2.new(W, minimized and 72 or H) * uiScale.Scale
    return Vector2.new(math.clamp(position.X, 8, math.max(8, viewport.X - size.X - 8)),
        math.clamp(position.Y, 8, math.max(8, viewport.Y - size.Y - 8)))
end
local function place(position)
    local p = clampWindow(position)
    window.Position = UDim2.fromOffset(p.X, p.Y)
end
local function fit(center)
    local camera = workspace.CurrentCamera
    if not camera then return end
    viewport = camera.ViewportSize
    portrait = viewport.Y > viewport.X
    if portrait then
        W, H = 536, 722
        uiScale.Scale = math.min(1, (viewport.X - 20) / W, (viewport.Y - 20) / H)
    else
        H = LANDSCAPE_HEIGHT; W = H * ART_ASPECT
        uiScale.Scale = math.min(viewport.X * 0.94 / W, viewport.Y * 0.92 / H)
    end
    window.Size = UDim2.fromOffset(W, minimized and 72 or H)
    body.Position = UDim2.fromScale(0, 0)
    body.Size = UDim2.fromScale(1, 1)
    anime.Position = UDim2.fromScale(0, 0)
    for _, t in ipairs(ambientTweens) do t:Cancel() end
    local light = window:FindFirstChild("CharacterLight")
    light.Position = UDim2.fromScale(0.23, 0.49)
    light.Size = UDim2.fromScale(0.16, 0.36)
    light.BackgroundTransparency = 0.992
    ambientTweens[1] = TweenService:Create(light,
        TweenInfo.new(2.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
        {BackgroundTransparency = 0.983, Size = UDim2.fromScale(0.16064, 0.36144),
            Position = UDim2.new(0.23, 0, 0.49, math.min(2, 2 / uiScale.Scale))})
    hairOverlay.Position = UDim2.fromScale(0.5, 0.5)
    hairTween = TweenService:Create(hairOverlay,
        TweenInfo.new(3.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
        {Position = UDim2.new(0.5, math.min(2, 1.5 / uiScale.Scale), 0.5, math.min(1, 0.5 / uiScale.Scale))})
    ambientTweens[2] = hairTween
    if not minimized then
        ambientTweens[1]:Play()
        if hairOverlay.Visible then hairTween:Play() end
    end
    backgroundImage.ImageTransparency = portrait and 0.55 or 0
    backgroundShade.Position = UDim2.fromScale(portrait and 0 or WORK.left, portrait and 0 or WORK.top)
    backgroundShade.Size = UDim2.fromScale(portrait and 1 or WORK.width, portrait and 1 or WORK.height)
    shadeGradient.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, portrait and 0.72 or 0.98),
        NumberSequenceKeypoint.new(0.5, portrait and 0.70 or 0.94), NumberSequenceKeypoint.new(1, portrait and 0.65 or 0.90)})
    sidebar.Position = portrait and UDim2.fromOffset(12, 86) or UDim2.fromScale(0.016, 0.17)
    sidebar.Size = UDim2.fromOffset(RAIL.width, RAIL.height)
    local availableWidth = portrait and 452 or W * WORK.width
    local availableHeight = portrait and 612 or H * WORK.height
    -- Fit the entire 500x438 dashboard to BOTH axes, including START/STOP.
    contentScale.Scale = math.min(availableWidth / 500, availableHeight / 438)
    pageHost.Position = portrait and UDim2.fromOffset(72, 86) or UDim2.new(WORK.left, 0, WORK.top, 0)
    pageHost.Size = UDim2.fromOffset(500, availableHeight / contentScale.Scale)
    closeDropdown(); sliderInput = nil
    if center then place((viewport - Vector2.new(W, H) * uiScale.Scale) / 2)
    else place(Vector2.new(window.Position.X.Offset, window.Position.Y.Offset)) end
end
local function toggleMinimize()
    closeDropdown(); sliderInput = nil
    minimized = not minimized
    body.Visible = not minimized
    setAtmospherePaused(minimized)
    header.Minimize.Text = minimized and "+" or "−"
    animate(window, {Size = UDim2.fromOffset(W, minimized and 72 or H)})
    place(Vector2.new(window.Position.X.Offset, window.Position.Y.Offset))
end
local function cleanup()
    if not alive then return end
    alive = false; state.running = false; state.generation += 1
    TradeBackend.cleanupTradeBot()
    stopNavPulse()
    if particleThread then task.cancel(particleThread); particleThread = nil end
    for _, t in ipairs(ambientTweens) do t:Cancel() end
    table.clear(ambientTweens)
    local petals = {}
    for object in pairs(activePetals) do table.insert(petals, object) end
    for _, object in ipairs(petals) do removePetal(object) end
    sliderInput = nil; closeDropdown()
    disconnect(connections); disconnect(rowScope)
    if cameraConnection then cameraConnection:Disconnect() end
    for _, t in pairs(tweens) do t:Cancel() end
    table.clear(tweens); table.clear(logs)
end
local function destroyGUI() gui:Destroy() end
local function createMainWindow()
    local player = Players.LocalPlayer
    assert(player, "Run this script on the Roblox client")
    local playerGui = player:WaitForChild("PlayerGui")
    local candidates = {}
    if type(gethui) == "function" then
        local ok, result = pcall(gethui)
        if ok and typeof(result) == "Instance" then table.insert(candidates, result) end
    end
    local ok, core = pcall(function() return game:GetService("CoreGui") end)
    if ok then table.insert(candidates, core) end
    table.insert(candidates, playerGui)
    for _, parent in ipairs(candidates) do
        pcall(function()
            for _, name in ipairs({GUI_NAME, "AdoptMeDeltaBotGUI"}) do
                local old = parent:FindFirstChild(name)
                if old then old:Destroy() end
            end
        end)
    end
    gui = make("ScreenGui", nil, {Name = GUI_NAME, ResetOnSpawn = false, IgnoreGuiInset = true,
        DisplayOrder = 10000, ZIndexBehavior = Enum.ZIndexBehavior.Sibling})
    local attached = false
    for _, parent in ipairs(candidates) do
        local success = pcall(function() gui.Parent = parent end)
        if success and gui.Parent == parent then attached = true; break end
    end
    assert(attached, "Unable to parent GUI")
    -- Connect before starting effects, so rerun also cleans a partial build.
    connect(gui.Destroying, cleanup)
    window = frame(gui, 0, 0, W, H, C.bg, 0.07)
    window.Name = "Window"; corners(window, 12); stroke(window, C.pink, 0.48)
    window.ClipsDescendants = true
    uiScale = make("UIScale", window, {Scale = 1})
    for i = 1, 3 do
        local glow = frame(window, -i * 2, -i * 2, W + i * 4, H + i * 4, C.bg, 1)
        glow.Size = UDim2.new(1, i * 4, 1, i * 4)
        corners(glow, 12 + i * 2); stroke(glow, C.pink, 0.96 + i * 0.012, 2)
        glow.ZIndex = Z.decoration
    end
    body = frame(window, 0, 0, W, H, C.bg, 1)
    body.Name = "DashboardBody"
    createAnimePanel(); createSidebar()
    pageHost = frame(body, 0, 0, 500, 438, C.bg, 1)
    pageHost.Name = "Workspace"
    make("UISizeConstraint", pageHost, {MinSize = Vector2.new(500, 438), MaxSize = Vector2.new(500, 700)})
    contentScale = make("UIScale", pageHost, {Scale = 1})
    popupLayer = frame(window, 0, 0, W, H, C.bg, 1)
    popupLayer.Size = UDim2.fromScale(1, 1); popupLayer.ZIndex = 50; popupLayer.Visible = false
    local dismiss = make("TextButton", popupLayer, {Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
        Text = "", ZIndex = 50, AutoButtonColor = false})
    connect(dismiss.Activated, closeDropdown)
end
local function createHeader()
    header = frame(window, 0, 0, W, 72, C.bg, 1)
    header.Size = UDim2.new(1, 0, 0, 72); header.Active = true; header.ZIndex = Z.header
    make("Frame", header, {Position = UDim2.new(0, 14, 1, -1), Size = UDim2.new(1, -28, 0, 1),
        BackgroundColor3 = C.pink, BackgroundTransparency = 0.78, BorderSizePixel = 0,
        Active = false, ZIndex = Z.decoration})
    text(header, "✿", 16, 14, 30, 38, 26, C.pink)
    local title = text(header, 'Takizawa<font color="#C27797">_swaga</font>', 54, 12, 310, 28, 22)
    title.RichText = true; title.Font = Enum.Font.GothamBold
    text(header, "ADOPT ME • TRADE BOT", 56, 42, 280, 18, 10, C.muted)
    local minimize = createButton(header, "−", 0, 16, 38, 36)
    minimize.Name = "Minimize"; minimize.Position = UDim2.new(1, -94, 0, 16)
    local close = createButton(header, "×", 0, 16, 38, 36)
    close.Position = UDim2.new(1, -48, 0, 16)
    connect(minimize.Activated, toggleMinimize); connect(close.Activated, destroyGUI)
    local dragInput, origin, startPosition
    connect(header.InputBegan, function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
        if input.Position.X >= minimize.AbsolutePosition.X or dragInput then return end
        closeDropdown(); dragInput = input; origin = input.Position
        startPosition = Vector2.new(window.Position.X.Offset, window.Position.Y.Offset)
    end)
    connect(UIS.InputChanged, function(input)
        if dragInput and (input == dragInput or (dragInput.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseMovement)) then
            local delta = input.Position - origin
            place(startPosition + Vector2.new(delta.X, delta.Y))
        end
        if sliderInput and sliderTrack and (input == sliderInput or (sliderInput.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseMovement)) then sliderTrack(input) end
    end)
    connect(UIS.InputEnded, function(input)
        if input == dragInput then dragInput = nil end
        if input == sliderInput then sliderInput = nil; sliderTrack = nil end
    end)
    connect(UIS.WindowFocusReleased, function() dragInput = nil; sliderInput = nil; sliderTrack = nil end)
end
-- BEGIN TRADE BACKEND: client GUI only; no remotes or connection firing.
do
    local B = TradeBackend
    local function norm(value)
        return tostring(value or ""):gsub("<[^>]*>", ""):gsub("(%l)(%u)", "%1 %2"):gsub("_", " "):lower():gsub("%s+", " "):match("^%s*(.-)%s*$")
    end
    B.normalize = norm
    local function read(o, key)
        local ok, value = pcall(function() return o[key] end)
        if ok then return value end
    end
    local function attr(o, key)
        local ok, value = pcall(function() return o:GetAttribute(key) end)
        if ok then return value end
    end
    local function is(o, class)
        return o and o:IsA(class)
    end
    local function within(o, ancestor)
        while o do if o == ancestor then return true end; o = o.Parent end
        return false
    end
    local function enabledTree(o)
        while o do
            if o == gui or o.Name == GUI_NAME then return false end
            if is(o, "GuiObject") and not o.Visible then return false end
            if is(o, "ScreenGui") and read(o, "Enabled") == false then return false end
            o = o.Parent
        end
        return true
    end
    local function path(o)
        local parts = {}
        while o do table.insert(parts, 1, o.Name); o = o.Parent end
        return table.concat(parts, ".")
    end
    local function shown(o)
        if not o or not o.Parent then return false end
        local node = o
        while node do
            if node == gui or node.Name == GUI_NAME then return false end
            if is(node, "GuiObject") and not node.Visible then return false end
            if is(node, "ScreenGui") and read(node, "Enabled") == false then return false end
            node = node.Parent
        end
        if is(o, "GuiObject") then
            local size = o.AbsoluteSize
            return size.X > 0 and size.Y > 0
        end
        return true
    end
    local function walk(root, visibleOnly)
        local out, stack = {}, {root}
        while #stack > 0 and #out < TradeConfig.MaxNodes do
            local o = table.remove(stack)
            if o ~= gui and o.Name ~= GUI_NAME then
                if not visibleOnly or enabledTree(o) then
                    table.insert(out, o)
                    for _, child in ipairs(o:GetChildren()) do table.insert(stack, child) end
                end
            end
        end
        return out, #stack > 0
    end
    local function words(o)
        local texts = {norm(o.Name)}
        if is(o, "TextLabel") or is(o, "TextButton") or is(o, "TextBox") then table.insert(texts, norm(o.Text)) end
        for _, child in ipairs(o:GetChildren()) do
            if shown(child) and (is(child, "TextLabel") or is(child, "TextButton")) then table.insert(texts, norm(child.Text)) end
        end
        return texts
    end
    local function exact(o, choices)
        for _, value in ipairs(words(o)) do
            for _, choice in ipairs(choices) do
                if value == choice or value:gsub("%s", "") == choice:gsub("%s", "") then return true end
            end
        end
        return false
    end
    local function button(o)
        return is(o, "TextButton") or is(o, "ImageButton")
    end
    local function resolve(root, choices, predicate)
        local candidates = {}
        local nodes, truncated = walk(root, true)
        if truncated then return nil, "action scan budget exceeded" end
        for _, o in ipairs(nodes) do
            if button(o) and (not predicate or predicate(o)) and exact(o, choices) then
                local explicit = is(o, "TextButton") and norm(o.Text) ~= "" and exact({
                    Name = "", Text = o.Text, IsA = function(_, c) return c == "TextButton" end,
                    GetChildren = function() return {} end,
                }, choices)
                table.insert(candidates, {instance = o, score = explicit and 0.96 or 0.84,
                    reasons = {explicit and "exact visible action text" or "exact action name + verified context"}})
            end
        end
        table.sort(candidates, function(a, b) return a.score > b.score end)
        if #candidates == 0 then return nil, "target missing" end
        if #candidates > 1 and candidates[1].score - candidates[2].score < TradeConfig.AmbiguityMargin then
            return nil, "ambiguous action: " .. #candidates .. " candidates"
        end
        return candidates[1]
    end
    B.resolve = resolve
    local function roles(root, dialog)
        local first, second = {}, {}
        local left = dialog and {"you give", "your offer", "give items"} or {"you", "wants", "wanted", "looking for", "requested items"}
        local right = dialog and {"they give", "you receive", "their offer"} or {"them", "offers", "offered", "offered items", "giving"}
        for _, o in ipairs(walk(root, true)) do
            if is(o, "Frame") or is(o, "ScrollingFrame") then
                local a, b = exact(o, left), exact(o, right)
                if a and not b then table.insert(first, o) elseif b and not a then table.insert(second, o) end
            end
        end
        -- Nested copies of the same side are okay; choose the highest side root.
        local function top(list)
            local out = {}
            for _, o in ipairs(list) do
                local nested = false
                for _, other in ipairs(list) do if o ~= other and within(o, other) then nested = true end end
                if not nested then table.insert(out, o) end
            end
            return #out == 1 and out[1] or nil
        end
        return top(first), top(second)
    end
    B.findSides = roles
    local function catalog()
        local names = {}
        for _, item in ipairs(ITEMS) do names[norm(item.name)] = item.name end
        if state.give then names[norm(state.give.name)] = state.give.name end
        if state.want then names[norm(state.want.name)] = state.want.name end
        return names
    end
    local function itemName(o)
        local names = catalog()
        for _, key in ipairs({"ItemName", "DisplayName", "PetName"}) do
            local value = attr(o, key)
            if value and names[norm(value)] then return names[norm(value)], 0.98 end
        end
        for _, value in ipairs(words(o)) do
            local stripped = value:gsub("%s+[x×]%s*%d+$", ""):gsub("^%d+%s*[x×]%s*", "")
            if names[stripped] then return names[stripped], 0.94 end
        end
        return nil
    end
    local function quantity(o)
        for _, key in ipairs({"Quantity", "Count", "Amount"}) do
            local n = tonumber(attr(o, key))
            if n and n >= 1 and n % 1 == 0 then return n end
        end
        for _, value in ipairs(words(o)) do
            local n = tonumber(value:match("[x×]%s*(%d+)$") or value:match("^(%d+)%s*[x×]"))
            if n then return n end
        end
        for _, child in ipairs(o:GetChildren()) do
            if shown(child) and exact(child, {"quantity", "count", "amount"}) then
                local n = tonumber(read(child, "Text"))
                if n and n >= 1 then return n end
            end
        end
        return nil -- never assume that an icon means quantity one
    end
    local function images(o)
        local out = {}
        for _, child in ipairs(walk(o, true)) do
            if is(child, "ImageLabel") or is(child, "ImageButton") then
                local uri = read(child, "Image")
                if uri and uri ~= "" then table.insert(out, uri) end
            end
        end
        return out
    end
    function B.imageKey(o)
        local uri = read(o, "Image") or ""
        local size, offset = read(o, "ImageRectSize"), read(o, "ImageRectOffset")
        if size and (size.X ~= 0 or size.Y ~= 0) then
            return uri .. "|offset=" .. tostring(offset and offset.X or 0) .. "," .. tostring(offset and offset.Y or 0)
                .. "|size=" .. tostring(size.X) .. "," .. tostring(size.Y)
        end
        return uri
    end
    function B.parseItems(root)
        local result, seen = {}, {}
        if not root then return result end
        local nodes, truncated = walk(root, true)
        if truncated then return {{root = root, unknown = true, confidence = 0}} end
        for _, o in ipairs(nodes) do
            if is(o, "GuiObject") then
                local name, confidence
                if o ~= root then name, confidence = itemName(o) end
                if exact(o, {"you", "them", "you give", "they give", "wants", "wanted", "offers", "offered", "inventory", "backpack"}) then name = nil end
                local tile = o
                if name and (is(o, "TextLabel") or is(o, "ImageLabel")) and is(o.Parent, "GuiObject") then tile = o.Parent end
                if not name and (is(o, "ImageLabel") or is(o, "ImageButton")) then
                    name = TradeConfig.ItemImages[B.imageKey(o)]
                    if name then confidence = 0.92 end
                end
                if name and not seen[tile] then
                    seen[tile] = true
                    local icons = images(tile)
                    local n = quantity(tile)
                    local action = button(tile) and tile or nil
                    if not action then
                        for _, child in ipairs(walk(tile, true)) do
                            if button(child) and not exact(child, {"remove", "delete", "close", "x", "+", "add"}) then
                                if action then action = nil; break end
                                action = child
                            end
                        end
                    end
                    table.insert(result, {root = tile, name = name, quantity = n, image = icons[1],
                        images = icons, confidence = n and confidence or 0.60, unknown = n == nil, action = action})
                elseif not name and (is(o, "ImageLabel") or is(o, "ImageButton")) and read(o, "Image") ~= ""
                    and (norm(o.Name):find("item", 1, true) or norm(o.Name):find("pet", 1, true) or norm(o.Parent.Name):find("slot", 1, true))
                    and not exact(o, {"add", "add item", "plus", "remove", "close"}) then
                    -- Preserve uninterpreted icon evidence for diagnostics, not matching.
                    table.insert(result, {root = o, name = nil, quantity = quantity(o), image = read(o, "Image"), unknown = true, confidence = 0})
                end
            end
        end
        -- Do not count nested label/icon representations twice.
        local out = {}
        for _, entry in ipairs(result) do
            local nested = false
            for _, other in ipairs(result) do
                if entry ~= other and other.name and within(entry.root, other.root) and entry.root ~= other.root then nested = true end
            end
            if not nested then table.insert(out, entry) end
        end
        return out
    end
    local function total(items, expected)
        local count, confidence = 0, 1
        for _, entry in ipairs(items) do
            if entry.unknown or not entry.name or not entry.quantity then return nil, 0, "unknown item/quantity" end
            if norm(entry.name) ~= norm(expected) then return nil, 0, "different/additional item" end
            count += entry.quantity; confidence = math.min(confidence, entry.confidence)
        end
        return count, confidence
    end
    function B.parseListing(card)
        local wants, offers = roles(card, false)
        local listing = {root = card, wants = B.parseItems(wants), offers = B.parseItems(offers),
            player = attr(card, "UserId") or attr(card, "PlayerName") or attr(card, "Owner"),
            id = attr(card, "ListingId"), confidence = 0, visibleText = {}, images = images(card)}
        for _, o in ipairs(walk(card, true)) do
            if is(o, "TextLabel") or is(o, "TextButton") then
                local value = norm(o.Text)
                table.insert(listing.visibleText, o.Text)
                listing.id = listing.id or value:match("listing%s*#(%d+)")
                if not listing.player and (norm(o.Name) == "player" or norm(o.Name) == "username") then listing.player = o.Text end
            end
        end
        listing.action = resolve(card, {"send offer", "open listing", "view listing", "open offer"})
        listing.unknown = not wants or not offers or #listing.wants == 0 or #listing.offers == 0
        if not listing.unknown then
            listing.confidence = 0.94
            for _, set in ipairs({listing.wants, listing.offers}) do
                for _, item in ipairs(set) do
                    listing.confidence = math.min(listing.confidence, item.confidence)
                    if item.unknown then listing.unknown = true end
                end
            end
        end
        local function terms(items)
            local out = {}
            for _, item in ipairs(items) do
                table.insert(out, tostring(item.name) .. ":" .. tostring(item.quantity) .. ":" .. table.concat(item.images or {item.image or ""}, ","))
            end
            table.sort(out); return table.concat(out, "|")
        end
        listing.signature = tostring(listing.player or "unknown owner") .. ":" .. tostring(listing.id)
            .. ":wants=" .. terms(listing.wants) .. ":offers=" .. terms(listing.offers)
        -- Timers, hover text and button state must not invalidate duplicate cache.
        listing.key = tostring(listing.player or "unknown owner") .. ":" .. tostring(listing.id or path(card))
            .. (listing.id and "" or ":" .. listing.signature)
        return listing
    end
    function B.matchesRules(listing, rules)
        if listing.unknown or listing.confidence < TradeConfig.MinConfidence then return false, "parser confidence/unknown fields" end
        local give, gc, why = total(listing.wants, rules.give.name)
        if give ~= rules.giveQuantity then return false, "wants " .. (why or "different quantity") end
        local receive, rc, reason = total(listing.offers, rules.want.name)
        if receive ~= rules.wantQuantity then return false, "offers " .. (reason or "different quantity") end
        if not listing.action or listing.action.score < TradeConfig.MinConfidence then return false, "no confident action" end
        return true, math.min(gc, rc, listing.confidence, listing.action.score)
    end
    function B.scoreListing(listing, rules)
        local match, confidence = B.matchesRules(listing, rules)
        return match and confidence - (listing.player and 0 or 0.02) - (listing.id and 0 or 0.02) or 0
    end
    function B.findTradeHubGui(playerGui)
        local best, runner = nil, nil
        for _, root in ipairs(playerGui:GetChildren()) do
            if root ~= gui and root.Name ~= GUI_NAME and shown(root) then
                local texts, listingContainer = {}, false
                for _, o in ipairs(walk(root, true)) do
                    if is(o, "GuiObject") then for _, value in ipairs(words(o)) do texts[value] = true end end
                    if is(o, "ScrollingFrame") and exact(o, {"listings", "listing results", "search results"}) then listingContainer = true end
                end
                local score, reasons = 0, {}
                if norm(root.Name):find("trade", 1, true) then score += 0.30; table.insert(reasons, "trade root name") end
                local menu = texts["search listings"] and texts["offers i sent"]
                local listing = texts["send offer"] and (texts["you"] or texts["wants"] or texts["wanted"])
                    and (texts["them"] or texts["offers"] or texts["offered"])
                local dialog = texts["you give"] and texts["they give"]
                if menu or listing or dialog then score = math.max(score, 0.94); table.insert(reasons, "trade-specific semantic structure") end
                if listingContainer and norm(root.Name):find("trade", 1, true) then
                    score = math.max(score, 0.84); table.insert(reasons, "trade root + named listings scrolling container (may be empty)")
                end
                if score >= TradeConfig.MinConfidence then
                    local candidate = {instance = root, score = score, reasons = reasons}
                    if not best or score > best.score then runner = best; best = candidate else runner = candidate end
                end
            end
        end
        if runner and best.score - runner.score < TradeConfig.AmbiguityMargin then return nil, "ambiguous trade roots" end
        return best, best and nil or "Trade Hub not found"
    end
    function B.collectListingCandidates(root)
        local cards, seen = {}, {}
        for _, action in ipairs(walk(root, true)) do
            if button(action) and exact(action, {"send offer", "open listing", "view listing", "open offer"}) then
                local node = action.Parent
                for _ = 1, TradeConfig.MaxAncestors do
                    if not node or node == root then break end
                    local wants, offers = roles(node, false)
                    if wants and offers then
                        if not seen[node] then seen[node] = true; table.insert(cards, node) end
                        break
                    end
                    node = node.Parent
                end
            end
            if #cards >= TradeConfig.MaxCards then break end
        end
        return cards
    end
    function B.findListingsContainer(root)
        local cards = B.collectListingCandidates(root)
        if #cards == 0 then return nil, cards end
        local container = cards[1].Parent
        while container and container ~= root do
            local all = true
            for _, card in ipairs(cards) do if not within(card, container) then all = false end end
            if all then return container, cards end
            container = container.Parent
        end
        return root, cards
    end
    function B.findOfferDialog(root)
        local candidates = {}
        for _, o in ipairs(walk(root, true)) do
            if is(o, "Frame") or is(o, "ScrollingFrame") then
                local give, receive = roles(o, true)
                if give and receive and resolve(o, {"make offer", "send offer", "submit offer"}) then
                    table.insert(candidates, {instance = o, score = 0.94, reasons = {"you give + they give + submit action"}, give = give, receive = receive})
                end
            end
        end
        local leaves = {}
        for _, candidate in ipairs(candidates) do
            local broad = false
            for _, other in ipairs(candidates) do
                if candidate ~= other and within(other.instance, candidate.instance) then broad = true end
            end
            if not broad then table.insert(leaves, candidate) end
        end
        return #leaves == 1 and leaves[1] or nil
    end
    function B.findAddItemButton(dialog)
        return resolve(dialog.give, {"add", "add item", "add pet", "+", "plus"})
    end
    function B.findInventoryItems(playerGui, wanted)
        local candidates = {}
        for _, o in ipairs(walk(playerGui, true)) do
            if (is(o, "Frame") or is(o, "ScrollingFrame") or is(o, "ScreenGui"))
                and exact(o, {"inventory", "backpack", "inventory items", "item picker"}) then
                table.insert(candidates, o)
            end
        end
        local roots = {}
        for _, o in ipairs(candidates) do
            local nested = false
            for _, other in ipairs(candidates) do if o ~= other and within(o, other) then nested = true end end
            if not nested then table.insert(roots, o) end
        end
        if #roots ~= 1 then return nil, {}, "inventory missing/ambiguous" end
        local items = {}
        for _, entry in ipairs(B.parseItems(roots[1])) do
            if entry.name and norm(entry.name) == norm(wanted) and not entry.unknown and entry.action then table.insert(items, entry) end
        end
        return roots[1], items
    end
    function B.findInventorySearch(root)
        local candidates = {}
        for _, o in ipairs(walk(root, true)) do
            if is(o, "TextBox") and (norm(o.Name):find("search", 1, true) or norm(read(o, "PlaceholderText")):find("search", 1, true)) then
                table.insert(candidates, {instance = o, score = 0.92, reasons = {"unique inventory search TextBox"}})
            end
        end
        return #candidates == 1 and candidates[1] or nil
    end
    function B.detectResult(root)
        local matches = {}
        for _, o in ipairs(walk(root, true)) do
            if is(o, "TextLabel") then
                local value = norm(o.Text)
                local kind
                if value:find("offer", 1, true) and (value:find("offer sent", 1, true) or value:find("offer was sent", 1, true)
                    or value:find("successfully sent", 1, true) or value:find("offer successfully submitted", 1, true)) then kind = "SUCCESS"
                elseif value:find("no longer valid", 1, true) or value:find("offer expired", 1, true) or value:find("listing expired", 1, true) or value:find("invalid offer", 1, true) then kind = "INVALID"
                elseif value:find("offer rejected", 1, true) or value:find("offer declined", 1, true) then kind = "REJECTED"
                elseif value:find("offer failed", 1, true) or value:find("trade error", 1, true) then kind = "ERROR"
                elseif value:find("automatically", 1, true) and value:find("accepted", 1, true)
                    or value:find("are you sure", 1, true) or value:find("confirm this", 1, true) then kind = "CONFIRMATION"
                elseif (norm(o.Parent.Name):find("popup", 1, true) or norm(o.Parent.Name):find("dialog", 1, true))
                    and resolve(o.Parent, {"confirm", "yes", "okay", "ok"}) then kind = "UNKNOWN" end
                if kind then table.insert(matches, {kind = kind, text = o.Text, root = o.Parent, score = 0.94}) end
            end
        end
        if #matches == 1 then return matches[1] end
        if #matches > 1 then return {kind = "UNKNOWN", text = "multiple result dialogs", score = 0} end
        return nil
    end
    function B.dumpRelevantTradeGui()
        local pg = Players.LocalPlayer:WaitForChild("PlayerGui")
        local hub = B.findTradeHubGui(pg)
        local nodes, truncated = walk(hub and hub.instance or pg, true)
        local lines = {}
        for _, o in ipairs(nodes) do
            if is(o, "GuiObject") and #lines < TradeConfig.MaxDumpLines then
                local p, size = o.AbsolutePosition, o.AbsoluteSize
                table.insert(lines, string.format("%s class=%s visible=%s rect=%.0f,%.0f,%.0f,%.0f text=%q image=%q",
                    path(o), read(o, "ClassName") or "GuiObject", tostring(o.Visible), p.X, p.Y, size.X, size.Y,
                    tostring(read(o, "Text") or ""), tostring(read(o, "Image") or ""))
                    .. " imageKey=" .. ((is(o, "ImageLabel") or is(o, "ImageButton")) and B.imageKey(o) or "")
                    .. " item=" .. tostring(attr(o, "ItemName")) .. " quantity=" .. tostring(quantity(o))
                    .. " listing=" .. tostring(attr(o, "ListingId")) .. " owner=" .. tostring(attr(o, "UserId")))
            end
        end
        table.insert(lines, "truncated=" .. tostring(truncated or #lines >= TradeConfig.MaxDumpLines))
        local value = table.concat(lines, "\n")
        print("[BOT GUI DUMP]\n" .. value)
        return value
    end
    local Controller = {}; Controller.__index = Controller
    B.Controller = Controller
    function Controller.new()
        return setmetatable({currentState = "IDLE", running = false, processedListings = {}, connections = {},
            pending = nil, resultBaseline = {}, scanSignature = nil, input = nil, lastError = nil}, Controller)
    end
    function Controller:log(category, message)
        addLog(category, message); print("[" .. category .. "] " .. message)
    end
    function Controller:debug(message)
        if TradeConfig.Debug then self:log("BOT", message) end
    end
    function Controller:setState(value)
        self.currentState = value
        setStatus(value, value == "FAILED" and C.red or C.green)
        self:debug("State=" .. value)
    end
    function Controller:active()
        return self.running and state.running and alive and self.generation == state.generation
    end
    function Controller:dryRun()
        return TradeConfig.DryRun or self.rules.mode ~= "Auto"
    end
    function Controller:settingsValid()
        return state.give.id == self.rules.give.id and state.want.id == self.rules.want.id
            and state.giveQuantity == self.rules.giveQuantity and state.wantQuantity == self.rules.wantQuantity
            and state.mode == self.rules.mode
    end
    function Controller:schedule(delay)
        if not self:active() or self.pending then return end
        self.pending = task.delay(delay, function()
            self.pending = nil
            if not self:active() then return end
            local ok, reason = xpcall(function() if self.liveTest then self:liveTradeLoop() else self:tradeLoop() end end, function(err) return tostring(err) end)
            if not ok and self:active() then
                if self.liveTest then self:liveFinish("ERROR: CLICK FAILED", "Live test exception: " .. reason)
                else self:handleFailure("backend exception: " .. reason) end
            end
        end)
    end
    function Controller:click(target, purpose)
        if not self:active() then return false, "STOP/cancellation" end
        if not self:settingsValid() then return false, "settings changed; restart required" end
        if purpose == "submit" and self:dryRun() then return false, "DRY RUN final submit blocked" end
        if purpose == "confirm" then return false, "unknown confirmation never auto-clicked" end
        if not target or target.score < TradeConfig.MinConfidence or not shown(target.instance)
            or not (button(target.instance) or purpose == "focus search" and is(target.instance, "TextBox")) then
            return false, "low confidence or target disappeared"
        end
        local o = target.instance
        if exact(o, {"okay", "ok", "yes", "confirm", "confirm offer", "accept"}) and purpose ~= "recover" then
            return false, "confirmation action never automated"
        end
        local finalAction = exact(o, {"make offer", "submit offer", "confirm", "confirm offer"})
        local offerDialog = self.hub and B.findOfferDialog(self.hub.instance)
        if exact(o, {"send offer"}) and offerDialog and within(o, offerDialog.instance) then finalAction = true end
        if finalAction and (purpose ~= "submit" or self:dryRun()) then return false, "final action blocked by mode/context" end
        if read(o, "Active") == false or read(o, "Interactable") == false then return false, "target not interactable" end
        local point = o.AbsolutePosition + o.AbsoluteSize / 2
        local viewportSize = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize
        if not viewportSize or point.X < 0 or point.Y < 0 or point.X >= viewportSize.X or point.Y >= viewportSize.Y then
            return false, "target outside viewport"
        end
        local parent = o.Parent
        while parent do
            if is(parent, "GuiObject") and parent.ClipsDescendants then
                local p, sz = parent.AbsolutePosition, parent.AbsoluteSize
                if point.X < p.X or point.Y < p.Y or point.X >= p.X + sz.X or point.Y >= p.Y + sz.Y then return false, "target clipped" end
            end
            parent = parent.Parent
        end
        if not self.input then
            local ok, input = pcall(function() return UIS:CreateVirtualInput() end)
            if not ok or not input then return false, "VirtualInput unavailable; no restricted-input bypass" end
            self.input = input
        end
        -- The approved dashboard can overlap game UI. Temporarily disable the
        -- overlay for this synchronous click and restore it even on failure;
        -- never move or resize any controls.
        local enabled = gui.Enabled
        gui.Enabled = false
        local okHit, hits = pcall(function() return self.playerGui:GetGuiObjectsAtPosition(point.X, point.Y) end)
        if not okHit then gui.Enabled = enabled; return false, "GUI hit testing unavailable" end
        local top = hits[1]
        if not top or not (within(top, o) or within(o, top)) then gui.Enabled = enabled; return false, "target occluded or hit-test mismatch" end
        if not self:active() then gui.Enabled = enabled; return false, "STOP/cancellation" end
        local pressed = false
        local ok, reason = pcall(function()
            self.input:SendMouseButton(point, Enum.UserInputType.MouseButton1, true, 0)
            pressed = true
            self.input:SendMouseButton(point, Enum.UserInputType.MouseButton1, false, 0)
            pressed = false
        end)
        if pressed then pcall(function() self.input:SendMouseButton(point, Enum.UserInputType.MouseButton1, false, 0) end) end
        gui.Enabled = enabled
        self:log("OFFER", string.format("VirtualInput %s %s confidence=%.2f client=(%.0f,%.0f) accepted=%s; awaiting UI evidence",
            purpose, path(o), target.score, point.X, point.Y, tostring(ok)))
        return ok, ok and nil or tostring(reason)
    end
    function Controller:remember(result)
        local count, oldest, time = 0, nil, math.huge
        for key, record in pairs(self.processedListings) do
            if os.clock() - record.timestamp >= TradeConfig.ListingCooldown then self.processedListings[key] = nil
            else
                count += 1
                if record.timestamp < time then oldest, time = key, record.timestamp end
            end
        end
        if count >= TradeConfig.MaxProcessed and oldest then self.processedListings[oldest] = nil end
        if self.listing then self.processedListings[self.listing.key] = {timestamp = os.clock(), result = result} end
    end
    function Controller:processed(key)
        local record = self.processedListings[key]
        if record and os.clock() - record.timestamp < TradeConfig.ListingCooldown then return true end
        self.processedListings[key] = nil
        return false
    end
    function Controller:scanTradeHub()
        if not self.hub or not shown(self.hub.instance) or not within(self.hub.instance, self.playerGui) then
            local reason; self.hub, reason = B.findTradeHubGui(self.playerGui)
            if not self.hub then return nil, reason end
            self:debug("Trade root=" .. path(self.hub.instance) .. " confidence=" .. self.hub.score)
        end
        local container, cards = B.findListingsContainer(self.hub.instance)
        return {container = container, cards = cards}
    end
    function Controller:openListing(listing)
        local fresh = B.parseListing(listing.root)
        if fresh.key ~= listing.key or fresh.signature ~= listing.signature or not B.matchesRules(fresh, self.rules) then return false, "Listing changed" end
        self.listing = fresh
        return self:click(fresh.action, "open listing")
    end
    function Controller:finalValidation()
        if not self:settingsValid() then return false, "settings changed" end
        if not self.dialog or not shown(self.dialog.instance) then return false, "offer dialog disappeared" end
        if B.detectResult(self.playerGui) then return false, "popup present / listing invalid" end
        if not shown(self.listing.root) then
            -- A modal may hide its listing. Require independently verified terms,
            -- but never invent a validity marker from an absent source card.
            return false, "listing validity cannot be verified while source card hidden"
        end
        local fresh = B.parseListing(self.listing.root)
        if fresh.key ~= self.listing.key or fresh.signature ~= self.listing.signature or not B.matchesRules(fresh, self.rules) then return false, "Listing changed" end
        local give, gc, errorGive = total(B.parseItems(self.dialog.give), self.rules.give.name)
        local receive, rc, errorReceive = total(B.parseItems(self.dialog.receive), self.rules.want.name)
        if give ~= self.rules.giveQuantity then return false, "our item/quantity invalid: " .. tostring(errorGive or give) end
        if receive ~= self.rules.wantQuantity then return false, "received item/quantity invalid: " .. tostring(errorReceive or receive) end
        local submit = resolve(self.dialog.instance, {"make offer", "send offer", "submit offer"})
        if not submit then return false, "Submit button not found" end
        return math.min(gc, rc, fresh.confidence, submit.score) >= TradeConfig.MinConfidence, submit
    end
    function Controller:buildOffer()
        local selected, confidence, problem = total(B.parseItems(self.dialog.give), self.rules.give.name)
        if not selected or selected > self.rules.giveQuantity then
            local old = B.parseItems(self.dialog.give)
            local clear = resolve(self.dialog.give, {"clear", "clear all", "clear items"})
            if not clear and old[1] then clear = resolve(old[1].root, {"remove", "remove item", "delete", "x", "×"}) end
            if not clear then return false, "previous selection cannot be cleared safely: " .. tostring(problem or selected) end
            self.clearAttempts = (self.clearAttempts or 0) + 1
            if self.clearAttempts > TradeConfig.MaxOfferQuantity then return false, "clear selection retry limit" end
            self.clearBefore = #old
            self.clearCount = 0
            for _, item in ipairs(old) do self.clearCount += item.quantity or 0 end
            local ok, why = self:click(clear, "clear previous selection")
            return ok, ok and "clearing" or why
        end
        if selected == self.rules.giveQuantity then return true, "ready" end
        local add = B.findAddItemButton(self.dialog)
        if not add then return false, "Add item button missing/ambiguous" end
        self.selectedBefore = selected
        return self:click(add, "open inventory")
    end
    function Controller:selectOfferItem()
        local inventory, items, reason = B.findInventoryItems(self.playerGui, self.rules.give.name)
        if not inventory then return nil, reason end
        local available = 0
        for _, item in ipairs(items) do available += item.quantity end
        local required = self.rules.giveQuantity - self.selectedBefore
        if #items == 0 and not self.inventorySearched then
            local search = B.findInventorySearch(inventory)
            if search then
                self.inventorySearch = search.instance; self.inventorySearched = true
                local ok, why = self:click(search, "focus search")
                return ok, ok and "focus search" or why
            end
        end
        if #items == 0 and self.inventorySearched then return nil, "Item not found after inventory search" end
        if available < required then return false, "Not enough selected items required=" .. required .. " found=" .. available end
        table.sort(items, function(a, b) return a.confidence > b.confidence end)
        local item = items[1]
        if not item then return false, "Item not found" end
        self:log("OFFER", "Found selected item: " .. item.name .. " available=" .. available)
        return self:click({instance = item.action, score = item.confidence, reasons = {"exact inventory item + quantity"}}, "select item")
    end
    function Controller:submitOffer()
        if self:dryRun() then return false, "DRY RUN final submit blocked" end
        local valid, submit = self:finalValidation()
        if not valid then return false, tostring(submit) end
        self.resultBaseline = {}
        local result = B.detectResult(self.playerGui)
        if result then self.resultBaseline[result.root] = true end
        local ok, why = self:click(submit, "submit")
        if ok then self:remember("SUBMITTED_UNVERIFIED") end
        return ok, why
    end
    function Controller:recover()
        local popup = B.detectResult(self.playerGui)
        if popup and (popup.kind == "CONFIRMATION" or popup.kind == "UNKNOWN") then return false, "confirmation/unknown popup requires user review" end
        local root = popup and popup.root or self.dialog and self.dialog.instance
        if not root then return true end
        local close = resolve(root, popup and {"okay", "ok", "close", "cancel"} or {"cancel", "back", "close"})
        if not close then return false, "safe close action missing/ambiguous" end
        return self:click(close, "recover")
    end
    function Controller:handleFailure(reason, kind)
        self.lastError = reason; self:log("ERROR", reason)
        if kind == "INVALID" then incrementInvalid() else incrementErrors() end
        self:remember(kind or "FAILED"); self:setState("FAILED")
        if not self:active() then return end
        local recovered, errorRecover = self:recover()
        if not recovered then self:log("ERROR", "recovery blocked: " .. tostring(errorRecover)); setRunning(false); return end
        self:setState("RECOVERING"); self.deadline = os.clock() + TradeConfig.DialogTimeout; self:schedule(TradeConfig.PollInterval)
    end
    function Controller:handleSuccess(result)
        incrementSent(); incrementSuccess(); self:remember("SUCCESS"); self:setState("SUCCESS")
        local ok, why = self:recover()
        if not ok then self:handleFailure(why); return end
        self:setState("RECOVERING"); self.deadline = os.clock() + TradeConfig.DialogTimeout
        self:schedule(TradeConfig.PollInterval)
    end
    function Controller:handleRejected(result) self:handleFailure(result.text, "REJECTED") end
    function Controller:handleInvalid(result) self:handleFailure(result.text, "INVALID") end
    function Controller:handleTimeout(message) self:handleFailure(message) end
    function Controller:cooldown(result)
        if result ~= "PROCESSED" then self:remember(result) end
        self:setState("COOLDOWN")
        self:schedule(math.max(state.delay, TradeConfig.ActionDelay))
    end
    function Controller:tradeLoop()
        if not self:active() then return end
        if not self:settingsValid() then self:log("ERROR", "settings changed; stopping stale offer"); setRunning(false); return end
        local phase = self.currentState
        if phase == "SCANNING" then
            local scan, reason = self:scanTradeHub()
            if not scan then
                local launcher = not self.launchAttempted and resolve(self.playerGui, {"trade hub"})
                if launcher then
                    self.launchAttempted = true
                    local ok, why = self:click(launcher, "open Trade Hub")
                    if not ok then self:handleFailure(why); return end
                    self:setState("OPENING_HUB"); self.deadline = os.clock() + TradeConfig.DialogTimeout
                    self:schedule(TradeConfig.PollInterval); return
                end
                if reason ~= self.lastScanError then self:log("ERROR", tostring(reason)); self.lastScanError = reason end
                self:schedule(TradeConfig.ScanInterval); return
            end
            self.lastScanError = nil
            if #scan.cards == 0 then
                local search = resolve(self.hub.instance, {"search listings"})
                if search and not self.navigationAttempted then
                    self.navigationAttempted = true
                    local ok, why = self:click(search, "open search listings")
                    if not ok then self:handleFailure(why); return end
                    self:setState("OPENING_SEARCH"); self.deadline = os.clock() + TradeConfig.DialogTimeout
                    self:schedule(TradeConfig.PollInterval); return
                end
                if self.scanSignature ~= "empty" then self:log("SCAN", "No listings; waiting for visible search results"); self.scanSignature = "empty" end
                self:schedule(TradeConfig.ScanInterval); return
            end
            local best, parsed, matched = nil, 0, 0
            for _, card in ipairs(scan.cards) do
                local listing = B.parseListing(card)
                if not listing.unknown then parsed += 1 end
                local score = B.scoreListing(listing, self.rules)
                if score > 0 and not self:processed(listing.key) then
                    matched += 1; listing.score = score
                    if not best or score > best.score or score == best.score and listing.key < best.key then best = listing end
                elseif TradeConfig.Debug then self:debug("SKIP " .. listing.key .. " " .. tostring(select(2, B.matchesRules(listing, self.rules)))) end
                if TradeConfig.Debug then self:debug("PARSE " .. path(card) .. " confidence=" .. listing.confidence .. " unknown=" .. tostring(listing.unknown)) end
            end
            local signature = #scan.cards .. ":" .. parsed .. ":" .. matched
            if self.scanSignature ~= signature then
                self:log("SCAN", "Found " .. #scan.cards .. " listing candidates")
                self:log("PARSE", "Parsed " .. parsed .. "/" .. #scan.cards .. "; matches=" .. matched)
                self.scanSignature = signature
            end
            if not best then self:schedule(TradeConfig.ScanInterval); return end
            self.listing = best; self:setState("MATCH_FOUND")
            self:log("MATCH", "Best listing=" .. best.key .. " score=" .. best.score)
            self:schedule(TradeConfig.ActionDelay)
        elseif phase == "OPENING_HUB" then
            self.hub = B.findTradeHubGui(self.playerGui)
            if self.hub then self:setState("SCANNING"); self:schedule(TradeConfig.ActionDelay)
            elseif os.clock() >= self.deadline then self:handleFailure("Trade Hub navigation timeout") else self:schedule(TradeConfig.PollInterval) end
        elseif phase == "OPENING_SEARCH" then
            local scan = self:scanTradeHub()
            if scan and #scan.cards > 0 then self:setState("SCANNING"); self:schedule(TradeConfig.ActionDelay); return end
            local you, them
            if self.hub then you, them = roles(self.hub.instance, false) end
            if you and them then
                local want = total(B.parseItems(them), self.rules.want.name)
                if want == self.rules.wantQuantity then
                    local search = resolve(self.hub.instance, {"search"})
                    local ok, why = self:click(search, "search selected criteria")
                    if not ok then self:handleFailure(why); return end
                    self:setState("WAITING_LISTINGS"); self.deadline = os.clock() + TradeConfig.DialogTimeout
                    self:schedule(TradeConfig.PollInterval); return
                end
                self:handleFailure("Search panel opened, but selected wanted item is not verifiable. Supply relevant GUI dump; no guessed picker clicks."); return
            end
            if os.clock() >= self.deadline then self:handleFailure("Search Listings navigation timeout") else self:schedule(TradeConfig.PollInterval) end
        elseif phase == "WAITING_LISTINGS" then
            local scan = self:scanTradeHub()
            if scan and #scan.cards > 0 then self:setState("SCANNING"); self:schedule(TradeConfig.ActionDelay)
            elseif os.clock() >= self.deadline then self:handleFailure("No listings after verified search timeout") else self:schedule(TradeConfig.PollInterval) end
        elseif phase == "MATCH_FOUND" then
            self:setState("OPENING_LISTING")
            local ok, why = self:openListing(self.listing)
            if not ok then self:handleFailure(why); return end
            self.deadline = os.clock() + TradeConfig.DialogTimeout; self:schedule(TradeConfig.PollInterval)
        elseif phase == "OPENING_LISTING" then
            self.dialog = B.findOfferDialog(self.hub.instance)
            if self.dialog then
                local receive = total(B.parseItems(self.dialog.receive), self.rules.want.name)
                if receive ~= self.rules.wantQuantity then self:handleFailure("offer dialog received item mismatch"); return end
                self:setState("BUILDING_OFFER"); self:schedule(TradeConfig.ActionDelay)
            elseif os.clock() >= self.deadline then self:handleFailure("Offer dialog timeout") else self:schedule(TradeConfig.PollInterval) end
        elseif phase == "BUILDING_OFFER" then
            local ok, why = self:buildOffer()
            if not ok then self:handleFailure(why); return end
            if why == "ready" then self:setState("READY") elseif why == "clearing" then self:setState("VERIFYING_CLEAR") else self:setState("WAITING_INVENTORY") end
            self.deadline = os.clock() + TradeConfig.InventoryTimeout; self:schedule(TradeConfig.PollInterval)
        elseif phase == "VERIFYING_CLEAR" then
            local items, count = B.parseItems(self.dialog.give), 0
            for _, item in ipairs(items) do count += item.quantity or 0 end
            if #items < self.clearBefore or count < self.clearCount then self:setState("BUILDING_OFFER"); self:schedule(TradeConfig.ActionDelay)
            elseif os.clock() >= self.deadline then self:handleFailure("clear selection UI verification timeout") else self:schedule(TradeConfig.PollInterval) end
        elseif phase == "WAITING_INVENTORY" then
            local ok, why = self:selectOfferItem()
            if ok then self:setState(why == "focus search" and "FOCUSING_INVENTORY_SEARCH" or "VERIFYING_ITEM"); self.deadline = os.clock() + TradeConfig.InventoryTimeout
            elseif ok == false or os.clock() >= self.deadline then self:handleFailure(why or "Inventory timeout"); return end
            self:schedule(TradeConfig.PollInterval)
        elseif phase == "FOCUSING_INVENTORY_SEARCH" then
            local ok, focused = pcall(function() return UIS:GetFocusedTextBox() end)
            if ok and focused == self.inventorySearch then
                if not self:active() or not shown(focused) then return end
                local typed, why = pcall(function()
                    focused.SelectionStart = 1; focused.CursorPosition = #focused.Text + 1
                    self.input:SendTextInput(self.rules.give.name)
                end)
                if not typed then self:handleFailure("inventory text input unavailable: " .. tostring(why)); return end
                self:setState("VERIFYING_INVENTORY_SEARCH"); self:schedule(TradeConfig.PollInterval)
            elseif os.clock() >= self.deadline then self:handleFailure("inventory search focus not verified") else self:schedule(TradeConfig.PollInterval) end
        elseif phase == "VERIFYING_INVENTORY_SEARCH" then
            if norm(self.inventorySearch.Text) == norm(self.rules.give.name) then
                self:setState("WAITING_INVENTORY"); self:schedule(TradeConfig.PollInterval)
            elseif os.clock() >= self.deadline then self:handleFailure("inventory search text not verified") else self:schedule(TradeConfig.PollInterval) end
        elseif phase == "VERIFYING_ITEM" then
            local selected = total(B.parseItems(self.dialog.give), self.rules.give.name)
            if selected and selected == self.selectedBefore + 1 then
                self:log("OFFER", "Added " .. selected .. "/" .. self.rules.giveQuantity)
                self:setState("BUILDING_OFFER"); self:schedule(TradeConfig.ActionDelay)
            elseif selected and selected > self.selectedBefore + 1 then self:handleFailure("unexpected item quantity change")
            elseif os.clock() >= self.deadline then self:handleFailure("item selection UI verification timeout") else self:schedule(TradeConfig.PollInterval) end
        elseif phase == "READY" then
            local valid, why = self:finalValidation()
            if not valid then self:handleFailure("final validation: " .. tostring(why)); return end
            if self:dryRun() then
                self:log("DRY RUN", "Would submit Give: " .. self.rules.giveQuantity .. "x " .. self.rules.give.name
                    .. "; Receive: " .. self.rules.wantQuantity .. "x " .. self.rules.want.name
                    .. "; Listing: " .. self.listing.key .. "; Confidence: " .. self.listing.confidence .. "; final submit BLOCKED")
                if self.rules.mode == "Manual" then
                    self:remember("MANUAL_READY"); setRunning(false)
                    self.currentState = "READY"; setStatus("READY · Manual", C.pale); return
                end
                local ok, errorRecover = self:recover()
                if not ok then self:handleFailure(errorRecover); return end
                self:remember("DRY_RUN"); self:setState("RECOVERING"); self.deadline = os.clock() + TradeConfig.DialogTimeout
                self:schedule(TradeConfig.PollInterval)
            else self:setState("SUBMITTING"); self:schedule(TradeConfig.ActionDelay) end
        elseif phase == "SUBMITTING" then
            local ok, why = self:submitOffer()
            if not ok then self:handleFailure(why); return end
            self:setState("WAITING_RESULT"); self.deadline = os.clock() + TradeConfig.ResultTimeout; self:schedule(TradeConfig.PollInterval)
        elseif phase == "WAITING_RESULT" then
            local result = B.detectResult(self.playerGui)
            if result and not self.resultBaseline[result.root] then
                self:log("RESULT", result.kind .. ": " .. result.text)
                if result.kind == "SUCCESS" then
                    self:handleSuccess(result)
                elseif result.kind == "INVALID" then self:handleInvalid(result)
                elseif result.kind == "REJECTED" then self:handleRejected(result)
                elseif result.kind == "CONFIRMATION" or result.kind == "UNKNOWN" then self:handleFailure("confirmation/unknown popup requires review")
                else self:handleFailure(result.text, result.kind) end
            elseif os.clock() >= self.deadline then self:handleTimeout("Result timeout; submitted listing remains cached") else self:schedule(TradeConfig.PollInterval) end
        elseif phase == "RECOVERING" then
            if not B.findOfferDialog(self.hub and self.hub.instance or self.playerGui) and not B.detectResult(self.playerGui) then self:cooldown("PROCESSED")
            elseif os.clock() >= self.deadline then self:log("ERROR", "Recovery UI verification timeout"); setRunning(false) else self:schedule(TradeConfig.PollInterval) end
        elseif phase == "COOLDOWN" then
            if not state.repeatTrades then setRunning(false); return end
            self.listing = nil; self.dialog = nil; self:setState("SCANNING"); self:schedule(TradeConfig.ActionDelay)
        else self:handleFailure("Unknown UI/controller state: " .. tostring(phase)) end
    end
    -- Minimal live probe: discover, open ONE listing, verify, then stop.
    -- Uses existing input checks; never enters inventory/build/submit states.
    local function liveLog(message)
        print("[LIVE] " .. message); addLog("LIVE", message)
    end
    local function large(o)
        return shown(o) and (is(o, "Frame") or is(o, "ScrollingFrame"))
            and o.AbsoluteSize.X >= 180 and o.AbsoluteSize.Y >= 90
    end
    local function visibleTexts(root, limit)
        local texts = {}
        for _, o in ipairs(walk(root, true)) do
            if shown(o) and (is(o, "TextLabel") or is(o, "TextButton")) and norm(o.Text) ~= "" then
                table.insert(texts, {instance = o, text = o.Text})
                if #texts >= limit then break end
            end
        end
        return texts
    end
    local function liveTextDump(root)
        for _, entry in ipairs(visibleTexts(root, 150)) do
            local message = string.format("%s = %q", path(entry.instance), entry.text)
            print("[TEXT] " .. message); addLog("TEXT", message)
        end
    end
    local function liveAction(card)
        local candidates = {}
        for _, o in ipairs(walk(card, true)) do
            if shown(o) and button(o) and read(o, "Active") ~= false and read(o, "Interactable") ~= false then
                local excluded = exact(o, {"make offer", "submit offer", "confirm", "okay", "ok", "yes", "accept", "cancel", "close", "add", "+", "remove"})
                if not excluded then
                    local opening = exact(o, {"send offer", "open listing", "view listing", "open", "view", "offer"})
                    -- Unnamed icon buttons are usable only with verified repeated-card context.
                    table.insert(candidates, {instance = o, score = opening and 0.96 or 0.84,
                        reasons = {opening and "visible listing action" or "button in repeated listing row"}})
                end
            end
        end
        table.sort(candidates, function(a, b)
            if a.score ~= b.score then return a.score > b.score end
            if a.instance.AbsolutePosition.Y ~= b.instance.AbsolutePosition.Y then
                return a.instance.AbsolutePosition.Y < b.instance.AbsolutePosition.Y
            end
            return a.instance.AbsolutePosition.X < b.instance.AbsolutePosition.X
        end)
        if #candidates > 1 and candidates[1].score == candidates[2].score then
            return nil -- do not guess between several unlabeled item/action icons
        end
        return candidates[1]
    end
    local function liveContainers(root)
        local best, bestCards, bestScore
        for _, container in ipairs(walk(root, true)) do
            if large(container) then
                local scroll = is(container, "ScrollingFrame")
                local arranged = false
                for _, child in ipairs(container:GetChildren()) do
                    if is(child, "UIListLayout") or is(child, "UIGridLayout") then arranged = true end
                end
                local rows = {}
                for _, child in ipairs(container:GetChildren()) do
                    local name = norm(child.Name)
                    if shown(child) and (is(child, "Frame") or button(child))
                        and child.AbsoluteSize.X >= 100 and child.AbsoluteSize.Y >= 45
                        and child.AbsoluteSize.X >= container.AbsoluteSize.X * 0.45
                        and not name:find("template", 1, true) and not name:find("header", 1, true) then
                        local texts, visual = visibleTexts(child, 30), false
                        for _, node in ipairs(walk(child, true)) do
                            if shown(node) and (button(node) or is(node, "ImageLabel")) then visual = true; break end
                        end
                        if visual and #texts > 0 then table.insert(rows, child) end
                    end
                end
                local cards = {}
                for _, row in ipairs(rows) do
                    local similar = 0
                    for _, other in ipairs(rows) do
                        if row.ClassName == other.ClassName
                            and math.abs(row.AbsoluteSize.X - other.AbsoluteSize.X) <= row.AbsoluteSize.X * 0.20
                            and math.abs(row.AbsoluteSize.Y - other.AbsoluteSize.Y) <= row.AbsoluteSize.Y * 0.25 then
                            similar += 1
                        end
                    end
                    local action = liveAction(row)
                    if (scroll or arranged or similar >= 2) and action
                        and (action.score >= 0.96 or similar >= 2) then
                        table.insert(cards, {root = row, action = action})
                    end
                end
                local score = #cards + (scroll and 5 or arranged and 2 or 0)
                if #cards > 0 and (not bestScore or score > bestScore) then
                    best, bestCards, bestScore = container, cards, score
                end
            end
        end
        if bestCards then
            table.sort(bestCards, function(a, b)
                local ap, bp = a.root.AbsolutePosition, b.root.AbsolutePosition
                return ap.Y == bp.Y and ap.X < bp.X or ap.Y < bp.Y
            end)
        end
        return best, bestCards or {}
    end
    local function liveHub(playerGui)
        local fallback
        local keywords = {"search listings", "listings", "send offer", "make offer", "looking for", "trading", "offer"}
        local entries = visibleTexts(playerGui, TradeConfig.MaxNodes)
        table.sort(entries, function(a, b)
            local aa = norm(a.text):find("search listings", 1, true) ~= nil
            local bb = norm(b.text):find("search listings", 1, true) ~= nil
            if aa ~= bb then return aa end
            return path(a.instance) < path(b.instance)
        end)
        for _, entry in ipairs(entries) do
            local text, relevant = norm(entry.text), false
            for _, keyword in ipairs(keywords) do if text:find(keyword, 1, true) then relevant = true; break end end
            if relevant then
                if text:find("search listings", 1, true) then
                    liveLog("Search Listings text found: " .. path(entry.instance))
                end
                local parent = entry.instance.Parent
                for _ = 1, TradeConfig.MaxAncestors do
                    if not parent or parent == playerGui then break end
                    if large(parent) then
                        fallback = fallback or parent
                        local container, cards = liveContainers(parent)
                        if container then liveLog("Candidate root: " .. path(parent)); return parent, container, cards end
                    end
                    parent = parent.Parent
                end
            end
        end
        if fallback then liveLog("Candidate root: " .. path(fallback)) end
        return fallback, nil, {}
    end
    local function liveSnapshot(root)
        local visible = {}
        for _, o in ipairs(walk(root, true)) do if shown(o) then visible[o] = true end end
        return visible
    end
    local function liveHit(target, playerGui)
        local o = target.instance
        if not shown(o) then return false end
        local point = o.AbsolutePosition + o.AbsoluteSize / 2
        local view = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize
        if not view or point.X < 0 or point.Y < 0 or point.X >= view.X or point.Y >= view.Y then return false end
        local parent = o.Parent
        while parent do
            if is(parent, "GuiObject") and parent.ClipsDescendants then
                local p, s = parent.AbsolutePosition, parent.AbsoluteSize
                if point.X < p.X or point.Y < p.Y or point.X >= p.X+s.X or point.Y >= p.Y+s.Y then return false end
            end
            parent = parent.Parent
        end
        local enabled = gui.Enabled; gui.Enabled = false
        local ok, hits = pcall(function() return playerGui:GetGuiObjectsAtPosition(point.X, point.Y) end)
        gui.Enabled = enabled
        local top = ok and hits[1]
        return top and (within(top, o) or within(o, top)) or false
    end
    local function liveOpened(root, before, container, hub)
        local hubScreen = hub
        while hubScreen and not is(hubScreen, "ScreenGui") do hubScreen = hubScreen.Parent end
        for _, o in ipairs(walk(root, true)) do
            if large(o) and not within(o, container) then
                local keywords, strong, changed = false, false, not before[o]
                for _, entry in ipairs(visibleTexts(o, 60)) do
                    local text = norm(entry.text)
                    for _, keyword in ipairs({"make offer", "send offer", "add item", "confirm", "cancel", "you give", "they give", "offer"}) do
                        if text:find(keyword, 1, true) then
                            keywords = true
                            if not before[entry.instance] then changed = true end
                        end
                    end
                    if text:find("make offer", 1, true) or text:find("add item", 1, true)
                        or text:find("you give", 1, true) or text:find("they give", 1, true)
                        or text == "confirm" or text == "cancel" then strong = true end
                end
                -- Existing listings contain "Send Offer": only NEW visible UI counts.
                -- New rows/timers and unrelated chat/HUD are not evidence of opening.
                local inHub = hubScreen and within(o, hubScreen)
                if changed and (not before[o] and (inHub or keywords and strong)
                    or before[o] and strong and inHub) then return o end
            end
        end
    end
    function Controller:liveFinish(status, errorMessage)
        if errorMessage then print("[LIVE ERROR] " .. errorMessage); addLog("LIVE ERROR", errorMessage) end
        setRunning(false)
        self.currentState = status
        setStatus(status, errorMessage and C.red or C.green)
    end
    function Controller:liveClickDump()
        for _, o in ipairs({self.liveCard and self.liveCard.root, self.liveCard and self.liveCard.action.instance}) do
            liveLog(string.format("Target: %s ClassName=%s AbsolutePosition=%s AbsoluteSize=%s Visible=%s Active=%s Selectable=%s Text=%q",
                path(o), tostring(o.ClassName), tostring(o.AbsolutePosition), tostring(o.AbsoluteSize),
                tostring(o.Visible), tostring(read(o, "Active")), tostring(read(o, "Selectable")), tostring(read(o, "Text") or "")))
        end
        local count = 0
        local function children(o, depth)
            if depth > 4 or count >= 150 then return end
            for _, child in ipairs(o:GetChildren()) do
                if count >= 150 then break end
                count += 1
                liveLog(string.format("Card child depth=%d %s ClassName=%s Visible=%s Text=%q", depth,
                    path(child), tostring(child.ClassName), tostring(read(child, "Visible")), tostring(read(child, "Text") or "")))
                children(child, depth + 1)
            end
        end
        if self.liveCard then children(self.liveCard.root, 1) end
    end
    function Controller:liveTradeLoop()
        if not self:active() then return end
        if self.currentState == "SEARCHING TRADE HUB" then
            local root, container, cards = liveHub(self.playerGui)
            if not root then
                liveTextDump(self.playerGui)
                self:liveFinish("ERROR: TRADE HUB NOT FOUND", "Trade Hub not found; visible text dump follows START")
                return
            end
            self.hub = {instance = root, score = 0.90}
            self:setState("TRADE HUB FOUND"); liveLog("TRADE HUB FOUND")
            if not container or #cards == 0 then
                liveTextDump(self.playerGui)
                self:liveFinish("ERROR: NO LISTINGS", "No clickable repeated listing rows; open search results before START")
                return
            end
            liveLog("Listings container: " .. path(container))
            liveLog("Candidate cards: " .. #cards)
            self.liveCards = cards
            self.liveContainer = container
            self:setState("FOUND " .. #cards .. " LISTINGS")
            self:schedule(0)
        elseif self.currentState:match("^FOUND %d+ LISTINGS$") then
            if B.findOfferDialog(self.playerGui) then
                self:liveFinish("ERROR: CLICK FAILED", "Offer dialog already open; close it before this test")
                return
            end
            -- Select the first row with an opening action; never inventory/final controls.
            for _, card in ipairs(self.liveCards) do
                if liveHit(card.action, self.playerGui) then self.liveCard = card; break end
            end
            if not self.liveCard then
                self.liveCard = self.liveCards[1]; self:liveClickDump()
                self:liveFinish("ERROR: CLICK FAILED", "Listing click failed: all candidate actions are clipped, outside viewport or occluded")
                return
            end
            liveLog("Selected listing: " .. path(self.liveCard.root))
            liveLog("Texts:")
            for _, entry in ipairs(visibleTexts(self.liveCard.root, 30)) do liveLog(entry.text) end
            self.liveBefore = liveSnapshot(self.playerGui)
            liveLog("Input method: UserInputService:CreateVirtualInput / SendMouseButton")
            local ok, reason = self:click(self.liveCard.action, "open live listing")
            if not ok then
                self:liveClickDump()
                self:liveFinish("ERROR: CLICK FAILED", "Listing click failed: " .. tostring(reason))
                return
            end
            self:setState("OPENING LISTING")
            self.deadline = os.clock() + 5
            self:schedule(0)
        elseif self.currentState == "OPENING LISTING" then
            local opened = liveOpened(self.playerGui, self.liveBefore, self.liveContainer, self.hub.instance)
            if opened then
                liveLog("Opened GUI: " .. path(opened))
                liveLog("OFFER WINDOW OPENED")
                self:liveFinish("LISTING OPENED")
            elseif os.clock() >= self.deadline then
                self:liveClickDump(); liveTextDump(self.playerGui)
                self:liveFinish("ERROR: CLICK FAILED", "Listing click failed: no new visible offer/listing window within 5s")
            else self:schedule(TradeConfig.PollInterval) end
        else self:liveFinish("ERROR: CLICK FAILED", "Unexpected live-test state: " .. tostring(self.currentState)) end
    end

    function Controller:startTradeBot()
        if self.running then return false end
        self.playerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
        if not self.playerGui then
            print("[LIVE ERROR] PlayerGui unavailable"); setStatus("ERROR: TRADE HUB NOT FOUND", C.red); return false
        end
        self.rules = {give = state.give, want = state.want, giveQuantity = state.giveQuantity,
            wantQuantity = state.wantQuantity, mode = state.mode}
        if not LIVE_TEST and (self.rules.giveQuantity > TradeConfig.MaxOfferQuantity or self.rules.wantQuantity > TradeConfig.MaxOfferQuantity) then
            self:log("ERROR", "quantity exceeds safe UI batch limit"); return false
        end
        self.running = true; self.generation = state.generation
        self.navigationAttempted = false; self.launchAttempted = false; self.lastScanError = nil; self.scanSignature = nil; self.inventorySearched = false
        self.clearAttempts = 0; self.listing = nil; self.dialog = nil; self.hub = nil
        self:log("BOT", "Started; DryRun=" .. tostring(self:dryRun()) .. "; GUI resolver + verified input")
        self.liveTest = LIVE_TEST
        self.liveCard = nil; self.liveCards = nil; self.liveBefore = nil
        self:setState(LIVE_TEST and "SEARCHING TRADE HUB" or "SCANNING"); self:schedule(0); return true
    end
    function Controller:stopTradeBot()
        self.running = false
        self.liveBefore = nil; self.liveCards = nil; self.liveContainer = nil; self.liveCard = nil
        if self.pending then task.cancel(self.pending); self.pending = nil end
        disconnect(self.connections)
        self.currentState = "STOPPED"
    end
    function Controller:cleanupTradeBot()
        self:stopTradeBot()
        if self.input then pcall(function() self.input:Destroy() end); self.input = nil end
    end
    function B.startTradeBot()
        if not B.controller then B.controller = Controller.new() end
        return B.controller:startTradeBot()
    end
    function B.stopTradeBot()
        if B.controller then B.controller:stopTradeBot() end
    end
    function B.cleanupTradeBot()
        if B.controller then B.controller:cleanupTradeBot() end
    end
    -- Public diagnostic surface; no input or mode switching through globals.
    local api = {dumpRelevantTradeGui = B.dumpRelevantTradeGui, config = TradeConfig,
        getState = function() return B.controller and B.controller.currentState or "IDLE" end}
    local apiEnv = _G
    if type(getgenv) == "function" then
        local ok, env = pcall(getgenv)
        if ok and type(env) == "table" then apiEnv = env end
    end
    local published = pcall(function() apiEnv.TakizawaTradeBot = api end)
    if not published then print("[BOT] Diagnostic export unavailable; enable TradeConfig.Debug for selector logs") end
end
-- END TRADE BACKEND

createMainWindow(); createHeader()
createHomePage(); createAutoTradePage(); createItemsPage(); createSettingsPage(); createStatsPage(); createInfoPage()
updateTrade(false); updateSettings(); switchPage("home")
local function watchCamera()
    if cameraConnection then cameraConnection:Disconnect() end
    local camera = workspace.CurrentCamera
    if camera then cameraConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(function() fit(false) end) end
    fit(false)
end
connect(workspace:GetPropertyChangedSignal("CurrentCamera"), watchCamera)
watchCamera(); fit(true)
for _ = 1, 3 do spawnPetal() end
schedulePetal()
local lastSecond = -1
connect(RunService.Heartbeat, function(delta)
    if state.running then state.elapsed += delta end
    local seconds = math.floor(state.elapsed)
    if seconds ~= lastSecond then
        lastSecond = seconds
        local value = string.format("%02d:%02d:%02d", math.floor(seconds / 3600), math.floor(seconds / 60) % 60, seconds % 60)
        for _, view in ipairs(timerViews) do view.Text = value end
    end
end)
addLog("GUI", "Loaded — mobile interface")
addLog("Trade", tradeText())
