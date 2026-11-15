-- SPDX-License-Identifier: GPL-2.0-only
-- WritPrice: Coin Pouch rewards. When a writ is turned in, the rank is remembered; when a Coin Pouch then
-- appears in the bags it is tagged with that rank; when a pouch is opened, the money gained is recorded
-- as a sample for its rank. The median of all samples (own + shared by other players) is deducted from
-- the cost of each writ.
local ADDON, ns = ...
local L = ns.L

local MAX_PER_RANK = 200      -- samples kept per rank (oldest dropped)
local TURNIN_WINDOW = 15      -- a pouch received within 15 s of a writ turn-in comes from it
local OPEN_WINDOW = 10        -- money gained within 10 s of a pouch disappearing comes from it
local MIN_COPPER, MAX_COPPER = 1, 200000 -- sanity range for one pouch (0 c - 20 g)

local recentTurnIns = {}      -- { rank, t } (FIFO)
local pouchCount              -- Coin Pouches in the bags at the last check
local lastMoney
local openedAt                -- time a pouch disappeared from the bags

------------------------------------------------------------
-- Storage
------------------------------------------------------------
local function DB()
  local db = ns.db
  if type(db.pouch) ~= "table" then db.pouch = {} end
  local p = db.pouch
  p.samples = type(p.samples) == "table" and p.samples or {}
  p.seen = type(p.seen) == "table" and p.seen or {}
  p.queue = type(p.queue) == "table" and p.queue or {} -- ranks of unopened pouches, oldest first
  p.bySender = type(p.bySender) == "table" and p.bySender or {}
  return p
end

local function ValidSample(rank, copper, t)
  if not ns.RANKS[rank] then return false end
  if type(copper) ~= "number" or copper < MIN_COPPER or copper > MAX_COPPER then return false end
  if type(t) ~= "number" then return false end
  local now = time()
  if t > now + 86400 or t < now - 90 * 86400 then return false end
  return true
end

-- free text from the game or from another player: no separators, bounded length
local function CleanText(v, max)
  if type(v) ~= "string" or v == "" then return nil end
  v = v:gsub("|", ""):gsub("[%c]", "")
  if #v > max then v = v:sub(1, max) end
  return v ~= "" and v or nil
end
ns.CleanShareText = CleanText

