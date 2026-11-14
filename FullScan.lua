-- SPDX-License-Identifier: GPL-2.0-only
-- WritPrice: fast full scan. One request returns every auction (modern: C_AuctionHouse.ReplicateItems,
-- legacy: QueryAuctionItems getAll); the server allows it about once every 15 minutes (per account).
-- Auctions are read in slices so the game does not freeze, grouped by item ID, and item names are resolved
-- once per ID at the end. When a full scan is not possible, the targeted scan (Scan.lua) is used.
local ADDON, ns = ...
local L = ns.L

local COOLDOWN = 15 * 60  -- server limit for a full scan (estimate: no API tells the real value)
local RETRY_AFTER = 60    -- after a refused request, local delay before trying again
local WAIT_ANSWER = 60    -- seconds to wait for the server answer
local WAIT_NAMES = 8      -- seconds to wait for item names not in the client cache
local BUDGET_MS = 8       -- reading time per frame
local BATCH = 400         -- entries per frame when debugprofilestop is missing
local STATUS_EVERY = 0.25 -- seconds between two window refreshes while reading

local F = { running = false }

local function Modern()
  return C_AuctionHouse and C_AuctionHouse.ReplicateItems and C_AuctionHouse.GetNumReplicateItems
    and C_AuctionHouse.GetReplicateItemInfo
end

local function Legacy()
  return QueryAuctionItems and GetAuctionItemInfo and GetNumAuctionItems and CanSendAuctionQuery
end

local function ModernAH() return AuctionHouseFrame and AuctionHouseFrame:IsShown() end
local function LegacyAH() return AuctionFrame and AuctionFrame:IsShown() end

local function Status(text, force)
  ns.scanStatus = text
  local t = GetTime()
  if force or not F.statusAt or t - F.statusAt >= STATUS_EVERY then
    F.statusAt = t
    if ns.RefreshUI then ns.RefreshUI() end
  end
end

------------------------------------------------------------
-- Availability (one time stamp: the server limit is per account)
------------------------------------------------------------
local function LastFull()
  local v = ns.db and ns.db.fullAt
  return type(v) == "number" and v or nil
end

-- Seconds before the next full scan is allowed (0 = now), or nil when this client cannot do it
function ns.FullScanWait()
  if not ns.db then return nil end
  local nextAt = F.retryAt or 0
  local last = LastFull()
  if last then nextAt = math.max(nextAt, last + COOLDOWN) end
  local wait = math.max(0, nextAt - time())
  if ModernAH() then
    if not Modern() then return nil end
  elseif LegacyAH() then
    if not Legacy() then return nil end
    local _, canAll = CanSendAuctionQuery()
    if not canAll then return math.max(wait, 1) end
  elseif not (Modern() or Legacy()) then
    return nil
  end
  return wait
end

function ns.FullScanText()
  local w = ns.FullScanWait()
  if w == nil then return L.FULL_UNSUPPORTED end
  if w <= 0 then return L.FULL_READY end
  return ns.F("FULL_WAIT", math.floor(w / 60), w % 60)
end

------------------------------------------------------------
-- Reading the auctions (grouped by item ID; names come later)
------------------------------------------------------------
local function Info(i)
  if F.kind == "modern" then return C_AuctionHouse.GetReplicateItemInfo(i) end
  return GetAuctionItemInfo("list", i)
end

local function Link(i)
  if F.kind == "modern" then
    return C_AuctionHouse.GetReplicateItemLink and C_AuctionHouse.GetReplicateItemLink(i)
  end
  return GetAuctionItemLink and GetAuctionItemLink("list", i)
end

local function Bucket(map, key)
  local b = map[key]
  if not b then
    b = { n = 0 }
    map[key] = b
  end
  return b
end

local function ReadOne(i)
  local name, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID = Info(i)
  if not buyout or buyout <= 0 then return end
  count = math.max(count or 1, 1)
  local unit = buyout / count
  local b
  if itemID then
    b = Bucket(F.byID, itemID)
    if name and name ~= "" then b.name = b.name or name end
  elseif name and name ~= "" then
    b = Bucket(F.byName, name)
  else
    return
  end
  b.n = b.n + count
  if not b.min or unit < b.min then b.min, b.idx = unit, i end
end

-- Name of an item ID: the game client first (WoW Forever names), then our tables
local function ResolveName(id)
  if C_Item and C_Item.GetItemNameByID then
    local ok, v = pcall(C_Item.GetItemNameByID, id)
    if ok and v and v ~= "" then return v end
  end
  local v = ns.GetItemInfo and ns.GetItemInfo(id)
  if v and v ~= "" then return v end
  return F.reverse and F.reverse[id]
end

