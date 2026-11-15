-- SPDX-License-Identifier: GPL-2.0-only
-- WritPrice: the character's professions, known recipes, and how to learn a recipe
local ADDON, ns = ...
local L = ns.L

-- French client: maps profession names to the internal English names, so skill levels are read.
-- Recipe names are translated back to English by item ID (Names.lua).
local CLIENT_PROF = {
  ["Alchimie"] = "Alchemy", ["Forge"] = "Blacksmithing", ["Ingénierie"] = "Engineering",
  ["Travail du cuir"] = "Leatherworking", ["Couture"] = "Tailoring", ["Cuisine"] = "Cooking",
  ["Secourisme"] = "First Aid", ["Enchantement"] = "Enchanting", ["Joaillerie"] = "Jewelcrafting",
}
local function ProfKey(name) return CLIENT_PROF[name] or name end

local function CharKey()
  return (UnitName and UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "?")
end

local function Char()
  if not ns.db then return nil end
  ns.db.chars = ns.db.chars or {}
  local key = CharKey()
  local c = ns.db.chars[key]
  if not c then
    c = { skills = {}, known = {}, seen = {} }
    ns.db.chars[key] = c
  end
  c.skills, c.known, c.seen = c.skills or {}, c.known or {}, c.seen or {}
  return c
end
ns.Char = Char

-- Profession skill levels (Skills tab)
function ns.ReadSkills()
  local c = Char()
  if not c then return end
  local found = {}
  pcall(function()
    if GetNumSkillLines and GetSkillLineInfo then
      for i = 1, GetNumSkillLines() do
        local name, isHeader, _, rank = GetSkillLineInfo(i)
        if name and not isHeader and rank then found[ProfKey(name)] = rank end
      end
    end
  end)
  pcall(function()
    if GetProfessions and GetProfessionInfo then
      for _, idx in pairs({ GetProfessions() }) do
        if idx then
          local name, _, rank = GetProfessionInfo(idx)
          if name and rank then found[ProfKey(name)] = rank end
        end
      end
    end
  end)
  local any = false
  for _, prof in pairs(ns.PROF_NAMES or {}) do
    if found[prof] then
      c.skills[prof] = found[prof]
      any = true
    end
  end
  if any then
    -- unlearned professions are removed
    for prof in pairs(c.skills) do if not found[prof] then c.skills[prof] = nil end end
    c.skillsRead = true
  end
end

-- Known recipes: read when a profession window opens
function ns.ReadKnownRecipes()
  local c = Char()
  if not c then return end
  local profName, rank
  local names = {}
  pcall(function()
    if GetTradeSkillLine then profName, rank = GetTradeSkillLine() end
    if GetNumTradeSkills and GetTradeSkillInfo then
      for i = 1, GetNumTradeSkills() do
        local name, kind = GetTradeSkillInfo(i)
        if name and kind ~= "header" and kind ~= "subheader" then
          local link = GetTradeSkillItemLink and GetTradeSkillItemLink(i)
          local id = type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
          names[#names + 1] = ns.CanonName(name, id)
        end
      end
    end
  end)
  if #names == 0 then
    pcall(function()
      if C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs and C_TradeSkillUI.GetRecipeInfo then
        for _, id in ipairs(C_TradeSkillUI.GetAllRecipeIDs() or {}) do
          local info = C_TradeSkillUI.GetRecipeInfo(id)
          if info and info.name and info.learned ~= false then names[#names + 1] = ns.CanonName(info.name) end
        end
        if C_TradeSkillUI.GetTradeSkillLine then
          local _, n, r = C_TradeSkillUI.GetTradeSkillLine()
          profName, rank = profName or n, rank or r
        end
      end
    end)
  end
  if #names == 0 then return end
  for _, n in ipairs(names) do c.known[n] = true end
  if profName then
    profName = ProfKey(profName)
    c.seen[profName] = time()
    if rank and rank > 0 then c.skills[profName] = rank end
  end
  if ns.RefreshUI then ns.RefreshUI() end
end

-- Recipe status for this character.
-- Returns code, short text (column), long text (tooltip), hex color
-- code: "known" | "trainer" | "trainer_low" | "pattern" | "noprof" | nil (no recipe data)
function ns.CraftStatus(item)
  local rc = item and ns.RECIPES and ns.RECIPES[item]
  if not rc then return nil end
  local c = Char()
  local prof = (ns.PROF_NAMES and ns.PROF_NAMES[rc.p]) or "?"
  local profName = ns.PROF_KEYS[prof] and ns.ProfName(prof) or L["PROF_" .. prof]
  if prof == "?" then profName = "?" end
  local skill = c and c.skills[prof]
  if c and c.known[item] then
    return "known", L.RECIPE_KNOWN_SHORT, ns.F("RECIPE_KNOWN_LONG", profName, tostring(skill or "?")), "40ff40"
  end
  if not skill then
    if c and not c.skillsRead then
      return "noprof", "?", L.RECIPE_SKILLS_UNREAD, "999999"
    end
    return "noprof", "-", ns.F("RECIPE_NOPROF", profName, rc.s), "808080"
  end
  local learnedWindowSeen = c.seen[prof] ~= nil
  local note = (learnedWindowSeen or skill < rc.s) and "" or L.RECIPE_CHECK_NOTE
  if rc.t == "pattern" then
    local how
    if rc.v then
      how = ns.F("RECIPE_SOLD_BY", table.concat(rc.v, ", "))
    elseif rc.d then
      how = L.RECIPE_DROP
    else
      how = L.RECIPE_OTHER_SRC
    end
    local lvl = skill >= rc.s and ns.F("RECIPE_SKILL_OK", skill, rc.s) or ns.F("RECIPE_SKILL_LOW", skill, rc.s)
    return "pattern", L.RECIPE_PATTERN_SHORT,
      ns.F("RECIPE_PATTERN_LONG", rc.pat or "?", how, lvl, note),
      skill >= rc.s and "ffb040" or "ff6040"
  end
  if skill >= rc.s then
    return "trainer", L.RECIPE_TRAINER_SHORT,
      ns.F("RECIPE_TRAINER_LONG", profName, rc.s, skill, note), "ffd100"
  end
  return "trainer_low", ns.F("RECIPE_TRAINER_LOW_SHORT", rc.s),
    ns.F("RECIPE_TRAINER_LOW_LONG", profName, rc.s, skill), "ff6040"
end

local f = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "SKILL_LINES_CHANGED", "TRADE_SKILL_SHOW", "TRADE_SKILL_UPDATE",
  "TRADE_SKILL_LIST_UPDATE", "NEW_RECIPE_LEARNED" }) do
  pcall(f.RegisterEvent, f, e)
end
local pending = false
f:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGIN" or event == "SKILL_LINES_CHANGED" then
    ns.Safe(ns.ReadSkills)
    if ns.RefreshUI then ns.Safe(ns.RefreshUI) end
    return
  end
  if pending then return end
  pending = true
  C_Timer.After(0.3, function()
    pending = false
    ns.Safe(ns.ReadKnownRecipes)
  end)
end)