-- Adds a sample; returns true when it is new and valid. src = "me" or the sender's name.
-- info (optional) = { item = requested item, dest = turn-in NPC and place, zone = zone }
function ns.AddPouchSample(rank, copper, t, uid, src, info)
  copper, t = tonumber(copper), tonumber(t)
  if not ValidSample(rank, copper, t) or type(uid) ~= "string" or uid == "" then return false end
  local p = DB()
  if p.seen[uid] then return false end
  if src ~= "me" and src ~= "import" then -- an import is the player's own choice: no per-sender limit
    local n = p.bySender[src] or 0
    if n >= 30 then return false end -- one player cannot flood our data
    p.bySender[src] = n + 1
  end
  p.seen[uid] = t
  local list = p.samples[rank]
  if not list then
    list = {}
    p.samples[rank] = list
  end
  info = info or {}
  local sample = { v = math.floor(copper), t = t, src = src, id = uid,
    item = CleanText(info.item, 60), dest = CleanText(info.dest, 90), zone = CleanText(info.zone, 40) }
  list[#list + 1] = sample
  -- a turn-in place reported by another player helps when we never accepted that writ ourselves
  if src ~= "me" and sample.item and sample.dest then
    p.sharedDest = type(p.sharedDest) == "table" and p.sharedDest or {}
    p.sharedDest[sample.item] = { dest = sample.dest, zone = sample.zone, t = t }
  end
  while #list > MAX_PER_RANK do
    local old = table.remove(list, 1)
    if old and old.src ~= "me" and old.src ~= "import" and p.bySender[old.src] then
      p.bySender[old.src] = math.max(0, p.bySender[old.src] - 1)
    end
  end
  ns.pouchCache = nil
  if ns.RefreshUI then ns.RefreshUI() end
  return true
end

-- Median Coin Pouch value of a rank (copper), number of samples, number of own samples.
-- Without any sample, the built-in default of the release (ns.POUCH_DEFAULT, from merged exports) is used.
function ns.PouchMedian(rank)
  ns.pouchCache = ns.pouchCache or {}
  local c = ns.pouchCache[rank]
  if c then return c.m, c.n, c.own end
  local p = ns.db and ns.db.pouch
  local list = p and p.samples and p.samples[rank]
  local vals, own = {}, 0
  for _, s in ipairs(list or {}) do
    vals[#vals + 1] = s.v
    if s.src == "me" then own = own + 1 end
  end
  local m
  if #vals > 0 then
    table.sort(vals)
    local h = math.floor(#vals / 2)
    if #vals % 2 == 1 then m = vals[h + 1] else m = math.floor((vals[h] + vals[h + 1]) / 2) end
  end
  if not m and ns.POUCH_DEFAULT and ns.POUCH_DEFAULT[rank] then
    m = ns.POUCH_DEFAULT[rank]
  end
  ns.pouchCache[rank] = { m = m, n = #vals, own = own }
  return m, #vals, own
end

------------------------------------------------------------
-- Detection
------------------------------------------------------------
local function CountPouches()
  local n = 0
  local C = C_Container
  local numSlots = (C and C.GetContainerNumSlots) or GetContainerNumSlots
  if not numSlots then return nil end
  for bag = 0, (NUM_BAG_SLOTS or 4) do
    for slot = 1, numSlots(bag) or 0 do
      local id, count
      if C and C.GetContainerItemInfo then
        local info = C.GetContainerItemInfo(bag, slot)
        if info then id, count = info.itemID, info.stackCount end
      elseif GetContainerItemInfo then
        local _, c, _, _, _, _, link, _, _, itemID = GetContainerItemInfo(bag, slot)
        id, count = itemID, c
      end
      if id then
        local name = ns.GetItemInfo and ns.GetItemInfo(id)
        if ns.IsPouch(id, name) then
          n = n + (count or 1)
          if name == ns.GAME.POUCH then DB().itemID = id end -- English client: ID learned for exports
        end
      end
    end
  end
  return n
end

local function Uid()
  local who = (UnitGUID and UnitGUID("player")) or (UnitName and UnitName("player")) or "?"
  local h = 0
  for i = 1, #who do h = (h * 31 + who:byte(i)) % 2147483647 end
  return string.format("%x-%x-%x", h, time(), math.random(0, 0xffff))
end

-- a writ was turned in (called from Quests.lua)
function ns.OnWritTurnedIn(writName)
  if not ns.db then return end
  local w = ns.db.writs[writName]
  local item = (w and w.item) or ns.ItemFromWrit(writName)
  local rank = (w and w.rank) or (item and ns.WRIT_LIST and ns.WRIT_LIST[item] and ns.WRIT_LIST[item].rank)
  local dest, zone = nil, nil
  if ns.WritDestination then dest, zone = ns.WritDestination(writName) end
  if dest then dest = dest:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") end
  recentTurnIns[#recentTurnIns + 1] = { rank = rank, item = item, dest = dest, zone = zone, t = GetTime() }
end

local function RecordOpen(copper)
  local p = DB()
  local src = table.remove(p.queue, 1)
  if type(src) ~= "table" or not ns.RANKS[src.rank] then return end -- pouch of unknown origin: not used
  local uid = Uid()
  local t = time()
  local info = { item = src.item, dest = src.dest, zone = src.zone }
  if ns.AddPouchSample(src.rank, copper, t, uid, "me", info) then
    ns.Debug(ns.F("CHAT_POUCH_RECORDED", ns.Coins(copper), src.rank))
    if ns.SharePouch then ns.SharePouch(src.rank, copper, t, uid, info) end
  end
end

-- Opening a pouch removes it from the bags and adds money; the two events can come in either order.
local opened = 0          -- pouches gone from the bags, money not matched yet
local gain                -- { v = copper, t } money gained, pouch not matched yet

local function Match()
  local now = GetTime()
  if opened > 0 and gain and math.abs(now - gain.t) <= OPEN_WINDOW and openedAt and now - openedAt <= OPEN_WINDOW then
    opened = opened - 1
    local v = gain.v
    gain = nil
    RecordOpen(v)
  end
  if openedAt and now - openedAt > OPEN_WINDOW then opened, openedAt = 0, nil end
  if gain and now - gain.t > OPEN_WINDOW then gain = nil end
end

local function OnBags()
  local n = CountPouches()
  if not n then return end
  if pouchCount == nil then pouchCount = n return end
  local now = GetTime()
  if n > pouchCount then
    -- new pouches: each takes the rank of a recent writ turn-in
    for _ = 1, n - pouchCount do
      local src
      while recentTurnIns[1] do
        local r = table.remove(recentTurnIns, 1)
        if now - r.t <= TURNIN_WINDOW then src = r break end
      end
      local q = DB().queue
      q[#q + 1] = src and { rank = src.rank, item = src.item, dest = src.dest, zone = src.zone } or { rank = "?" }
      while #q > 50 do table.remove(q, 1) end
    end
  elseif n < pouchCount then
    opened = opened + (pouchCount - n)
    openedAt = now
  end
  pouchCount = n
  Match()
end

local function OnMoney()
  local m = GetMoney and GetMoney() or 0
  if lastMoney and m > lastMoney then
    gain = { v = m - lastMoney, t = GetTime() }
  end
  lastMoney = m
  Match()
end

local f = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "BAG_UPDATE_DELAYED", "PLAYER_MONEY" }) do
  pcall(f.RegisterEvent, f, e)
end
f:SetScript("OnEvent", function(_, event)
  ns.Safe(function()
    if not ns.db then return end
    if event == "PLAYER_LOGIN" then
      DB()
      lastMoney = GetMoney and GetMoney() or 0
      pouchCount = CountPouches()
    elseif event == "BAG_UPDATE_DELAYED" then
      OnBags()
    elseif event == "PLAYER_MONEY" then
      OnMoney()
    end
  end)
end)

-- /writs pouch: what WritPrice knows about Coin Pouches
function ns.PrintPouch()
  ns.Print(L.CHAT_POUCH_HEADER)
  local all = {}
  for _, rank in ipairs(ns.RANK_ORDER) do
    local m, n, own = ns.PouchMedian(rank)
    if m then
      print("  " .. ns.F("CHAT_POUCH_LINE", rank, ns.Coins(m), n, own))
    else
      print("  " .. ns.F("CHAT_POUCH_NONE", rank))
    end
    local list = ns.db.pouch and ns.db.pouch.samples and ns.db.pouch.samples[rank]
    for _, s in ipairs(list or {}) do all[#all + 1] = { rank = rank, s = s } end
  end
  -- latest samples with what was turned in and where
  table.sort(all, function(a, b) return a.s.t > b.s.t end)
  if #all > 0 then print("  " .. L.CHAT_POUCH_LATEST) end
  for i = 1, math.min(8, #all) do
    local a = all[i]
    print(("    %s - %s - %s - %s%s"):format(date and date("%d/%m %H:%M", a.s.t) or a.s.t, a.rank, ns.Coins(a.s.v),
      a.s.item and ns.Disp(a.s.item) or "?", a.s.dest and (" @ " .. a.s.dest) or ""))
  end
end
