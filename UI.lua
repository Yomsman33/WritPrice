-- SPDX-License-Identifier: GPL-2.0-only
-- WritPrice: the /writs window (writs ranked by cost per reputation point)
local ADDON, ns = ...
local L = ns.L

local ROW_H, NUM_ROWS = 18, 16
local MIN_WIDTH = 770
local WIDTH = MIN_WIDTH
local COLS = {
  { key = "rank",   w = 75,  justify = "LEFT" },
  { key = "item",   w = 180, justify = "LEFT" },
  { key = "zone",   w = 105, justify = "LEFT",   optional = true },
  { key = "qty",    w = 35,  justify = "CENTER" },
  { key = "writ",   w = 90,  justify = "RIGHT",  optional = true },
  { key = "unit",   w = 95,  justify = "RIGHT",  optional = true },
  { key = "craft",  w = 95,  justify = "RIGHT",  optional = true },
  { key = "recipe", w = 75,  justify = "CENTER", optional = true },
  { key = "pouch",  w = 80,  justify = "RIGHT",  optional = true },
  { key = "total",  w = 105, justify = "RIGHT" },
  { key = "rep",    w = 90,  justify = "RIGHT" },
}
local LIST_TOP = -78

local frame, scroll, rows, status, plan, pending, empty, title
local scanBtn, craftBtn, profBtn, colsBtn, goalBtn, helpBtn
local headers, filterBtns = {}, {}
local profMenu, colsMenu, zoneMenu, zoneHdr
local filter = "ALL"
local data = {}

------------------------------------------------------------
-- Reputation goal: fixed number (db.goal > 0) or "next reputation level" (db.goal = 0 or unset)
------------------------------------------------------------
function ns.GetGoal()
  local g = ns.db and ns.db.goal
  if g and g > 0 then return g, nil end
  local label, cur, size
  if ns.FactionStanding then label, cur, size = ns.FactionStanding() end
  if label and size and size > 0 and cur then
    local left = size - cur
    if left > 0 then return left, label end
  end
  return 1000, nil
end

function ns.SetGoal(n)
  n = tonumber(n)
  if not n or n < 0 then return false end
  ns.db.goal = math.floor(n)
  if ns.RefreshUI then ns.RefreshUI() end
  return true
end

local function EditBoxOf(self)
  return self.editBox or self.EditBox or (self.GetEditBox and self:GetEditBox())
end

StaticPopupDialogs["WRITPRICE_GOAL"] = {
  text = "",
  button1 = OKAY or "OK",
  button2 = CANCEL or "Cancel",
  hasEditBox = true,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
  preferredIndex = 3,
  OnAccept = function(self)
    local eb = EditBoxOf(self)
    if eb then ns.SetGoal(eb:GetText()) end
  end,
  OnShow = function(self)
    local eb = EditBoxOf(self)
    if not eb then return end
    eb:SetText(tostring((ns.db and ns.db.goal) or 0))
    eb:HighlightText()
    eb:SetFocus()
  end,
  EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
  EditBoxOnEnterPressed = function(self)
    local parent = self:GetParent()
    StaticPopupDialogs["WRITPRICE_GOAL"].OnAccept(parent)
    parent:Hide()
  end,
}

StaticPopupDialogs["WRITPRICE_QTY"] = {
  text = "",
  button1 = OKAY or "OK",
  button2 = CANCEL or "Cancel",
  hasEditBox = true,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
  preferredIndex = 3,
  OnAccept = function(self, writName)
    local eb = EditBoxOf(self)
    local n = eb and tonumber(eb:GetText())
    n = n and math.floor(n)
    if not (n and writName) then return end
    if n > 0 then
      ns.SetQty(writName, n, "manual")
    elseif n == 0 then
      ns.SetQty(writName, nil, nil)
    end
  end,
  OnShow = function(self, d)
    local eb = EditBoxOf(self)
    if not eb then return end
    d = d or self.data
    local w = ns.db and d and ns.db.writs[d]
    eb:SetText(w and w.qty and tostring(w.qty) or "")
    eb:HighlightText()
    eb:SetFocus()
  end,
  EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
  EditBoxOnEnterPressed = function(self)
    local parent = self:GetParent()
    StaticPopupDialogs["WRITPRICE_QTY"].OnAccept(parent, parent.data)
    parent:Hide()
  end,
}

------------------------------------------------------------
-- Helpers
------------------------------------------------------------
local function Ago(t)
  if not t then return L.AGO_NEVER end
  local m = math.floor((time() - t) / 60)
  if m < 1 then return L.AGO_NOW end
  if m < 60 then return ns.F("AGO_MIN", m) end
  if m < 2880 then return ns.F("AGO_H", math.floor(m / 60)) end
  return ns.F("AGO_D", math.floor(m / 1440))
end
ns.Ago = Ago

-- Age of the last saved scan (tooltips, broker)
function ns.LastScanText()
  local sc = ns.CurrentScan and ns.CurrentScan()
  if not (sc and sc.t) then return L.UI_NO_SCAN_SAVED end
  return ns.F("UI_LAST_SCAN", Ago(sc.t))
end

-- Wrapped tooltip lines need a minimum width, otherwise the tooltip becomes a narrow column
local function TipMinWidth(w)
  if GameTooltip.SetMinimumWidth then pcall(GameTooltip.SetMinimumWidth, GameTooltip, w) end
end

local function TipTitle(owner, text)
  GameTooltip:SetOwner(owner, "ANCHOR_TOP")
  TipMinWidth(320)
  GameTooltip:AddLine(text, 1, 0.82, 0)
end

local function TipHide()
  TipMinWidth(0)
  GameTooltip:Hide()
end

local function HexColor(hex)
  hex = hex or "ffffff"
  return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
end

