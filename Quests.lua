-- SPDX-License-Identifier: GPL-2.0-only
-- WritPrice: requested quantities read from the quest log, writs turned in today
local ADDON, ns = ...
local L = ns.L

ns.questMap = {} -- questID -> writ name
ns.activeWrits = {} -- writ name -> { questID, have, need } for writ quests in progress

local function EachQuest(fn)
  if C_QuestLog and C_QuestLog.GetInfo and C_QuestLog.GetNumQuestLogEntries then
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
      local q = C_QuestLog.GetInfo(i)
      if q and not q.isHeader and q.title then fn(q.questID, q.title, i) end
    end
  elseif GetNumQuestLogEntries and GetQuestLogTitle then
    for i = 1, GetNumQuestLogEntries() do
      local title, _, _, isHeader, _, _, _, questID = GetQuestLogTitle(i)
      if title and not isHeader then fn(questID, title, i) end
    end
  end
end

local function Objectives(questID, logIndex)
  local out = {}
  if questID and C_QuestLog and C_QuestLog.GetQuestObjectives then
    for _, o in ipairs(C_QuestLog.GetQuestObjectives(questID) or {}) do
      out[#out + 1] = { text = o.text, type = o.type, need = o.numRequired, have = o.numFulfilled, finished = o.finished }
    end
  end
  if #out == 0 and GetNumQuestLeaderBoards and GetQuestLogLeaderBoard then
    for j = 1, GetNumQuestLeaderBoards(logIndex) or 0 do
      local text, typ = GetQuestLogLeaderBoard(j, logIndex)
      out[#out + 1] = { text = text, type = typ }
    end
  end
  return out
end

-- "Name: 0/5" (Classic) or "0/5 Name" (modern). The name is returned in English (see Names.lua).
local function ParseObjective(o)
  local t = o.text or ""
  local name, have, need = t:match("^(.-)%s*:%s*(%d+)%s*/%s*(%d+)")
  if not name then have, need, name = t:match("^(%d+)%s*/%s*(%d+)%s+(.+)$") end
  if name == "" then name = nil end
  return ns.CanonName(name), o.need or tonumber(need), o.have or tonumber(have), name
end

-- Objective text of a quest ("Deliver ... to <NPC> at <place> in <zone>.")
local function QuestObjectiveText(questID, logIndex)
  local ok, text = pcall(function()
    if C_QuestLog and C_QuestLog.GetSelectedQuest and C_QuestLog.SetSelectedQuest and questID then
      local prev = C_QuestLog.GetSelectedQuest()
      C_QuestLog.SetSelectedQuest(questID)
      local _, obj = GetQuestLogQuestText()
      if prev then C_QuestLog.SetSelectedQuest(prev) end
      return obj
    end
    if SelectQuestLogEntry and GetQuestLogSelection and logIndex then
      local prev = GetQuestLogSelection()
      SelectQuestLogEntry(logIndex)
      local _, obj = GetQuestLogQuestText()
      if prev and prev > 0 then SelectQuestLogEntry(prev) end
      return obj
    end
  end)
  if ok and type(text) == "string" and text ~= "" then return text end
  return nil
end

-- Writ quests only say "deliver ... to the location marked on your map": that is not a turn-in place.
-- 0.1.0 learned it anyway; such texts are ignored and cleaned.
function ns.IsJunkDest(text)
  if type(text) ~= "string" then return false end
  local t = text:lower()
  return t:find("location marked", 1, true) ~= nil or t:find("your possession", 1, true) ~= nil
    or t:find("your map", 1, true) ~= nil
end

-- "... to Ziz Fizziks at Windshear Crag in Stonetalon Mountains." -> "Ziz Fizziks at Windshear Crag in Stonetalon Mountains"
local function ParseDestination(text)
  -- English quest text only: another client falls back to the built-in list
  if not text or not ns.EnglishClient() then return nil end
  text = text:gsub("%s+", " ")
  local dest = text:match(ns.GAME.DELIVER_TO) or text:match(ns.GAME.TO)
  if dest and #dest > 2 and #dest < 120 and not ns.IsJunkDest(dest) then return dest end
  return nil
end

-- Where to turn in a writ: learned from the quest log, else the built-in list
-- Returns: full text, zone, source ("quest" or "guide")
function ns.WritDestination(name)
  local w = ns.db and ns.db.writs[name]
  local item = (w and w.item) or ns.ItemFromWrit(name)
  local d = item and ns.WRIT_DEST and ns.WRIT_DEST[item]
  if w and ns.IsJunkDest(w.dest) then w.dest = nil end
  if w and w.dest then
    local zone = w.dest:match(ns.GAME.IN_ZONE) or (d and d.zone)
    return w.dest, zone, "quest"
  end
  -- turn-in place reported by another WritPrice user (Coin Pouch sharing)
  local shared = item and ns.db and ns.db.pouch and ns.db.pouch.sharedDest and ns.db.pouch.sharedDest[item]
  if shared and ns.IsJunkDest(shared.dest) then
    ns.db.pouch.sharedDest[item] = nil
    shared = nil
  end
  if shared and shared.dest then
    return shared.dest .. " |cff999999" .. L.DEST_SHARED .. "|r", shared.zone, "shared"
  end
  if d then
    local place = (d.sub ~= "" and (d.sub .. ", ") or "") .. d.zone
    local npc = d.obj and (d.npc .. " " .. L.DEST_OBJECT) or d.npc
    local xy = (d.xy and d.xy ~= "") and (" (" .. d.xy:gsub(",", ", ") .. ")") or ""
    local text = ("%s - %s%s"):format(npc, place, xy)
    if d.check then text = text .. " |cff999999" .. L.DEST_UNVERIFIED .. "|r" end
    return text, d.zone, "guide"
  end
  return nil
end

function ns.SetQty(writName, qty, src)
  local w = ns.WritInfo(writName)
  w.qty = qty
  w.qtySrc = src
  if ns.RefreshUI then ns.RefreshUI() end
end

-- Known writ (scanned or hovered) whose requested item has this name (simple English plural accepted)
local function Same(item, what)
  return item == what or item .. "s" == what or item .. "es" == what
end

local function WritForItem(what)
  if type(what) ~= "string" or what == "" then return nil end
  -- the exact writ name seen by the last scan wins (avoids a duplicate row)
  local sc = ns.CurrentScan and ns.CurrentScan()
  if sc and sc.writs then
    for name in pairs(sc.writs) do
      local item = ns.ItemFromWrit(name)
      if item and Same(item, what) then return name end
    end
  end
  for name, w in pairs(ns.db.writs) do
    local item = w.item or ns.ItemFromWrit(name)
    if item and (item == what or item .. "s" == what or item .. "es" == what) then return name end
  end
  -- writ never seen by the addon: trust the built-in Forever writ list
  for item in pairs(ns.WRIT_LIST or {}) do
    if Same(item, what) then return ns.GAME.WRIT_PREFIX .. ": " .. item end
  end
  return nil
end

function ns.ScanQuestLog()
  if not ns.db then return end
  local changed = false
  local active = {}
  EachQuest(function(questID, title, idx)
    local objs = Objectives(questID, idx)
    local canonTitle = ns.CanonName(title)
    local writName = ns.IsWrit(canonTitle) and canonTitle or nil
    for _, o in ipairs(objs) do
      local n = ParseObjective(o)
      if ns.IsWrit(n) then writName = n end
    end
    -- fallback: "Deliver N <Item>" quest whose objectives do not name the writ
    local titleQty
    if not writName then
      local n, what = title:match(ns.GAME.DELIVER_TITLE)
      if n then
        writName = WritForItem(what)
        if not writName then
          for _, o in ipairs(objs) do
            writName = writName or WritForItem((ParseObjective(o)))
          end
        end
        titleQty = tonumber(n)
      end
    end
    -- another client language: a quest asking for a writ item, named in the title (item or quantity)
    if not writName and not ns.EnglishClient() then
      for _, o in ipairs(objs) do
        local n, need, _, raw = ParseObjective(o)
        if not writName and n and ns.WRIT_LIST and ns.WRIT_LIST[n] and (o.type == nil or o.type == "item") then
          local named = (raw and title:find(raw, 1, true))
            or (need and title:find("%f[%d]" .. need .. "%f[%D]"))
          if named then writName = WritForItem(n) end
        end
      end
    end
    if not writName then return end
    if questID then ns.questMap[questID] = writName end
    local wanted = ns.ItemFromWrit(writName)
    local qty, have
    for _, o in ipairs(objs) do
      local n, need, got = ParseObjective(o)
      if n and need and not ns.IsWrit(n) and (o.type == nil or o.type == "item") then
        if not wanted or n == wanted then
          ns.WritInfo(writName).item = n
          qty, have = need, got
        end
      end
    end
    qty = qty or titleQty
    active[writName] = { questID = questID, have = have or 0, need = qty }
    -- turn-in NPC: read once from the quest text, then remembered
    local wi = ns.WritInfo(writName)
    if not wi.dest then
      local dest = ParseDestination(QuestObjectiveText(questID, idx))
      if dest then wi.dest = dest; changed = true end
    end
    if qty and qty > 0 then
      -- the quest log is authoritative: it replaces the estimate and a manual entry
      local w = ns.WritInfo(writName)
      if w.qty ~= qty or w.qtySrc ~= "quest" then
        w.qty, w.qtySrc = qty, "quest"
        changed = true
      end
    end
  end)
  -- writs in progress: refresh the window when the list or the progress changed
  local old = ns.activeWrits or {}
  for k, v in pairs(active) do
    local o = old[k]
    if not o or o.have ~= v.have or o.need ~= v.need then changed = true end
  end
  for k in pairs(old) do if not active[k] then changed = true end end
  ns.activeWrits = active
  if changed and ns.RefreshUI then ns.RefreshUI() end
end

function ns.ActiveWrit(name)
  return ns.activeWrits and ns.activeWrits[name]
end

-- Reputation waiting in accepted writ quests
-- Returns: writ count, total rep, ready count, ready rep, count of unknown rank
function ns.PendingRep()
  local n, rep, nReady, repReady, unknown = 0, 0, 0, 0, 0
  for name, a in pairs(ns.activeWrits or {}) do
    local w = ns.db and ns.db.writs[name]
    local item = (w and w.item) or ns.ItemFromWrit(name)
    local rank = (w and w.rank) or (item and ns.WRIT_LIST and ns.WRIT_LIST[item] and ns.WRIT_LIST[item].rank)
    local r = rank and ns.RANKS[rank]
    n = n + 1
    if r then
      rep = rep + r
      if a.need and (a.have or 0) >= a.need then
        nReady, repReady = nReady + 1, repReady + r
      end
    else
      unknown = unknown + 1
    end
  end
  return n, rep, nReady, repReady, unknown
end

-- Current standing with the Azeroth Commerce Authority (nil when not found)
-- Returns: standing label, value within the standing, standing size
-- Azeroth Commerce Authority (Alliance) or Durotar Supply and Logistics (Horde).
-- Found by faction ID (any client language) or by its English name; an English client learns the ID.
local function IsACA(name, id)
  if ns.FactionIDKnown(id) then return true end
  if ns.IsWritFaction(name) then
    if type(id) == "number" and ns.db then
      ns.db.factionIDs = type(ns.db.factionIDs) == "table" and ns.db.factionIDs or {}
      ns.db.factionIDs[name] = id
    end
    return true
  end
  return false
end
local function Standing(d)
  local label = _G["FACTION_STANDING_LABEL" .. (d.reaction or 0)] or "?"
  return label, (d.currentStanding or 0) - (d.currentReactionThreshold or 0),
    (d.nextReactionThreshold or 0) - (d.currentReactionThreshold or 0)
end

-- Faction data by ID: known IDs first; an English client without one looks the IDs up once
-- (the reputation list hides the factions of collapsed categories).
local probed = false
local function ByID()
  if not (C_Reputation and C_Reputation.GetFactionDataByID) then return nil end
  local function get(id)
    local ok, d = pcall(C_Reputation.GetFactionDataByID, id)
    return ok and type(d) == "table" and d or nil
  end
  local ids = {}
  for _, id in pairs(ns.FACTION_IDS or {}) do ids[#ids + 1] = id end
  for _, id in pairs(ns.db and ns.db.factionIDs or {}) do ids[#ids + 1] = id end
  for _, id in ipairs(ids) do
    local d = get(id)
    if d and (d.reaction or d.currentStanding) then return d end
  end
  if probed or not ns.EnglishClient() then return nil end
  probed = true
  local found
  for id = 1, 5000 do
    local d = get(id)
    if d and ns.IsWritFaction(d.name) then
      IsACA(d.name, id)
      if d.reaction or d.currentStanding then found = found or d end
    end
  end
  return found
end

function ns.FactionStanding()
  local ok, a, b, c = pcall(function()
    if C_Reputation and C_Reputation.GetFactionDataByIndex then
      local n = C_Reputation.GetNumFactions and C_Reputation.GetNumFactions() or 500
      for i = 1, n do
        local d = C_Reputation.GetFactionDataByIndex(i)
        if not d and not C_Reputation.GetNumFactions then break end
        if d and IsACA(d.name, d.factionID) then return Standing(d) end
      end
      local d = ByID()
      if d then return Standing(d) end
    end
    if GetNumFactions and GetFactionInfo then
      for i = 1, GetNumFactions() do
        local name, _, standingID, barMin, barMax, barValue, _, _, _, _, _, _, _, factionID = GetFactionInfo(i)
        if IsACA(name, factionID) then
          return _G["FACTION_STANDING_LABEL" .. (standingID or 0)] or "?", barValue - barMin, barMax - barMin
        end
      end
    end
  end)
  if ok and a then return a, b, c end
  return nil
end

function ns.DumpQuests()
  local found = false
  EachQuest(function(questID, title, idx)
    found = true
    print(("|cffffd100[%s]|r %s"):format(tostring(questID), title))
    local ot = QuestObjectiveText(questID, idx)
    if ot then print("   " .. L.DEBUG_TEXT .. ": " .. ot) end
    for _, o in ipairs(Objectives(questID, idx)) do
      print(("   - %s (type=%s, need=%s)"):format(tostring(o.text), tostring(o.type), tostring(o.need)))
    end
  end)
  if not found then ns.Print(L.CHAT_QUESTLOG_EMPTY) end
end

-- Turn-in places learned in game (to check and improve the built-in list)
function ns.DumpDests()
  local n = 0
  for name, w in pairs(ns.db.writs) do
    if w.dest then
      n = n + 1
      print(("  %s: %s"):format(name, w.dest))
    end
  end
  ns.Print(ns.F("CHAT_DESTS_LEARNED", n))
end

local pending = false
local ev = CreateFrame("Frame")
for _, e in ipairs({ "QUEST_LOG_UPDATE", "QUEST_TURNED_IN", "PLAYER_LOGIN" }) do
  pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event, questID)
  if event == "QUEST_TURNED_IN" then
    ns.Safe(function()
      local writName = ns.questMap[questID]
      if writName and ns.db then
        local reset = GetQuestResetTime and GetQuestResetTime() or 86400
        ns.db.done[writName] = time() + reset
        if ns.OnWritTurnedIn then ns.OnWritTurnedIn(writName) end
        if ns.RefreshUI then ns.RefreshUI() end
      end
    end)
    return
  end
  if pending then return end
  pending = true
  C_Timer.After(0.5, function()
    pending = false
    ns.Safe(ns.ScanQuestLog)
  end)
end)
