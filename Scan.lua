-- SPDX-License-Identifier: GPL-2.0-only
-- WritPrice: targeted auction house scan
-- Two engines: modern auction house (C_AuctionHouse, Buy/Sell tabs) and legacy one (QueryAuctionItems)
local ADDON, ns = ...
local L = ns.L

local S = { queue = {}, cur = nil, running = false, failed = 0 }
ns.scanStatus = nil
local res -- results of the running scan
local UpdateAHButton -- defined below

local PRICE_KEEP = 24 * 3600 -- a price that is not scanned again is kept 24 h at most
local REAGENT_TTL = 30 * 60  -- a reagent scanned less than 30 min ago is not searched again

local function Modern()
  return C_AuctionHouse and C_AuctionHouse.SendBrowseQuery and C_AuctionHouse.GetBrowseResults
end

local function Legacy()
  return QueryAuctionItems and GetAuctionItemInfo and GetNumAuctionItems and CanSendAuctionQuery
end

local function AHOpen()
  return (AuctionHouseFrame and AuctionHouseFrame:IsShown()) or (AuctionFrame and AuctionFrame:IsShown())
end

local function SetStatus(text)
  ns.scanStatus = text
  if UpdateAHButton then UpdateAHButton() end
  if ns.RefreshUI then ns.RefreshUI() end
end

local function ItemName(itemID)
  if not itemID then return nil end
  local n
  if C_Item and C_Item.GetItemNameByID then n = C_Item.GetItemNameByID(itemID) end
  if not n then n = ns.GetItemInfo(itemID) end
  if not n and C_Item and C_Item.RequestLoadItemDataByID then
    pcall(C_Item.RequestLoadItemDataByID, itemID)
  end
  return n
end

------------------------------------------------------------
-- Modern auction house engine
------------------------------------------------------------
-- "Exact name" filter: avoids getting every item whose name contains the text.
-- S.exactOK: nil = not checked yet on this client, true = reliable, false = do not use
local function ExactFilter()
  return Enum and Enum.AuctionHouseFilter and Enum.AuctionHouseFilter.ExactMatch
end

local function ModernQuery(q)
  local so = (Enum and Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price) or 0
  local filters = {}
  local ex = ExactFilter()
  q.exactFilter = false
  if q.exact and not q.noExact and S.exactOK ~= false and ex then
    filters[1] = ex
    q.exactFilter = true
  end
  C_AuctionHouse.SendBrowseQuery({
    searchString = q.text,
    sorts = { { sortOrder = so, reverseSort = false } },
    filters = filters,
    itemClassFilters = {},
  })
end

local function ModernReady()
  if C_AuctionHouse.IsThrottledMessageSystemReady then
    return C_AuctionHouse.IsThrottledMessageSystemReady()
  end
  return true
end