local function SearchInAH(name)
  if ns.IsScanning and ns.IsScanning() then
    ns.Print(L.CHAT_SEARCH_BUSY)
    return
  end
  name = ns.Disp(name) -- the auction house searches in the client language
  local bar = AuctionHouseFrame and AuctionHouseFrame:IsShown() and AuctionHouseFrame.SearchBar
  if bar and bar.SearchBox then
    -- on another tab (Sell, Auctions, Auctionator...): go back to Buy first
    if not bar:IsVisible() then
      local tab = AuctionHouseFrameBuyTab
      if tab and tab.Click then pcall(tab.Click, tab) end
      if not bar:IsVisible() and AuctionHouseFrame.SetDisplayMode
         and AuctionHouseFrameDisplayMode and AuctionHouseFrameDisplayMode.Buy then
        pcall(AuctionHouseFrame.SetDisplayMode, AuctionHouseFrame, AuctionHouseFrameDisplayMode.Buy)
      end
    end
    bar.SearchBox:SetText(name)
    if bar.StartSearch then bar:StartSearch() end
    if not bar:IsVisible() then ns.Print(ns.F("CHAT_SEARCH_SWITCH_TAB", name)) end
    return
  end
  if BrowseName and AuctionFrameBrowse and AuctionFrameBrowse:IsShown() then
    BrowseName:SetText(name)
    if AuctionFrameBrowse_Search then AuctionFrameBrowse_Search() end
  else
    ns.Print(ns.F("CHAT_SEARCH_OPEN_AH", name))
  end
end

local function Visible(c)
  return not (c.optional and ns.db and ns.db.colOff and ns.db.colOff[c.key])
end

------------------------------------------------------------
-- Cell texts
------------------------------------------------------------
local function CellText(row, key)
  if key == "rank" then
    return row.rank and (row.rank .. " " .. row.rep) or "?"
  elseif key == "item" then
    local s = ns.Disp(row.item or row.name)
    if row.noItem then s = s .. " |cffff6060" .. L.CELL_NOT_ON_AH .. "|r" end
    if row.notScanned then s = s .. " |cff999999" .. L.CELL_NOT_SCANNED .. "|r" end
    if row.done then s = s .. " |cffff6060" .. L.CELL_DONE .. "|r" end
    if row.ready then
      s = s .. " |cff40ff40" .. L.CELL_READY .. "|r"
    elseif row.active then
      s = s .. " |cff4fc3ff" .. ns.F("CELL_ACTIVE", tostring(row.have or 0), tostring(row.qty or "?")) .. "|r"
    end
    return s
  elseif key == "qty" then
    if row.qtyEst then return "|cff999999" .. row.qty .. "?|r" end
    return tostring(row.qty)
  elseif key == "writ" then
    if row.active then return "|cff4fc3ff" .. L.CELL_OWNED .. "|r" end
    return ns.Coins(row.writMin)
  elseif key == "unit" then
    if not row.unit then return "-" end
    return ns.Coins(row.unit) .. (row.unitOld and "|cff999999~|r" or "") .. (row.unitAtr and "|cff8fa8ffA|r" or "")
  elseif key == "craft" then
    if not row.hasRecipe then return "|cff666666-|r" end
    if not row.craft then return "|cff999999?|r" end
    local cheaper = (not row.unit) or row.craft < row.unit
    return (cheaper and "|cff40ff40" or "") .. ns.Coins(row.craft) .. (cheaper and "|r" or "")
  elseif key == "zone" then
    if not row.zone then return "|cff666666?|r" end
    return (row.destSrc == "quest" and "|cffffd080" or "|cffd0b070") .. row.zone .. "|r"
  elseif key == "recipe" then
    if not row.recipeCode then return "|cff666666-|r" end
    return "|cff" .. row.recipeColor .. row.recipeShort .. "|r"
  elseif key == "total" then
    if not row.total then return "-" end
    return (row.viaCraft and "|cff40ff40" or "") .. ns.Coins(row.total) .. (row.viaCraft and "|r" or "")
      .. (row.qtyEst and "|cff999999*|r" or "")
  elseif key == "pouch" then
    if not row.pouch then return "|cff666666-|r" end
    return "|cff40ff40" .. ns.Coins(row.pouch) .. "|r"
  elseif key == "rep" then
    return row.perRep and ns.Coins(row.perRep) or "-"
  end
end

