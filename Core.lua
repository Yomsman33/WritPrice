-- SPDX-License-Identifier: GPL-2.0-only
-- WritPrice: core (saved data, API compatibility, helpers, slash commands)
local ADDON, ns = ...
local L = ns.L

ns.RANKS = { Journeyman = 75, Expert = 125, Artisan = 200 }
ns.RANK_ORDER = { "Journeyman", "Expert", "Artisan" }
ns.OnLoad = {}
ns.OnLocale = {} -- called when the language changes (options page, minimap tooltip, popups)
ns.errorCount = 0

-- English game texts. Names are kept in English inside the addon; Names.lua translates them for clients
-- in another language (by item ID). The quest-text patterns below are only used on an English client.
ns.GAME = {
  WRIT_PREFIX = "Craftsman's Writ",
  POUCH = "Coin Pouch",
  FACTION = "Azeroth Commerce Authority",
  FACTION_HORDE = "Durotar Supply and Logistics",          -- the Horde's writ faction
  DELIVER_TITLE = "^Deliver%s+(%d+)%s+(.+)$",            -- quest title "Deliver N <item>"
  DELIVER_TO = "[Dd]eliver.-%sto%s(.-)%.?%s*$",           -- objective text "... to <NPC> at <place> in <zone>."
  TO = "%sto%s(.-)%.?%s*$",
  IN_ZONE = "%sin%s([^,]+)$",
}

-- Writ professions (internal English keys; displayed through ns.ProfName)
ns.PROFS = { "Alchemy", "Blacksmithing", "Engineering", "Leatherworking", "Tailoring", "Other" }
ns.PROF_KEYS = { Alchemy = true, Blacksmithing = true, Engineering = true, Leatherworking = true, Tailoring = true, Other = true }

function ns.ProfName(key)
  return L["PROF_" .. tostring(key)]
end

------------------------------------------------------------
-- Version
------------------------------------------------------------
do
  local v
  pcall(function()
    if C_AddOns and C_AddOns.GetAddOnMetadata then v = C_AddOns.GetAddOnMetadata(ADDON, "Version") end
    if not v and GetAddOnMetadata then v = GetAddOnMetadata(ADDON, "Version") end
  end)
  ns.VERSION = (type(v) == "string" and v ~= "") and v or "0.1.0"
end

