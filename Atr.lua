-- SPDX-License-Identifier: GPL-2.0-only
-- WritPrice: optional bridge to Auctionator's public API (prices it already knows). Nothing here is required.
local ADDON, ns = ...

local CALLER = "WritPrice"

local function API()
  local a = Auctionator and Auctionator.API and Auctionator.API.v1
  if type(a) == "table" and type(a.GetAuctionPriceByItemID) == "function" then return a end
  return nil
end

-- Auctionator installed and its prices allowed in the settings
function ns.AtrAvailable()
  return API() ~= nil and not (ns.db and ns.db.useAtr == false)
end

function ns.AtrInstalled() return API() ~= nil end

-- itemID of an item name: saved scans, built-in table, then the client cache
function ns.ItemIDByName(name)
  if type(name) ~= "string" then return nil end
  local id = (ns.db and ns.db.itemIDs[name]) or (ns.ITEM_IDS and ns.ITEM_IDS[name])
  if id then return id end
  if C_Item and C_Item.GetItemInfoInstant then
    local ok, v = pcall(C_Item.GetItemInfoInstant, name)
    if ok and type(v) == "number" then return v end
  elseif GetItemInfoInstant then
    local ok, v = pcall(GetItemInfoInstant, name)
    if ok and type(v) == "number" then return v end
  end
  return nil
end

-- cache name -> { price, age } (negative results too), cleared after 60 s, on Auctionator updates,
-- when the option changes and at the end of our scans
local cache, cacheAt = {}, 0
function ns.AtrClearCache() cache, cacheAt = {}, 0 end

-- Auctionator price (copper, per unit) and age in days (nil when Auctionator cannot tell)
function ns.AtrPrice(name)
  if not ns.AtrAvailable() or type(name) ~= "string" then return nil end
  local now = GetTime()
  if now - cacheAt > 60 then cache, cacheAt = {}, now end
  local c = cache[name]
  if c then return c.price, c.age end
  local api = API()
  local id = ns.ItemIDByName(name)
  local price, age
  if id then
    local ok, p = pcall(api.GetAuctionPriceByItemID, CALLER, id)
    if ok and type(p) == "number" and p > 0 then
      price = p
      if type(api.GetAuctionAgeByItemID) == "function" then
        local ok2, a = pcall(api.GetAuctionAgeByItemID, CALLER, id)
        if ok2 and type(a) == "number" then age = a end
      end
    end
  end
  cache[name] = { price = price, age = age }
  return price, age
end

-- Auctionator price usable instead of ours: known age, at most 2 days, and newer than what we know.
-- it = our item entry (may be nil), asked = when our last scan searched it (nil = never)
function ns.AtrFallback(name, it, asked)
  local price, age = ns.AtrPrice(name)
  if not price or age == nil or age > 2 then return nil end
  local atrTime = time() - age * 86400
  if it and not it.old then return nil end                -- we have a fresh price of our own
  if it and it.old and (it.t or 0) >= atrTime then return nil end
  if not it and asked and asked >= atrTime then return nil end -- our scan says: not for sale
  return price, age
end

-- Price recent enough to skip our own search (same day by default)
function ns.AtrFresh(name)
  local price, age = ns.AtrPrice(name)
  if price and age and age <= ((ns.db and ns.db.atrMaxAge) or 0) then return price, age end
  return nil
end

-- Refresh the window when Auctionator finishes a scan
local f = CreateFrame("Frame")
pcall(f.RegisterEvent, f, "PLAYER_LOGIN")
f:SetScript("OnEvent", function()
  ns.Safe(function()
    local api = API()
    if api and type(api.RegisterForDBUpdate) == "function" then
      local pending = false
      pcall(api.RegisterForDBUpdate, CALLER, function()
        ns.AtrClearCache()
        if pending or not (C_Timer and C_Timer.After) then return end
        pending = true
        C_Timer.After(0.5, function() -- Auctionator may call this in bursts
          pending = false
          if ns.RefreshUI then ns.Safe(ns.RefreshUI) end
        end)
      end)
    end
  end)
end)
