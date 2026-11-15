-- SPDX-License-Identifier: GPL-2.0-only
-- WritPrice: /writs export and /writs import. The export is plain text the player copies (Ctrl+C) and
-- posts for the author, who merges many exports with dev/tools/merge_exports.py into the next release.
-- It holds only what the addon learned in game: turn-in places, quantities, ranks, own Coin Pouch samples.
-- No character, realm or money information.
--
-- Format (one record per line, fields separated by ";"):
--   WPX;1;<addon version>              header
--   D;<item>;<turn-in text>;<zone>     turn-in place read from the quest text
--   Q;<item>;<quantity>;<rank>         quantity read from the quest log (rank when known)
--   R;<item>;<rank>                    rank read from the writ tooltip
--   P;<rank>;<copper>;<time>;<id>;<item>;<turn-in text>;<zone>   own Coin Pouch sample
--   I;<English name>;<item ID>         writ, Coin Pouch or requested item ID (English client only)
--   F;<faction ID>;<English name>      writ faction ID (English client only)
--   END;<checksum>                     sum of the bytes of the lines above, modulo 65536, in hex
local ADDON, ns = ...
local L = ns.L

local FORMAT = "1"

local function Field(v)
  if v == nil then return "" end
  v = tostring(v):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("[;|\r\n]", " ")
  return v
end

local function Checksum(s)
  local sum = 0
  for i = 1, #s do sum = (sum + s:byte(i)) % 65536 end
  return string.format("%04x", sum)
end

