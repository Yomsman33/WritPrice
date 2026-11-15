-- SPDX-License-Identifier: GPL-2.0-only
-- WritPrice: merges the last scan and known quantities into sorted rows
local ADDON, ns = ...

function ns.CurrentScan()
  return ns.db and ns.db.scan[ns.RealmKey()]
end

local function AddRecipeStatus(row)
  if ns.WritDestination then row.dest, row.zone, row.destSrc = ns.WritDestination(row.name) end
  if not ns.CraftStatus then return row end
  local code, short, long, color = ns.CraftStatus(row.item)
  row.recipeCode, row.recipeShort, row.recipeLong, row.recipeColor = code, short, long, color
  return row
end

local function MakeRow(name, scanWrit, sc)
  local w = ns.db.writs[name] or {}
  local item = w.item or ns.ItemFromWrit(name)
  local rank = w.rank or (item and ns.WRIT_LIST and ns.WRIT_LIST[item] and ns.WRIT_LIST[item].rank)
  local rep = rank and ns.RANKS[rank]
  local it = sc and item and sc.items[item]
  local unit = it and it.min
  local unitAtr
  -- no price of ours (or only an old one): Auctionator's recent price, marked as such
  if item and ns.AtrFallback then
    local p, age = ns.AtrFallback(item, it, sc and sc.asked and sc.asked[item])
    if p then unit, unitAtr = p, age end
  end
  if it and it.src == "atr" then unitAtr = 0 end
  local writMin = scanWrit and scanWrit.min
  local qty = w.qty
  local qtyEst, qtyGuide = false, false
  local known = item and ns.WRIT_LIST and ns.WRIT_LIST[item]
  if not qty and known then
    qty, qtyGuide = known.qty, true -- quantity from the built-in writ list (guide)
  elseif not qty then
    qty, qtyEst = 1, true -- estimate: most writs ask for 1 item
  end
  local craft, rc = nil, nil
  if ns.CraftCost then craft, rc = ns.CraftCost(item) end
  -- item price used: auction house, or crafting when the option is on and it is cheaper
  local best, viaCraft = unit, false
  if ns.db.useCraft and craft and (not unit or craft < unit) then best, viaCraft = craft, true end
  -- writ quest already in progress: the writ is owned (cost 0), only missing items count
  local active = ns.ActiveWrit and ns.ActiveWrit(name)
  local remaining = qty
  if active then remaining = math.max((active.need or qty) - (active.have or 0), 0) end
  local total
  if active then
    if remaining == 0 then total = 0 elseif best then total = best * remaining end
  elseif writMin and best and qty then
    total = writMin + best * qty
  end
  -- Coin Pouch reward (median of the samples) deducted from the cost
  local pouch, pouchN
  if rank and ns.PouchMedian then pouch, pouchN = ns.PouchMedian(rank) end
  local net = total
  if total and pouch and ns.db.usePouch ~= false then net = total - pouch end
  local perRep = (net and rep) and (net / rep) or nil
  local doneUntil = ns.db.done[name]
  -- "not on AH" only when the item was really searched (old scans: no asked table)
  local asked = true
  if sc and sc.asked then asked = item ~= nil and sc.asked[item] ~= nil end
  return AddRecipeStatus({
    name = name, item = item, rank = rank, rep = rep,
    prof = ns.ProfOf(item),
    writMin = writMin, writCount = scanWrit and scanWrit.n,
    unit = unit, qty = qty, qtyEst = qtyEst, qtyGuide = qtyGuide, qtySrc = w.qtySrc or (qtyGuide and "guide" or nil),
    craft = craft, hasRecipe = rc ~= nil, recipe = rc, viaCraft = viaCraft,
    total = total, perRep = perRep, net = net, pouch = pouch, pouchN = pouchN,
    noItem = (sc ~= nil and it == nil and asked),
    notScanned = (sc ~= nil and it == nil and not asked),
    unitOld = (not unitAtr and it and it.old and it.t) or nil, -- price reused from an earlier scan (date)
    unitAtr = unitAtr, -- price from Auctionator (age in days, -1 = unknown)
    partial = it and it.partial,
    done = doneUntil ~= nil and doneUntil > time(),
    active = active ~= nil, have = active and active.have or nil, remaining = remaining,
    ready = active ~= nil and remaining == 0,
    dest = nil, zone = nil, destSrc = nil,
    recipeCode = nil, recipeShort = nil, recipeLong = nil, recipeColor = nil,
  })
end

function ns.RowFor(name)
  local sc = ns.CurrentScan()
  return MakeRow(name, sc and sc.writs[name], sc)
end

-- filter: "ALL", "Journeyman", "Expert" or "Artisan"
-- profOff (optional): unchecked professions { Alchemy = true, ... }; defaults to the saved filter
function ns.BuildRows(filter, profOff)
  local rows = {}
  local sc = ns.CurrentScan()
  if not sc then return rows, nil end
  local seen = {}
  local function add(name, sw)
    if seen[name] then return end
    seen[name] = true
    local row = MakeRow(name, sw, sc)
    if (filter == "ALL" or row.rank == filter) and ns.ProfWanted(row.prof, profOff) and ns.ZoneWanted(row.zone) then
      rows[#rows + 1] = row
    end
  end
  for name, sw in pairs(sc.writs) do add(name, sw) end
  -- writs in the quest log but missing from the scan (no longer for sale)
  for name in pairs(ns.activeWrits or {}) do add(name, nil) end
  table.sort(rows, function(a, b)
    local da, db_ = a.done and 1 or 0, b.done and 1 or 0
    if da ~= db_ then return da < db_ end
    -- quests in progress first (writ already owned)
    local aa, ab = a.active and 0 or 1, b.active and 0 or 1
    if aa ~= ab then return aa < ab end
    local ca, cb = a.perRep ~= nil, b.perRep ~= nil
    if ca ~= cb then return ca end
    if ca then return a.perRep < b.perRep end
    local ka = (a.writMin and a.rep) and a.writMin / a.rep or math.huge
    local kb = (b.writMin and b.rep) and b.writMin / b.rep or math.huge
    if ka ~= kb then return ka < kb end
    return a.name < b.name
  end)
  return rows, sc.t
end

-- Today's plan: the cheapest writs (rows already sorted) until goal points are reached.
-- Returns writ count, total reputation, total cost, estimate flag (assumed quantity), goal reached
function ns.Plan(rows, goal)
  local n, rep, cost, est = 0, 0, 0, false
  for _, row in ipairs(rows) do
    if rep >= goal then break end
    if row.perRep and not row.done then
      n, rep, cost = n + 1, rep + row.rep, cost + (row.net or row.total)
      if row.qtyEst then est = true end
    end
  end
  return n, rep, cost, est, rep >= goal
end