local function BuildReverse()
  F.reverse = {}
  for n, id in pairs(ns.ITEM_IDS or {}) do F.reverse[id] = n end
  for n, id in pairs(ns.db.itemIDs or {}) do F.reverse[id] = n end
end

-- names missing after the read: ask the client to load them (once per ID)
local function RequestNames()
  F.unresolved = {}
  for id, b in pairs(F.byID) do
    if not b.name then
      local n = ResolveName(id)
      if n then
        b.name = n
      else
        F.unresolved[id] = true
        if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
      end
    end
  end
end

local function TryResolve(id)
  local b = F.byID[id]
  if not (b and F.unresolved[id]) then return end
  local n = C_Item and C_Item.GetItemNameByID and select(2, pcall(C_Item.GetItemNameByID, id))
  if type(n) ~= "string" or n == "" then n = ResolveName(id) end
  if n then
    b.name = n
    F.unresolved[id] = nil
  end
end

------------------------------------------------------------
-- Saving
------------------------------------------------------------
local Finish

local function Merge()
  local seen = {}
  local function add(name, b, id)
    local s = seen[name]
    if not s then
      seen[name] = { min = b.min, n = b.n, idx = b.idx, id = id }
    else
      s.n = s.n + b.n
      if b.min < s.min then s.min, s.idx = b.min, b.idx end
      s.id = s.id or id
    end
  end
  for id, b in pairs(F.byID) do if b.name then add(b.name, b, id) end end
  for name, b in pairs(F.byName) do add(name, b, nil) end
  return seen
end

local function Commit()
  local now = time()
  local seen = Merge()
  F.seen = seen
  local unknownIDs = {}
  for id in pairs(F.unresolved or {}) do unknownIDs[id] = true end
  local res = { t = now, writs = {}, items = {}, asked = {}, filter = "ALL", profOff = {}, full = true }
  local wanted = {}
  for name, s in pairs(seen) do
    if ns.IsWrit(name) then
      res.writs[name] = { min = s.min, n = s.n, id = s.id }
      local w = ns.WritInfo(name)
      if w.item then wanted[w.item] = true end
    end
  end
  for item in pairs(ns.WRIT_LIST or {}) do wanted[item] = true end
  for name in pairs(ns.activeWrits or {}) do
    local item = ns.ItemFromWrit(name)
    if item then wanted[item] = true end
  end
  local reagents = {}
  for item in pairs(wanted) do
    for _, rn in ipairs(ns.ReagentsToScan and ns.ReagentsToScan(item) or {}) do reagents[rn] = true end
  end
  for rn in pairs(reagents) do wanted[rn] = true end
  local old = ns.CurrentScan and ns.CurrentScan()
  local found, asked = 0, 0
  for x in pairs(wanted) do
    asked = asked + 1
    local s = seen[x]
    if s then
      res.items[x] = { min = s.min, n = s.n, t = now }
      res.asked[x] = now
      if s.id then ns.db.itemIDs[x] = s.id end
      found = found + 1
    else
      -- an expected item whose ID is among the unidentified auctions: unknown, keep the older price
      local id = ns.ItemIDByName and ns.ItemIDByName(x)
      local maybe = (id and unknownIDs[id]) or (F.partial and not id)
      if maybe then
        if old and old.items and old.items[x] then
          local o = old.items[x]
          res.items[x] = { min = o.min, n = o.n, t = o.t or old.t, old = true }
        end
      else
        res.asked[x] = now -- complete snapshot: really not for sale
      end
    end
  end
  ns.db.scan[ns.RealmKey()] = res
  if ns.AtrClearCache then ns.AtrClearCache() end
  local nw = 0
  for _ in pairs(res.writs) do nw = nw + 1 end
  local unknown = 0
  for id in pairs(unknownIDs) do unknown = unknown + (F.byID[id] and F.byID[id].n or 0) end
  return nw, found, asked, unknown
end

-- ranks of new writs, read from their tooltips a few per frame after saving (index checked first)
local function IndexStillIs(idx, name)
  if F.kind == "modern" then
    local n = C_AuctionHouse.GetReplicateItemInfo(idx)
    return n == nil or n == "" or n == name
  end
  local n = GetAuctionItemInfo("list", idx)
  return n == name
end

local function RankStep()
  local n = 0
  while n < 5 do
    local item = table.remove(F.rankQueue)
    if not item then return true end
    local s = F.seen and F.seen[item.name]
    local w = ns.WritInfo(item.name)
    if s and s.idx and not w.rank and IndexStillIs(s.idx, item.name) then
      w.rank = ns.RankFromAuction(Link(s.idx), F.kind == "legacy" and s.idx or nil)
      if not w.rank and item.tries < 3 then
        item.tries = item.tries + 1
        table.insert(F.rankQueue, 1, item) -- tooltip not cached yet: try again later
      end
    end
    n = n + 1
  end
  return false