function ns.BuildExport()
  local lines = { "WPX;" .. FORMAT .. ";" .. Field(ns.VERSION) }
  local counts = { D = 0, Q = 0, R = 0, P = 0 }
  local items = {}
  for name, w in pairs(ns.db.writs) do
    local item = w.item or ns.ItemFromWrit(name)
    if item then items[#items + 1] = { item = item, w = w } end
  end
  table.sort(items, function(a, b) return a.item < b.item end)
  for _, e in ipairs(items) do
    local w = e.w
    if w.dest and not ns.IsJunkDest(w.dest) then
      local zone = w.dest:match(ns.GAME.IN_ZONE)
      lines[#lines + 1] = table.concat({ "D", Field(e.item), Field(w.dest), Field(zone) }, ";")
      counts.D = counts.D + 1
    end
    if w.qtySrc == "quest" and w.qty then
      lines[#lines + 1] = table.concat({ "Q", Field(e.item), tostring(w.qty), Field(w.rank) }, ";")
      counts.Q = counts.Q + 1
    end
    if w.rank then
      lines[#lines + 1] = table.concat({ "R", Field(e.item), w.rank }, ";")
      counts.R = counts.R + 1
    end
  end
  local p = ns.db.pouch
  for rank, list in pairs(p and p.samples or {}) do
    for _, s in ipairs(list) do
      if s.src == "me" then
        lines[#lines + 1] = table.concat({ "P", rank, tostring(s.v), tostring(s.t), Field(s.id),
          Field(s.item), Field(s.dest), Field(s.zone) }, ";")
        counts.P = counts.P + 1
      end
    end
  end
  -- IDs for clients in other languages (Names.lua). Only an English client knows the English names.
  counts.I = 0
  if ns.EnglishClient() then
    local ids = {}
    for name, id in pairs(ns.db.itemIDs or {}) do
      local item = ns.ItemFromWrit(name)
      local wanted = (ns.IsWrit(name) and item and ns.WRIT_LIST and ns.WRIT_LIST[item])
        or (ns.WRIT_LIST and ns.WRIT_LIST[name] and not (ns.ITEM_IDS and ns.ITEM_IDS[name]))
      if wanted and type(id) == "number" and not (ns.EXTRA_IDS and ns.EXTRA_IDS[name] == id) then ids[name] = id end
    end
    local sc = ns.CurrentScan and ns.CurrentScan()
    for name, sw in pairs(sc and sc.writs or {}) do
      if sw.id and not ids[name] and not (ns.EXTRA_IDS and ns.EXTRA_IDS[name]) then ids[name] = sw.id end
    end
    local pid = ns.db.pouch and ns.db.pouch.itemID
    if type(pid) == "number" and not (ns.EXTRA_IDS and ns.EXTRA_IDS[ns.GAME.POUCH]) then ids[ns.GAME.POUCH] = pid end
    local names = {}
    for name in pairs(ids) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
      lines[#lines + 1] = table.concat({ "I", Field(name), tostring(ids[name]) }, ";")
      counts.I = counts.I + 1
    end
    if ns.FactionStanding then ns.FactionStanding() end -- learns the faction ID when not known yet
    for name, fid in pairs(ns.db.factionIDs or {}) do
      if type(fid) == "number" and ns.IsWritFaction(name) and not (ns.FACTION_IDS and ns.FACTION_IDS[name] == fid) then
        lines[#lines + 1] = table.concat({ "F", tostring(fid), Field(name) }, ";")
        counts.I = counts.I + 1
      end
    end
  end
  local body = table.concat(lines, "\n")
  return body .. "\nEND;" .. Checksum(body), counts
end

-- Returns a summary table, or nil and an error key
function ns.ApplyImport(text)
  if type(text) ~= "string" then return nil, "IMPORT_BAD" end
  text = text:gsub("\r", "")
  local body, sum = text:match("^%s*(WPX;.-)\nEND;(%x+)%s*$")
  if not body then return nil, "IMPORT_BAD" end
  if Checksum(body) ~= sum:lower() then return nil, "IMPORT_CHECKSUM" end
  local res = { D = 0, Q = 0, R = 0, P = 0 }
  local p = ns.db.pouch or {}
  p.sharedDest = type(p.sharedDest) == "table" and p.sharedDest or {}
  ns.db.pouch = p
  for line in (body .. "\n"):gmatch("([^\n]*)\n") do
    local f = {}
    for v in (line .. ";"):gmatch("([^;]*);") do f[#f + 1] = v end
    local kind = f[1]
    if kind == "D" and f[2] ~= "" and f[3] ~= "" then
      local item = ns.CleanShareText(f[2], 60)
      local w = ns.db.writs[ns.GAME.WRIT_PREFIX .. ": " .. item]
      if not (w and w.dest) then
        p.sharedDest[item] = { dest = ns.CleanShareText(f[3], 90), zone = ns.CleanShareText(f[4], 40), t = time() }
        res.D = res.D + 1
      end
    elseif kind == "Q" then
      local item, qty = ns.CleanShareText(f[2], 60), tonumber(f[3])
      if item and qty and qty >= 1 and qty <= 500 then
        local w = ns.WritInfo(ns.GAME.WRIT_PREFIX .. ": " .. item)
        if w.qtySrc ~= "quest" and w.qtySrc ~= "manual" then
          w.qty, w.qtySrc = math.floor(qty), "import"
          res.Q = res.Q + 1
        end
        if ns.RANKS[f[4]] and not w.rank then w.rank = f[4] end
      end
    elseif kind == "R" then
      local item = ns.CleanShareText(f[2], 60)
      if item and ns.RANKS[f[3]] then
        local w = ns.WritInfo(ns.GAME.WRIT_PREFIX .. ": " .. item)
        if not w.rank then
          w.rank = f[3]
          res.R = res.R + 1
        end
      end
    elseif kind == "P" then
      local info = { item = f[6], dest = f[7], zone = f[8] }
      if ns.AddPouchSample(f[2], tonumber(f[3]), tonumber(f[4]), f[5], "import", info) then res.P = res.P + 1 end
    elseif kind == "I" then
      -- an English player's IDs: lets a client in another language find these items at once
      local name, id = ns.CleanShareText(f[2], 80), tonumber(f[3])
      local item = name and ns.ItemFromWrit(name)
      local valid = name and id and id > 0 and id < 10000000 and ((ns.IsWrit(name) and item and ns.WRIT_LIST and ns.WRIT_LIST[item])
        or name == ns.GAME.POUCH or (ns.WRIT_LIST and ns.WRIT_LIST[name]))
      if valid and not ns.IdOf(name) then
        if name == ns.GAME.POUCH then
          ns.db.pouch.itemID = ns.db.pouch.itemID or id
        else
          ns.LearnItemID(name, id)
        end
      end
    elseif kind == "F" then
      local id, name = tonumber(f[2]), f[3] or ns.GAME.FACTION
      if id and id > 0 and ns.IsWritFaction(name) then
        ns.db.factionIDs = type(ns.db.factionIDs) == "table" and ns.db.factionIDs or {}
        if not ns.db.factionIDs[name] then ns.db.factionIDs[name] = id end
      end
    end
  end
  ns.pouchCache = nil
  if ns.RefreshUI then ns.RefreshUI() end
  return res
end

------------------------------------------------------------
-- Copy / paste window
------------------------------------------------------------
local win, edit, importBtn, hint

local function Build()
  win = CreateFrame("Frame", "WritPriceExportFrame", UIParent, "BasicFrameTemplateWithInset")
  win:SetSize(520, 360)
  win:SetPoint("CENTER")
  win:SetFrameStrata("DIALOG")
  win:SetMovable(true)
  win:EnableMouse(true)
  win:RegisterForDrag("LeftButton")
  win:SetScript("OnDragStart", win.StartMoving)
  win:SetScript("OnDragStop", win.StopMovingOrSizing)
  win:SetClampedToScreen(true)
  tinsert(UISpecialFrames, "WritPriceExportFrame")
  win.title = win.TitleText or win:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  if not win.TitleText then win.title:SetPoint("TOP", 0, -5) end

  hint = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  hint:SetPoint("TOPLEFT", 14, -30)
  hint:SetWidth(490)
  hint:SetJustifyH("LEFT")

  local ok, sf = pcall(CreateFrame, "ScrollFrame", "WritPriceExportScroll", win, "UIPanelScrollFrameTemplate")
  if not ok then sf = CreateFrame("ScrollFrame", "WritPriceExportScroll", win) end
  sf:SetPoint("TOPLEFT", 14, -62)
  sf:SetPoint("BOTTOMRIGHT", -34, 44)
  edit = CreateFrame("EditBox", "WritPriceExportEdit", sf)
  edit:SetMultiLine(true)
  edit:SetAutoFocus(false)
  edit:SetFontObject("ChatFontNormal")
  edit:SetWidth(460)
  edit:SetScript("OnEscapePressed", function() win:Hide() end)
  sf:SetScrollChild(edit)

  importBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
  importBtn:SetSize(140, 22)
  importBtn:SetPoint("BOTTOMRIGHT", -14, 12)
  importBtn:SetScript("OnClick", function()
    ns.Safe(function()
      local res, err = ns.ApplyImport(edit:GetText())
      if not res then
        ns.Print(L[err])
        return
      end
      ns.Print(ns.F("CHAT_IMPORTED", res.D, res.Q, res.R, res.P))
      win:Hide()
    end)
  end)
  win:Hide()
end

local function Open(mode)
  if not win then Build() end
  if mode == "export" then
    local text, c = ns.BuildExport()
    win.title:SetText(L.EXPORT_TITLE)
    hint:SetText(ns.F("EXPORT_HINT", c.D, c.Q, c.R, c.P))
    edit:SetText(text)
    importBtn:Hide()
    win:Show()
    edit:SetFocus()
    edit:HighlightText()
  else
    win.title:SetText(L.IMPORT_TITLE)
    hint:SetText(L.IMPORT_HINT)
    edit:SetText("")
    importBtn:SetText(L.IMPORT_BTN)
    importBtn:Show()
    win:Show()
    edit:SetFocus()
  end
end

function ns.OpenExport() Open("export") end
function ns.OpenImport() Open("import") end