------------------------------------------------------------
-- Refresh
------------------------------------------------------------
function ns.RefreshUI()
  if not frame or not frame:IsShown() then return end
  ns.Safe(function()
    local t
    data, t = ns.BuildRows(filter)
    headers.zone:SetText(L.COL_zone .. (ns.ZoneFilterActive() and " |cff40ff40*|r" or ""))
    FauxScrollFrame_Update(scroll, #data, NUM_ROWS, ROW_H)
    local offset = FauxScrollFrame_GetOffset(scroll)
    for i = 1, NUM_ROWS do
      local btn = rows[i]
      local row = data[i + offset]
      if row then
        btn.row = row
        local dim = row.done or not row.perRep
        for _, c in ipairs(COLS) do
          local fs = btn.cells[c.key]
          if Visible(c) then
            fs:SetText(CellText(row, c.key))
            if dim then fs:SetTextColor(0.6, 0.6, 0.6) else fs:SetTextColor(1, 1, 1) end
          end
        end
        btn:Show()
      else
        btn.row = nil
        btn:Hide()
      end
    end
    for key, b in pairs(filterBtns) do
      if key == filter then b:LockHighlight() else b:UnlockHighlight() end
    end

    -- empty list: tell the player what to do
    if #data == 0 then
      if not t then
        empty:SetText(L.EMPTY_TITLE .. "\n\n" .. L.EMPTY_STEP1 .. "\n" .. L.EMPTY_STEP2 .. "\n" .. L.EMPTY_STEP3)
      elseif ns.ProfCount() == 0 then
        empty:SetText(L.EMPTY_NO_PROF)
      else
        empty:SetText(L.EMPTY_FILTERED)
      end
      empty:Show()
    else
      empty:Hide()
    end

    local scanning = ns.IsScanning and ns.IsScanning()
    local msg
    if scanning and ns.scanStatus then
      msg = ns.scanStatus
    elseif not t then
      msg = L.UI_NO_SCAN_SAVED
    else
      msg = ns.F("UI_LAST_SCAN", Ago(t)) .. "  -  " .. ns.Plural(#data, "UI_ROWS")
    end
    status:SetText(msg)

    -- reputation waiting in accepted writ quests (+ current standing when found)
    local np, rp, nr, rr, unk = ns.PendingRep()
    local parts = {}
    local label, cur, size = ns.FactionStanding()
    if label then parts[#parts + 1] = ns.F("UI_ACA", label, cur or 0, size or 0) end
    if np > 0 then
      local s = "|cff4fc3ff" .. ns.Plural(np, "UI_PENDING", rp) .. "|r"
      if nr > 0 then s = s .. " |cff40ff40" .. ns.F("UI_PENDING_READY", nr, rr) .. "|r" end
      if unk > 0 then s = s .. " |cff999999" .. ns.F("UI_PENDING_UNKNOWN", unk) .. "|r" end
      parts[#parts + 1] = s
    else
      parts[#parts + 1] = "|cff999999" .. L.UI_NO_PENDING .. "|r"
    end
    pending:SetText(table.concat(parts, "   -   "))

    -- today's plan: the cheapest writs that reach the goal
    local goal, tier = ns.GetGoal()
    local goalText = tier and ns.F("UI_GOAL_TEXT_TIER", goal, tier) or ns.F("UI_GOAL_TEXT", goal)
    local n, rep, cost, est, reached = ns.Plan(data, goal)
    local star = est and " |cff999999*|r" or ""
    if n == 0 then
      plan:SetText("")
    elseif reached then
      plan:SetText(ns.Plural(n, "UI_PLAN_OK", rep, ns.Coins(cost), star, goalText))
    else
      plan:SetText(ns.F("UI_PLAN_SHORT", n, rep, ns.Coins(cost), star, goalText))
    end

    scanBtn:SetText(scanning and L.UI_BTN_STOP or L.UI_BTN_SCAN)
    if scanning or (ns.AHOpen and ns.AHOpen()) then scanBtn:Enable() else scanBtn:Disable() end
    craftBtn:SetText(ns.db.useCraft and L.UI_BTN_CRAFT_ON or L.UI_BTN_CRAFT_OFF)
    goalBtn:SetText((ns.db.goal and ns.db.goal > 0) and ns.F("UI_BTN_GOAL", ns.db.goal) or L.UI_BTN_GOAL_TIER)
    profBtn:SetText(ns.F("UI_BTN_PROFS", ns.ProfSummary()))
    if profMenu and profMenu:IsShown() then profMenu:Refresh() end
    if colsMenu and colsMenu:IsShown() then colsMenu:Refresh() end
  end)
end

-- True when the cursor is over the "Requested item", "Item each" or "Craft each" columns
local function ItemZone(btn)
  local left = btn:GetLeft()
  if not left then return false end
  local x = GetCursorPosition() / btn:GetEffectiveScale() - left
  local cx = 4
  for _, c in ipairs(COLS) do
    if Visible(c) then
      if x >= cx and x < cx + c.w + 6 then
        return c.key == "item" or c.key == "unit" or c.key == "craft"
      end
      cx = cx + c.w + 6
    end
  end
  return false
end

local function ResetScroll()
  if not scroll then return end
  FauxScrollFrame_SetOffset(scroll, 0)
  local sb = scroll.ScrollBar or _G["WritPriceScrollScrollBar"]
  if sb and sb.SetValue then sb:SetValue(0) end
end

------------------------------------------------------------
-- Column layout and window scale
------------------------------------------------------------
-- Keep the top-right corner where it is on screen when the width or the scale changes
local function Repin(newScale)
  local r, t, o = frame:GetRight(), frame:GetTop(), frame:GetScale()
  if not (r and t and o) then return end -- not shown yet
  local k = o / (newScale or o)
  frame:ClearAllPoints()
  frame:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", r * k, t * k)
  if ns.db.pos then ns.db.pos = { "TOPRIGHT", "BOTTOMLEFT", r * k, t * k } end
end

local function LayoutColumns()
  if not frame then return end
  -- spare width (many columns hidden) goes to the item column
  local used = 4
  for _, c in ipairs(COLS) do if Visible(c) then used = used + c.w + 6 end end
  local extra = math.max(0, MIN_WIDTH - 4 - used)
  local x = 4
  for _, c in ipairs(COLS) do
    local h = headers[c.key]
    local show = Visible(c)
    local w = c.w + ((c.key == "item") and extra or 0)
    h:SetWidth(w)
    h:ClearAllPoints()
    if show then
      h:SetPoint("TOPLEFT", frame, "TOPLEFT", 16 + x, LIST_TOP + 16)
      h:Show()
    else
      h:Hide()
    end
    if c.key == "zone" and zoneHdr then
      if show then zoneHdr:Show() else zoneHdr:Hide() end
    end
    for _, btn in ipairs(rows) do
      local fs = btn.cells[c.key]
      fs:ClearAllPoints()
      fs:SetWidth(w)
      if show then
        fs:SetPoint("LEFT", btn, "LEFT", x, 0)
        fs:Show()
      else
        fs:Hide()
      end
    end
    if show then x = x + w + 6 end
  end
  WIDTH = math.max(MIN_WIDTH, x + 4)
  Repin()
  frame:SetWidth(WIDTH + 40)
  scroll:SetWidth(WIDTH)
  for _, btn in ipairs(rows) do btn:SetWidth(WIDTH) end
  status:SetWidth(WIDTH - 280)
  plan:SetWidth(WIDTH)
  pending:SetWidth(WIDTH)
  empty:SetWidth(WIDTH - 80)
  if ns.ApplyScale then ns.ApplyScale() end
end

function ns.ApplyScale()
  if not frame then return end
  local s = (ns.db and tonumber(ns.db.scale)) or 1
  local parentW = 1365
  pcall(function() parentW = tonumber(UIParent:GetWidth()) or parentW end)
  local fw = WIDTH + 40
  if fw * s > parentW - 20 then s = (parentW - 20) / fw end
  if s < 0.5 then s = 0.5 elseif s > 1.5 then s = 1.5 end
  if math.abs((frame:GetScale() or 1) - s) > 0.001 then
    Repin(s)
    pcall(frame.SetScale, frame, s)
  end
  ns.effectiveScale = s
  return s
end

------------------------------------------------------------
-- Small check-box menu (own frame: no Blizzard menu API, so no taint)
------------------------------------------------------------
function ns.MakeCheck(parent)
  local ok, cb = pcall(CreateFrame, "CheckButton", nil, parent, "UICheckButtonTemplate")
  if not ok or not cb then
    cb = CreateFrame("CheckButton", nil, parent)
    cb:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
    cb:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
    cb:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
    cb:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
  end
  cb:SetSize(22, 22)
  local own = cb.text or cb.Text
  if own and own.SetText then pcall(own.SetText, own, "") end
  return cb
end

-- keys: list of keys; label(key) -> text; get(key) -> bool; set(key, bool); setAll(bool) optional
local function BuildCheckMenu(name, anchor, keys, label, get, set, setAll, rowH)
  local ROWH, W = rowH or 22, 190
  local n = #keys
  local m = CreateFrame("Frame", name, frame)
  local extra = setAll and (8 + 22 * 2 + 6) or 0
  m:SetSize(W, 12 + n * ROWH + extra + 4)
  m:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
  m:SetFrameStrata("FULLSCREEN_DIALOG")
  m:EnableMouse(true)
  m:SetClampedToScreen(true)
  local border = m:CreateTexture(nil, "BACKGROUND")
  border:SetAllPoints()
  border:SetColorTexture(0.6, 0.5, 0.2, 1)
  local bg = m:CreateTexture(nil, "BORDER")
  bg:SetPoint("TOPLEFT", 1, -1)
  bg:SetPoint("BOTTOMRIGHT", -1, 1)
  bg:SetColorTexture(0.05, 0.05, 0.08, 0.97)

  local checks, labels = {}, {}
  local function Changed()
    ResetScroll()
    if name == "WritPriceColsMenu" then LayoutColumns() end
    ns.RefreshUI()
  end

  for i, key in ipairs(keys) do
    local cb = ns.MakeCheck(m)
    cb:SetPoint("TOPLEFT", 8, -6 - (i - 1) * ROWH)
    cb:SetScript("OnClick", function(self)
      ns.Safe(function()
        set(key, self:GetChecked() and true or false)
        Changed()
      end)
    end)
    local lab = CreateFrame("Button", nil, m)
    lab:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    lab:SetSize(W - 44, ROWH)
    local fs = lab:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("LEFT", 0, 0)
    lab:SetScript("OnClick", function()
      ns.Safe(function()
        set(key, not get(key))
        Changed()
      end)
    end)
    checks[key], labels[key] = cb, fs
  end

  local allBtn, noneBtn
  if setAll then
    allBtn = CreateFrame("Button", nil, m, "UIPanelButtonTemplate")
    allBtn:SetSize(W - 16, 20)
    allBtn:SetPoint("TOPLEFT", 8, -6 - n * ROWH - 6)
    allBtn:SetScript("OnClick", function() ns.Safe(function() setAll(true); Changed() end) end)
    noneBtn = CreateFrame("Button", nil, m, "UIPanelButtonTemplate")
    noneBtn:SetSize(W - 16, 20)
    noneBtn:SetPoint("TOPLEFT", allBtn, "BOTTOMLEFT", 0, -4)
    noneBtn:SetScript("OnClick", function() ns.Safe(function() setAll(false); Changed() end) end)
  end

  -- a click outside the menu closes it (invisible full-screen button under the menu)
  local catcher = CreateFrame("Button", nil, frame)
  catcher:SetAllPoints(UIParent)
  catcher:SetFrameStrata("FULLSCREEN")
  catcher:RegisterForClicks("AnyUp")
  catcher:SetScript("OnClick", function() m:Hide() end)
  catcher:Hide()
  m:SetScript("OnHide", function() catcher:Hide() end)

  function m:Refresh()
    for key, cb in pairs(checks) do cb:SetChecked(get(key)) end
  end
  function m:Relabel()
    for key, fs in pairs(labels) do fs:SetText(label(key)) end
    if allBtn then
      allBtn:SetText(L.UI_CHECK_ALL)
      noneBtn:SetText(L.UI_CHECK_NONE)
    end
  end
  function m:Toggle()
    if self:IsShown() then
      self:Hide()
    else
      self:Relabel()
      self:Refresh()
      -- the window strata may have changed (opened from the settings): keep the menu above it
      self:SetFrameStrata("FULLSCREEN_DIALOG")
      catcher:SetFrameStrata("FULLSCREEN")
      catcher:Show()
      self:Show()
    end
  end
  m:Relabel()
  m:Hide()
  return m
end

local function ZoneLabel(z) return z == "?" and L.ZONE_UNKNOWN or z end
local function ToggleZoneMenu()
  if not zoneMenu then
    zoneMenu = BuildCheckMenu("WritPriceZoneMenu", zoneHdr, ns.ZoneList(), ZoneLabel,
      function(k) return ns.ZoneWanted(k) end, ns.SetZone, ns.SetAllZones, 18)
  end
  zoneMenu:Toggle()
end
ns.ToggleZoneMenu = ToggleZoneMenu

local function ToggleProfMenu()
  if not profMenu then
    profMenu = BuildCheckMenu("WritPriceProfMenu", profBtn, ns.PROFS, ns.ProfName,
      function(k) return ns.ProfWanted(k) end, ns.SetProf, ns.SetAllProfs)
  end
  profMenu:Toggle()
end

local OPTIONAL_COLS = {}
for _, c in ipairs(COLS) do if c.optional then OPTIONAL_COLS[#OPTIONAL_COLS + 1] = c.key end end
ns.OPTIONAL_COLS = OPTIONAL_COLS

-- Re-layout after a column or scale change made outside the window (options page)
function ns.LayoutUI()
  if not frame then return end
  ResetScroll()
  LayoutColumns()
  if colsMenu and colsMenu:IsShown() then colsMenu:Refresh() end
  ns.RefreshUI()
end

function ns.ToggleColsMenu()
  if not frame then return end
  if not colsMenu then
    colsMenu = BuildCheckMenu("WritPriceColsMenu", colsBtn, OPTIONAL_COLS,
      function(k) return L["COL_" .. k] end,
      function(k) return not ns.db.colOff[k] end,
      function(k, on) ns.db.colOff[k] = (not on) or nil end)
    colsMenu:ClearAllPoints()
    colsMenu:SetPoint("BOTTOMRIGHT", colsBtn, "TOPRIGHT", 0, 2)
  end
  colsMenu:Toggle()
end

------------------------------------------------------------
-- Texts that depend on the language
------------------------------------------------------------
function ns.ApplyLocale()
  for _, fn in ipairs(ns.OnLocale) do ns.Safe(fn) end
  StaticPopupDialogs.WRITPRICE_GOAL.text = L.POPUP_GOAL
  StaticPopupDialogs.WRITPRICE_QTY.text = L.POPUP_QTY
  StaticPopupDialogs.WRITPRICE_GOAL.button2 = CANCEL or L.CANCEL
  StaticPopupDialogs.WRITPRICE_QTY.button2 = CANCEL or L.CANCEL
  if not frame then return end
  title:SetText(ns.F("UI_TITLE", ns.VERSION))
  for _, c in ipairs(COLS) do headers[c.key]:SetText(L["COL_" .. c.key]) end
  if zoneMenu then zoneMenu:Relabel() end
  if filterBtns.ALL then filterBtns.ALL:SetText(L.UI_FILTER_ALL) end
  colsBtn:SetText(L.UI_BTN_COLS)
  if profMenu then profMenu:Relabel() end
  if colsMenu then colsMenu:Relabel() end
  ns.RefreshUI()
end

------------------------------------------------------------
-- Row tooltip
------------------------------------------------------------
-- Row tooltip: short by default (header, costs, turn-in, status), details while Shift is held
local function CostLine(label, copper, r, g, b)
  GameTooltip:AddDoubleLine(label, copper and ns.Coins(copper) or "|cff999999-|r", r or 0.85, g or 0.85, b or 0.85, 1, 1, 1)
end

local function RowTooltip(self)
  local row = self.row
  if not row then return end
  local details = IsShiftKeyDown and IsShiftKeyDown()
  local overItem = ItemZone(self) and row.item ~= nil
  self.tipState = (details and "d" or "") .. (overItem and "i" or "w")
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  TipMinWidth(300)

  -- header: writ, rank and reputation; profession or recipe status
  GameTooltip:AddDoubleLine(ns.Disp(row.name),
    row.rank and ns.F("TT2_RANK", row.rank, row.rep or 0) or "", 1, 0.82, 0, 0.6, 0.6, 0.6)
  if row.recipeLong then
    local r, g, b = HexColor(row.recipeColor)
    GameTooltip:AddLine(row.recipeLong, r, g, b, true)
  elseif row.prof then
    GameTooltip:AddLine(ns.ProfName(row.prof), 0.6, 0.8, 1)
  end
  if row.done then
    GameTooltip:AddLine(L.ROW_DONE_TODAY, 1, 0.4, 0.4)
  elseif row.ready then
    GameTooltip:AddLine(L.ROW_QUEST_READY, 0.25, 1, 0.25)
  elseif row.active then
    GameTooltip:AddLine(ns.F("TT2_ACTIVE", row.have or 0, row.qty or 0), 0.3, 0.76, 1)
  end

  -- costs
  GameTooltip:AddLine(" ")
  if row.active then
    GameTooltip:AddDoubleLine(L.TT2_WRIT, L.TT2_OWNED, 0.85, 0.85, 0.85, 0.6, 0.6, 0.6)
  else
    local lab = L.TT2_WRIT .. (row.writCount and (" |cff999999" .. ns.F("TT2_FOR_SALE", row.writCount) .. "|r") or "")
    CostLine(lab, row.writMin)
  end
  if row.item then
    local n = row.active and (row.remaining or 0) or (row.qty or 1)
    local best = row.viaCraft and row.craft or row.unit
    local mark = (row.qtyEst and "?" or "") .. (row.unitOld and " ~" or "") .. (row.unitAtr and " A" or "")
      .. (row.viaCraft and (" |cff40ff40" .. L.TT2_CRAFTED .. "|r") or "")
    local lab = ("%s x%d%s"):format(ns.Disp(row.item), n, mark)
    if best then
      CostLine(lab, best * n)
    else
      GameTooltip:AddDoubleLine(lab, "|cff999999" .. (row.notScanned and L.TT2_NOT_SCANNED or L.TT2_NOT_FOR_SALE) .. "|r",
        0.85, 0.85, 0.85, 1, 1, 1)
    end
  end
  if row.pouch and row.total and ns.db.usePouch ~= false then
    GameTooltip:AddDoubleLine((row.pouchN or 0) > 0 and L.TT2_POUCH or L.TT2_POUCH_EST,
      "-" .. ns.Coins(row.pouch), 0.25, 1, 0.25, 0.25, 1, 0.25)
  end
  CostLine(L.TT2_TOTAL, row.net or row.total, 1, 1, 1)
  if row.perRep then
    GameTooltip:AddDoubleLine(L.TT2_PER_POINT, ns.Coins(row.perRep), 1, 0.82, 0, 1, 0.82, 0)
  end

  -- crafting: one line, the reagents with details
  if row.hasRecipe and ns.AddCraftLines then
    if details then
      GameTooltip:AddLine(" ")
      ns.AddCraftLines(GameTooltip, row.item, row.qty)
    elseif row.craft then
      GameTooltip:AddDoubleLine(ns.F("TT2_CRAFT", ns.ProfLabel(row.recipe)), ns.F("TT2_EACH", ns.Coins(row.craft)),
        0.4, 1, 0.4, 0.4, 1, 0.4)
    end
  end

  -- turn-in place
  if row.dest then
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(ns.F("ROW_TURNIN", row.dest), 1, 0.82, 0.5, true)
  end

  -- details: where the numbers come from
  if details then
    GameTooltip:AddLine(" ")
    local function note(t) GameTooltip:AddLine(t, 0.7, 0.7, 0.7, true) end
    if row.qtyEst then note(L.ROW_QTY_EST)
    elseif row.qtySrc == "quest" then note(ns.F("ROW_QTY_QUEST", row.qty))
    elseif row.qtySrc == "manual" then note(ns.F("ROW_QTY_MANUAL", row.qty))
    elseif row.qtyGuide then note(ns.F("ROW_QTY_GUIDE", row.qty)) end
    if row.unitOld then note(ns.F("ROW_OLD_PRICE", Ago(row.unitOld))) end
    if row.unitAtr then note(row.unitAtr >= 0 and ns.F("ROW_ATR_PRICE", row.unitAtr) or L.ROW_ATR_PRICE_NOAGE) end
    if row.pouch then
      note((row.pouchN or 0) > 0 and ns.F("ROW_POUCH", ns.Coins(row.pouch), row.pouchN)
        or ns.F("ROW_POUCH_DEFAULT", ns.Coins(row.pouch)))
    else
      note(L.ROW_POUCH_NONE)
    end
    if row.notScanned then note(L.ROW_NOT_SCANNED_WHY) end
    if row.partial then note(L.ROW_PARTIAL) end
    if row.destSrc == "guide" then note(L.ROW_DEST_GUIDE)
    elseif not row.dest then note(L.ROW_DEST_UNKNOWN) end
  end

  -- what a click does here
  GameTooltip:AddLine(" ")
  local hint = overItem and ns.F("TT2_HINT_ITEM", ns.Disp(row.item)) or L.TT2_HINT_WRIT
  GameTooltip:AddLine(hint .. "  |cff999999" .. L.TT2_HINT_RIGHT .. (details and "" or ("  " .. L.TT2_HINT_SHIFT)) .. "|r",
    0.5, 0.8, 1)
  GameTooltip:Show()
end

-- Redraw the tooltip when the cursor moves between the item and the writ part, or Shift changes
local function RowTipUpdate(self, elapsed)
  self.tipT = (self.tipT or 0) + (elapsed or 0)
  if self.tipT < 0.1 then return end
  self.tipT = 0
  if not (self.row and GameTooltip:IsOwned(self)) then return end
  local state = ((IsShiftKeyDown and IsShiftKeyDown()) and "d" or "") .. ((ItemZone(self) and self.row.item) and "i" or "w")
  if state ~= self.tipState then ns.Safe(RowTooltip, self) end
end

------------------------------------------------------------
-- Row menu (right-click)
------------------------------------------------------------
local rowMenu
local function RowMenu(btn)
  local row = btn.row
  if not row then return end
  if not rowMenu then
    local m = CreateFrame("Frame", "WritPriceRowMenu", UIParent)
    m:SetFrameStrata("FULLSCREEN_DIALOG")
    m:EnableMouse(true)
    m:SetClampedToScreen(true)
    local border = m:CreateTexture(nil, "BACKGROUND")
    border:SetAllPoints()
    border:SetColorTexture(0.6, 0.5, 0.2, 1)
    local bg = m:CreateTexture(nil, "BORDER")
    bg:SetPoint("TOPLEFT", 1, -1)
    bg:SetPoint("BOTTOMRIGHT", -1, 1)
    bg:SetColorTexture(0.05, 0.05, 0.08, 0.97)
    m.title = m:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    m.title:SetPoint("TOPLEFT", 10, -8)
    m.title:SetJustifyH("LEFT")
    m.items = {}
    local catcher = CreateFrame("Button", nil, UIParent)
    catcher:SetAllPoints(UIParent)
    catcher:SetFrameStrata("FULLSCREEN")
    catcher:RegisterForClicks("AnyUp")
    catcher:SetScript("OnClick", function() m:Hide() end)
    catcher:Hide()
    m:SetScript("OnShow", function() catcher:Show() end)
    m:SetScript("OnHide", function() catcher:Hide() end)
    m:Hide()
    tinsert(UISpecialFrames, "WritPriceRowMenu")
    rowMenu = m
  end
  local m = rowMenu
  local entries = {
    { L.MENU_SEARCH_WRIT, function() SearchInAH(row.name) end },
  }
  if row.item then
    entries[#entries + 1] = { ns.F("MENU_SEARCH_ITEM", ns.Disp(row.item)), function() SearchInAH(row.item) end }
  end
  entries[#entries + 1] = { L.MENU_QTY, function()
    local dlg = StaticPopup_Show("WRITPRICE_QTY", ns.Disp(row.name), nil, row.name)
    if dlg then dlg.data = row.name end
  end }
  local canMap = ns.TurnInPoint and ns.TurnInPoint(row.name)
  entries[#entries + 1] = { canMap and L.MENU_MAP or ("|cff808080" .. L.MENU_MAP .. "|r"), canMap and function()
    ns.ShowTurnIn(row.name)
  end or nil }
  m.title:SetText(ns.Disp(row.name))
  local W = math.max(220, m.title:GetStringWidth() + 20)
  for i, e in ipairs(entries) do
    local b = m.items[i]
    if not b then
      b = CreateFrame("Button", nil, m)
      b:SetHeight(20)
      b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
      b.fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      b.fs:SetPoint("LEFT", 10, 0)
      m.items[i] = b
    end
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", 1, -24 - (i - 1) * 20)
    b:SetPoint("RIGHT", m, "RIGHT", -1, 0)
    b.fs:SetText(e[1])
    W = math.max(W, b.fs:GetStringWidth() + 24)
    b:SetScript("OnClick", function()
      m:Hide()
      if e[2] then ns.Safe(e[2]) end
    end)
    b:SetEnabled(e[2] ~= nil)
    b:Show()
  end
  for i = #entries + 1, #m.items do m.items[i]:Hide() end
  m:SetSize(W, 30 + #entries * 20)
  m:ClearAllPoints()
  local x, y = GetCursorPosition()
  local sc = UIParent:GetEffectiveScale()
  m:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / sc - 4, y / sc + 4)
  TipHide()
  m:Show()
end

------------------------------------------------------------
-- Window
------------------------------------------------------------
local function Button(w, text)
  local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  b:SetSize(w, 22)
  if text then b:SetText(text) end
  b:SetScript("OnLeave", TipHide)
  return b
end

local function Build()
  frame = CreateFrame("Frame", "WritPriceFrame", UIParent, "BasicFrameTemplateWithInset")
  frame:SetSize(WIDTH + 40, 172 + NUM_ROWS * ROW_H)
  local pos = ns.db.pos
  if type(pos) == "table" and pos[1] and pos[2] and tonumber(pos[3]) and tonumber(pos[4]) then
    frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
  else
    frame:SetPoint("CENTER")
  end
  frame:SetMovable(true)
  frame:SetClampedToScreen(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint(1)
    if p then ns.db.pos = { p, rp, x, y } end
  end)
  frame:SetFrameStrata("HIGH")
  if frame.SetToplevel then frame:SetToplevel(true) end
  frame:Hide()
  tinsert(UISpecialFrames, "WritPriceFrame")

  title = frame.TitleText or frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  if not frame.TitleText then title:SetPoint("TOP", 0, -5) end

  -- Rank filters
  local ranks = { "ALL", "Journeyman", "Expert", "Artisan" }
  local prev
  for _, key in ipairs(ranks) do
    local b = Button(84, key)
    if prev then b:SetPoint("LEFT", prev, "RIGHT", 6, 0) else b:SetPoint("TOPLEFT", 16, -32) end
    b:SetScript("OnClick", function()
      filter = key
      ResetScroll()
      ns.RefreshUI()
    end)
    filterBtns[key] = b
    prev = b
  end

  -- Profession filter
  profBtn = Button(130)
  profBtn:SetPoint("LEFT", prev, "RIGHT", 8, 0)
  profBtn:SetScript("OnClick", function() ns.Safe(ToggleProfMenu) end)
  profBtn:SetScript("OnEnter", function(self)
    TipTitle(self, L.TIP_PROF_1)
    GameTooltip:AddLine(L.TIP_PROF_2, 1, 1, 1, true)
    GameTooltip:AddLine(L.TIP_PROF_3, 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
  end)

  -- Scan
  scanBtn = Button(100)
  scanBtn:SetPoint("TOPRIGHT", -20, -32)
  scanBtn:SetScript("OnClick", function()
    if ns.IsScanning() then
      ns.Safe(ns.StopScan)
    else
      ns.Safe(ns.StartAutoScan, IsShiftKeyDown and IsShiftKeyDown())
    end
  end)
  scanBtn:SetScript("OnEnter", function(self)
    TipTitle(self, L.TIP_SCAN_1)
    GameTooltip:AddLine(L.TIP_SCAN_2, 1, 1, 1, true)
    GameTooltip:AddLine(L.TIP_SCAN_3, 0.7, 0.7, 0.7, true)
    GameTooltip:AddLine(L.TIP_SCAN_4, 0.7, 0.7, 0.7, true)
    GameTooltip:AddLine(ns.LastScanText(), 0.4, 1, 0.4)
    if ns.FullScanText then GameTooltip:AddLine(ns.FullScanText(), 0.56, 0.66, 1) end
    if ns.AtrAvailable and ns.AtrAvailable() then GameTooltip:AddLine(L.TIP_SCAN_ATR, 0.56, 0.66, 1, true) end
    GameTooltip:AddLine(L.TIP_SCAN_SHIFT, 0.7, 0.7, 0.7, true)
    if not (ns.AHOpen and ns.AHOpen()) then GameTooltip:AddLine(L.TIP_SCAN_AH_CLOSED, 1, 0.4, 0.4) end
    GameTooltip:Show()
  end)
  if scanBtn.SetMotionScriptsWhileDisabled then pcall(scanBtn.SetMotionScriptsWhileDisabled, scanBtn, true) end

  -- Count crafting in the total when it is cheaper than buying
  craftBtn = Button(120)
  craftBtn:SetPoint("RIGHT", scanBtn, "LEFT", -6, 0)
  craftBtn:SetScript("OnClick", function()
    ns.db.useCraft = not ns.db.useCraft or nil
    ns.RefreshUI()
  end)
  craftBtn:SetScript("OnEnter", function(self)
    TipTitle(self, L.TIP_CRAFT_1)
    GameTooltip:AddLine(L.TIP_CRAFT_2, 1, 1, 1, true)
    GameTooltip:AddLine(L.TIP_CRAFT_3, 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
  end)

  -- Bottom-right: help, goal, columns
  helpBtn = Button(24, "?")
  helpBtn:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 10)
  helpBtn:SetScript("OnClick", function() SlashCmdList.WRITPRICE("help") end)
  helpBtn:SetScript("OnEnter", function(self)
    TipTitle(self, L.TIP_HELP_TITLE)
    for i = 1, 8 do
      local line = L["TIP_HELP_" .. i]
      if line ~= "TIP_HELP_" .. i then GameTooltip:AddLine(line, 1, 1, 1, true) end
    end
    GameTooltip:Show()
  end)

  goalBtn = Button(130)
  goalBtn:SetPoint("RIGHT", helpBtn, "LEFT", -6, 0)
  goalBtn:SetScript("OnClick", function() StaticPopup_Show("WRITPRICE_GOAL") end)
  goalBtn:SetScript("OnEnter", function(self)
    TipTitle(self, L.TIP_GOAL_1)
    GameTooltip:AddLine(L.TIP_GOAL_2, 1, 1, 1, true)
    GameTooltip:AddLine(L.TIP_GOAL_3, 1, 1, 1, true)
    local g, tier = ns.GetGoal()
    GameTooltip:AddLine(ns.F("TIP_GOAL_CURRENT", tier and ns.F("UI_GOAL_TEXT_TIER", g, tier) or ns.F("UI_GOAL_TEXT", g)),
      0.7, 0.7, 0.7)
    GameTooltip:Show()
  end)

  colsBtn = Button(100)
  colsBtn:SetPoint("RIGHT", goalBtn, "LEFT", -6, 0)
  colsBtn:SetScript("OnClick", function() ns.Safe(ns.ToggleColsMenu) end)
  colsBtn:SetScript("OnEnter", function(self)
    TipTitle(self, L.TIP_COLS_1)
    GameTooltip:AddLine(L.TIP_COLS_2, 1, 1, 1, true)
    GameTooltip:Show()
  end)

  -- Column headers
  for _, c in ipairs(COLS) do
    local h = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    h:SetWidth(c.w)
    h:SetJustifyH(c.justify)
    headers[c.key] = h
  end
  -- the Zone header filters by turn-in zone
  zoneHdr = CreateFrame("Button", nil, frame)
  zoneHdr:SetPoint("TOPLEFT", headers.zone, "TOPLEFT", -2, 3)
  zoneHdr:SetPoint("BOTTOMRIGHT", headers.zone, "BOTTOMRIGHT", 2, -3)
  zoneHdr:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  zoneHdr:SetScript("OnClick", function() ns.Safe(ToggleZoneMenu) end)
  zoneHdr:SetScript("OnEnter", function(self)
    TipTitle(self, L.TIP_ZONE_1)
    GameTooltip:AddLine(L.TIP_ZONE_2, 1, 1, 1, true)
    GameTooltip:Show()
  end)
  zoneHdr:SetScript("OnLeave", TipHide)

  scroll = CreateFrame("ScrollFrame", "WritPriceScroll", frame, "FauxScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 16, LIST_TOP)
  scroll:SetSize(WIDTH, NUM_ROWS * ROW_H)
  scroll:SetScript("OnVerticalScroll", function(self, offset)
    FauxScrollFrame_OnVerticalScroll(self, offset, ROW_H, ns.RefreshUI)
  end)

  rows = {}
  for i = 1, NUM_ROWS do
    local btn = CreateFrame("Button", nil, frame)
    btn:SetSize(WIDTH, ROW_H)
    btn:SetPoint("TOPLEFT", 16, LIST_TOP - (i - 1) * ROW_H)
    btn:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn.cells = {}
    for _, c in ipairs(COLS) do
      local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      fs:SetWidth(c.w)
      fs:SetJustifyH(c.justify)
      fs:SetWordWrap(false)
      btn.cells[c.key] = fs
    end
    btn:SetScript("OnClick", function(self, mouse)
      if not self.row then return end
      if mouse == "RightButton" then
        RowMenu(self)
      elseif ItemZone(self) and self.row.item then
        SearchInAH(self.row.item)
      else
        SearchInAH(self.row.name)
      end
    end)
    btn:SetScript("OnEnter", function(self) ns.Safe(RowTooltip, self) end)
    btn:SetScript("OnUpdate", RowTipUpdate)
    btn:SetScript("OnLeave", TipHide)
    rows[i] = btn
  end

  -- empty-state text, centered on the list area
  empty = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  empty:SetPoint("TOP", frame, "TOP", 0, LIST_TOP - 60)
  empty:SetJustifyH("CENTER")
  empty:Hide()

  -- bottom lines: pending reputation, plan, status (buttons sit on the status line, on the right)
  pending = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  pending:SetPoint("BOTTOMLEFT", 20, 62)
  pending:SetJustifyH("LEFT")
  pending:SetWordWrap(false)

  plan = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  plan:SetPoint("BOTTOMLEFT", 20, 44)
  plan:SetJustifyH("LEFT")
  plan:SetWordWrap(false)

  status = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  status:SetPoint("BOTTOMLEFT", 20, 16)
  status:SetJustifyH("LEFT")
  status:SetWordWrap(false)

  frame:SetScript("OnShow", ns.RefreshUI)
  frame:HookScript("OnHide", function()
    if frame:GetFrameStrata() ~= "HIGH" then frame:SetFrameStrata("HIGH") end
    if profMenu then profMenu:Hide() end
    if colsMenu then colsMenu:Hide() end
    if zoneMenu then zoneMenu:Hide() end
  end)

  LayoutColumns()
  ns.ApplyLocale()
end

function ns.GetFilter() return filter end

-- fromOptions: opened from the settings page, so show it above that page until it is closed
function ns.ShowUI(fromOptions)
  if not frame then Build() end
  ns.ApplyScale()
  local above = fromOptions or (SettingsPanel and SettingsPanel:IsShown())
    or (InterfaceOptionsFrame and InterfaceOptionsFrame:IsShown())
  local strata = above and "DIALOG" or "HIGH"
  if frame:GetFrameStrata() ~= strata then frame:SetFrameStrata(strata) end
  frame:Show()
  if above and frame.Raise then frame:Raise() end
  ns.RefreshUI()
end

function ns.ToggleUI()
  if frame and frame:IsShown() then frame:Hide() else ns.ShowUI() end
end

-- /writs reset: default position, scale and columns
function ns.ResetUI()
  if not frame then return end
  frame:ClearAllPoints()
  frame:SetPoint("CENTER")
  if colsMenu then colsMenu:Hide() end
  LayoutColumns()
  ns.RefreshUI()
end