end

local function FreeMemory()
  F.byID, F.byName, F.seen, F.unresolved, F.reverse, F.rankQueue = nil, nil, nil, nil, nil, nil
end

------------------------------------------------------------
-- Driver
------------------------------------------------------------
local runner = CreateFrame("Frame")
runner:Hide()

local function Now() return debugprofilestop and debugprofilestop() or nil end

local function SendRequest()
  if F.kind == "modern" then
    F.countBefore = C_AuctionHouse.GetNumReplicateItems() or 0
    C_AuctionHouse.ReplicateItems()
    F.sent = true
  else
    local canQuery, canAll = CanSendAuctionQuery()
    if canQuery and canAll then
      QueryAuctionItems("", nil, nil, 0, false, nil, true, false, nil)
      F.sent = true
    end
  end
  if F.sent then F.sentAt = GetTime() end
end

local function AnswerReady(t)
  if not (F.sent and F.eventAt and F.eventAt - F.sentAt >= 0 and t - F.eventAt > 0.3) then return nil end
  if F.kind == "modern" then
    local n = C_AuctionHouse.GetNumReplicateItems() or 0
    if n > 0 then return n, n end
    return nil
  end
  -- legacy: accept only the getAll answer (more than one page, or everything in one batch)
  local batch, total = GetNumAuctionItems("list")
  batch, total = batch or 0, total or 0
  if batch > 0 and (batch > (NUM_AUCTION_ITEMS_PER_PAGE or 50) or batch == total) then return batch, total end
  return nil
end

