-- SPDX-License-Identifier: GPL-2.0-only
-- WritPrice: shares Coin Pouch samples with other WritPrice users (guild and group) through hidden
-- addon messages. Only our own samples are sent (no relaying, so no loops); received samples are checked
-- and added to our data. Can be turned off in the settings.
local ADDON, ns = ...
local L = ns.L

local PREFIX = "WRITPRICE"
local VERSION = "2" -- 2: with the writ item, turn-in place and zone (version 1 still accepted)
local SYNC_COUNT = 20  -- own samples re-sent at login (latest first)
local SEND_EVERY = 1.5 -- seconds between two messages (gentle throttling)

local queue = {}
local sender = CreateFrame("Frame")
sender:Hide()
local nextAt = 0

local function Enabled() return ns.db and ns.db.share ~= false end

local function Channels()
  local out = {}
  if IsInGuild and IsInGuild() then out[#out + 1] = "GUILD" end
  if IsInRaid and IsInRaid() then
    out[#out + 1] = "RAID"
  elseif IsInGroup and IsInGroup() then
    out[#out + 1] = "PARTY"
  end
  return out
end

local function Send(msg, channel)
  local f = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
  if f then pcall(f, PREFIX, msg, channel) end
end

sender:SetScript("OnUpdate", function(self)
  local t = GetTime()
  if t < nextAt then return end
  local item = table.remove(queue, 1)
  if not item then self:Hide() return end
  Send(item.msg, item.channel)
  nextAt = t + SEND_EVERY
end)

local function Queue(msg, groupOnly)
  if not Enabled() then return end
  for _, ch in ipairs(Channels()) do
    if groupOnly and ch == "GUILD" then ch = nil end
    if ch then
    queue[#queue + 1] = { msg = msg, channel = ch }
    end
  end
  while #queue > 100 do table.remove(queue, 1) end
  if #queue > 0 then sender:Show() end
end

-- message: P|version|rank|copper|time|uid|item|turn-in place|zone (addon messages are limited to 255 bytes)
local function Encode(rank, copper, t, uid, info)
  info = info or {}
  local clean = ns.CleanShareText or function(v) return v end
  local msg = table.concat({ "P", VERSION, rank, tostring(math.floor(copper)), tostring(t), uid,
    clean(info.item, 60) or "", clean(info.dest, 90) or "", clean(info.zone, 40) or "" }, "|")
  if #msg > 250 then msg = msg:sub(1, 250) end
  return msg
end

function ns.SharePouch(rank, copper, t, uid, info)
  Queue(Encode(rank, copper, t, uid, info))
end

-- At login (and when joining a group), re-send our latest own samples: peers ignore what they already have
local function SyncOwn(groupOnly)
  if not Enabled() then return end
  local p = ns.db and ns.db.pouch
  if not (p and p.samples) then return end
  local own = {}
  for rank, list in pairs(p.samples) do
    for _, s in ipairs(list) do
      if s.src == "me" then own[#own + 1] = { rank = rank, s = s } end
    end
  end
  table.sort(own, function(a, b) return a.s.t > b.s.t end)
  for i = 1, math.min(SYNC_COUNT, #own) do
    local o = own[i]
    Queue(Encode(o.rank, o.s.v, o.s.t, o.s.id, o.s), groupOnly)
  end
end

local function Receive(prefix, text, channel, from)
  if prefix ~= PREFIX or not Enabled() or type(text) ~= "string" then return end
  local me = UnitName and UnitName("player")
  local short = type(from) == "string" and from:match("^([^%-]+)") or from
  if short == me then return end
  local kind, ver, rank, copper, t, uid, item, dest, zone = strsplit("|", text)
  if kind ~= "P" or (ver ~= "1" and ver ~= "2") then return end
  local info = (ver == "2") and { item = item, dest = dest, zone = zone } or nil
  if ns.AddPouchSample(rank, tonumber(copper), tonumber(t), uid, tostring(from), info) then
    ns.Debug(ns.F("CHAT_POUCH_RECEIVED", tostring(from), ns.Coins(tonumber(copper)), rank))
  end
end

local f = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "CHAT_MSG_ADDON", "GROUP_JOINED" }) do
  pcall(f.RegisterEvent, f, e)
end
f:SetScript("OnEvent", function(_, event, ...)
  ns.Safe(function(...)
    if event == "PLAYER_LOGIN" then
      local reg = (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) or RegisterAddonMessagePrefix
      if reg then pcall(reg, PREFIX) end
      if C_Timer and C_Timer.After then C_Timer.After(20, function() ns.Safe(SyncOwn) end) end
    elseif event == "GROUP_JOINED" then
      if C_Timer and C_Timer.After then C_Timer.After(5, function() ns.Safe(SyncOwn, true) end) end
    elseif event == "CHAT_MSG_ADDON" then
      Receive(...)
    end
  end, ...)
end)
