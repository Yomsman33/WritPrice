-- SPDX-License-Identifier: GPL-2.0-only
-- WritPrice: crafting cost of an item (reagents at auction house price, or vendor price for supplies)
local ADDON, ns = ...
local L = ns.L

-- Reagent price: cheapest of the auction house (last scan) and the vendor (supplies)
function ns.ReagentPrice(name)
  local sc = ns.CurrentScan()
  local it = sc and sc.items and sc.items[name]
  local ah = it and it.min
  local src = (it and it.src == "atr") and "atr" or "ah"
  if ns.AtrFallback then
    local p = ns.AtrFallback(name, it, sc and sc.asked and sc.asked[name])
    if p then ah, src = p, "atr" end
  end
  local vend
  local id = ns.VENDOR and ns.VENDOR[name]
  if id then
    local sell = select(11, ns.GetItemInfo(id))
    if sell and sell > 0 then vend = sell * 4 end
  end
  if ah and vend then
    if vend <= ah then return vend, "vendor" end
    return ah, src
  end
  if ah then return ah, src end
  if vend then return vend, "vendor" end
  return nil
end

-- Cost to craft ONE item. Returns cost (nil if a price is missing), recipe, details, missing reagents
function ns.CraftCost(item)
  local rc = item and ns.RECIPES and ns.RECIPES[item]
  if not rc then return nil end
  local total, parts, missing = 0, {}, {}
  for i = 1, #rc.r, 2 do
    local name, count = rc.r[i], rc.r[i + 1]
    local price, src = ns.ReagentPrice(name)
    parts[#parts + 1] = { name = name, count = count, price = price, src = src }
    if price then total = total + price * count else missing[#missing + 1] = name end
  end
  local cost = (#missing == 0) and total / (rc.n or 1) or nil
  return cost, rc, parts, missing
end

-- Reagents to look up at the auction house for an item (vendor supplies excluded)
function ns.ReagentsToScan(item)
  local rc = item and ns.RECIPES and ns.RECIPES[item]
  local out = {}
  if not rc then return out end
  for i = 1, #rc.r, 2 do
    local name = rc.r[i]
    if not (ns.VENDOR and ns.VENDOR[name]) then out[#out + 1] = name end
  end
  return out
end

function ns.ProfLabel(rc)
  if not rc then return "" end
  local key = ns.PROF_NAMES and ns.PROF_NAMES[rc.p]
  local name = key and (ns.PROF_KEYS[key] and ns.ProfName(key) or L["PROF_" .. key]) or "?"
  return name .. " " .. (rc.s or "?")
end

-- Adds the recipe breakdown to a tooltip
function ns.AddCraftLines(tt, item, qty)
  local cost, rc, parts, missing = ns.CraftCost(item)
  if not rc then return end
  qty = qty or 1
  tt:AddLine(ns.F("TIP_CRAFT_HEADER", ns.ProfLabel(rc)) .. ((rc.n or 1) > 1 and ns.F("TIP_CRAFT_MAKES", rc.n) or ""), 1, 0.82, 0)
  for _, p in ipairs(parts) do
    local right = p.price and (ns.Coins(p.price * p.count) .. " |cff999999" .. L["SRC_" .. p.src] .. "|r")
      or ("|cff999999" .. L.TIP_NO_PRICE .. "|r")
    tt:AddDoubleLine(("  %d x %s"):format(p.count, p.name), right, 0.9, 0.9, 0.9, 1, 1, 1)
  end
  if cost then
    tt:AddDoubleLine(L.TIP_CRAFT_UNIT, ns.Coins(cost), 0.4, 1, 0.4, 1, 1, 1)
    if qty > 1 then tt:AddDoubleLine(ns.F("TIP_CRAFT_TOTAL", qty), ns.Coins(cost * qty), 0.4, 1, 0.4, 1, 1, 1) end
  else
    tt:AddLine(ns.F("TIP_PRICE_MISSING", table.concat(missing, ", ")), 0.7, 0.7, 0.7)
    tt:AddLine(L.TIP_PRICE_MISSING_WHY, 0.7, 0.7, 0.7)
  end
end

-- Preload vendor supply items (their sell price gives the vendor price)
local f = CreateFrame("Frame")
pcall(f.RegisterEvent, f, "PLAYER_LOGIN")
f:SetScript("OnEvent", function()
  if not (ns.VENDOR and C_Item and C_Item.RequestLoadItemDataByID) then return end
  for _, id in pairs(ns.VENDOR) do pcall(C_Item.RequestLoadItemDataByID, id) end
end)
