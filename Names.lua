-- SPDX-License-Identifier: GPL-2.0-only
-- WritPrice: game names in the language of the player's client.
--
-- Everything inside the addon (saved data, built-in lists, exports, sharing) uses the English names,
-- called "canonical" here. On an English client nothing is translated. On another client:
--   ns.LocName(en)        -> the name shown by this client (nil while unknown)
--   ns.CanonName(name, id) -> the English name of a name read in game (unchanged when unknown)
--   ns.Disp(en)           -> the name to show to the player
-- Item IDs (Recipes.lua, Ids.lua, IDs learned by scans) are the bridge: the client gives the
-- translated name of an ID. Writs whose ID is not known yet are recognized by their shape:
-- "<translated writ prefix><separator><translated requested item>".
local ADDON, ns = ...

local N = {
  loc = {},     -- English name -> client name
  rev = {},     -- client name -> English name
  revF = {},    -- folded client name (see Fold) -> English name
  byID = nil,   -- item ID -> English name (built on first use)
  pending = {}, -- item ID -> English name, waiting for GET_ITEM_INFO_RECEIVED
}

function ns.ClientLocale()
  return (GetLocale and GetLocale()) or "enUS"
end

function ns.EnglishClient()
  local l = ns.ClientLocale()
  return l == "enUS" or l == "enGB"
end

local function WritOf(item) return ns.GAME.WRIT_PREFIX .. ": " .. item end

-- Folded for comparisons: lower case, no accents, plain apostrophe. A writ may write its item in
-- lower case ("Commission d'artisan : potion de mana" for "Potion de mana").
local FOLD = {
  ["à"] = "a", ["â"] = "a", ["ä"] = "a", ["À"] = "a", ["Â"] = "a", ["Ä"] = "a",
  ["é"] = "e", ["è"] = "e", ["ê"] = "e", ["ë"] = "e", ["É"] = "e", ["È"] = "e", ["Ê"] = "e", ["Ë"] = "e",
  ["î"] = "i", ["ï"] = "i", ["Î"] = "i", ["Ï"] = "i", ["ô"] = "o", ["ö"] = "o", ["Ô"] = "o", ["Ö"] = "o",
  ["ù"] = "u", ["û"] = "u", ["ü"] = "u", ["Ù"] = "u", ["Û"] = "u", ["Ü"] = "u", ["ç"] = "c", ["Ç"] = "c",
  ["œ"] = "oe", ["Œ"] = "oe", ["æ"] = "ae", ["Æ"] = "ae", ["’"] = "'", ["‘"] = "'", ["ß"] = "ss",
}
local function Fold(str)
  str = str:lower():gsub("[\195\197\226][\128-\191]+", function(c) return FOLD[c] end)
  return (str:gsub("%s+", " "))
end
ns.FoldName = Fold

local function SetLoc(en, n)
  N.loc[en], N.rev[n] = n, en
  N.revF[Fold(n)] = en
end

-- Item ID of an English name
function ns.IdOf(en)
  if type(en) ~= "string" then return nil end
  return (ns.db and ns.db.itemIDs and ns.db.itemIDs[en]) or (ns.ITEM_IDS and ns.ITEM_IDS[en])
    or (ns.EXTRA_IDS and ns.EXTRA_IDS[en])
end

local function ByID()
  if not N.byID then
    local t = {}
    for n, id in pairs(ns.ITEM_IDS or {}) do t[id] = n end
    for n, id in pairs(ns.EXTRA_IDS or {}) do t[id] = n end
    for n, id in pairs(ns.db and ns.db.itemIDs or {}) do
      -- only English names were saved since 0.1.1; a name in another language is skipped
      if ns.IsWrit(n) or (ns.ITEM_IDS and ns.ITEM_IDS[n]) or (ns.WRIT_LIST and ns.WRIT_LIST[n]) then t[id] = n end
    end
    N.byID = t
  end
  return N.byID
end

-- An ID seen with its English name (scans): remembered for exports and translations
function ns.LearnItemID(en, id)
  if not (ns.db and type(en) == "string" and type(id) == "number") then return end
  ns.db.itemIDs[en] = id
  if N.byID then N.byID[id] = en end
end