------------------------------------------------------------
-- Errors: each distinct error is printed once
------------------------------------------------------------
local seen = {}
function ns.Safe(fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then
    ns.errorCount = ns.errorCount + 1
    local key = tostring(err)
    if not seen[key] then
      seen[key] = true
      print("|cffff4040" .. L.ERROR_PREFIX .. "|r " .. key)
    end
  end
  return ok, err
end

function ns.Print(msg)
  print("|cffffd100WritPrice|r: " .. tostring(msg))
end

function ns.Debug(msg)
  if ns.db and ns.db.debug then ns.Print("|cff999999" .. tostring(msg) .. "|r") end
end

------------------------------------------------------------
-- API compatibility
------------------------------------------------------------
ns.GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo

function ns.Coins(copper)
  if not copper then return "|cff999999?|r" end
  copper = math.floor(copper + 0.5)
  if copper < 0 then return "-" .. ns.Coins(-copper) end
  local f = (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString) or GetCoinTextureString
  if f then
    local ok, s = pcall(f, copper)
    if ok and s then return s end
  end
  if GetMoneyString then return GetMoneyString(copper) end
  return tostring(copper) .. "c"
end

------------------------------------------------------------
-- Writs
------------------------------------------------------------
local PREFIX_PATTERN = "^" .. ns.GAME.WRIT_PREFIX:gsub("%p", "%%%0")

function ns.IsWrit(name)
  return type(name) == "string" and name:find(PREFIX_PATTERN) ~= nil
end

function ns.ItemFromWrit(name)
  if type(name) ~= "string" then return nil end
  return name:match(PREFIX_PATTERN .. "%s*[:%-]%s*(.+)$")
end

function ns.RealmKey()
  return (GetRealmName and GetRealmName() or "?") .. "-" .. (UnitFactionGroup("player") or "?")
end

-- Rank: strict match on tooltip lines 2 to 6 (never the name line)
local function Clean(t)
  if type(t) ~= "string" then return nil end
  t = t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  return t:match("^%s*(.-)%s*$")
end

function ns.RankFromLines(get, n)
  for i = 2, math.min(n or 0, 6) do
    local ok, raw = pcall(get, i)
    local t = ok and Clean(raw) or nil
    if t and ns.RANKS[t] then return t end
  end
  return nil
end

local scanTip
function ns.RankFromAuction(link, auctionIndex)
  if C_TooltipInfo and C_TooltipInfo.GetHyperlink and link then
    local ok, d = pcall(C_TooltipInfo.GetHyperlink, link)
    if ok and d and d.lines then
      local r = ns.RankFromLines(function(i) return d.lines[i] and d.lines[i].leftText end, #d.lines)
      if r then return r end
    end
  end
  local r
  pcall(function()
    if not scanTip then
      scanTip = CreateFrame("GameTooltip", "WritPriceScanTip", nil, "GameTooltipTemplate")
    end
    scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
    scanTip:ClearLines()
    if auctionIndex and scanTip.SetAuctionItem then
      scanTip:SetAuctionItem("list", auctionIndex)
    elseif link then
      scanTip:SetHyperlink(link)
    end
    r = ns.RankFromLines(function(i)
      local fs = _G["WritPriceScanTipTextLeft" .. i]
      return fs and fs:GetText()
    end, scanTip:NumLines())
    scanTip:Hide()
  end)
  return r
end

-- Saved record of a writ (key = writ name)
function ns.WritInfo(name)
  local db = ns.db
  local w = db.writs[name]
  if not w then
    w = {}
    db.writs[name] = w
  end
  w.item = w.item or ns.ItemFromWrit(name)
  return w
end

------------------------------------------------------------
-- Profession filter (ns.db.profOff[key] = true when unchecked)
------------------------------------------------------------
-- Profession of a requested item: built-in writ list, then recipe data, then "Other"
function ns.ProfOf(item)
  if item then
    local k = ns.WRIT_LIST and ns.WRIT_LIST[item]
    if k and k.prof and ns.PROF_KEYS[k.prof] then return k.prof end
    local rc = ns.RECIPES and ns.RECIPES[item]
    local pn = rc and ns.PROF_NAMES and ns.PROF_NAMES[rc.p]
    if pn and pn ~= "Other" and ns.PROF_KEYS[pn] then return pn end
  end
  return "Other"
end

-- off: table of unchecked professions (defaults to the saved filter)
function ns.ProfWanted(prof, off)
  off = off or (ns.db and ns.db.profOff)
  return not (off and off[prof or "Other"])
end

function ns.SetProf(prof, on)
  if not (ns.db and ns.PROF_KEYS[prof]) then return end
  if type(ns.db.profOff) ~= "table" then ns.db.profOff = {} end
  ns.db.profOff[prof] = (not on) or nil
end

function ns.SetAllProfs(on)
  for _, p in ipairs(ns.PROFS) do ns.SetProf(p, on) end
end

-- checked count, total count
function ns.ProfCount()
  local n = 0
  for _, p in ipairs(ns.PROFS) do
    if ns.ProfWanted(p) then n = n + 1 end
  end
  return n, #ns.PROFS
end

function ns.ProfSummary()
  local n, total = ns.ProfCount()
  if n == total then return L.PROF_ALL end
  if n == 0 then return L.PROF_NONE end
  return n .. "/" .. total
end

-- frozen copy of the filter (for a running scan)
function ns.ProfOffCopy()
  local c = {}
  for _, p in ipairs(ns.PROFS) do
    if not ns.ProfWanted(p) then c[p] = true end
  end
  return c
end

-- Lower case that also folds the French accented letters used in profession names
local ACCENTS = { ["é"] = "e", ["è"] = "e", ["ê"] = "e", ["É"] = "e", ["È"] = "e", ["Ê"] = "e", ["à"] = "a", ["â"] = "a",
  ["À"] = "a", ["î"] = "i", ["ô"] = "o", ["û"] = "u", ["ç"] = "c", ["Ç"] = "c" }
local function Fold(s)
  s = s:lower()
  for a, b in pairs(ACCENTS) do s = s:gsub(a, b) end
  return s
end

-- Profession from typed text: English key, localized name or alias, in full or as a prefix
function ns.ProfFromText(txt)
  txt = type(txt) == "string" and Fold(txt:match("^%s*(.-)%s*$")) or ""
  if txt == "" then return nil end
  -- main names (English key and every translation), then aliases
  local function mainNames(p)
    local t = { Fold(p) }
    for _, loc in pairs(ns.LOCALES) do
      if loc["PROF_" .. p] then t[#t + 1] = Fold(loc["PROF_" .. p]) end
    end
    return t
  end
  local function aliases(p)
    local t = {}
    for _, loc in pairs(ns.LOCALES) do
      local a = loc["PROF_ALIASES_" .. p]
      if a then for w in a:gmatch("%S+") do t[#t + 1] = Fold(w) end end
    end
    return t
  end
  local tests = {
    function(n) return n == txt end,
    function(n) return n:sub(1, #txt) == txt end,
    function(n) return n:find(txt, 1, true) ~= nil end,
  }
  for _, test in ipairs(tests) do
    for _, list in ipairs({ mainNames, aliases }) do
      for _, p in ipairs(ns.PROFS) do
        for _, n in ipairs(list(p)) do if test(n) then return p end end
      end
    end
  end
  return nil
end

------------------------------------------------------------
-- Loading
------------------------------------------------------------
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
pcall(loader.RegisterEvent, loader, "PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self, event, name)
  if event == "PLAYER_LOGIN" then
    -- one welcome line, on the very first login only
    if ns.db and ns.db.welcomed ~= true and C_Timer and C_Timer.After then
      C_Timer.After(4, function()
        ns.Safe(function()
          if ns.db and ns.db.welcomed ~= true then
            ns.db.welcomed = true
            ns.Print(ns.F("WELCOME", ns.VERSION))
          end
        end)
      end)
    end
    return
  end
  if name ~= ADDON then return end
  self:UnregisterEvent("ADDON_LOADED")
  WritPriceDB = WritPriceDB or {}
  local db = WritPriceDB
  db.v = 3
  db.writs = type(db.writs) == "table" and db.writs or {}
  db.itemIDs = type(db.itemIDs) == "table" and db.itemIDs or {}
  db.scan = type(db.scan) == "table" and db.scan or {}
  db.done = type(db.done) == "table" and db.done or {}
  -- unchecked professions (empty = all checked); keep known keys only
  if type(db.profOff) ~= "table" then db.profOff = {} end
  for k, v in pairs(db.profOff) do
    if not ns.PROF_KEYS[k] or v ~= true then db.profOff[k] = nil end
  end
  -- hidden columns
  if type(db.colOff) ~= "table" then db.colOff = {} end
  for k, v in pairs(db.colOff) do
    if v ~= true then db.colOff[k] = nil end
  end
  if db.scale ~= nil and type(db.scale) ~= "number" then db.scale = nil end
  if type(db.minimap) ~= "table" then db.minimap = {} end
  if db.minimap.minimapPos ~= nil and type(db.minimap.minimapPos) ~= "number" then db.minimap.minimapPos = nil end
  if db.ahButton ~= false then db.ahButton = nil end
  if db.tooltip ~= false then db.tooltip = nil end
  if db.locale ~= nil and not ns.LOCALES[db.locale] then db.locale = nil end
  -- drop expired "turned in today" marks
  local now = time()
  for k, untilT in pairs(db.done) do
    if type(untilT) ~= "number" or untilT <= now then db.done[k] = nil end
  end
  ns.db = db
  if db.locale then ns.SetLocale(db.locale) end
  for _, fn in ipairs(ns.OnLoad) do ns.Safe(fn) end
  if ns.ApplyLocale then ns.Safe(ns.ApplyLocale) end
end)

------------------------------------------------------------
-- Client API diagnostic (/writs debug api)
------------------------------------------------------------
local function Has(path)
  local t = _G
  for part in path:gmatch("[^%.]+") do
    if type(t) ~= "table" then return false end
    t = t[part]
  end
  return t ~= nil
end

function ns.PrintAPI()
  local build = GetBuildInfo and select(4, GetBuildInfo()) or "?"
  ns.Print(ns.F("DEBUG_CLIENT", tostring(build)))
  if ns.NamesDiag then
    local loc, nLoc, nPend, head = ns.NamesDiag()
    ns.Print(ns.F("DEBUG_NAMES", loc, nLoc, nPend, head or "?"))
  end
  if ns.FactionStanding then
    local label = ns.FactionStanding()
    local ids = {}
    for name, id in pairs(ns.db.factionIDs or {}) do ids[#ids + 1] = name .. "=" .. id end
    ns.Print(ns.F("DEBUG_FACTION", label or "-", #ids > 0 and table.concat(ids, ", ") or "-"))
  end
  local list = {
    "QueryAuctionItems", "GetAuctionItemInfo", "CanSendAuctionQuery", "GetAuctionItemLink",
    "C_AuctionHouse.SendBrowseQuery", "C_AuctionHouse.GetBrowseResults",
    "C_AuctionHouse.HasFullBrowseResults", "C_AuctionHouse.RequestMoreBrowseResults",
    "C_AuctionHouse.IsThrottledMessageSystemReady", "Enum.AuctionHouseFilter.ExactMatch",
    "Enum.AuctionHouseSortOrder.Price", "AuctionFrame", "AuctionHouseFrame",
    "AuctionHouseFrame.SearchBar", "AuctionHouseFrame.SetDisplayMode", "AuctionHouseFrameDisplayMode.Buy",
    "GetItemInfo", "C_Item.GetItemInfo", "TooltipDataProcessor", "C_TooltipInfo",
    "C_QuestLog.GetInfo", "C_QuestLog.GetQuestObjectives", "GetQuestLogTitle",
    "GetQuestResetTime", "C_Reputation.GetFactionDataByIndex", "GetFactionInfo",
    "GetNumSkillLines", "C_TradeSkillUI", "LibStub", "Auctionator.API.v1",
    "Settings.RegisterCanvasLayoutCategory", "Settings.RegisterAddOnCategory", "Settings.OpenToCategory",
    "SettingsPanel", "InterfaceOptions_AddCategory", "InterfaceOptionsFrame_OpenToCategory",
    "Minimap", "MinimapCluster", "GetMinimapShape", "AddonCompartmentFrame", "LibDBIcon10_WritPrice",
  }
  for _, p in ipairs(list) do
    print(("  %s: %s"):format(p, Has(p) and ("|cff00ff00" .. L.YES .. "|r") or ("|cffff4040" .. L.NO .. "|r")))
  end
  if ns.ScanDiag then ns.ScanDiag() end
end

------------------------------------------------------------
-- Slash commands
------------------------------------------------------------
local CMDS = {}
local ALIAS = {
  objectif = "goal",
  profs = "prof", metier = "prof", metiers = "prof", ["métier"] = "prof", ["métiers"] = "prof",
  langue = "lang", locale = "lang", language = "lang",
  echelle = "scale", ["échelle"] = "scale",
  colonnes = "cols", columns = "cols",
  config = "options", settings = "options", opt = "options", reglages = "options", ["réglages"] = "options",
  minicarte = "minimap",
  bourse = "pouch", bourses = "pouch", pouches = "pouch",
  exporter = "export", importer = "import",
  aide = "help", ["?"] = "help",
  apropos = "about", version = "about",
  -- older names, kept for players of the test versions
  api = "debug_api", quests = "debug_quests",
}

local function Lower(s) return (s or ""):lower() end

local function RefreshOptions()
  if ns.RefreshOptions then ns.Safe(ns.RefreshOptions) end
end

-- Default position, scale and columns of the window
function ns.ResetWindow()
  ns.db.pos, ns.db.scale, ns.db.colOff = nil, nil, {}
  if ns.ResetUI then ns.ResetUI() end
  RefreshOptions()
end

-- Forget the auction house prices saved for this realm and faction (ranks, quantities, turn-in places kept)
function ns.ClearScan()
  if ns.IsScanning and ns.IsScanning() then ns.StopScan() end
  ns.db.scan[ns.RealmKey()] = nil
  if ns.RefreshUI then ns.RefreshUI() end
  ns.Print(L.CHAT_CLEARED)
end

CMDS.scan = function(rest)
  local m = Lower(rest)
  if m == "full" or m == "complet" or m == "fast" or m == "rapide" then
    ns.StartFullScan()
  elseif m == "targeted" or m == "cible" or m == "ciblé" then
    ns.StartScan()
  else
    ns.StartAutoScan()
  end
end

CMDS.stop = function()
  if ns.IsScanning() then ns.StopScan() else ns.Print(L.CHAT_NO_SCAN_RUNNING) end
end

CMDS.goal = function(rest)
  if ns.SetGoal and rest ~= "" and ns.SetGoal(rest) then
    local g, tier = ns.GetGoal()
    if tier then ns.Print(ns.F("CHAT_GOAL_TIER", g, tier)) else ns.Print(ns.F("CHAT_GOAL", g)) end
    RefreshOptions()
  else
    ns.Print(L.CMD_GOAL_USAGE)
  end
end

CMDS.craft = function()
  ns.db.noReagents = not ns.db.noReagents or nil
  ns.Print(ns.db.noReagents and L.CHAT_REAGENTS_OFF or L.CHAT_REAGENTS_ON)
  RefreshOptions()
end

CMDS.prof = function(rest)
  local low = Lower(rest)
  if low == "all" or low == "tous" or low == "tout" then
    ns.SetAllProfs(true)
  elseif low == "none" or low == "aucun" or low == "rien" then
    ns.SetAllProfs(false)
  elseif low ~= "" then
    local p = ns.ProfFromText(rest)
    if p then
      ns.SetProf(p, not ns.ProfWanted(p))
    else
      ns.Print(ns.F("CHAT_PROF_UNKNOWN", rest))
      return
    end
  end
  local parts = {}
  for _, p in ipairs(ns.PROFS) do
    parts[#parts + 1] = (ns.ProfWanted(p) and "|cff40ff40" or "|cff999999") .. ns.ProfName(p) .. "|r"
  end
  ns.Print(ns.F("CHAT_PROFS", ns.ProfSummary(), table.concat(parts, ", ")))
  if ns.RefreshUI then ns.RefreshUI() end
end

CMDS.set = function(rest)
  local n = tonumber(rest)
  n = n and math.floor(n)
  if n and n >= 0 and ns.lastWrit then
    if n == 0 then
      ns.SetQty(ns.lastWrit, nil, nil)
      ns.Print(ns.F("CHAT_QTY_RESET", ns.lastWrit))
    else
      ns.SetQty(ns.lastWrit, n, "manual")
      ns.Print(ns.F("CHAT_QTY_SET", ns.lastWrit, n))
    end
  else
    ns.Print(L.CMD_SET_USAGE)
  end
end

CMDS.lang = function(rest)
  local low = Lower(rest)
  local map = { en = "enUS", enus = "enUS", english = "enUS", anglais = "enUS",
    fr = "frFR", frfr = "frFR", french = "frFR", ["français"] = "frFR", francais = "frFR", auto = "auto" }
  if low ~= "" then
    if not (map[low] and ns.SetLocale(map[low])) then
      ns.Print(L.CHAT_LANG_USAGE)
      return
    end
  end
  local code = ns.LocaleCode()
  ns.Print(ns.F("CHAT_LANG", L["LANG_" .. code] .. ((ns.db and ns.db.locale) and "" or (" " .. L.LANG_AUTO))))
  RefreshOptions()
end

CMDS.scale = function(rest)
  local n = tonumber(rest)
  if n and n >= 50 and n <= 150 then
    ns.db.scale = n / 100
    if ns.ApplyScale then ns.ApplyScale() end
  elseif rest ~= "" then
    ns.Print(L.CMD_SCALE_USAGE)
    return
  end
  local s = ns.effectiveScale or ns.db.scale or 1
  ns.Print(ns.F("CHAT_SCALE", math.floor(s * 100 + 0.5)))
  RefreshOptions()
end

CMDS.cols = function()
  if ns.ShowUI then ns.ShowUI() end
  if ns.ToggleColsMenu then ns.ToggleColsMenu() end
end

CMDS.reset = function()
  ns.ResetWindow()
  ns.Print(L.CHAT_RESET)
end

CMDS.export = function()
  if ns.OpenExport then ns.OpenExport() end
end

CMDS.import = function()
  if ns.OpenImport then ns.OpenImport() end
end

CMDS.pouch = function()
  if ns.PrintPouch then ns.PrintPouch() end
end

CMDS.options = function()
  if ns.OpenOptions then ns.OpenOptions() end
end

CMDS.minimap = function()
  ns.db.minimap.hide = not ns.db.minimap.hide or nil
  if ns.UpdateMinimapButton then ns.UpdateMinimapButton() end
  ns.Print(ns.db.minimap.hide and L.CHAT_MINIMAP_OFF or L.CHAT_MINIMAP_ON)
  RefreshOptions()
end

CMDS.about = function()
  ns.Print(ns.F("ABOUT_1", ns.VERSION))
  print("  " .. L.ABOUT_2)
  print("  " .. L.ABOUT_3)
end

CMDS.help = function()
  ns.Print(ns.F("HELP_HEADER", ns.VERSION))
  for i = 1, 10 do
    local line = L["HELP_" .. i]
    if line ~= "HELP_" .. i then print("  " .. line) end
  end
  if ns.db.debug then print("  " .. L.HELP_DEBUG) end
end

CMDS.debug = function(rest)
  local sub = Lower(rest)
  if sub == "api" then
    ns.PrintAPI()
  elseif sub == "quests" then
    ns.DumpQuests()
  elseif sub == "dests" then
    if ns.DumpDests then ns.DumpDests() end
  elseif sub == "on" or sub == "off" then
    ns.db.debug = (sub == "on") or nil
    ns.Print(ns.db.debug and L.CHAT_DEBUG_ON or L.CHAT_DEBUG_OFF)
  else
    ns.Print(L.HELP_DEBUG)
  end
end
CMDS.debug_api = function() ns.PrintAPI() end
CMDS.debug_quests = function() ns.DumpQuests() end

SLASH_WRITPRICE1 = "/writs"
SLASH_WRITPRICE2 = "/writprice"
SlashCmdList.WRITPRICE = function(msg)
  ns.Safe(function()
    if not ns.db then return end
    msg = (msg or ""):match("^%s*(.-)%s*$")
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = Lower(cmd)
    cmd = ALIAS[cmd] or cmd
    local fn = CMDS[cmd]
    if fn then
      fn(rest or "")
    elseif cmd == "" then
      ns.ToggleUI()
    else
      ns.Print(L.CHAT_UNKNOWN_CMD)
    end
  end)
end
