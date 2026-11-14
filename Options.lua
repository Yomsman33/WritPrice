-- SPDX-License-Identifier: GPL-2.0-only
-- WritPrice: settings page (Options > AddOns > WritPrice). Own widgets only, changes apply immediately.
local ADDON, ns = ...
local L = ns.L

local panel = CreateFrame("Frame")
panel.name = "WritPrice" -- read by InterfaceOptions_AddCategory
panel:Hide()
panel.OnCommit = function() end  -- called by the Blizzard settings panel: must exist
panel.OnDefault = function() end -- our own "Reset the window" button is used instead
local categoryID, mode
local built, ready = false, false
local W = {} -- widgets to refresh: { kind, widget, get / set... }
local Refresh

------------------------------------------------------------
-- Popup: clear scanned prices
------------------------------------------------------------
StaticPopupDialogs["WRITPRICE_CLEAR"] = {
  text = "",
  button1 = OKAY or "OK",
  button2 = CANCEL or "Cancel",
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
  preferredIndex = 3,
  OnAccept = function() ns.Safe(ns.ClearScan) end,
}

------------------------------------------------------------
-- Widgets
------------------------------------------------------------
local function Text(parent, font, x, y, width)
  local fs = parent:CreateFontString(nil, "OVERLAY", font)
  fs:SetPoint("TOPLEFT", x, y)
  fs:SetJustifyH("LEFT")
  if width then fs:SetWidth(width) end
  return fs
end

local function Tip(owner, textKey, titleKey)
  owner:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if GameTooltip.SetMinimumWidth then pcall(GameTooltip.SetMinimumWidth, GameTooltip, 280) end
    GameTooltip:AddLine(titleKey and L[titleKey] or "WritPrice", 1, 0.82, 0)
    GameTooltip:AddLine(L[textKey], 1, 1, 1, true)
    GameTooltip:Show()
  end)
  owner:SetScript("OnLeave", function()
    if GameTooltip.SetMinimumWidth then pcall(GameTooltip.SetMinimumWidth, GameTooltip, 0) end
    GameTooltip:Hide()
  end)
end

