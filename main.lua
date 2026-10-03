-- Takizawa_swaga / AdoptMeDeltaBot. GUI only: no Trade Hub actions.
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
    pink = Color3.fromRGB(255, 111, 187), magenta = Color3.fromRGB(172, 44, 117),
    pale = Color3.fromRGB(255, 202, 230), text = Color3.fromRGB(246, 235, 247),
    muted = Color3.fromRGB(173, 149, 178), line = Color3.fromRGB(91, 62, 91),
    green = Color3.fromRGB(73, 221, 117), red = Color3.fromRGB(255, 101, 129),
}
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
local W, H, portrait = 900, 530, false
local activePage = "home"
local cameraConnection, dropdownClose, dropdownAnchor, listRefresh
local backgroundImage, backgroundShade, shadeGradient, petalLayer
local ambientTweens, activePetals = {}, {}
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
    local transparency = bright and 0.20 or 0.40
    local b = make("TextButton", parent, {Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(width, height),
        BackgroundColor3 = base, BackgroundTransparency = transparency, AutoButtonColor = false,
        Text = value, TextColor3 = bright and C.text or C.pale, TextSize = 15, Font = Enum.Font.GothamMedium, ZIndex = Z.control})
    corners(b, 8); stroke(b, C.pink, bright and 0.2 or 0.58)
    if bright then gradient(b, C.pink, C.magenta, 25) end
    local function appearance(hover, pressed)
        local selected = b:GetAttribute("GlassSelected") == true
        local opacity = selected and 0.22 or transparency
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
    corners(card); stroke(card, C.pink, 0.70)
    -- UIGradient multiplies the surface colour: use light tint stops rather
    -- than multiplying dark glass by another near-black gradient.
    gradient(card, Color3.fromRGB(246, 210, 232), Color3.fromRGB(188, 172, 198), 70)
    text(card, title, 12, 8, width - 24, 22, 13, C.pale)
    frame(card, 10, 34, width - 20, 1, C.line, 0.4).ZIndex = Z.decoration
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
-- Future Trader may call the four counters above. No actions are attached yet.
local function setStatus(value, color)
    for _, view in ipairs(statusViews) do
        view.label.Text = value; animate(view.label, {TextColor3 = color})
        animate(view.dot, {BackgroundColor3 = color})
    end
end
local startButtons = {}
local function setRunning(running)
    if running and state.running then return end
    closeDropdown()
    if running and (not state.give or not state.want or state.giveQuantity < 1 or state.wantQuantity < 1) then
        incrementErrors(); setStatus("Ошибка", C.red); addLog("Error", "Некорректное предложение"); return
    end
    state.running = running
    state.generation += 1 -- Future async work must check this cancellation token.
    for _, b in ipairs(startButtons) do
        b.Active = not running
        animate(b, {TextTransparency = running and 0.5 or 0, BackgroundTransparency = running and 0.22 or 0.15})
    end
    setStatus(running and "Работает" or "Остановлен", running and C.green or C.red)
    addLog("Bot", running and "Started — GUI only" or "Stopped")
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
    local card = createCard(parent, "ПРЕДЛОЖЕНИЕ", 0, y, 500, 164)
    text(card, "Я отдаю", 12, 40, 210, 22, 13, C.muted)
    text(card, "Я получаю", 278, 40, 210, 22, 13, C.muted)
    local give = createButton(card, "", 12, 66, 210, 38)
    local want = createButton(card, "", 278, 66, 210, 38)
    local arrow = text(card, "⇄", 226, 68, 48, 36, 30, C.pink)
    arrow.TextXAlignment = Enum.TextXAlignment.Center
    local view = {give = give, want = want}
    for _, side in ipairs({"give", "want"}) do
        local x = side == "give" and 12 or 278
        local minus = createButton(card, "−", x, 110, 54, 34)
        view[side .. "Quantity"] = text(card, "1", x + 60, 110, 90, 34, 16)
        view[side .. "Quantity"].TextXAlignment = Enum.TextXAlignment.Center
        local plus = createButton(card, "+", x + 156, 110, 54, 34)
        connect(minus.Activated, function()
            state[side .. "Quantity"] = math.max(1, state[side .. "Quantity"] - 1); updateTrade(true)
        end)
        connect(plus.Activated, function()
            state[side .. "Quantity"] = math.min(9999, state[side .. "Quantity"] + 1); updateTrade(true)
        end)
        bindDropdown(view[side], ITEMS, function() return state[side].id end,
            function(item) state[side] = item; updateTrade(true) end)
    end
    view.preview = text(parent, tradeText(), 8, y + 167, 484, 22, 12, C.pale)
    view.preview.TextXAlignment = Enum.TextXAlignment.Center
    table.insert(tradeViews, view)
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
    local delay = createCard(parent, "ЗАДЕРЖКА МЕЖДУ ТРЕЙДАМИ", 0, y, 260, 90)
    local track = frame(delay, 16, 59, 170, 5, C.line)
    corners(track, 4)
    local fill = frame(track, 0, 0, 0, 5, C.pink); corners(fill, 4)
    local knob = frame(track, 0, -5, 16, 16, C.pink); corners(knob, 16)
    local hit = make("TextButton", track, {Position = UDim2.fromOffset(-8, -17), Size = UDim2.new(1, 16, 0, 40),
        BackgroundTransparency = 1, Text = "", AutoButtonColor = false})
    local value = text(delay, "", 200, 45, 55, 32, 14, C.pink)
    local mode = createCard(parent, "РЕЖИМ", 272, y, 228, 90)
    local modeButton = createButton(mode, "", 10, 43, 90, 34)
    modeButton.TextSize = 11
    local repeatButton = createButton(mode, "", 106, 43, 114, 34)
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
    bindDropdown(modeButton, {{id = "normal", name = "Обычный"}}, function() return "normal" end,
        function(option) state.mode = option.name; updateSettings() end)