-- Reads the results. Returns:
--   "done": finished (rows passed to q.onRow)
--   "more": next page requested, waiting for the event
--   "wait": read again a bit later (names not loaded yet, or auction house not ready)
local function ModernRead(q)
  local list = C_AuctionHouse.GetBrowseResults() or {}
  local rows, missing, found = {}, false, false
  for _, r in ipairs(list) do
    local id = r.itemKey and r.itemKey.itemID
    local name = ItemName(id)
    if not name then
      missing = true
    else
      name = ns.CanonName(name, id) -- English name inside the addon
      rows[#rows + 1] = { name = name, unit = r.minPrice, count = r.totalQuantity or 1, id = id }
      if q.want and name == q.want then found = true end
    end
  end
  -- item query: once the wanted row is there, no need to load more
  if not found and not q.force then
    local full = not C_AuctionHouse.HasFullBrowseResults or C_AuctionHouse.HasFullBrowseResults()
    if not full and C_AuctionHouse.RequestMoreBrowseResults then
      if q.more < 20 then
        if not ModernReady() then return "wait" end
        q.more = q.more + 1
        C_AuctionHouse.RequestMoreBrowseResults()
        return "more"
      end
      q.partial = true
    end
    if missing and q.waits < (q.want and 4 or 12) then
      q.waits = q.waits + 1
      return "wait"
    end
  end
  for _, row in ipairs(rows) do ns.Safe(q.onRow, row) end
  return "done"
end

------------------------------------------------------------
-- Legacy auction house engine
------------------------------------------------------------
local PAGE = NUM_AUCTION_ITEMS_PER_PAGE or 50

local function LegacyRead(q)
  local batch, total = GetNumAuctionItems("list")
  batch, total = batch or 0, total or 0
  local rows, missing = {}, false
  for i = 1, batch do
    local name, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID, hasAll =
      GetAuctionItemInfo("list", i)
    if not name or name == "" or hasAll == false then
      missing = true
    elseif not name:find(q.text, 1, true) then
      return "stale"
    elseif (buyout or 0) > 0 then
      local c = math.max(count or 1, 1)
      rows[#rows + 1] = { name = ns.CanonName(name, itemID), unit = buyout / c, count = c, id = itemID, i = i }
    end
  end
  if missing and q.waits < 3 then
    q.waits = q.waits + 1
    return "wait"
  end
  for _, r in ipairs(rows) do ns.Safe(q.onRow, r) end
  if (q.page + 1) * PAGE < total and q.page + 1 < q.maxPages then
    q.page, q.sent, q.waits = q.page + 1, false, 0
    return "next"
  end
  return "done"
end

------------------------------------------------------------
-- Query queue (one at a time)
------------------------------------------------------------
local Finish
local runner = CreateFrame("Frame")
runner:Hide()
-- RegisterEvent errors when the event does not exist on this client: each call is protected
for _, e in ipairs({
  "AUCTION_ITEM_LIST_UPDATE",
  "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", "AUCTION_HOUSE_BROWSE_RESULTS_ADDED",
  "AUCTION_HOUSE_BROWSE_FAILURE",
}) do
  pcall(runner.RegisterEvent, runner, e)
end
runner:SetScript("OnEvent", function(_, event)
  local q = S.cur
  if not (q and q.sent) then return end
  if event == "AUCTION_HOUSE_BROWSE_FAILURE" then
    q.t = -1e9 -- failure reported by the server: retry at once instead of waiting
  else
    q.dirtyAt = GetTime()
  end
end)

local function ResetQuery(q)
  q.sent, q.waits, q.more = false, 0, 0
  q.dirtyAt, q.pollAt, q.partial, q.force = nil, nil, nil, nil
end

local function Tick()
  if not AHOpen() then
    Finish("closed")
    return
  end
  local q = S.cur
  if not q then
    q = table.remove(S.queue, 1)
    S.cur = q
    if not q then
      Finish()
      return
    end
    if q.label then SetStatus(q.label) end
  end
  local now = GetTime()
  if not q.sent and not q.text then
    -- name in the client language, asked to the game: wait a little for it, then skip this item
    q.text = q.textFn and q.textFn()
    if not q.text then
      q.nameT0 = q.nameT0 or now
      if now - q.nameT0 > 3 then
        S.cur = nil
        if res then res.noName = (res.noName or 0) + 1 end
      end
      return
    end
  end
  if not q.sent then
    if S.modern then
      if ModernReady() then
        q.sent, q.t, q.dirtyAt, q.pollAt = true, now, nil, nil
        ModernQuery(q)
      end
    elseif CanSendAuctionQuery() then
      q.sent, q.t, q.dirtyAt, q.pollAt = true, now, nil, nil
      QueryAuctionItems(q.text, nil, nil, q.page, false, nil, false, q.exact, nil)
    end
    return
  end
  -- read shortly after the last event, or a scheduled re-read (waiting for names)
  local delay = S.modern and 0.05 or 0.2
  local ready = (q.dirtyAt and now - q.dirtyAt > delay) or (q.pollAt and now >= q.pollAt)
  if ready then
    q.dirtyAt, q.pollAt = nil, nil
    local r
    if S.modern then r = ModernRead(q) else r = LegacyRead(q) end
    if r == "done" then
      S.cur = nil
      if q.onDone then ns.Safe(q.onDone, q) end
    elseif r == "wait" then
      q.t, q.pollAt = now, now + 0.3
    elseif r == "more" or r == "next" then
      q.t = now
    end
  elseif now - q.t > ((S.modern and q.want) and 5 or 10) then
    -- no answer: retry, then give up this query
    -- (item on the modern auction house: 2 tries of 5 s; otherwise 3 tries of 10 s)
    q.tries = (q.tries or 0) + 1
    if q.tries >= ((S.modern and q.want) and 2 or 3) then
      S.cur = nil
      S.failed = S.failed + 1
      if S.modern and not q.want then
        -- writ list: use whatever was received
        -- (nothing received: the queue stays empty and Finish keeps the previous scan)
        q.force = true
        ns.Safe(ModernRead, q)
        if res and next(res.writs) and q.onDone then ns.Safe(q.onDone, q) end
      end
    else
      ResetQuery(q)
    end
  end
end

runner:SetScript("OnUpdate", function()
  local ok = ns.Safe(Tick)
  if not ok and S.running then
    -- unexpected error: stop cleanly instead of repeating it every frame
    ns.Safe(Finish, "error")
  end
end)

local function Enqueue(q)
  q.page, q.waits, q.more = 0, 0, 0
  q.maxPages = q.maxPages or 10
  S.queue[#S.queue + 1] = q
end

------------------------------------------------------------
-- Scan the writs, then the requested items
------------------------------------------------------------
local function WritLink(r)
  local link
  if r.i and GetAuctionItemLink then link = GetAuctionItemLink("list", r.i) end
  if not link and r.id then link = select(2, ns.GetItemInfo(r.id)) or ("item:" .. r.id) end
  return link
end

local function OnWritRow(r)
  if not ns.IsWrit(r.name) or not r.unit or r.unit <= 0 then return end
  local sw = res.writs[r.name]
  if not sw then
    sw = { n = 0 }
    res.writs[r.name] = sw
  end
  sw.n = sw.n + (r.count or 1)
  if not sw.min or r.unit < sw.min then sw.min = r.unit end
  sw.id = r.id or sw.id
  if r.id then ns.LearnItemID(r.name, r.id) end
  local w = ns.WritInfo(r.name)
  if not w.rank then w.rank = ns.RankFromAuction(WritLink(r), r.i) end
end

local function ItemQuery(item, label)
  return {
    textFn = function() return ns.LocName(item) end, want = item, exact = true, maxPages = 10, label = label,
    onRow = function(r)
      if r.name ~= item or not r.unit or r.unit <= 0 then return end
      local it = res.items[item]
      if it and it.old then it = nil end
      if not it then
        it = { n = 0, t = time() }
        res.items[item] = it
      end
      it.n = it.n + (r.count or 1)
      if not it.min or r.unit < it.min then it.min = r.unit end
      if r.id then ns.LearnItemID(item, r.id) end
    end,
    onDone = function(q)
      local it = res.items[item]
      local fresh = it ~= nil and not it.old
      if q.exactFilter then
        if fresh then
          S.exactOK = true
        elseif S.exactOK == nil and not q.retried then
          -- "exact name" filter not checked yet on this client: ask again without it
          q.retried, q.noExact, q.tries = true, true, nil
          ResetQuery(q)
          table.insert(S.queue, 1, q)
          return
        end
      elseif q.retried and fresh and S.exactOK == nil then
        S.exactOK = false -- found without the filter but not with it: stop using it
      end
      res.asked[item] = time()
      res.nAsked = res.nAsked + 1
      if it and it.old then
        res.items[item] = nil -- searched and not found: the old price is no longer valid
      elseif it and q.partial then
        it.partial = true
      end
    end,
  }
end

local function OnWritsDone()
  res.writsDone = true
  local items, list = {}, {}
  local f = res.filter
  local profOff = res.profOff
  local now = time()
  for name, sw in pairs(res.writs) do
    local w = ns.WritInfo(name)
    -- second try for ranks not read yet (tooltip not loaded on the first pass)
    if not w.rank and sw.id then w.rank = ns.RankFromAuction(WritLink({ id = sw.id })) end
    local item = w.item
    -- rank read from the tooltip, else the built-in list (a client in another language reads no rank)
    local rank = w.rank or (item and ns.WRIT_LIST and ns.WRIT_LIST[item] and ns.WRIT_LIST[item].rank)
    local wanted = (f == "ALL" or not rank or rank == f)
    -- profession filter: only search items of checked professions
    if wanted and not ns.ProfWanted(ns.ProfOf(item), profOff) then wanted = false end
    local doneUntil = ns.db.done[name]
    if doneUntil and doneUntil > now then wanted = false end
    if item and wanted and not items[item] then
      items[item] = true
      list[#list + 1] = item
    end
  end
  table.sort(list)
  -- recipe reagents (crafting cost), no duplicates, skipping recently scanned ones
  local reag = {}
  if not ns.db.noReagents then
    for _, item in ipairs(list) do
      for _, rn in ipairs(ns.ReagentsToScan and ns.ReagentsToScan(item) or {}) do
        if not items[rn] then
          items[rn] = true
          local a = res.asked[rn]
          if a and now - a < REAGENT_TTL then
            res.cached = res.cached + 1
          else
            reag[#reag + 1] = rn
          end
        end
      end
    end
  end
  table.sort(reag)
  -- prices Auctionator already knows from today: no search needed
  if ns.AtrFresh then
    local function Keep(names)
      local out = {}
      for _, n in ipairs(names) do
        local price = ns.AtrFresh(n)
        if price then
          local _, age = ns.AtrPrice(n)
          res.items[n] = { min = price, n = 0, t = now - (age or 0) * 86400, src = "atr" }
          res.asked[n] = now
          res.atr = (res.atr or 0) + 1
          res.nAsked = res.nAsked + 1
        else
          out[#out + 1] = n
        end
      end
      return out
    end
    list, reag = Keep(list), Keep(reag)
  end
  local fl = (f == "ALL") and L.FILTER_ALL or f
  for i, item in ipairs(list) do
    Enqueue(ItemQuery(item, ns.F("SCAN_STATUS_ITEMS", fl, i, #list)))
  end
  for i, rn in ipairs(reag) do
    Enqueue(ItemQuery(rn, ns.F("SCAN_STATUS_REAGENTS", fl, i, #reag)))
  end
end

local function Duration(sec)
  sec = math.floor(sec + 0.5)
  if sec < 60 then return ns.F("DURATION_S", sec) end
  return ns.F("DURATION_MS", math.floor(sec / 60), sec % 60)
end

-- why: nil = complete scan, otherwise the reason it stopped
Finish = function(why)
  S.running, S.queue, S.cur = false, {}, nil
  runner:Hide()
  local r = res
  res = nil
  if not r then
    SetStatus(nil)
    return
  end
  if not r.writsDone then
    -- incomplete writ list: keep the previous scan
    SetStatus(nil)
    ns.Print(ns.F("CHAT_SCAN_ABORTED", L["SCAN_WHY_" .. (why or "timeout")]))
    return
  end
  local nw, found, asked = 0, 0, r.nAsked
  for _ in pairs(r.writs) do nw = nw + 1 end
  for _, v in pairs(r.items) do if not v.old then found = found + 1 end end
  local took = Duration(GetTime() - (S.t0 or GetTime()))
  local cached, failed = r.cached, S.failed
  -- working fields not needed in the saved data
  r.writsDone, r.cached, r.nAsked = nil, nil, nil
  if ns.AtrClearCache then ns.AtrClearCache() end
  ns.db.scan[ns.RealmKey()] = r
  local msg
  if why then
    msg = ns.F("CHAT_SCAN_PARTIAL", L["SCAN_WHY_" .. why], took, nw, found, asked)
  else
    msg = ns.F("CHAT_SCAN_DONE", took, nw, found, asked)
  end
  if failed > 0 then msg = msg .. ns.F("CHAT_SCAN_FAILED", failed) end
  if (r.atr or 0) > 0 then msg = msg .. ns.F("CHAT_ATR_USED", r.atr) end
  r.atr = nil
  SetStatus(nil)
  ns.Print(msg)
  if cached > 0 then ns.Debug(ns.F("CHAT_SCAN_CACHED", cached)) end
  if (r.noName or 0) > 0 then ns.Print(ns.F("CHAT_LOC_NONAME", r.noName)) end
  r.noName = nil
end

function ns.StopScan()
  if S.running then Finish("stopped") end
end

function ns.StartScan()
  if S.running or (ns.IsFullScanning and ns.IsFullScanning()) then
    ns.Print(L.CHAT_SCAN_RUNNING)
    return
  end
  if not AHOpen() then
    ns.Print(L.CHAT_OPEN_AH)
    return
  end
  if AuctionHouseFrame and AuctionHouseFrame:IsShown() and Modern() then
    S.modern = true
  elseif Legacy() then
    S.modern = false
  else
    ns.Print(L.CHAT_AH_API)
    return
  end
  -- client in another language: the writ name is learned from a full scan (or a known writ ID)
  local writText = ns.WritSearchText()
  if not writText then
    if ns.StartFullScan and ns.FullScanWait and ns.FullScanWait() == 0 then
      ns.Print(L.CHAT_LOC_FULL)
      ns.StartFullScan()
    else
      ns.Print(L.CHAT_LOC_NEED_FULL)
    end
    return
  end
  local filter = (ns.GetFilter and ns.GetFilter()) or "ALL"
  local now = time()
  res = { t = now, writs = {}, items = {}, asked = {}, filter = filter, cached = 0, nAsked = 0,
    profOff = ns.ProfOffCopy() } -- profession filter frozen at start
  -- keep recent prices of the previous scan for what is not scanned again
  local old = ns.CurrentScan and ns.CurrentScan()
  if old and old.items then
    for k, v in pairs(old.items) do
      local t = v.t or old.t or 0
      if now - t < PRICE_KEEP then res.items[k] = { min = v.min, n = v.n, t = t, old = true, src = v.src } end
    end
  end
  if old and old.asked then
    for k, t in pairs(old.asked) do
      if now - t < REAGENT_TTL then res.asked[k] = t end
    end
  end
  S.queue, S.cur, S.running, S.failed, S.t0 = {}, nil, true, 0, GetTime()
  Enqueue({
    text = writText, exact = false, maxPages = 20,
    label = L.SCAN_STATUS_WRITS,
    onRow = OnWritRow, onDone = OnWritsDone,
  })
  runner:Show()
  SetStatus(L.SCAN_STATUS_WRITS)
end

function ns.IsScanning() return S.running end
function ns.AHOpen() return AHOpen() end

function ns.ScanDiag()
  local e = S.exactOK
  print("  " .. ns.F("DEBUG_EXACT", e == nil and L.DEBUG_EXACT_UNKNOWN
    or (e and ("|cff00ff00" .. L.DEBUG_EXACT_OK .. "|r") or ("|cffff4040" .. L.DEBUG_EXACT_BAD .. "|r"))))
end

------------------------------------------------------------
-- "WritPrice" button above the auction house window: opens / closes the /writs window.
-- It never starts a scan (scans start from the WritPrice window or /writs scan).
------------------------------------------------------------
local button

UpdateAHButton = function()
  if button then button:SetText("WritPrice") end
end

local function PlaceButton()
  if ns.db and ns.db.ahButton == false then
    if button then button:Hide() end
    return true -- handled: no retry
  end
  local parent = (AuctionHouseFrame and AuctionHouseFrame:IsShown() and AuctionHouseFrame)
    or (AuctionFrame and AuctionFrame:IsShown() and AuctionFrame)
  if not parent then return false end
  if not button or button:GetParent() ~= parent then
    button = button or CreateFrame("Button", "WritPriceScanButton", parent, "UIPanelButtonTemplate")
    button:SetParent(parent)
    button:ClearAllPoints()
    button:SetSize(130, 24)
    button:SetPoint("BOTTOMRIGHT", parent, "TOPRIGHT", -40, 2)
    button:SetFrameStrata("HIGH")
    button:SetScript("OnClick", function()
      if ns.ToggleUI then ns.Safe(ns.ToggleUI) end
    end)
    button:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:AddLine("WritPrice", 1, 0.82, 0)
      GameTooltip:AddLine(L.TIP_AHBTN_1, 1, 1, 1)
      GameTooltip:AddLine(L.TIP_AHBTN_2, 0.7, 0.7, 0.7)
      if ns.LastScanText then GameTooltip:AddLine(ns.LastScanText(), 0.7, 0.7, 0.7) end
      GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end
  UpdateAHButton()
  button:Show()
  return true
end

function ns.UpdateAHButtonVisibility()
  if (AuctionHouseFrame and AuctionHouseFrame:IsShown()) or (AuctionFrame and AuctionFrame:IsShown()) then
    PlaceButton()
  elseif button and ns.db.ahButton == false then
    button:Hide()
  end
end

local ah = CreateFrame("Frame")
pcall(ah.RegisterEvent, ah, "AUCTION_HOUSE_SHOW")
pcall(ah.RegisterEvent, ah, "AUCTION_HOUSE_CLOSED")
ah:SetScript("OnEvent", function(_, event)
  ns.Safe(function()
    if event == "AUCTION_HOUSE_SHOW" and not PlaceButton() then
      -- the auction house window may only show after this event: try again
      C_Timer.After(0.5, function() ns.Safe(PlaceButton) end)
    end
    if ns.RefreshUI then ns.RefreshUI() end
  end)
end)