-- check box + clickable label; get() -> bool, set(bool)
local function Check(x, y, labelKey, get, set, tipKey, enabled)
  local cb = ns.MakeCheck(panel)
  cb:SetPoint("TOPLEFT", x, y)
  local lab = CreateFrame("Button", nil, panel)
  lab:SetPoint("LEFT", cb, "RIGHT", 2, 0)
  lab:SetSize(284, 22)
  local fs = lab:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  fs:SetPoint("LEFT", 0, 0)
  fs:SetWidth(284)
  fs:SetJustifyH("LEFT")
  fs:SetWordWrap(false)
  local function Apply(on)
    ns.Safe(set, on)
    Refresh()
  end
  cb:SetScript("OnClick", function(self) Apply(self:GetChecked() and true or false) end)
  lab:SetScript("OnClick", function() if cb:IsEnabled() then Apply(not get()) end end)
  if tipKey then Tip(lab, tipKey, labelKey) Tip(cb, tipKey, labelKey) end
  W[#W + 1] = { kind = "check", cb = cb, fs = fs, key = labelKey, get = get, enabled = enabled }
  return cb
end

-- radio button: selected when get() == value
local function Radio(x, y, labelKey, value, get, set, width)
  local ok, rb = pcall(CreateFrame, "CheckButton", nil, panel, "UIRadioButtonTemplate")
  if not ok or not rb then
    rb = CreateFrame("CheckButton", nil, panel)
    rb:SetNormalTexture("Interface\\Buttons\\UI-RadioButton")
    rb:SetCheckedTexture("Interface\\Buttons\\UI-RadioButton")
    local n, c = rb:GetNormalTexture(), rb:GetCheckedTexture()
    if n then n:SetTexCoord(0, 0.25, 0, 1) end
    if c then c:SetTexCoord(0.25, 0.5, 0, 1) end
  end
  rb:SetSize(18, 18)
  rb:SetPoint("TOPLEFT", x, y)
  local own = rb.text or rb.Text
  if own and own.SetText then pcall(own.SetText, own, "") end
  local lab = CreateFrame("Button", nil, panel)
  lab:SetPoint("LEFT", rb, "RIGHT", 2, 0)
  lab:SetSize(width or 130, 20)
  local fs = lab:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  fs:SetPoint("LEFT", 0, 0)
  fs:SetWidth(width or 130)
  fs:SetJustifyH("LEFT")
  fs:SetWordWrap(false)
  local function Apply()
    ns.Safe(set, value)
    Refresh()
  end
  rb:SetScript("OnClick", Apply)
  lab:SetScript("OnClick", Apply)
  W[#W + 1] = { kind = "radio", cb = rb, fs = fs, key = labelKey, value = value, get = get }
end

-- bottom buttons are anchored to the bottom of the page (y = distance from the bottom)
local function PanelButton(x, y, w, labelKey, onClick, tipKey)
  local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  b:SetSize(w, 22)
  b:SetPoint("BOTTOMLEFT", x, y)
  b:SetScript("OnClick", function() ns.Safe(onClick) Refresh() end)
  if tipKey then Tip(b, tipKey) end
  W[#W + 1] = { kind = "button", b = b, key = labelKey }
  return b
end

local function Section(x, y, key)
  local fs = Text(panel, "GameFontNormal", x, y)
  W[#W + 1] = { kind = "label", fs = fs, key = key }
  return fs
end

------------------------------------------------------------
-- Page content
------------------------------------------------------------
local title, subtitle, scaleLabel, scaleNote, scaleSlider, goalBox, goalNow, colsNote, fullNow

local function SetLocaleChoice(v) ns.SetLocale(v) end
local function GetLocaleChoice() return (ns.db and ns.db.locale) or "auto" end

local function Build()
  if built then return end
  built = true
  local X1, X2 = 16, 330

  title = Text(panel, "GameFontNormalLarge", X1, -16)
  subtitle = Text(panel, "GameFontHighlightSmall", X1, -40, 600)

  -- left column -------------------------------------------------------
  Section(X1, -72, "OPT_SEC_GENERAL")
  local lang = Text(panel, "GameFontHighlight", X1, -96)
  W[#W + 1] = { kind = "label", fs = lang, key = "OPT_LANG" }
  Radio(X1 + 4, -116, "OPT_LANG_AUTO", "auto", GetLocaleChoice, SetLocaleChoice)
  Radio(X1 + 4, -138, "OPT_LANG_EN", "enUS", GetLocaleChoice, SetLocaleChoice)
  Radio(X1 + 4, -160, "OPT_LANG_FR", "frFR", GetLocaleChoice, SetLocaleChoice)

  scaleLabel = Text(panel, "GameFontHighlight", X1, -192, 290)
  scaleLabel:SetWordWrap(false)
  scaleNote = Text(panel, "GameFontDisableSmall", X1, -236, 290)
  scaleSlider = CreateFrame("Slider", "WritPriceOptionsScale", panel)
  scaleSlider:SetOrientation("HORIZONTAL")
  scaleSlider:SetSize(250, 16)
  scaleSlider:SetPoint("TOPLEFT", X1 + 4, -214)
  scaleSlider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
  local thumb = scaleSlider.GetThumbTexture and scaleSlider:GetThumbTexture()
  if thumb then thumb:SetSize(32, 32) end
  if scaleSlider.SetHitRectInsets then scaleSlider:SetHitRectInsets(0, 0, -8, -8) end
  local track = scaleSlider:CreateTexture(nil, "BACKGROUND")
  track:SetPoint("LEFT", 0, 0)
  track:SetPoint("RIGHT", 0, 0)
  track:SetHeight(6)
  track:SetColorTexture(0.25, 0.25, 0.3, 1)
  scaleSlider:SetMinMaxValues(50, 150)
  scaleSlider:SetValueStep(5)
  if scaleSlider.SetObeyStepOnDrag then pcall(scaleSlider.SetObeyStepOnDrag, scaleSlider, true) end
  scaleSlider:EnableMouse(true)
  scaleSlider:SetScript("OnValueChanged", function(self, v)
    if self.updating then return end
    ns.Safe(function()
      v = math.floor((tonumber(v) or 100) / 5 + 0.5) * 5
      ns.db.scale = (v ~= 100) and v / 100 or nil
      if ns.ApplyScale then ns.ApplyScale() end
      Refresh()
    end)
  end)

  Section(X1, -262, "OPT_SEC_ACCESS")
  Check(X1, -284, "OPT_MINIMAP_SHOW",
    function() return not ns.db.minimap.hide end,
    function(on) ns.db.minimap.hide = (not on) or nil; ns.UpdateMinimapButton() end,
    nil, function() return ns.HasMinimap and ns.HasMinimap() end)
  Check(X1, -308, "OPT_MINIMAP_LOCK",
    function() return ns.db.minimap.lock == true end,
    function(on) ns.db.minimap.lock = on or nil end,
    nil, function() return ns.HasMinimap and ns.HasMinimap() and not ns.db.minimap.hide end)
  Check(X1, -332, "OPT_AHBUTTON",
    function() return ns.db.ahButton ~= false end,
    function(on) ns.db.ahButton = (not on) and false or nil; ns.UpdateAHButtonVisibility() end)
  Check(X1, -356, "OPT_TOOLTIP",
    function() return ns.db.tooltip ~= false end,
    function(on) ns.db.tooltip = (not on) and false or nil end, "OPT_TOOLTIP_TIP")
  Check(X1, -380, "OPT_USEPOUCH",
    function() return ns.db.usePouch ~= false end,
    function(on) ns.db.usePouch = (not on) and false or nil; if ns.RefreshUI then ns.RefreshUI() end end,
    "OPT_USEPOUCH_TIP")
  Check(X1, -404, "OPT_SHARE",
    function() return ns.db.share ~= false end,
    function(on) ns.db.share = (not on) and false or nil end, "OPT_SHARE_TIP")

  -- right column ------------------------------------------------------
  Section(X2, -72, "OPT_SEC_PRICES")
  local modeLabel = Text(panel, "GameFontHighlight", X2, -94)
  W[#W + 1] = { kind = "label", fs = modeLabel, key = "OPT_SCANMODE" }
  local function GetMode() return ns.db.scanMode or "auto" end
  local function SetMode(v) ns.db.scanMode = (v ~= "auto") and v or nil end
  Radio(X2 + 4, -114, "OPT_SCANMODE_AUTO", "auto", GetMode, SetMode, 260)
  Radio(X2 + 4, -136, "OPT_SCANMODE_FULL", "full", GetMode, SetMode, 260)
  Radio(X2 + 4, -158, "OPT_SCANMODE_TARGETED", "targeted", GetMode, SetMode, 260)
  fullNow = Text(panel, "GameFontHighlightSmall", X2 + 4, -180, 270)
  Check(X2, -198, "OPT_REAGENTS",
    function() return not ns.db.noReagents end,
    function(on) ns.db.noReagents = (not on) or nil end, "OPT_REAGENTS_TIP")
  Check(X2, -222, "OPT_USECRAFT",
    function() return ns.db.useCraft == true end,
    function(on) ns.db.useCraft = on or nil; if ns.RefreshUI then ns.RefreshUI() end end, "TIP_CRAFT_2")
  Check(X2, -246, "OPT_ATR",
    function() return ns.db.useAtr ~= false end,
    function(on)
      ns.db.useAtr = (not on) and false or nil
      if ns.AtrClearCache then ns.AtrClearCache() end
      if ns.RefreshUI then ns.RefreshUI() end
    end,
    "OPT_ATR_TIP", function() return ns.AtrInstalled and ns.AtrInstalled() end)

  local goalLabel = Text(panel, "GameFontHighlight", X2, -280)
  W[#W + 1] = { kind = "label", fs = goalLabel, key = "OPT_GOAL" }
  local okBox, box = pcall(CreateFrame, "EditBox", "WritPriceOptionsGoal", panel, "InputBoxTemplate")
  goalBox = okBox and box or CreateFrame("EditBox", "WritPriceOptionsGoal", panel)
  if not okBox then goalBox:SetFontObject("ChatFontNormal") end
  goalBox:SetSize(70, 20)
  goalBox:SetPoint("TOPLEFT", X2 + 190, -276)
  goalBox:SetAutoFocus(false)
  goalBox:SetNumeric(true)
  goalBox:SetMaxLetters(6)
  local function CommitGoal(self)
    if self.committing then return end
    self.committing = true
    local n = tonumber(self:GetText())
    if n then ns.SetGoal(n) end
    self:ClearFocus()
    self.committing = nil
    Refresh()
  end
  goalBox:SetScript("OnEnterPressed", function(self) ns.Safe(CommitGoal, self) end)
  goalBox:SetScript("OnEditFocusLost", function(self) ns.Safe(CommitGoal, self) end)
  goalBox:SetScript("OnEscapePressed", function(self)
    self:SetText(tostring(ns.db.goal or 0)) -- Escape cancels: put the saved value back before losing focus
    self:ClearFocus()
  end)
  local goalHint = Text(panel, "GameFontDisableSmall", X2, -302, 270)
  W[#W + 1] = { kind = "label", fs = goalHint, key = "OPT_GOAL_HINT" }
  goalNow = Text(panel, "GameFontHighlightSmall", X2, -318, 270)

  Section(X2, -344, "OPT_SEC_COLS")
  local y = -366
  for _, key in ipairs(ns.OPTIONAL_COLS or {}) do
    Check(X2, y, "COL_" .. key,
      function() return not ns.db.colOff[key] end,
      function(on) ns.db.colOff[key] = (not on) or nil; if ns.LayoutUI then ns.LayoutUI() end end)
    y = y - 24
  end
  colsNote = Text(panel, "GameFontDisableSmall", X2, y - 4, 270)
  W[#W + 1] = { kind = "label", fs = colsNote, key = "OPT_COLS_FIXED" }

  -- bottom buttons ----------------------------------------------------
  PanelButton(X1, 40, 170, "OPT_BTN_EXPORT", function() ns.OpenExport() end, "OPT_BTN_EXPORT_TIP")
  PanelButton(X1 + 178, 40, 190, "OPT_BTN_IMPORT", function() ns.OpenImport() end, "OPT_BTN_IMPORT_TIP")
  PanelButton(X1, 12, 170, "OPT_BTN_OPEN", function() ns.ShowUI(true) end)
  PanelButton(X1 + 178, 12, 190, "OPT_BTN_RESET", function()
    ns.ResetWindow()
    ns.Print(L.CHAT_RESET)
  end, "OPT_BTN_RESET_TIP")
  PanelButton(X1 + 376, 12, 190, "OPT_BTN_CLEAR", function() StaticPopup_Show("WRITPRICE_CLEAR") end,
    "OPT_BTN_CLEAR_TIP")
  ready = true
end

------------------------------------------------------------
-- Refresh: re-read every setting and every text (language may have changed)
------------------------------------------------------------
Refresh = function()
  if not ready or not ns.db then return end
  title:SetText("WritPrice " .. ns.VERSION)
  subtitle:SetText(L.OPT_SUBTITLE)
  local cur = ns.effectiveScale or ns.db.scale or 1
  local wanted = ns.db.scale or 1
  local pct = math.floor(wanted * 100 + 0.5)
  scaleLabel:SetText(ns.F("OPT_SCALE", pct))
  if math.abs(cur - wanted) > 0.005 and ns.effectiveScale then
    scaleNote:SetText(ns.F("OPT_SCALE_CLAMPED", math.floor(cur * 100 + 0.5)))
  else
    scaleNote:SetText("")
  end
  scaleSlider.updating = true
  scaleSlider:SetValue(pct)
  scaleSlider.updating = nil
  if not goalBox:HasFocus() then goalBox:SetText(tostring(ns.db.goal or 0)) end
  fullNow:SetText(ns.FullScanText and ns.FullScanText() or "")
  local g, tier = ns.GetGoal()
  goalNow:SetText(ns.F("TIP_GOAL_CURRENT", tier and ns.F("UI_GOAL_TEXT_TIER", g, tier) or ns.F("UI_GOAL_TEXT", g)))
  for _, w in ipairs(W) do
    if w.kind == "label" then
      w.fs:SetText(L[w.key])
    elseif w.kind == "button" then
      w.b:SetText(L[w.key])
    elseif w.kind == "check" then
      w.fs:SetText(L[w.key])
      w.cb:SetChecked(w.get() and true or false)
      local on = (w.enabled == nil) or (w.enabled() and true or false)
      if on then w.cb:Enable() w.fs:SetTextColor(1, 1, 1) else w.cb:Disable() w.fs:SetTextColor(0.5, 0.5, 0.5) end
    elseif w.kind == "radio" then
      w.fs:SetText(L[w.key])
      w.cb:SetChecked(w.get() == w.value)
    end
  end
end

function ns.RefreshOptions()
  if panel:IsShown() then Refresh() end
end

panel.OnRefresh = function() ns.Safe(Refresh) end
panel:SetScript("OnShow", function()
  ns.Safe(Build)
  ns.Safe(Refresh)
end)

-- full-scan countdown: refreshed every second while the page is visible
local tickAt = 0
panel:SetScript("OnUpdate", function()
  local t = GetTime()
  if t - tickAt < 1 then return end
  tickAt = t
  if ready and fullNow and ns.FullScanText then fullNow:SetText(ns.FullScanText()) end
end)

-- language change: texts of this page and of the clear popup
ns.OnLocale[#ns.OnLocale + 1] = function()
  StaticPopupDialogs.WRITPRICE_CLEAR.text = L.POPUP_CLEAR
  StaticPopupDialogs.WRITPRICE_CLEAR.button2 = CANCEL or L.CANCEL
  if panel:IsShown() then Refresh() end
end

------------------------------------------------------------
-- Registration and opening
------------------------------------------------------------
local function Register()
  if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
    local cat = Settings.RegisterCanvasLayoutCategory(panel, "WritPrice")
    Settings.RegisterAddOnCategory(cat)
    categoryID = (cat and cat.GetID and cat:GetID()) or (cat and cat.ID)
    mode = "settings"
  elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(panel)
    mode = "legacy"
  else
    -- no options UI on this client: a standalone movable frame
    mode = "standalone"
    panel:SetParent(UIParent)
    panel:SetSize(640, 560)
    panel:SetPoint("CENTER")
    panel:SetFrameStrata("DIALOG")
    panel:EnableMouse(true)
    panel:SetMovable(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
    local bg = panel:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.05, 0.08, 0.95)
    tinsert(UISpecialFrames, "WritPriceOptionsFrame")
    _G.WritPriceOptionsFrame = panel
  end
end
ns.OnLoad[#ns.OnLoad + 1] = Register

function ns.OpenOptions()
  if mode ~= "standalone" and InCombatLockdown and InCombatLockdown() then
    ns.Print(L.OPT_COMBAT)
    return
  end
  if mode == "settings" and Settings.OpenToCategory and categoryID then
    Settings.OpenToCategory(categoryID)
  elseif mode == "legacy" and InterfaceOptionsFrame_OpenToCategory then
    InterfaceOptionsFrame_OpenToCategory(panel)
    InterfaceOptionsFrame_OpenToCategory(panel) -- twice: known Blizzard bug on the first call
  else
    if panel:IsShown() then panel:Hide() else panel:Show() end
  end
end
