-- SPDX-License-Identifier: GPL-2.0-only
-- WritPrice: localization engine (English default, French available)
local ADDON, ns = ...

ns.LOCALES = {}
local forced -- nil = follow the game client; "enUS" or "frFR" when forced by the player

local function Code()
  if forced and ns.LOCALES[forced] then return forced end
  local g = GetLocale and GetLocale() or "enUS"
  if ns.LOCALES[g] then return g end
  return "enUS"
end

-- ns.L.KEY returns the text in the active language, then English, then the key itself
ns.L = setmetatable({}, {
  __index = function(_, k)
    local t = ns.LOCALES[Code()]
    local v = t and t[k]
    if v == nil and ns.LOCALES.enUS then v = ns.LOCALES.enUS[k] end
    if v == nil then return tostring(k) end
    return v
  end,
  __newindex = function() end,
})

-- Protected string.format on a localized key
function ns.F(key, ...)
  local fmt = ns.L[key]
  local ok, s = pcall(string.format, fmt, ...)
  if ok then return s end
  -- a format error is a bug: count it (tests) and show it in debug mode
  ns.errorCount = (ns.errorCount or 0) + 1
  if ns.Debug then ns.Debug("format error: " .. tostring(key)) end
  return fmt
end

-- KEY_1 for one, KEY_N otherwise (French treats 0 as singular)
function ns.Plural(n, key, ...)
  local one = (n == 1) or (n == 0 and ns.L.PLURAL_ZERO_ONE == "1")
  return ns.F(key .. (one and "_1" or "_N"), n, ...)
end

function ns.LocaleCode() return Code() end

-- "auto" (or nil), "enUS", "frFR"; returns false for an unknown code
function ns.SetLocale(code)
  if code == nil or code == "auto" then
    forced = nil
  elseif ns.LOCALES[code] then
    forced = code
  else
    return false
  end
  if ns.db then ns.db.locale = forced end
  if ns.ApplyLocale then ns.Safe(ns.ApplyLocale) end
  return true
end
