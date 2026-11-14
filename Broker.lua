-- SPDX-License-Identifier: GPL-2.0-only
-- WritPrice: optional entry points (addon compartment, LibDataBroker launcher). No library is embedded.
local ADDON, ns = ...
local L = ns.L

-- Shared tooltip of the launchers (minimap icon, LDB displays)
function ns.LauncherTooltip(tt, canDrag)
  tt:AddLine("WritPrice", 1, 0.82, 0)
  if ns.LastScanText then tt:AddLine(ns.LastScanText(), 0.7, 0.7, 0.7) end
  tt:AddLine(L.BROKER_CLICK, 1, 1, 1)
  tt:AddLine(L.MM_RIGHT, 1, 1, 1)
  if canDrag then tt:AddLine(L.MM_DRAG, 0.7, 0.7, 0.7) end
end

local function LauncherClick(button)
  if button == "RightButton" then
    if ns.OpenOptions then ns.Safe(ns.OpenOptions) end
  elseif ns.ToggleUI then
    ns.Safe(ns.ToggleUI)
  end
end
ns.LauncherClick = LauncherClick

-- Addon compartment (minimap addon menu) on clients that have it; see AddonCompartmentFunc in the .toc
function WritPrice_OnAddonCompartmentClick(_, button)
  LauncherClick(button)
end

function WritPrice_OnAddonCompartmentEnter(_, owner)
  if not owner then return end
  GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
  ns.LauncherTooltip(GameTooltip, false)
  GameTooltip:Show()
end

function WritPrice_OnAddonCompartmentLeave()
  GameTooltip:Hide()
end

local f = CreateFrame("Frame")
pcall(f.RegisterEvent, f, "PLAYER_LOGIN")
f:SetScript("OnEvent", function()
  ns.Safe(function()
    if type(LibStub) ~= "table" and type(LibStub) ~= "function" then return end
    local ok, ldb = pcall(LibStub, "LibDataBroker-1.1", true)
    if not (ok and ldb and ldb.NewDataObject) then return end
    ldb:NewDataObject("WritPrice", {
      type = "launcher",
      icon = "Interface\\Icons\\INV_Scroll_03",
      label = "WritPrice",
      OnClick = function(_, button) LauncherClick(button) end,
      OnTooltipShow = function(tt) ns.LauncherTooltip(tt, false) end,
    })
  end)
end)
