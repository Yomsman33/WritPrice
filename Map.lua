-- SPDX-License-Identifier: GPL-2.0-only
-- WritPrice: turn-in place on the map (TomTom waypoint when TomTom is installed, else the game's own pin).
local ADDON, ns = ...
local L = ns.L

-- Classic zone map IDs (C_Map), for clients whose zone names are not in English.
-- An English client finds every zone by its name, new WoW Forever zones included.
local ZONE_MAPS = {
  ["Durotar"] = 1411, ["Mulgore"] = 1412, ["The Barrens"] = 1413,
  ["Alterac Mountains"] = 1416, ["Arathi Highlands"] = 1417, ["Badlands"] = 1418, ["Blasted Lands"] = 1419,
  ["Tirisfal Glades"] = 1420, ["Silverpine Forest"] = 1421, ["Western Plaguelands"] = 1422,
  ["Eastern Plaguelands"] = 1423, ["Hillsbrad Foothills"] = 1424, ["The Hinterlands"] = 1425,
  ["Dun Morogh"] = 1426, ["Searing Gorge"] = 1427, ["Burning Steppes"] = 1428, ["Elwynn Forest"] = 1429,
  ["Deadwind Pass"] = 1430, ["Duskwood"] = 1431, ["Loch Modan"] = 1432, ["Redridge Mountains"] = 1433,
  ["Stranglethorn Vale"] = 1434, ["Swamp of Sorrows"] = 1435, ["Westfall"] = 1436, ["Wetlands"] = 1437,
  ["Teldrassil"] = 1438, ["Darkshore"] = 1439, ["Ashenvale"] = 1440, ["Thousand Needles"] = 1441,
  ["Stonetalon Mountains"] = 1442, ["Desolace"] = 1443, ["Feralas"] = 1444, ["Dustwallow Marsh"] = 1445,
  ["Tanaris"] = 1446, ["Azshara"] = 1447, ["Felwood"] = 1448, ["Un'Goro Crater"] = 1449,
  ["Moonglade"] = 1450, ["Silithus"] = 1451, ["Winterspring"] = 1452,
}

local byName -- English client: zone name -> map ID, read from the game
local function ZoneMapID(zone)
  if not zone or zone == "" then return nil end
  if ns.EnglishClient() and C_Map and C_Map.GetMapChildrenInfo then
    if not byName then
      byName = {}
      for _, root in ipairs({ 947, 1414, 1415 }) do
        local ok, list = pcall(C_Map.GetMapChildrenInfo, root, nil, true)
        for _, info in ipairs(ok and type(list) == "table" and list or {}) do
          if info.name and info.mapID and not byName[info.name] then byName[info.name] = info.mapID end
        end
      end
    end
    if byName[zone] then return byName[zone] end
  end
  return ZONE_MAPS[zone]
end

-- Map point of a writ's turn-in place: mapID, x, y (0-1), label; nil when unknown
function ns.TurnInPoint(writName)
  local w = ns.db and ns.db.writs[writName]
  local item = (w and w.item) or ns.ItemFromWrit(writName)
  local d = item and ns.WRIT_DEST and ns.WRIT_DEST[item]
  if not (d and d.xy and d.xy ~= "") then return nil end
  local x, y = d.xy:match("^%s*([%d%.]+)%s*,%s*([%d%.]+)")
  x, y = tonumber(x), tonumber(y)
  local mapID = ZoneMapID(d.zone)
  if not (x and y and mapID) then return nil end
  local place = (d.sub ~= "" and (d.sub .. ", ") or "") .. d.zone
  return mapID, x / 100, y / 100, ("%s - %s"):format(d.npc, place), d
end

function ns.ShowTurnIn(writName)
  local mapID, x, y, label, d = ns.TurnInPoint(writName)
  if not mapID then
    ns.Print(L.CHAT_MAP_UNKNOWN)
    return
  end
  local title = label .. " (" .. ns.Disp(writName) .. ")"
  if TomTom and TomTom.AddWaypoint then
    local ok = pcall(TomTom.AddWaypoint, TomTom, mapID, x, y, { title = title, from = "WritPrice", persistent = false })
    if ok then
      ns.Print(ns.F("CHAT_MAP_TOMTOM", label, d.xy))
      return
    end
  end
  if C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
    local ok = pcall(function()
      C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, x, y))
      if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
    end)
    if ok then
      if OpenWorldMap then pcall(OpenWorldMap, mapID) end
      ns.Print(ns.F("CHAT_MAP_PIN", label, d.xy))
      return
    end
  end
  ns.Print(ns.F("CHAT_MAP_TEXT", label, d.xy))
end