-- Saved per client language: the translated writ head ("Commande d'artisan : ")
local function LocDB()
  if not ns.db then return nil end
  ns.db.locNames = type(ns.db.locNames) == "table" and ns.db.locNames or {}
  local l = ns.ClientLocale()
  ns.db.locNames[l] = type(ns.db.locNames[l]) == "table" and ns.db.locNames[l] or {}
  return ns.db.locNames[l]
end

local function Head()
  if N.head then return N.head end
  local d = LocDB()
  if d and type(d.head) == "string" and d.head ~= "" then N.head = d.head end
  return N.head
end

-- lowerFirst: the writ writes its item with a lower-case first letter
local function SetHead(head, lowerFirst)
  if type(head) ~= "string" or head == "" or #head > 60 then return end
  N.head = head
  local d = LocDB()
  if d then
    d.head = head
    if lowerFirst ~= nil then d.lowerFirst = lowerFirst or nil end
  end
end

local function IsLowerFirst(rest, item)
  local a, b = rest:sub(1, 1), item:sub(1, 1)
  return a ~= b and a == b:lower()
end

local function ClientName(id)
  local n
  if C_Item and C_Item.GetItemNameByID then
    local ok, v = pcall(C_Item.GetItemNameByID, id)
    if ok and type(v) == "string" and v ~= "" then n = v end
  end
  if not n and ns.GetItemInfo then
    local ok, v = pcall(ns.GetItemInfo, id)
    if ok and type(v) == "string" and v ~= "" then n = v end
  end
  return n
end