end
local function createActions(parent, y)
    local start = createButton(parent, "▶  ЗАПУСТИТЬ", 0, y, 244, 42, true)
    local stop = createButton(parent, "■  ОСТАНОВИТЬ", 256, y, 244, 42)
    stroke(stop, C.red, 0.5)
    table.insert(startButtons, start)
    connect(start.Activated, function() setRunning(true) end)
    connect(stop.Activated, function() setRunning(false) end)
end
local function createStatus(parent, y)
    local card = createCard(parent, "СТАТУС", 0, y, 500, 65)
    local dot = frame(card, 14, 43, 10, 10, C.green); corners(dot, 10)
    local value = text(card, "Готов к работе", 32, 36, 320, 26, 15, C.green)
    local timer = text(card, "00:00:00", 388, 36, 100, 26, 14, C.pink)
    table.insert(statusViews, {label = value, dot = dot}); table.insert(timerViews, timer)
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
    page.CanvasSize = UDim2.fromOffset(0, 540)
    createStatus(page, 0); createProposal(page, 76)
    local card = createCard(page, "СПИСОК ПЕТОВ", 0, 274, 500, 92)
    local summary = text(card, "", 12, 40, 242, 44, 12, C.pale)
    summary.TextTruncate = Enum.TextTruncate.None
    table.insert(schemeSummaries, summary)
    local add = createButton(card, "+", 276, 44, 62, 34)
    local remove = createButton(card, "−", 348, 44, 62, 34)
    local clear = createButton(card, "Очистить", 420, 44, 68, 34)
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
    createSettingsControls(page, 378); createActions(page, 482)
end
local function createAutoTradePage()
    local page = createPage("trade")
    createStatus(page, 0); createProposal(page, 76); createActions(page, 274)
    local card = createCard(page, "GUI PROTOTYPE", 0, 330, 500, 94)
    local note = text(card, "START управляет только состоянием интерфейса.\nПредложения не отправляются. Trade Hub будет подключён позже.", 12, 43, 476, 42, 13, C.muted)
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
    local note = text(card, "Перетаскивайте окно за верхнюю панель.\nМасштаб автоматически подстраивается под экран.\nЗадержка и режим сохранены в текущей сессии для будущего Trader.", 12, 44, 476, 72, 14, C.muted)
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
    local note = text(card, "Mobile GUI prototype\nSTART / STOP управляют состоянием GUI.\nAnime asset можно подключить через ANIME_IMAGE_ID.\nНастоящая Trade Hub автоматизация ещё не реализована.", 12, 42, 476, 78, 13, C.muted)
    note.TextWrapped = true; note.TextTruncate = Enum.TextTruncate.None
    local logCard = createCard(page, "ЖУРНАЛ • ПОСЛЕДНИЕ 80 СТРОК", 0, 144, 500, 280)
    local scroll = make("ScrollingFrame", logCard, {Position = UDim2.fromOffset(8, 42), Size = UDim2.fromOffset(484, 228),
        BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3, ScrollBarImageColor3 = C.pink,
        CanvasSize = UDim2.fromOffset(0, 0)})
    local log = text(scroll, "", 8, 4, 460, 0, 12, C.muted)
    log.TextYAlignment = Enum.TextYAlignment.Top; log.TextTruncate = Enum.TextTruncate.None
    table.insert(logLabels, {label = log, scroll = scroll})
