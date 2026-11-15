-- SPDX-License-Identifier: GPL-2.0-only
-- WritPrice: extra lines in a Craftsman's Writ tooltip
local ADDON, ns = ...
local L = ns.L

local done = setmetatable({}, { __mode = "k" })

local function LineGetter(tooltip, data)
  if data and data.lines then
    return function(i) return data.lines[i] and data.lines[i].leftText end, #data.lines
  end
  local base = tooltip:GetName()
  return function(i)
    local fs = base and _G[base .. "TextLeft" .. i]
    return fs and fs:GetText()
  end, tooltip:NumLines()
end

local function Handle(tooltip, data)
  if not ns.db or done[tooltip] or not tooltip.GetItem then return end
  local ok, name, link = pcall(tooltip.GetItem, tooltip)
  if not ok then return end
  local id = type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
  name = ns.CanonName(name, id) -- English name inside the addon
  if not ns.IsWrit(name) then return end
  done[tooltip] = true
  ns.lastWrit = name

  local w = ns.WritInfo(name)
  if not w.rank then
    local get, n = LineGetter(tooltip, data)
    w.rank = ns.RankFromLines(get, n)
  end

  if ns.db.tooltip == false then return end -- lines turned off in the settings (rank and lastWrit still learned)

  local row = ns.RowFor(name)
  local out = {}
  local function Add(left, right, r, g, b)
    out[#out + 1] = { left, right, r or 1, g or 1, b or 1 }
  end

  if row.rank then
    Add(L.TT_RANK, ns.F("TT_RANK_VAL", row.rank, row.rep), 0.6, 0.8, 1)
  end
  if ns.CurrentScan() then
    Add(L.TT_WRIT_LAST, row.active and L.CELL_OWNED or (row.writMin and ns.Coins(row.writMin) or L.TT_NOT_FOR_SALE))
    local label = (row.qtyEst and "1? x " or (row.qty .. " x ")) .. (row.item and ns.Disp(row.item) or "?")
    local value
    if row.unit then
      value = ns.Coins(row.unit * row.qty)
    elseif row.notScanned then
      value = L.TT_NOT_SCANNED
    else
      value = L.TT_NOT_FOR_SALE
    end
    Add(ns.F("TT_ITEM_LINE", label), value)
    if row.total then
      Add(row.viaCraft and L.TT_TOTAL_CRAFT or L.TT_TOTAL, ns.Coins(row.total), 0.4, 1, 0.4)
      if row.pouch and ns.db.usePouch ~= false then Add(ns.F("TT_POUCH", row.pouchN or 0), "-" .. ns.Coins(row.pouch), 0.4, 1, 0.4) end
      if row.perRep then Add(L.TT_PER_REP, ns.Coins(row.perRep), 0.4, 1, 0.4) end
    end
  else
    Add(L.TT_NO_SCAN, nil, 0.7, 0.7, 0.7)
  end
  if row.hasRecipe then
    if row.craft then
      Add(ns.F("TT_CRAFT_UNIT", ns.ProfLabel(row.recipe)), ns.Coins(row.craft), 0.4, 0.8, 1)
    else
      Add(ns.F("TT_CRAFT_MISSING", ns.ProfLabel(row.recipe)), nil, 0.7, 0.7, 0.7)
    end
  end
  if row.qtyEst then
    Add(L.TT_QTY_EST, nil, 0.7, 0.7, 0.7)
  elseif row.qtySrc == "manual" then
    Add(L.TT_QTY_MANUAL, nil, 0.7, 0.7, 0.7)
  end
  if row.done then
    Add(L.ROW_DONE_TODAY, nil, 1, 0.4, 0.4)
  end
  if row.recipeLong then
    local hex = row.recipeColor or "ffffff"
    Add(row.recipeLong, nil, tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255,
      tonumber(hex:sub(5, 6), 16) / 255)
  end
  if row.dest then
    Add(ns.F("ROW_TURNIN", row.dest), nil, 1, 0.82, 0.5)
  end
  if row.ready then
    Add(L.ROW_QUEST_READY, nil, 0.25, 1, 0.25)
  elseif row.active then
    Add(ns.F("TT_QUEST_PROGRESS", row.have or 0, row.qty or 0), nil, 0.3, 0.76, 1)
  end

  tooltip:AddLine(" ")
  tooltip:AddLine("WritPrice", 1, 0.82, 0)
  for _, l in ipairs(out) do
    if l[2] then
      tooltip:AddDoubleLine(l[1], l[2], l[3], l[4], l[5], 1, 1, 1)
    else
      tooltip:AddLine(l[1], l[3], l[4], l[5])
    end
  end
end

local function SafeHandle(tooltip, data)
  ns.Safe(Handle, tooltip, data)
end

local function Cleared(tooltip)
  done[tooltip] = nil
end

local useProcessor = TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
  and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item

if useProcessor then
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
    if tooltip == GameTooltip or tooltip == ItemRefTooltip then SafeHandle(tooltip, data) end
  end)
end

for _, tt in ipairs({ GameTooltip, ItemRefTooltip }) do
  if tt then
    tt:HookScript("OnTooltipCleared", Cleared)
    if not useProcessor then tt:HookScript("OnTooltipSetItem", SafeHandle) end
  end
end
