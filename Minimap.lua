-- SPDX-License-Identifier: GPL-2.0-only
-- WritPrice: minimap icon (own button, no LibDBIcon). Left click: window. Right click: settings. Drag: move.
local ADDON, ns = ...

local btn

local function Place()
  if not (btn and Minimap) then return end
  if btn:GetParent() ~= Minimap then return end -- taken over by a button collector
  local a = math.rad(ns.db.minimap.minimapPos or 215)
  local cx, cy = math.cos(a), math.sin(a)
  local mw, mh = Minimap:GetWidth(), Minimap:GetHeight()
  local w = ((mw and mw > 0) and mw or 140) / 2 + 5
  local h = ((mh and mh > 0) and mh or 140) / 2 + 5
  local shape = GetMinimapShape and GetMinimapShape() or "ROUND" -- set by SexyMap, ElvUI...
  local x, y
  if shape == "ROUND" then
    x, y = cx * w, cy * h
  else -- square (or mixed corners): slide along the edges
    x = math.max(-w, math.min(cx * w * 1.4142, w))
    y = math.max(-h, math.min(cy * h * 1.4142, h))
  end
  btn:ClearAllPoints()
  btn:SetPoint("CENTER", Minimap, "CENTER", x, y)
end
ns.PlaceMinimapButton = Place

local function DragUpdate(self)
  if self:GetParent() ~= Minimap then return end -- moved into a button collector
  local mx, my = Minimap:GetCenter()
  local s = Minimap:GetEffectiveScale()
  if not (mx and my and s and s > 0) then return end
  local px, py = GetCursorPosition()
  local ang = math.deg(math.atan2(py / s - my, px / s - mx)) % 360
  ns.db.minimap.minimapPos = ang
  Place()
end

function ns.BuildMinimapButton()
  if btn then return btn end
  if not (Minimap and Minimap.GetCenter) then return nil end
  btn = CreateFrame("Button", "WritPriceMinimapButton", Minimap)
  btn:SetSize(31, 31)
  btn:SetFrameStrata("MEDIUM")
  btn:SetFrameLevel(8)
  if btn.SetFixedFrameStrata then pcall(btn.SetFixedFrameStrata, btn, true) end
  if btn.SetFixedFrameLevel then pcall(btn.SetFixedFrameLevel, btn, true) end
  btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  btn:RegisterForDrag("LeftButton")

  local bg = btn:CreateTexture(nil, "BACKGROUND")
  bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  bg:SetSize(20, 20)
  bg:SetPoint("TOPLEFT", 7, -5)
  local icon = btn:CreateTexture(nil, "ARTWORK")
  icon:SetTexture("Interface\\Icons\\INV_Scroll_03")
  icon:SetSize(17, 17)
  icon:SetPoint("TOPLEFT", 7, -6)
  icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
  local border = btn:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetSize(53, 53)
  border:SetPoint("TOPLEFT")
  btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  btn:SetScript("OnClick", function(_, button) if ns.LauncherClick then ns.LauncherClick(button) end end)
  btn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    ns.LauncherTooltip(GameTooltip, not ns.db.minimap.lock)
    GameTooltip:Show()
  end)
  btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
  btn:SetScript("OnDragStart", function(self)
    if ns.db.minimap.lock then return end
    GameTooltip:Hide()
    self:LockHighlight()
    self:SetScript("OnUpdate", DragUpdate)
  end)
  btn:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
    self:UnlockHighlight()
  end)
  btn:SetScript("OnShow", function() ns.Safe(Place) end)
  btn:SetScript("OnHide", function(self)
    self:SetScript("OnUpdate", nil)
    self:UnlockHighlight()
  end)
  return btn
end

function ns.UpdateMinimapButton()
  local b = ns.BuildMinimapButton()
  if not b then return end
  if ns.db.minimap.hide then b:Hide() else b:Show(); Place() end
end

function ns.HasMinimap()
  return Minimap ~= nil and Minimap.GetCenter ~= nil
end

local f = CreateFrame("Frame")
pcall(f.RegisterEvent, f, "PLAYER_LOGIN")
f:SetScript("OnEvent", function()
  ns.Safe(ns.UpdateMinimapButton)
end)