end
local function switchPage(id)
    closeDropdown(); sliderInput = nil; sliderTrack = nil
    activePage = id
    for name, page in pairs(pages) do page.Visible = name == id end
    for name, entry in pairs(navButtons) do
        local selected = name == id
        entry.gradient.Enabled = selected
        entry.stroke.Color = selected and C.pink or C.line
        entry.stroke.Transparency = selected and 0.24 or 0.64
        entry.button:SetAttribute("GlassSelected", selected)
        animate(entry.button, {BackgroundColor3 = selected and C.magenta or C.glass,
            BackgroundTransparency = selected and 0.22 or 0.40})
    end
    local page = pages[id]
    page.CanvasPosition = Vector2.zero
    page.Position = UDim2.fromOffset(6, 0)
    animate(page, {Position = UDim2.fromOffset(0, 0), ScrollBarImageTransparency = 0.1})
end
local function createAnimePanel()
    -- Whole-window 16:9 art. Fit retains the character at the left edge;
    -- the small breathing overscan cannot crop any meaningful part of it.
    anime = make("Frame", window, {Name = "AnimeBackground", Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1, BorderSizePixel = 0, ClipsDescendants = true,
        Active = false, ZIndex = Z.background})
    backgroundImage = make("ImageLabel", anime, {Name = "AnimeArt", AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1.004, 1.004),
        BackgroundTransparency = 1, Image = ANIME_IMAGE_ID or "", ImageTransparency = 0,
        Visible = ANIME_IMAGE_ID ~= nil,
        ScaleType = Enum.ScaleType.Fit, Active = false, Selectable = false, ZIndex = Z.background})
    backgroundShade = make("Frame", window, {Name = "RightShade", Position = UDim2.fromScale(0.33, 0),
        Size = UDim2.fromScale(0.67, 1), BackgroundColor3 = C.bg, BorderSizePixel = 0,
        Active = false, ZIndex = Z.lighting})
    shadeGradient = gradient(backgroundShade, C.bg, C.bg)
    local glow = make("Frame", window, {Name = "CharacterLight", Position = UDim2.fromScale(0.02, 0.1),
        Size = UDim2.fromScale(0.32, 0.82), BackgroundColor3 = C.magenta,
        BackgroundTransparency = 0.965, BorderSizePixel = 0, Active = false, ZIndex = Z.lighting})
    corners(glow, 120)
    local lightGradient = gradient(glow, C.magenta, C.pink, 35)
    lightGradient.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 1),
        NumberSequenceKeypoint.new(0.5, 0.4), NumberSequenceKeypoint.new(1, 1)})
    petalLayer = make("Frame", window, {Name = "SakuraLayer", Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1, BorderSizePixel = 0, ClipsDescendants = true, Active = false, ZIndex = Z.petals})
    table.insert(ambientTweens, TweenService:Create(backgroundImage,
        TweenInfo.new(5.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
        {Position = UDim2.new(0.5, 0, 0.5, 2), Size = UDim2.fromScale(1.010, 1.010)}))
    table.insert(ambientTweens, TweenService:Create(glow,
        TweenInfo.new(4.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
        {BackgroundTransparency = 0.945}))
    for _, t in ipairs(ambientTweens) do t:Play() end
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
    if not alive or minimized or petalCount >= 18 then return end
    local startX = random:NextNumber() < 0.25 and random:NextNumber(0.04, 0.20) or -0.025
    local startY = random:NextNumber(0.02, 0.90)
    local endY = startY + random:NextNumber(0.04, 0.15)
    local width, height = random:NextInteger(5, 9), random:NextInteger(9, 16)
    local object = make("Frame", petalLayer, {Name = "SakuraPetal", AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(startX, startY), Size = UDim2.fromOffset(width, height),
        BackgroundColor3 = C.pale:Lerp(C.pink, random:NextNumber(0.05, 0.45)),
        BackgroundTransparency = random:NextNumber(0.28, 0.55), Rotation = random:NextNumber(-100, 100),
        BorderSizePixel = 0, Active = false, ZIndex = Z.petals})
    make("UICorner", object, {CornerRadius = UDim.new(0.7, 0)})
    local entry = {connections = {}}
    activePetals[object] = entry; petalCount += 1
    local duration = random:NextNumber(8.5, 12.5)
    local rotation = object.Rotation + random:NextNumber(150, 400)
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
    particleThread = task.delay(random:NextNumber(0.60, 0.95), function()
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
    for _, t in ipairs(ambientTweens) do if paused then t:Pause() else t:Play() end end
    for _, entry in pairs(activePetals) do if paused then entry.tween:Pause() else entry.tween:Play() end end
    if not paused then schedulePetal() end
end
local function createSidebar()
    sidebar = frame(body, 12, 10, 176, 330, C.bg, 1)
    for i, entry in ipairs({{"home", "⌂  Главная"}, {"trade", "⇄  Авто Трейд"}, {"items", "◇  Предметы"},
        {"settings", "⚙  Настройки"}, {"stats", "▥  Статистика"}, {"info", "ⓘ  Инфо"}}) do
        local b = createButton(sidebar, entry[2], 0, (i - 1) * 52, 176, 44)
        b.TextSize = 15
        local g = gradient(b, Color3.fromRGB(255, 220, 241), Color3.fromRGB(186, 146, 186)); g.Enabled = false
        navButtons[entry[1]] = {button = b, gradient = g, stroke = b:FindFirstChildOfClass("UIStroke")}
        connect(b.Activated, function() switchPage(entry[1]) end)
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
        -- Derive the canvas from BOTH viewport axes; no fixed desktop-size cap.
        H = 530
        uiScale.Scale = viewport.Y * 0.92 / H
        W = viewport.X * 0.94 / uiScale.Scale
    end
    window.Size = UDim2.fromOffset(W, minimized and 72 or H)
    local padding = portrait and 14 or math.clamp(W * 0.014, 10, 16)
    body.Position = UDim2.fromOffset(padding, 78)
    body.Size = UDim2.fromOffset(W - padding * 2, H - 86)
    -- Shift the existing full-window art slightly right, without changing its
    -- aspect ratio or breathing tween; sidebar stays to the left of both eyes.
    anime.Position = UDim2.fromScale(portrait and 0 or 0.03, 0)
    backgroundImage.ImageTransparency = portrait and 0.55 or 0
    backgroundShade.Position = UDim2.fromScale(portrait and 0 or 0.465, 0)
    backgroundShade.Size = UDim2.fromScale(portrait and 1 or 0.535, 1)
    shadeGradient.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, portrait and 0.72 or 1),
        NumberSequenceKeypoint.new(0.5, portrait and 0.70 or 0.96), NumberSequenceKeypoint.new(1, portrait and 0.65 or 0.85)})
    local sidebarWidth = portrait and 508 or W * 0.175
    local navHeight = math.min(math.max(44, 32 / uiScale.Scale), (H - 102) / 6 - 8)
    sidebar.Position = UDim2.fromOffset(0, portrait and 0 or 10)
    sidebar.Size = UDim2.fromOffset(sidebarWidth, portrait and 98 or H - 96)
    local order = {"home", "trade", "items", "settings", "stats", "info"}
    for i, id in ipairs(order) do
        navButtons[id].button.Position = portrait and UDim2.fromOffset(((i - 1) % 3) * 170, math.floor((i - 1) / 3) * 48) or UDim2.fromOffset(0, (i - 1) * (navHeight + 8))
        navButtons[id].button.Size = UDim2.fromOffset(portrait and 162 or sidebarWidth, portrait and 40 or navHeight)
    end
    local contentLeft = W * 0.465
    local contentWidth = W - contentLeft - padding * 2
    contentScale.Scale = portrait and 1 or contentWidth / 500
    pageHost.Position = UDim2.fromOffset(portrait and 4 or contentLeft - padding, portrait and 104 or 0)
    pageHost.Size = UDim2.fromOffset(500, portrait and 522 or (H - 86) / contentScale.Scale)
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
    window.Name = "Window"; corners(window, 12); stroke(window, C.pink, 0.1)
    window.ClipsDescendants = true
    uiScale = make("UIScale", window, {Scale = 1})
    for i = 1, 3 do
        local glow = frame(window, -i * 2, -i * 2, W + i * 4, H + i * 4, C.bg, 1)
        glow.Size = UDim2.new(1, i * 4, 1, i * 4)
        corners(glow, 12 + i * 2); stroke(glow, C.pink, 0.88 + i * 0.025, 2)
        glow.ZIndex = Z.decoration
    end
    body = frame(window, 14, 78, W - 28, H - 86, C.bg, 1)
    createAnimePanel(); createSidebar()
    pageHost = frame(body, 372, 0, 500, 438, C.bg, 1)
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
    text(header, "✿", 16, 12, 38, 42, 31, C.pink)
    local title = text(header, 'Takizawa<font color="#FF6FBB">_swaga</font>', 62, 10, 370, 34, 26)
    title.RichText = true; title.Font = Enum.Font.GothamBold
    text(header, "ADOPT ME • TRADE BOT", 64, 44, 310, 18, 12, C.muted)
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
for _ = 1, 8 do spawnPetal() end
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