-- Client name of a translated writ: learns the writ head from it
-- "<head><separator><item>": the head and separator, when the rest is the item (folded)
local function SplitWrit(name, isItem)
  for _, sep in ipairs({ ":", "-" }) do
    local start = 1
    while true do
      local i = name:find(sep, start, true)
      if not i then break end
      local after = name:sub(i + 1)
      local spaces = after:match("^%s*")
      local rest = after:sub(#spaces + 1)
      if i > 1 and rest ~= "" and isItem(rest) then return name:sub(1, i) .. spaces, rest end
      start = i + 1
    end
  end
  return nil
end

local function LearnWritHead(en, n)
  if not ns.IsWrit(en) then return end
  local item = ns.ItemFromWrit(en)
  local li = item and N.loc[item]
  if not li then return end
  local fli = Fold(li)
  local head, rest = SplitWrit(n, function(r) return Fold(r) == fli end)
  if head then SetHead(head, IsLowerFirst(rest, li)) end
end

-- Asks the client for the name of an ID; returns it when already known
local function Learn(id, en)
  local n = ClientName(id)
  if n then
    SetLoc(en, n)
    LearnWritHead(en, n)
    return n
  end
  if not N.pending[id] then
    N.pending[id] = en
    if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
  end
  return nil
end

function ns.LocName(en)
  if type(en) ~= "string" then return nil end
  if ns.EnglishClient() then return en end
  local n = N.loc[en]
  if n then return n end
  local id = ns.IdOf(en)
  if id then
    n = Learn(id, en)
    if n then return n end
  end
  if ns.IsWrit(en) then
    local li = ns.LocName(ns.ItemFromWrit(en))
    local head = Head()
    if li and head then
      local d = LocDB()
      if d and d.lowerFirst then li = li:sub(1, 1):lower() .. li:sub(2) end
      return head .. li
    end
  end
  return nil
end

function ns.Disp(en)
  return ns.LocName(en) or en
end

-- Translated writ name -> English writ name (shape "<head><item>")
local function ItemEn(rest)
  local en = N.rev[rest] or N.revF[Fold(rest)]
  return (en and ns.WRIT_LIST and ns.WRIT_LIST[en]) and en or nil
end

local function CanonWrit(name)
  local head = Head()
  if head and #name > #head and name:sub(1, #head) == head then
    local en = ItemEn(name:sub(#head + 1))
    if en then return WritOf(en) end
  end
  -- unknown head: try each ":" (then "-") as the separator, the rest must be a requested item
  local h, rest = SplitWrit(name, function(r) return ItemEn(r) ~= nil end)
  if h then
    local en = ItemEn(rest)
    SetHead(h, N.loc[en] and IsLowerFirst(rest, N.loc[en]) or false)
    return WritOf(en)
  end
  return nil
end

function ns.CanonName(name, id)
  if type(name) ~= "string" or name == "" then return name end
  if ns.EnglishClient() then return name end
  if id then
    local en = ByID()[id]
    if en then
      SetLoc(en, name)
      LearnWritHead(en, name)
      return en
    end
  end
  local en = N.rev[name] or N.revF[Fold(name)]
  if en then return en end
  return CanonWrit(name) or name
end

-- Text searched at the auction house to list every writ (nil while unknown on this client)
function ns.WritSearchText()
  if ns.EnglishClient() then return ns.GAME.WRIT_PREFIX end
  local head = Head()
  if not head then
    -- a known writ ID gives it at once
    for en, id in pairs(ns.EXTRA_IDS or {}) do
      if ns.IsWrit(en) then
        local li = ns.LocName(ns.ItemFromWrit(en))
        local n = li and Learn(id, en)
        if n then break end
      end
    end
    head = Head()
  end
  if not head then
    -- writ names of another shape: their common beginning (at least 2 names, 5 letters)
    local common, count = nil, 0
    local function add(en, id)
      local n = ns.IsWrit(en) and type(id) == "number" and ClientName(id)
      if not n then return end
      count = count + 1
      if not common then common = n return end
      local i = 0
      while i < #common and i < #n and common:byte(i + 1) == n:byte(i + 1) do i = i + 1 end
      common = common:sub(1, i)
    end
    for en, id in pairs(ns.EXTRA_IDS or {}) do add(en, id) end
    for en, id in pairs(ns.db and ns.db.itemIDs or {}) do add(en, id) end
    local t = common and common:match("^(.-)[%s:%-%(]*$")
    if count >= 2 and t and #t >= 5 then return t end
    return nil
  end
  local t = head:match("^(.-)[%s:%-]*$")
  return (t and t ~= "") and t or nil
end

-- Coin Pouch: by item ID (any language), or by its English name
function ns.IsPouch(id, name)
  if id then
    if ns.EXTRA_IDS and ns.EXTRA_IDS[ns.GAME.POUCH] == id then return true end
    if ns.db and ns.db.pouch and ns.db.pouch.itemID == id then return true end
  end
  return name == ns.GAME.POUCH
end

-- Writ factions (English names) and their IDs (built-in, or learned on an English client)
function ns.IsWritFaction(name)
  return name == ns.GAME.FACTION or name == ns.GAME.FACTION_HORDE
end

function ns.FactionIDKnown(id)
  if type(id) ~= "number" then return false end
  for _, fid in pairs(ns.FACTION_IDS or {}) do if fid == id then return true end end
  for _, fid in pairs(ns.db and ns.db.factionIDs or {}) do if fid == id then return true end end
  return false
end

-- Translated names wanted on a non-English client: requested items, their reagents, known writ IDs
local function Preload()
  if ns.EnglishClient() then return end
  Head()
  local function want(en)
    local id = ns.IdOf(en)
    if id and not N.loc[en] then Learn(id, en) end
  end
  for item in pairs(ns.WRIT_LIST or {}) do
    want(item)
    for _, rn in ipairs(ns.ReagentsToScan and ns.ReagentsToScan(item) or {}) do want(rn) end
  end
  for en in pairs(ns.EXTRA_IDS or {}) do want(en) end
end
ns.PreloadNames = Preload

-- for the test bench: forget what was learned (the client language changed)
function ns.ResetNames()
  N.loc, N.rev, N.revF, N.byID, N.pending, N.head = {}, {}, {}, nil, {}, nil
end

function ns.NamesDiag()
  local nLoc = 0
  for _ in pairs(N.loc) do nLoc = nLoc + 1 end
  local nPend = 0
  for _ in pairs(N.pending) do nPend = nPend + 1 end
  return ns.ClientLocale(), nLoc, nPend, Head() or ns.WritSearchText()
end

local ev = CreateFrame("Frame")
pcall(ev.RegisterEvent, ev, "PLAYER_LOGIN")
pcall(ev.RegisterEvent, ev, "GET_ITEM_INFO_RECEIVED")
ev:SetScript("OnEvent", function(_, event, id, success)
  if event == "PLAYER_LOGIN" then
    ns.Safe(Preload)
    return
  end
  local en = id and N.pending[id]
  if not en then return end
  N.pending[id] = nil
  if success ~= false then
    ns.Safe(function()
      local n = ClientName(id)
      if n then
        SetLoc(en, n)
        LearnWritHead(en, n)
      end
    end)
  end
end)