local function Tick()
  local t = GetTime()
  if F.phase == "ranks" then
    if RankStep() then
      runner:Hide()
      F.phase = nil
      FreeMemory()
      if ns.RefreshUI then ns.RefreshUI() end
    end
    return
  end
  if not (ModernAH() or LegacyAH()) then
    if F.phase == "names" then
      F.closedDuringNames = true -- reading is done and the quota used: save what we have
    else
      Finish("closed")
      return
    end
  end
  if F.phase == "wait" then
    if not F.sent then
      SendRequest()
      if not F.sent and t - F.t0 > WAIT_ANSWER then Finish("refused") end
      return
    end
    local batch, total = AnswerReady(t)
    if batch then
      F.total, F.batch = batch, batch
      F.partial = (total and batch < total) or false
      F.i = F.kind == "modern" and 0 or 1
      F.last = F.kind == "modern" and batch - 1 or batch
      F.phase = "read"
    elseif t - F.sentAt > WAIT_ANSWER then
      Finish("refused")
    end
    return
  end
  if F.phase == "read" then
    local start = Now()
    local done = 0
    while F.i <= F.last do
      ReadOne(F.i)
      F.i = F.i + 1
      done = done + 1
      if start then
        if Now() - start > BUDGET_MS then break end
      elseif done >= BATCH then
        break
      end
    end
    Status(ns.F("SCAN_STATUS_FULL_READ", math.min(F.i, F.total), F.total))
    if F.i > F.last then
      RequestNames()
      F.phase, F.namesT0, F.sweepAt = "names", t, t
    end
    return
  end
  if F.phase == "names" then
    if t - F.sweepAt > 0.5 then
      F.sweepAt = t
      for id in pairs(F.unresolved) do F.toTry = F.toTry or {}; F.toTry[#F.toTry + 1] = id end
    end
    if F.toTry then
      local list = F.toTry
      F.toTry = nil
      for _, id in ipairs(list) do TryResolve(id) end
    end
    if next(F.unresolved) and t - F.namesT0 < WAIT_NAMES and not F.closedDuringNames then
      Status(L.SCAN_STATUS_FULL_NAMES)
      return
    end
    local nw, found, asked, unknown = Commit()
    F.result = { nw = nw, found = found, asked = asked, unknown = unknown }
    F.rankQueue = {}
    for name in pairs(F.seen) do
      if ns.IsWrit(name) and not ns.WritInfo(name).rank then
        F.rankQueue[#F.rankQueue + 1] = { name = name, tries = 0 }
      end
    end
    F.phase = (ModernAH() or LegacyAH()) and "ranks" or nil
    Finish(nil)
    if not F.phase then runner:Hide() FreeMemory() end
  end
end

runner:SetScript("OnUpdate", function()
  local ok = ns.Safe(Tick)
  if not ok then
    runner:Hide()
    if F.running then ns.Safe(Finish, "error") end
  end
end)

local ev = CreateFrame("Frame")
for _, e in ipairs({ "REPLICATE_ITEM_LIST_UPDATE", "AUCTION_ITEM_LIST_UPDATE", "ITEM_DATA_LOAD_RESULT" }) do
  pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event, itemID)
  if not F.running then return end
  if event == "ITEM_DATA_LOAD_RESULT" then
    if F.phase == "names" and itemID and F.unresolved and F.unresolved[itemID] then
      F.toTry = F.toTry or {}
      F.toTry[#F.toTry + 1] = itemID
    end
  elseif F.phase == "wait" and F.sent then
    if (event == "REPLICATE_ITEM_LIST_UPDATE" and F.kind == "modern")
       or (event == "AUCTION_ITEM_LIST_UPDATE" and F.kind == "legacy") then
      F.eventAt = GetTime()
    end
  end
end)

local function Duration(sec)
  sec = math.floor(sec + 0.5)
  if sec < 60 then return ns.F("DURATION_S", sec) end
  return ns.F("DURATION_MS", math.floor(sec / 60), sec % 60)
end

Finish = function(why)
  local wasRunning = F.running
  F.running = false
  ns.scanStatus = nil
  if why then
    runner:Hide()
    F.phase = nil
    FreeMemory()
    if why == "refused" then
      -- the request did not go through: the server limit did not start, try again in a minute
      ns.db.fullAt = F.prevFullAt
      F.retryAt = time() + RETRY_AFTER
      ns.Print(L.CHAT_FULL_REFUSED)
      if ns.RefreshUI then ns.RefreshUI() end
      if ns.StartScan and (ModernAH() or LegacyAH()) then ns.Safe(ns.StartScan) end
      return
    end
    if wasRunning then ns.Print(ns.F("CHAT_SCAN_ABORTED", L["SCAN_WHY_" .. why])) end
    if ns.RefreshUI then ns.RefreshUI() end
    return
  end
  local r = F.result
  local msg = ns.F("CHAT_FULL_DONE", Duration(GetTime() - F.startT), F.total or 0, r.nw, r.found, r.asked)
  if r.unknown > 0 then msg = msg .. ns.F("CHAT_FULL_PARTIAL", r.unknown) end
  ns.Print(msg)
  if ns.RefreshUI then ns.RefreshUI() end
end

------------------------------------------------------------
-- Entry points
------------------------------------------------------------
function ns.StartFullScan(quiet)
  if F.running or (ns.IsTargetedScanning and ns.IsTargetedScanning()) then
    if not quiet then ns.Print(L.CHAT_SCAN_RUNNING) end
    return false
  end
  if not (ModernAH() or LegacyAH()) then
    ns.Print(L.CHAT_OPEN_AH)
    return false
  end
  local wait = ns.FullScanWait()
  if wait == nil then
    ns.Print(L.CHAT_FULL_UNSUPPORTED)
    return false
  end
  if wait > 0 then
    ns.Print(ns.F("CHAT_FULL_THROTTLED", math.floor(wait / 60), wait % 60))
    return false
  end
  F.kind = ModernAH() and "modern" or "legacy"
  F.running, F.phase, F.t0, F.startT = true, "wait", GetTime(), GetTime()
  F.sent, F.sentAt, F.eventAt, F.statusAt, F.closedDuringNames = false, nil, nil, nil, nil
  F.byID, F.byName, F.unresolved, F.toTry, F.total, F.result, F.partial = {}, {}, {}, nil, 0, nil, false
  BuildReverse()
  F.prevFullAt = LastFull()
  ns.db.fullAt = time() -- the quota is used even if the auction house closes; restored if refused
  F.retryAt = nil
  SendRequest()
  Status(L.SCAN_STATUS_FULL_WAIT, true)
  runner:Show()
  return true
end

function ns.IsFullScanning() return F.running end

-- Auto: full scan when allowed, else targeted scan (which uses Auctionator's prices when it can)
function ns.StartAutoScan(forceTargeted)
  if ns.IsScanning() then
    ns.Print(L.CHAT_SCAN_RUNNING)
    return
  end
  local mode = forceTargeted and "targeted" or (ns.db.scanMode or "auto")
  if mode ~= "targeted" then
    local wait = ns.FullScanWait()
    if wait == 0 then
      if ns.StartFullScan(true) then return end
    elseif mode == "full" then
      if wait == nil then ns.Print(L.CHAT_FULL_UNSUPPORTED)
      else ns.Print(ns.F("CHAT_FULL_THROTTLED", math.floor(wait / 60), wait % 60)) end
      return
    end
  end
  ns.StartScan()
end

-- the targeted scan and the full scan share the "scanning" state and the Stop button
do
  local targetedIsScanning, targetedStop = ns.IsScanning, ns.StopScan
  ns.IsTargetedScanning = targetedIsScanning
  function ns.IsScanning() return F.running or targetedIsScanning() end
  function ns.StopScan()
    if F.running then Finish("stopped") else targetedStop() end
  end
end
