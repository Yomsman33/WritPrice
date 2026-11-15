"""WritPrice offline test bench (lupa + WoW API stubs).
Usage: python3 dev/tests/run_tests.py [--locale enUS|frFR]
Loads the files in .toc order, then checks filters, plan, menus, AH button, quests, goal, turn-in places,
recipe status, language switching, welcome message, columns, scale and scan messages."""
import os, sys
import lupa.lua51 as lupa  # WoW runs Lua 5.1

LOCALE = "enUS"
if "--locale" in sys.argv:
    LOCALE = sys.argv[sys.argv.index("--locale") + 1]
LEGACY = "--legacy-options" in sys.argv
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))

L = lupa.LuaRuntime(unpack_returned_tuples=True)
L.execute(r'''
NOW=1000000
function time() return NOW end
TNOW=1
function GetTime() return TNOW end
function GetRealmName() return "R" end
function UnitFactionGroup() return "Alliance" end
function UnitName() return "Tester" end
function GetCoinTextureString(c) return c.."c" end
function GetItemInfo() return nil end
function GetCursorPosition() return 0,0 end
WorldFrame={} UISpecialFrames={} StaticPopupDialogs={} SlashCmdList={}
OKAY="Okay" CANCEL="Cancel"
tinsert=table.insert
timers={}
C_Timer={After=function(_, f) timers[#timers+1]=f end}
function runTimers() local t=timers timers={} for _,f in ipairs(t) do f() end end
printed={}
function print(...) local t={} for i=1,select('#',...) do t[#t+1]=tostring(select(i,...)) end printed[#printed+1]=table.concat(t," ") end
frames={}
-- only the widget methods the addon really uses: a typo in an API name fails the tests
ALLOWED={}
for m in ([[AddDoubleLine AddLine ClearAllPoints ClearLines CreateFontString CreateTexture Disable Enable EnableMouse
  GetChecked GetEditBox GetEffectiveScale GetLeft GetName GetParent GetPoint GetRight GetScale GetText GetTop GetWidth
  Hide HighlightText HookScript IsShown IsVisible LockHighlight NumLines RegisterEvent RegisterForClicks RegisterForDrag
  SetAllPoints SetAuctionItem SetChecked SetCheckedTexture SetClampedToScreen SetColorTexture SetFocus SetFrameStrata
  SetHighlightTexture SetHyperlink SetJustifyH SetMovable SetNormalTexture SetOwner SetParent SetPoint SetPushedTexture
  SetScript SetSize SetText SetTextColor SetValue SetWidth SetWordWrap Show StartSearch StopMovingOrSizing UnlockHighlight
  UnregisterEvent Click GetScript SetScale SetMinimumWidth SetMotionScriptsWhileDisabled StartMoving GetItem
  SetDisplayMode SetFrameLevel SetFixedFrameStrata SetFixedFrameLevel SetTexture SetTexCoord SetHeight GetHeight GetCenter
  Raise SetOrientation SetThumbTexture SetMinMaxValues SetValueStep SetObeyStepOnDrag GetValue SetAutoFocus SetNumeric
  SetMaxLetters ClearFocus HasFocus IsEnabled GetFrameStrata SetToplevel GetThumbTexture SetHitRectInsets GetNormalTexture
  GetCheckedTexture SetFontObject SetMovable SetMultiLine SetScrollChild GetStringWidth SetEnabled IsOwned]]):gmatch("%S+") do ALLOWED[m]=true end
unknownCalls={}
function mock(kind)
  local o={_kind=kind,_scripts={},_shown=true,_checked=false,_width=0,_scale=1,_minw=0}
  local mt={}
  mt.__index=function(t,k)
    if k=="TitleText" or k=="ScrollBar" or k=="text" or k=="Text" or k=="editBox" or k=="EditBox" then return nil end
    if not ALLOWED[k] then
      -- method names start with a capital letter; lower-case keys and known data fields are plain reads
      if type(k)=="string" and k:match("^%u") and k~="SearchBar" then unknownCalls[#unknownCalls+1]=k end
      return nil
    end
    return function(self,...)
      if k=="SetScript" or k=="HookScript" then local n,f=... ; self._scripts[n]=f return end
      if k=="GetScript" then return self._scripts[...] end
      if k=="Show" then self._shown=true local f=self._scripts.OnShow if f then f(self) end return end
      if k=="Hide" then self._shown=false local f=self._scripts.OnHide if f then f(self) end return end
      if k=="IsShown" or k=="IsVisible" then return self._shown end
      if k=="SetChecked" then self._checked=(...) and true or false return end
      if k=="GetChecked" then return self._checked end
      if k=="SetText" then self._text=... return end
      if k=="GetText" then return self._text end
      if k=="GetStringWidth" then return 100 end
      if k=="AddLine" or k=="AddDoubleLine" then self._lines=self._lines or {} self._lines[#self._lines+1]=tostring((...)) return end
      if k=="SetOwner" or k=="ClearLines" then self._lines={} return end
      if k=="GetParent" then return self._parent end
      if k=="SetParent" then self._parent=... return end
      if k=="SetWidth" then self._width=... return end
      if k=="SetHeight" then self._height=... return end
      if k=="GetHeight" then return self._height or self._width end
      if k=="GetCenter" then return self._cx or 500, self._cy or 500 end
      if k=="SetValue" then self._value=... local f=self._scripts.OnValueChanged if f then f(self,self._value) end return end
      if k=="GetValue" then return self._value end
      if k=="Enable" then self._enabled=true return end
      if k=="Disable" then self._enabled=false return end
      if k=="IsEnabled" then return self._enabled~=false end
      if k=="HasFocus" then return false end
      if k=="SetFrameStrata" then self._strata=... return end
      if k=="GetWidth" then return self._width end
      if k=="SetSize" then local w,h=... self._width=w self._height=h return end
      if k=="SetScale" then self._scale=... return end
      if k=="GetScale" then return self._scale end
      if k=="GetRight" then return 900 end
      if k=="GetTop" then return 700 end
      if k=="SetPoint" then self._point={...} return end
      if k=="SetMinimumWidth" then self._minw=... return end
      if k=="CreateFontString" or k=="CreateTexture" then local r=mock("region") frames[#frames+1]=r return r end
      if k=="Click" then local f=self._scripts.OnClick if f then f(self,"LeftButton") end return end
      if k=="NumLines" then return 0 end
      if k=="GetLeft" then return 0 end
      if k=="GetEffectiveScale" then return 1 end
      return nil
    end
  end
  return setmetatable(o,mt)
end
function CreateFrame(kind,name,parent,tpl)
  local f=mock(kind) f._parent=parent f._tpl=tpl f._name=name
  if name then _G[name]=f end
  frames[#frames+1]=f
  return f
end
UIParent=mock("UIParent") UIParent._width=1365
GameTooltip=mock("tip")
function FauxScrollFrame_Update() end
function FauxScrollFrame_GetOffset() return 0 end
function FauxScrollFrame_SetOffset() end
lastPopup=nil
function StaticPopup_Show(which, a1, a2, d) lastPopup={which=which,a1=a1,data=d} return nil end
NS={}
function loadf(path) local f=assert(loadfile(path)) f("WritPrice",NS) end
function fire(event, ...) for _,f in ipairs(frames) do local s=f._scripts.OnEvent if s then s(f,event,...) end end end
''')
L.execute('function GetLocale() return "%s" end' % LOCALE)
L.execute(r'''
cursorX, cursorY = 0, 0
function GetCursorPosition() return cursorX, cursorY end
inCombat=false
function InCombatLockdown() return inCombat end
Minimap = mock("Minimap") Minimap._width = 140 Minimap._height = 140
settingsLog = {}
''')
if LEGACY:
    L.execute(r'''
function InterfaceOptions_AddCategory(f) settingsLog.frame = f end
function InterfaceOptionsFrame_OpenToCategory(f) settingsLog.opened = f end
''')
else:
    L.execute(r'''
Settings = {
  RegisterCanvasLayoutCategory = function(f, name) settingsLog.frame, settingsLog.name = f, name
    return { GetID = function() return 42 end } end,
  RegisterAddOnCategory = function(c) settingsLog.added = c end,
  OpenToCategory = function(id) settingsLog.opened = id end,
}
''')
L.execute('LEGACY = %s' % ('true' if LEGACY else 'false'))

files = []
for line in open(os.path.join(ROOT, "WritPrice.toc"), encoding="utf-8"):
    line = line.strip()
    if line and not line.startswith("#"):
        files.append(line.replace("\\", "/"))
for f in files:
    L.globals().loadf(os.path.join(ROOT, f))

result = L.execute(r'''
local ns=NS
local Lc=ns.L
local out={}
local function ok(c,m) if not c then error("FAIL "..m,2) end out[#out+1]="ok "..m end
fire("ADDON_LOADED","WritPrice")
assert(ns.db, "db")
local EXPECTED = ns.LOCALES[GetLocale()] and GetLocale() or "enUS"
ok(ns.LocaleCode()==EXPECTED, "langue = client ("..GetLocale().." -> "..EXPECTED..")")

-- welcome: once
fire("PLAYER_LOGIN") runTimers()
local function count(pat) local n=0 for _,p in ipairs(printed) do if p:find(pat,1,true) then n=n+1 end end return n end
local welcome = ns.F("WELCOME", ns.VERSION)
ok(count(welcome)==1 and ns.db.welcomed==true, "bienvenue affichee une fois")
fire("PLAYER_LOGIN") runTimers()
ok(count(welcome)==1, "pas de bienvenue a la 2e connexion")

-- professions
ok(ns.ProfOf("Elixir of Wisdom")=="Alchemy","prof liste")
ok(ns.ProfOf("Accurate Scope")=="Engineering","hors liste via RECIPES")
ok(ns.ProfOf("Anti-Venom")=="Other","First Aid -> Other")
local c,nw={},0
for item,w in pairs(ns.WRIT_LIST) do nw=nw+1 c[w.prof]=(c[w.prof] or 0)+1 assert(ns.PROF_KEYS[w.prof]) end
ok(nw==150 and c.Alchemy==30 and c.Tailoring==30,"150 writs, 30 par metier")

-- fake scan
local W="Craftsman's Writ: "
local items={"Elixir of Wisdom","Mana Potion","Big Bronze Knife","Shadow Goggles","Colorful Kilt","Accurate Scope","Truc Inconnu","Dark Leather Tunic"}
local sc={t=NOW-120,writs={},items={},asked={}}
for i,it in ipairs(items) do sc.writs[W..it]={min=100*i,n=1} sc.items[it]={min=1000*i,n=1} sc.asked[it]=NOW end
ns.db.scan[ns.RealmKey()]=sc
ns.db.writs[W.."Accurate Scope"]={rank="Expert"}
local function names(f,off) local r=ns.BuildRows(f,off) local t={} for _,x in ipairs(r) do t[#t+1]=x.item end table.sort(t) return table.concat(t,"|"),#r,r end
local s,n=names("ALL") ok(n==8,"tout coche -> 8")
ok(ns.ProfSummary()==Lc.PROF_ALL,"libelle tous")
ns.SetProf("Alchemy",false)
s,n=names("ALL") ok(n==6,"sans alchimie -> 6")
ok(ns.ProfSummary()=="5/6","libelle 5/6")
ns.SetAllProfs(false) ok(ns.ProfSummary()==Lc.PROF_NONE and select(2,names("ALL"))==0,"tout decoche -> 0")
ns.SetProf("Tailoring",true) ns.SetProf("Engineering",true)
s,n=names("ALL") ok(s=="Accurate Scope|Colorful Kilt|Shadow Goggles","2 metiers")
local _,_,rws=names("ALL") local pn,prep=ns.Plan(rws,1000) ok(pn==3 and prep==75+75+125,"plan respecte le filtre")
ns.SetAllProfs(true) ok(next(ns.db.profOff)==nil,"tout cocher vide profOff")

-- commands in both languages
SlashCmdList.WRITPRICE("metier cuir") ok(ns.db.profOff.Leatherworking==true,"/writs metier cuir")
SlashCmdList.WRITPRICE("prof leather") ok(ns.db.profOff.Leatherworking==nil,"/writs prof leather")
SlashCmdList.WRITPRICE("prof ingé") ok(ns.db.profOff.Engineering==true,"/writs prof ingé (accent)")
SlashCmdList.WRITPRICE("prof all") ok(next(ns.db.profOff)==nil,"/writs prof all")
SlashCmdList.WRITPRICE("objectif 750") ok(ns.GetGoal()==750,"/writs objectif 750")
SlashCmdList.WRITPRICE("goal 0") ok(ns.db.goal==0,"/writs goal 0")
ns.db.goal=nil

-- UI
ns.ShowUI()
local profBtn
for _,f in ipairs(frames) do if f._text==ns.F("UI_BTN_PROFS", Lc.PROF_ALL) then profBtn=f end end
ok(profBtn~=nil,"bouton Metiers")
profBtn:Click()
ok(WritPriceProfMenu and WritPriceProfMenu:IsShown(),"menu metiers ouvert")
local checks={}
for _,f in ipairs(frames) do if f._kind=="CheckButton" and f._parent==WritPriceProfMenu then checks[#checks+1]=f end end
ok(#checks==6,"6 cases")
checks[1]._checked=false checks[1]:Click()
ok(ns.db.profOff.Alchemy==true and profBtn._text==ns.F("UI_BTN_PROFS","5/6"),"clic case -> 5/6")
for _,f in ipairs(frames) do if f._text==Lc.UI_CHECK_ALL then f:Click() end end
ok(profBtn._text==ns.F("UI_BTN_PROFS", Lc.PROF_ALL),"Tout cocher")
profBtn:Click() ok(not WritPriceProfMenu:IsShown(),"menu referme")

-- language switch without reload
SlashCmdList.WRITPRICE("lang fr")
ok(ns.db.locale=="frFR" and profBtn._text=="Métiers : tous","/writs lang fr")
SlashCmdList.WRITPRICE("lang en")
ok(ns.db.locale=="enUS" and profBtn._text=="Professions: all","/writs lang en")
SlashCmdList.WRITPRICE("lang auto")
ok(ns.db.locale==nil and ns.LocaleCode()==EXPECTED,"/writs lang auto")
ok(Lc.UNKNOWN_KEY_FOR_TEST=="UNKNOWN_KEY_FOR_TEST","cle inconnue = nom de la cle")

-- empty state
ns.db.scan[ns.RealmKey()]=nil
ns.RefreshUI()
local emptyShown=false
for _,f in ipairs(frames) do if f._text and tostring(f._text):find(Lc.EMPTY_TITLE,1,true) and f._shown then emptyShown=true end end
ok(emptyShown,"etat vide sans scan")
ns.db.scan[ns.RealmKey()]=sc

-- columns and scale
local frameW = WritPriceFrame._width
ns.db.colOff.zone=true ns.db.colOff.recipe=true
SlashCmdList.WRITPRICE("cols") SlashCmdList.WRITPRICE("cols") -- open/close menu
ok(WritPriceColsMenu~=nil,"menu colonnes")
local cb
for _,f in ipairs(frames) do if f._kind=="CheckButton" and f._parent==WritPriceColsMenu then cb=f break end end
cb._checked=true cb:Click() -- re-show zone via the menu -> relayout
ok(ns.db.colOff.zone==nil,"colonne zone reaffichee par le menu")
local w1=WritPriceFrame._width
ns.db.colOff.zone=true
cb._checked=false cb:Click()
local w2=WritPriceFrame._width
ok(w2 < w1,"masquer des colonnes reduit la fenetre ("..w1.." -> "..w2..")")
UIParent._width=700 ns.ApplyScale()
ok(WritPriceFrame._scale and WritPriceFrame._scale < 1,"ecran etroit -> echelle < 1")
UIParent._width=1365
SlashCmdList.WRITPRICE("reset")
ok(next(ns.db.colOff)==nil and ns.db.scale==nil,"/writs reset")
SlashCmdList.WRITPRICE("scale 80") ok(ns.db.scale==0.8,"/writs scale 80")
SlashCmdList.WRITPRICE("reset")

-- AH button never scans
local started=0 local orig=ns.StartScan ns.StartScan=function() started=started+1 end
AuctionHouseFrame=CreateFrame("Frame")
fire("AUCTION_HOUSE_SHOW")
ok(WritPriceScanButton and WritPriceScanButton._text=="WritPrice","bouton HV = WritPrice")
local shown=WritPriceFrame:IsShown()
WritPriceScanButton:Click() ok(WritPriceFrame:IsShown()~=shown,"bouton HV bascule la fenetre")
WritPriceScanButton:Click()
ok(started==0,"aucun scan declenche par HV / bouton HV / filtres")
ns.StartScan=orig
ok(ns.LastScanText()==ns.F("UI_LAST_SCAN", ns.F("AGO_MIN", 2)),"age du dernier scan")

-- help and about: no donation, help <= 11 lines
local before=#printed
SlashCmdList.WRITPRICE("help")
ok(#printed-before<=11,"aide <= 11 lignes ("..(#printed-before)..")")
SlashCmdList.WRITPRICE("about")
for i=before+1,#printed do
  local p=printed[i]:lower()
  ok(not (p:find("donat") or p:find("ko%-fi") or p:find("paypal") or p:find("patreon") or p:find("don ") or p:find("dons")),"pas de don dans aide/about")
end

-- quests in progress
local Q = {
  {questID=901, title="Craftsman's Writ: Comfortable Leather Hat", obj={{text="Comfortable Leather Hat: 0/1", type="item", numRequired=1, numFulfilled=0}}},
  {questID=902, title="Deliver 1 Star Belt", obj={{text="Star Belt: 1/1", type="item", numRequired=1, numFulfilled=1}}},
}
local sel=nil
C_QuestLog={}
C_QuestLog.GetNumQuestLogEntries=function() return #Q end
C_QuestLog.GetInfo=function(i) local q=Q[i] return q and {questID=q.questID,title=q.title,isHeader=false} end
C_QuestLog.GetQuestObjectives=function(id) for _,q in ipairs(Q) do if q.questID==id then return q.obj end end return {} end
C_QuestLog.GetSelectedQuest=function() return sel end
C_QuestLog.SetSelectedQuest=function(id) sel=id end
GetQuestLogQuestText=function() return "desc", "Deliver the Comfortable Leather Hat and the Craftsman's Writ to Garek at Dustwind Gulch in Badlands." end
sc.writs[W.."Comfortable Leather Hat"]={min=1900,n=3} sc.items["Comfortable Leather Hat"]={min=8900}
ns.ScanQuestLog()
local rows=ns.BuildRows("ALL")
local hat, belt
for _,r in ipairs(rows) do if r.item=="Comfortable Leather Hat" then hat=r end if r.item=="Star Belt" then belt=r end end
ok(hat and hat.active and not hat.ready and hat.total==8900,"writ en cours : total = objet seul")
ok(belt and belt.ready and belt.total==0,"writ pret, absent du scan mais liste")
ok(rows[1].active and rows[2].active,"en cours en tete")
local pn2,pr2,nr2,rr2=ns.PendingRep() ok(pn2==2 and pr2==250 and nr2==1 and rr2==125,"reputation en attente")
if ns.EnglishClient() then ok(hat.dest=="Garek at Dustwind Gulch in Badlands" and hat.zone=="Badlands","destination lue dans la quete") else ok(hat.destSrc=="guide" or hat.dest==nil,"client non anglais : destination du guide") end
local d,z,src=ns.WritDestination(W.."Heavy Quiver")
ok(z=="Stonetalon Mountains" and src=="guide","destination de la liste integree")
local cnt=0 for _,r in ipairs(rows) do if r.item=="Comfortable Leather Hat" then cnt=cnt+1 end end
ok(cnt==1,"pas de ligne en double")
ns.RefreshUI()
Q={} ns.ScanQuestLog()
for _,r in ipairs(ns.BuildRows("ALL")) do assert(not r.active) end
ok(true,"plus en cours apres rendu")

-- recipe status
GetNumSkillLines=function() return 3 end
local SK={{"Professions",true},{"Leatherworking",false,false,150},{"Skinning",false,false,160}}
GetSkillLineInfo=function(i) local s=SK[i] return s[1],s[2],s[3],s[4] end
ns.ReadSkills()
ok(select(1,ns.CraftStatus("Heavy Quiver"))=="trainer","Heavy Quiver = maitre")
ok(select(1,ns.CraftStatus("Comfortable Leather Hat"))=="pattern","Comfortable Leather Hat = patron")
ok(select(1,ns.CraftStatus("Mechanical Dragonling"))=="noprof","Dragonling = metier non appris")
GetNumTradeSkills=function() return 2 end
GetTradeSkillLine=function() return "Leatherworking",150,300 end
local TS={{"Leatherworking","header"},{"Heavy Quiver","optimal"}}
GetTradeSkillInfo=function(i) return TS[i][1],TS[i][2] end
ns.ReadKnownRecipes()
ok(select(1,ns.CraftStatus("Heavy Quiver"))=="known","recette connue apres fenetre de metier")

-- scan end message: one line outside debug mode
ns.db.debug=nil
AuctionHouseFrame=CreateFrame("Frame")
C_AuctionHouse={SendBrowseQuery=function() end, GetBrowseResults=function() return {} end}
ns.StartScan()
before=#printed
ns.StopScan()
if ns.EnglishClient() then ok(#printed-before==1,"une seule ligne a l'arret du scan") else ok(count(Lc.CHAT_LOC_NEED_FULL)+count(Lc.CHAT_LOC_FULL)>=1,"client non anglais : nom des writs inconnu -> scan complet demande") end


-- goal from the reputation level (bug of 0.9.2: always 1000)
GetNumFactions=function() return 1 end
GetFactionInfo=function(i) return "Azeroth Commerce Authority", "", 5, 3000, 9000, 4200 end
_G.FACTION_STANDING_LABEL5="Friendly"
ns.db.goal=0
local g,tier=ns.GetGoal()
ok(g==4800 and tier=="Friendly","objectif palier = 4800 (Friendly)")
ns.RefreshUI()
ns.db.goal=nil

-- popups: text, OnShow and OnAccept with an edit box
local eb=mock("EditBox")
local dlg=setmetatable({editBox=eb, data=W.."Mana Potion"}, {__index=function() return nil end})
ok(StaticPopupDialogs.WRITPRICE_QTY.text:find("%%s")~=nil,"popup quantite : texte avec %s")
StaticPopupDialogs.WRITPRICE_QTY.OnShow(dlg, dlg.data)
eb._text="3" StaticPopupDialogs.WRITPRICE_QTY.OnAccept(dlg, dlg.data)
ok(ns.db.writs[W.."Mana Potion"].qty==3 and ns.db.writs[W.."Mana Potion"].qtySrc=="manual","popup quantite -> 3")
eb._text="0" StaticPopupDialogs.WRITPRICE_QTY.OnAccept(dlg, dlg.data)
ok(ns.db.writs[W.."Mana Potion"].qty==nil,"popup quantite 0 -> defaut")
eb._text="250" StaticPopupDialogs.WRITPRICE_GOAL.OnAccept(dlg)
ok(ns.GetGoal()==250,"popup objectif -> 250")
ns.db.goal=nil

-- writ tooltip
local tip=mock("GameTooltip")
tip.GetItem=function() return W.."Mana Potion" end
local handled=false
for _,f in ipairs(frames) do end
if TooltipDataProcessor==nil then
  -- the bench has no TooltipDataProcessor: Tooltip.lua hooked OnTooltipSetItem on GameTooltip
  local h=GameTooltip._scripts.OnTooltipSetItem
  if h then GameTooltip.GetItem=function() return W.."Mana Potion" end GameTooltip._lines={} h(GameTooltip) handled=true end
end
ok(handled and GameTooltip._lines and #GameTooltip._lines>3,"infobulle de writ ("..(GameTooltip._lines and #GameTooltip._lines or 0).." lignes)")
GameTooltip._scripts.OnTooltipCleared(GameTooltip)

-- row tooltip
ns.ShowUI()
local rowBtn
for _,f in ipairs(frames) do if f._kind=="Button" and f._scripts.OnEnter and f.row then rowBtn=f break end end
ok(rowBtn~=nil,"ligne avec donnees")
rowBtn._scripts.OnEnter(rowBtn)
ok(#GameTooltip._lines>5 and GameTooltip._minw>0,"infobulle de ligne + largeur minimale")
rowBtn._scripts.OnLeave(rowBtn)
ok(GameTooltip._minw==0,"largeur minimale remise a 0")
local function hasLine(t) for _,l in ipairs(GameTooltip._lines or {}) do if l:find(t,1,true) then return true end end return false end
rowBtn._scripts.OnEnter(rowBtn)
local nShort=#GameTooltip._lines
ok(hasLine(Lc.TT2_TOTAL) and hasLine(Lc.TT2_HINT_SHIFT),"infobulle courte : total et aide")
GameTooltip.IsOwned=function(self, o) return o==rowBtn end
IsShiftKeyDown=function() return true end
rowBtn._scripts.OnUpdate(rowBtn, 0.2)
ok(#GameTooltip._lines>nShort and not hasLine(Lc.TT2_HINT_SHIFT),"Maj : details ajoutes ("..nShort.." -> "..#GameTooltip._lines..")")
IsShiftKeyDown=nil GameTooltip.IsOwned=nil
rowBtn._scripts.OnLeave(rowBtn)
-- right-click menu
rowBtn._scripts.OnClick(rowBtn, "RightButton")
ok(WritPriceRowMenu and WritPriceRowMenu._shown,"clic droit : menu affiche")
local menuItems={}
for _,f in ipairs(frames) do if f._parent==WritPriceRowMenu and f._kind=="Button" and f._shown then menuItems[#menuItems+1]=f end end
ok(#menuItems>=3,"menu : "..#menuItems.." actions")
WritPriceRowMenu:Hide()
-- turn-in place on the map
local mapID,x,y=ns.TurnInPoint("Craftsman's Writ: Elixir of Wisdom")
ok(mapID==1417 and math.abs(x-0.487)<1e-6 and math.abs(y-0.558)<1e-6,"lieu de rendu : carte 1417, 48.7/55.8")
local tt
TomTom={AddWaypoint=function(self,m,px,py,o) tt={m,px,py,o} return {} end}
ns.ShowTurnIn("Craftsman's Writ: Elixir of Wisdom")
ok(tt and tt[1]==1417 and tt[4].title:find("Muggol",1,true),"point TomTom pose")
TomTom=nil
local pin
C_Map={SetUserWaypoint=function(p) pin=p end} UiMapPoint={CreateFromCoordinates=function(m,px,py) return {m=m,x=px,y=py} end}
ns.ShowTurnIn("Craftsman's Writ: Elixir of Wisdom")
ok(pin and pin.m==1417,"sans TomTom : repere du jeu")
C_Map=nil UiMapPoint=nil
ok(ns.TurnInPoint("Craftsman's Writ: Truc Inconnu")==nil,"writ sans coordonnees : pas de point")

-- broker with a fake LibStub
local created
LibStub=function(name, silent) return {NewDataObject=function(self, n, d) created=d return d end} end
fire("PLAYER_LOGIN") runTimers()
ok(created and created.type=="launcher","lanceur LDB")
LibStub=nil

-- debug commands
SlashCmdList.WRITPRICE("debug api") SlashCmdList.WRITPRICE("debug dests") SlashCmdList.WRITPRICE("debug quests")
ok(true,"/writs debug api|dests|quests")



-- ===== fast full scan (modern: ReplicateItems) =====
local function tick(n, dt)
  for k=1,(n or 1) do
    TNOW=TNOW+(dt or 0.1)
    for _,f in ipairs(frames) do local u=f._scripts.OnUpdate if u and f._shown then u(f) end end
  end
end
AuctionFrame=nil
AuctionHouseFrame=CreateFrame("Frame")
local function E(name,count,buyout,id) return {name,nil,count,1,true,1,0,1,1,buyout,0,false,nil,"x",nil,0,id,true} end
local REP={}
for i=1,3000 do REP[#REP+1]=E("Junk "..(i%500),1,1000+i,90000+i) end
REP[#REP+1]=E("Craftsman's Writ: Mana Potion",1,500,50001)
REP[#REP+1]=E("Craftsman's Writ: Mana Potion",2,800,50001)
REP[#REP+1]=E("Mana Potion",5,5000,3827)
REP[#REP+1]=E("",1,700,ns.ITEM_IDS["Heavy Leather"])
REP[#REP+1]=E("",1,700,123456)
local replicated=0
C_AuctionHouse={SendBrowseQuery=function() end, GetBrowseResults=function() return {} end,
  ReplicateItems=function() replicated=replicated+1 end,
  GetNumReplicateItems=function() return #REP end,
  GetReplicateItemInfo=function(i) return unpack(REP[i+1]) end,
  GetReplicateItemLink=function(i) return "item:"..(REP[i+1][17] or 0) end}
ns.db.fullAt=nil ns.db.scanMode=nil
ok(ns.FullScanWait()==0,"scan complet disponible")
ns.StartAutoScan()
ok(replicated==1 and ns.IsScanning() and ns.IsFullScanning(),"scan complet lance (auto)")
fire("REPLICATE_ITEM_LIST_UPDATE")
tick(1,0.5)
tick(12)
ok(ns.IsFullScanning(),"attente des noms inconnus")
tick(1,9) tick(5)
ok(not ns.IsScanning(),"scan complet termine")
local fs=ns.CurrentScan()
ok(fs and fs.full and fs.writs["Craftsman's Writ: Mana Potion"].min==400 and fs.writs["Craftsman's Writ: Mana Potion"].n==3,"writ : prix unitaire minimal 400, 3 exemplaires")
ok(fs.items["Mana Potion"] and fs.items["Mana Potion"].min==1000,"objet demande : 1000 /u")
ok(fs.items["Heavy Leather"] and fs.items["Heavy Leather"].min==700,"nom retrouve par l'identifiant")
ok(fs.items["Mechanical Dragonling"]==nil and fs.asked["Mechanical Dragonling"]~=nil,"objet absent = cherche, pas en vente")
ok(count(ns.F("CHAT_FULL_PARTIAL",1))==1,"1 enchere non identifiee signalee")
ok(ns.FullScanWait()>0,"limite de 15 min apres un scan complet")
local started2=0 local origStart=ns.StartScan ns.StartScan=function() started2=started2+1 end
ns.StartAutoScan() ok(started2==1 and replicated==1,"auto pendant la limite -> scan cible")
ns.db.scanMode="full" ns.StartAutoScan() ok(started2==1,"mode complet pendant la limite : rien lance")
ns.db.scanMode=nil
-- refused: no answer from the server
ns.db.fullAt=nil
C_AuctionHouse.GetNumReplicateItems=function() return 0 end
local before=ns.db.fullAt
ns.StartFullScan()
tick(1,61)
ok(not ns.IsFullScanning() and started2==2 and count(Lc.CHAT_FULL_REFUSED)==1,"pas de reponse -> repli scan cible")
ok(ns.db.fullAt==before and ns.FullScanWait()>0 and ns.FullScanWait()<=60,"refus : limite non comptee, nouvel essai dans 1 min")
ns.StartScan=origStart
C_AuctionHouse=nil AuctionHouseFrame=nil

-- ===== full scan (legacy: getAll) =====
AuctionFrame=CreateFrame("Frame")
local qArgs
function CanSendAuctionQuery() return true, true end
function QueryAuctionItems(...) qArgs={...} end
function GetNumAuctionItems() return #REP, #REP end
function GetAuctionItemInfo(_, i) return unpack(REP[i]) end
function GetAuctionItemLink(_, i) return "item:1" end
ns.db.fullAt=nil NOW=NOW+61
ok(ns.FullScanWait()==0,"legacy : getAll disponible")
ns.StartFullScan()
ok(qArgs and qArgs[7]==true,"legacy : QueryAuctionItems getAll=true")
fire("AUCTION_ITEM_LIST_UPDATE") tick(1,0.5) tick(12) tick(1,9) tick(5)
fs=ns.CurrentScan()
ok(not ns.IsScanning() and fs.writs["Craftsman's Writ: Mana Potion"].min==400,"legacy : scan complet lu (base 1)")
function CanSendAuctionQuery() return true, false end
ok(ns.FullScanWait()>0,"legacy : getAll pas autorise")
AuctionFrame=nil CanSendAuctionQuery=nil QueryAuctionItems=nil GetNumAuctionItems=nil GetAuctionItemInfo=nil GetAuctionItemLink=nil

-- ===== Auctionator prices =====
Auctionator={API={v1={
  GetAuctionPriceByItemID=function(c,id) assert(type(c)=="string") if id==3827 then return 1234 end return nil end,
  GetAuctionAgeByItemID=function(c,id) return 0 end}}}
ok(ns.AtrFresh("Mana Potion")==1234,"prix Auctionator du jour")
fs.items["Mana Potion"]=nil
local mp
for _,r in ipairs(ns.BuildRows("ALL")) do if r.item=="Mana Potion" then mp=r end end
ok(mp and mp.unit==nil,"notre scan complet dit 'pas en vente' : pas de prix Auctionator plus ancien")
fs.asked["Mana Potion"]=nil
ns.AtrClearCache()
for _,r in ipairs(ns.BuildRows("ALL")) do if r.item=="Mana Potion" then mp=r end end
ok(mp and mp.unit==1234 and mp.unitAtr==0,"prix Auctionator en repli (marque A)")
Auctionator.API.v1.GetAuctionAgeByItemID=function() return 5 end ns.AtrClearCache()
for _,r in ipairs(ns.BuildRows("ALL")) do if r.item=="Mana Potion" then mp=r end end
ok(mp and mp.unit==nil,"prix Auctionator de 5 jours : ignore")
Auctionator.API.v1.GetAuctionAgeByItemID=function() return 0 end ns.AtrClearCache()
ns.db.useAtr=false ns.AtrClearCache()
ok(ns.AtrPrice("Mana Potion")==nil,"option Auctionator desactivee")
ns.db.useAtr=nil
Auctionator.API.v1.GetAuctionPriceByItemID=function() error("boom") end
ns.AtrClearCache()
local e0=ns.errorCount
ok(ns.AtrPrice("Mana Potion")==nil and ns.errorCount==e0,"API Auctionator en erreur : ignoree")
Auctionator=nil


-- ===== Coin Pouch samples and sharing =====
local POUCHID=999001
local PC=0
local money=100000
C_Container={GetContainerNumSlots=function(bag) return bag==0 and 1 or 0 end,
  GetContainerItemInfo=function(bag,slot) if bag==0 and slot==1 and PC>0 then return {itemID=POUCHID, stackCount=PC} end end}
local origGII=ns.GetItemInfo
ns.GetItemInfo=function(id) if id==POUCHID then return "Coin Pouch" end return origGII and origGII(id) end
function GetMoney() return money end
function UnitGUID() return "Player-1-0000ABCD" end
function IsInGuild() return true end
strsplit=strsplit or function(sep, str) local t={} for part in (str..sep):gmatch("(.-)"..sep:gsub("%p","%%%0")) do t[#t+1]=part end return unpack(t) end
local sent={}
C_ChatInfo={SendAddonMessage=function(prefix,msg,ch) sent[#sent+1]={prefix=prefix,msg=msg,ch=ch} end,
  RegisterAddonMessagePrefix=function() return true end}
fire("PLAYER_MONEY") fire("BAG_UPDATE_DELAYED")
ns.questMap[777]=W.."Mana Potion"
fire("QUEST_TURNED_IN",777)
PC=1 fire("BAG_UPDATE_DELAYED")
ok(ns.db.pouch.queue[1].rank=="Expert" and ns.db.pouch.queue[1].item=="Mana Potion","bourse recue apres un writ Expert : rang et writ notes")
TNOW=TNOW+30
PC=0 fire("BAG_UPDATE_DELAYED")
money=money+3915 fire("PLAYER_MONEY")
local m,n,own=ns.PouchMedian("Expert")
ok(m==3915 and n==1 and own==1,"bourse ouverte : 39 pa 15 enregistres (Expert)")
-- the other order: money first, then the bag update
fire("QUEST_TURNED_IN",777) PC=1 fire("BAG_UPDATE_DELAYED") TNOW=TNOW+5
money=money+3963 fire("PLAYER_MONEY") PC=0 fire("BAG_UPDATE_DELAYED")
m,n=ns.PouchMedian("Expert")
ok(n==2 and m==math.floor((3915+3963)/2),"ordre argent puis sac : enregistre aussi")
-- unrelated money (no pouch opened) is ignored
money=money+5000 fire("PLAYER_MONEY")
ok(select(2,ns.PouchMedian("Expert"))==2,"argent sans bourse ouverte : ignore")
tick(5,2)
local okSent=false for _,x in ipairs(sent) do if x.prefix=="WRITPRICE" and x.ch=="GUILD" and x.msg:find("^P|2|Expert|3915|") then okSent=true end end
ok(okSent,"bourse partagee avec la guilde")
local sample=ns.db.pouch.samples.Expert[1]
ok(sample.item=="Mana Potion" and sample.dest~=nil,"releve : writ et lieu de rendu enregistres")
local withItem=false for _,x in ipairs(sent) do if x.msg:find("|Mana Potion|",1,true) then withItem=true end end
ok(withItem,"message partage : contient le writ")
-- receive from another player
fire("CHAT_MSG_ADDON","WRITPRICE","P|2|Expert|2391|"..NOW.."|other-1|Wild Leather Helmet|Tester NPC at Somewhere in Feralas|Feralas","GUILD","Other-Realm")
ok(select(2,ns.PouchMedian("Expert"))==3,"releve recu ajoute")
local dWL,zWL,sWL=ns.WritDestination(W.."Wild Leather Helmet")
ok(zWL=="Feralas" and sWL=="shared","lieu de rendu appris d'un autre joueur")
fire("CHAT_MSG_ADDON","WRITPRICE","P|1|Expert|2391|"..NOW.."|other-1","PARTY","Other-Realm")
ok(select(2,ns.PouchMedian("Expert"))==3,"doublon ignore (meme identifiant)")
fire("CHAT_MSG_ADDON","WRITPRICE","P|1|Expert|99999999|"..NOW.."|other-2","GUILD","Other-Realm")
fire("CHAT_MSG_ADDON","WRITPRICE","P|1|Nope|2000|"..NOW.."|other-3","GUILD","Other-Realm")
fire("CHAT_MSG_ADDON","WRITPRICE","P|1|Expert|2000|"..(NOW+10*86400).."|other-4","GUILD","Other-Realm")
ok(select(2,ns.PouchMedian("Expert"))==3,"valeurs absurdes rejetees")
for i=1,40 do fire("CHAT_MSG_ADDON","WRITPRICE","P|1|Expert|2500|"..NOW.."|spam-"..i,"GUILD","Spammer") end
ok(select(2,ns.PouchMedian("Expert"))==3+30,"un meme joueur limite a 30 releves")
ns.db.share=false
fire("CHAT_MSG_ADDON","WRITPRICE","P|1|Expert|2600|"..NOW.."|x-1","GUILD","Someone")
ok(select(2,ns.PouchMedian("Expert"))==33,"partage desactive : rien recu")
ns.db.share=nil
-- net cost in the ranking
fs.items["Mana Potion"]={min=1000,n=1,t=NOW}
local row
for _,r in ipairs(ns.BuildRows("ALL")) do if r.name==W.."Mana Potion" then row=r end end
ok(row and row.pouch==ns.PouchMedian("Expert") and row.net==row.total-row.pouch,"cout net = total - bourse")
ok(row.perRep==row.net/125,"cout par point net")
ns.db.usePouch=false
for _,r in ipairs(ns.BuildRows("ALL")) do if r.name==W.."Mana Potion" then row=r end end
ok(row.perRep==row.total/125,"option : bourse non deduite")
ns.db.usePouch=nil
SlashCmdList.WRITPRICE("bourse")
ok(count("Expert")>0,"/writs bourse")
C_Container=nil ns.GetItemInfo=origGII
-- ===== export / import =====
ns.db.writs[W.."Heavy Quiver"]=ns.db.writs[W.."Heavy Quiver"] or {}
local hq=ns.db.writs[W.."Heavy Quiver"]
hq.dest="Ziz Fizziks at Windshear Crag in Stonetalon Mountains" hq.qty=1 hq.qtySrc="quest" hq.rank="Journeyman" hq.item="Heavy Quiver"
local text,c=ns.BuildExport()
ok(text:find("^WPX;1;") and text:find("\nEND;%x+$") and c.D>=1 and c.Q>=1 and c.P>=2,"export construit ("..c.D.." lieux, "..c.Q.." qte, "..c.P.." bourses)")
ok(not text:find("Tester") and not text:find("Player%-1"),"export sans nom de personnage")
SlashCmdList.WRITPRICE("export")
ok(WritPriceExportEdit and WritPriceExportEdit._text==text,"fenetre d'export avec le texte")
-- import into a fresh profile
local saved=ns.db.writs ns.db.writs={}
local savedPouch=ns.db.pouch ns.db.pouch=nil ns.pouchCache=nil
local res=ns.ApplyImport(text)
ok(res and res.D>=1 and res.P>=2,"import : lieux et bourses ajoutes")
local d,z,src=ns.WritDestination(W.."Heavy Quiver")
ok(z=="Stonetalon Mountains" and src=="shared","import : lieu de rendu utilisable")
ok(ns.db.writs[W.."Heavy Quiver"].qty==1 and ns.db.writs[W.."Heavy Quiver"].qtySrc=="import","import : quantite")
local res2=ns.ApplyImport(text)
ok(res2 and res2.P==0,"import repete : pas de doublon")
local bad=text:gsub("Ziz","Zaz",1)
local r3,err=ns.ApplyImport(bad)
ok(r3==nil and err=="IMPORT_CHECKSUM","export abime : refuse")
ok(select(2,ns.ApplyImport("hello"))=="IMPORT_BAD","texte quelconque : refuse")
ns.db.writs=saved ns.db.pouch=savedPouch ns.pouchCache=nil
-- built-in pouch default when no sample
ns.POUCH_DEFAULT={Artisan=12345} ns.pouchCache=nil
local pm,pn=ns.PouchMedian("Artisan")
ok(pm==12345 and pn==0,"valeur de bourse integree sans releve")
ns.POUCH_DEFAULT=nil ns.pouchCache=nil


-- ===== game client in French (names translated by item ID, Names.lua) =====
do
local origLocale=GetLocale()
local origGetLocale=GetLocale
GetLocale=function() return "frFR" end
ns.ResetNames() ns.db.locNames=nil
ns.db.itemIDs["Craftsman's Writ: Mana Potion"]=nil -- writ IDs not known yet: built-in ones set aside
local savedExtra=ns.EXTRA_IDS ns.EXTRA_IDS={}
local MP=ns.ITEM_IDS["Mana Potion"]
local HL=ns.ITEM_IDS["Heavy Leather"]
ok(MP==3827 and HL~=nil and ns.WRIT_LIST["Mana Potion"]~=nil,"donnees de test : Mana Potion 3827")
local WFR="Commande d'artisan : Potion de mana"
local FR={[MP]="Potion de mana", [HL]="Cuir épais", [50001]=WFR, [999002]="Bourse de pièces"}
local frGII=function(id) return FR[id] end
local origGII2=ns.GetItemInfo
ns.GetItemInfo=frGII
ok(not ns.EnglishClient(),"client francais detecte")
ns.PreloadNames()
ok(ns.LocName("Mana Potion")=="Potion de mana" and ns.Disp("Mana Potion")=="Potion de mana","nom traduit par l'identifiant")
ok(ns.Disp("Truc Inconnu")=="Truc Inconnu","nom inconnu affiche tel quel")
ok(ns.WritSearchText()==nil,"prefixe des writs encore inconnu")
ok(ns.CanonName(WFR)=="Craftsman's Writ: Mana Potion","writ francais reconnu par sa forme")
ok(ns.WritSearchText()=="Commande d'artisan","prefixe des writs appris")
ok(ns.LocName("Craftsman's Writ: Mana Potion")==WFR,"nom du writ en francais")
ok(ns.CanonName("Cuir épais",HL)=="Heavy Leather" and ns.CanonName("Truc",nil)=="Truc","noms ramenes a l'anglais")
ok(ns.CanonName("Commande d'artisan : Truc")=="Commande d'artisan : Truc","writ d'un objet inconnu : non reconnu")
-- full scan with French names
ns.ResetNames() ns.PreloadNames()
AuctionFrame=nil
AuctionHouseFrame=CreateFrame("Frame")
local function E2(name,count,buyout,id) return {name,nil,count,1,true,1,0,1,1,buyout,0,false,nil,"x",nil,0,id,true} end
local REP2={E2(WFR,1,600,50001),E2("Potion de mana",4,4000,MP),E2("Cuir épais",1,300,HL),E2("Objet quelconque",1,50,77777)}
FR[77777]="Objet quelconque"
C_AuctionHouse={SendBrowseQuery=function() end, GetBrowseResults=function() return {} end,
  ReplicateItems=function() end,
  GetNumReplicateItems=function() return #REP2 end,
  GetReplicateItemInfo=function(i) return unpack(REP2[i+1]) end,
  GetReplicateItemLink=function(i) return "item:"..(REP2[i+1][17] or 0) end}
ns.db.fullAt=nil ns.db.scanMode=nil NOW=NOW+3600
ns.StartFullScan()
fire("REPLICATE_ITEM_LIST_UPDATE") tick(1,0.5) tick(12) tick(1,9) tick(10)
ok(not ns.IsScanning(),"scan complet (client francais) termine")
local f2=ns.CurrentScan()
ok(f2.writs["Craftsman's Writ: Mana Potion"] and f2.writs["Craftsman's Writ: Mana Potion"].min==600,"scan complet : writ francais range sous son nom anglais")
ok(f2.items["Mana Potion"] and f2.items["Mana Potion"].min==1000,"scan complet : objet demande en francais")
ok(f2.items["Heavy Leather"] and f2.items["Heavy Leather"].min==300,"scan complet : composant en francais")
ok(ns.db.itemIDs["Craftsman's Writ: Mana Potion"]==50001,"identifiant du writ appris")
local anyFr=false for k in pairs(ns.db.itemIDs) do if k:find("Potion de",1,true) or k:find("Commande",1,true) then anyFr=true end end
ok(not anyFr,"aucun nom francais enregistre comme cle")
-- targeted scan: French search texts, results back in English
ns.db.done={} ns.db.noReagents=true
local queries={}
local lastQ
local BR={["Commande d'artisan"]={{itemKey={itemID=50001},minPrice=550,totalQuantity=2}},
  ["Potion de mana"]={{itemKey={itemID=MP},minPrice=900,totalQuantity=3}}}
C_AuctionHouse={SendBrowseQuery=function(q) queries[#queries+1]=q.searchString lastQ=q.searchString end,
  GetBrowseResults=function() return BR[lastQ] or {} end}
ns.StartScan()
for k=1,12 do tick(1,0.2) fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED") tick(1,0.2) end
ok(queries[1]=="Commande d'artisan","scan cible : writs cherches en francais")
local askedFr=false for _,q in ipairs(queries) do if q=="Potion de mana" then askedFr=true end end
ok(askedFr,"scan cible : objet cherche en francais")
ok(not ns.IsScanning(),"scan cible termine")
local f3=ns.CurrentScan()
ok(f3.writs["Craftsman's Writ: Mana Potion"] and f3.writs["Craftsman's Writ: Mana Potion"].min==550,"scan cible : writ sous son nom anglais")
ok(f3.items["Mana Potion"] and f3.items["Mana Potion"].min==900,"scan cible : prix de l'objet")
ns.db.noReagents=nil
-- display
ns.ShowUI() ns.RefreshUI()
local shownFr=false
for _,f in ipairs(frames) do if type(f._text)=="string" and f._text:find("Potion de mana",1,true) and f._shown then shownFr=true end end
ok(shownFr,"fenetre : nom affiche en francais")
-- quest log in French
Q={
  {questID=911, title="Livrer 5 Potions de mana", obj={{text="Potion de mana : 2/5", type="item", numRequired=5, numFulfilled=2}}},
  {questID=912, title="Le retour du roi", obj={{text="Potion de mana : 0/3", type="item", numRequired=3, numFulfilled=0}}},
}
GetQuestLogQuestText=function() return "desc", "Apportez les potions a quelqu'un." end
ns.ScanQuestLog()
local a=ns.ActiveWrit("Craftsman's Writ: Mana Potion")
ok(a and a.need==5 and a.have==2,"quete de writ en francais reconnue (2/5)")
ok(ns.questMap[912]==nil,"quete ordinaire avec le meme objet : ignoree")
Q={{questID=913, title="Commande d'artisan : Potion de mana", obj={{text="Potion de mana : 1/1", type="item", numRequired=1, numFulfilled=1}}}}
ns.ScanQuestLog()
ok(ns.questMap[913]=="Craftsman's Writ: Mana Potion","quete au nom du writ en francais")
Q={} ns.ScanQuestLog()
-- tooltip in French
GameTooltip._scripts.OnTooltipCleared(GameTooltip)
ns.lastWrit=nil
GameTooltip.GetItem=function() return WFR, "|cffffffff|Hitem:50001::::|h["..WFR.."]|h|r" end
GameTooltip._scripts.OnTooltipSetItem(GameTooltip)
ok(ns.lastWrit=="Craftsman's Writ: Mana Potion","infobulle d'un writ en francais")
GameTooltip._scripts.OnTooltipCleared(GameTooltip)
-- known recipes in French
GetNumTradeSkills=function() return 1 end
GetTradeSkillLine=function() return "Alchimie",200,300 end
GetTradeSkillInfo=function() return "Potion de mana","optimal" end
GetTradeSkillItemLink=function() return "|Hitem:"..MP.."|h[Potion de mana]|h" end
ns.ReadKnownRecipes()
ok(ns.Char().known["Mana Potion"]==true and ns.Char().known["Potion de mana"]==nil,"recette connue lue en francais")
GetTradeSkillItemLink=nil
-- Coin Pouch and faction by ID
ns.EXTRA_IDS["Coin Pouch"]=999002
ok(ns.IsPouch(999002,"Bourse de pièces") and not ns.IsPouch(5,"Truc"),"bourse reconnue par son identifiant")
ns.EXTRA_IDS["Coin Pouch"]=nil
ns.FACTION_IDS={["Azeroth Commerce Authority"]=1234}
GetNumFactions=function() return 1 end
GetFactionInfo=function() return "Autorité commerciale d'Azeroth", "", 5, 3000, 9000, 4200, nil,nil,nil,nil,nil,nil,nil,1234 end
ok(ns.FactionStanding()~=nil,"faction reconnue par son identifiant")
ns.FACTION_IDS={}
ok(ns.FactionStanding()==nil,"faction inconnue sans identifiant (client francais)")
GetLocale=function() return "enUS" end
GetFactionInfo=function() return "Durotar Supply and Logistics", "", 4, 0, 3000, 1200, nil,nil,nil,nil,nil,nil,nil,5678 end
ns.db.factionIDs=nil
ok(ns.FactionStanding()~=nil and ns.db.factionIDs["Durotar Supply and Logistics"]==5678,"faction de la Horde reconnue, identifiant appris")
ns.db.factionIDs=nil
GetLocale=function() return "frFR" end
GetFactionInfo=function() return "Autorité commerciale d'Azeroth", "", 5, 3000, 9000, 4200, nil,nil,nil,nil,nil,nil,nil,1234 end
-- export: no IDs from a French client
local tFr=ns.BuildExport()
ok(not tFr:find("\nI;") and not tFr:find("\nF;"),"export francais : pas d'identifiants")
-- English client: IDs exported, then imported by a French client
GetLocale=function() return "enUS" end ns.ResetNames()
GetFactionInfo=function() return "Azeroth Commerce Authority", "", 5, 3000, 9000, 4200, nil,nil,nil,nil,nil,nil,nil,1234 end
ns.db.factionIDs=nil
local tEn=ns.BuildExport()
ok(tEn:find("\nI;Craftsman's Writ: Mana Potion;50001",1,true) and tEn:find("\nF;1234;Azeroth Commerce Authority",1,true),"export anglais : identifiants du writ et de la faction")
GetLocale=function() return "frFR" end ns.ResetNames()
local savedIDs=ns.db.itemIDs ns.db.itemIDs={} ns.db.factionIDs=nil
local r=ns.ApplyImport(tEn)
ok(r and ns.db.itemIDs["Craftsman's Writ: Mana Potion"]==50001 and ns.db.factionIDs["Azeroth Commerce Authority"]==1234,"import des identifiants (client francais)")
ns.ResetNames() ns.PreloadNames()
ok(ns.WritSearchText()=="Commande d'artisan","prefixe connu des l'import (identifiant du writ)")
ns.db.itemIDs=savedIDs ns.db.factionIDs=nil
ns.ResetNames() ns.db.locNames=nil
local saved3=ns.db.itemIDs
ns.db.itemIDs={["Craftsman's Writ: Mana Potion"]=60001, ["Craftsman's Writ: Elixir of Wisdom"]=60002}
FR[60001]="Bon de commande (Potion de mana)" FR[60002]="Bon de commande (Elixir de sagesse)"
ok(ns.WritSearchText()=="Bon de commande","writs d'une autre forme : texte de recherche = debut commun")
ok(ns.CanonName("Bon de commande (Potion de mana)",60001)=="Craftsman's Writ: Mana Potion","writ d'une autre forme reconnu par son identifiant")
ns.db.itemIDs=saved3
-- back to the original client
GetLocale=origGetLocale ns.EXTRA_IDS=savedExtra ns.ResetNames() ns.GetItemInfo=origGII2
C_AuctionHouse=nil AuctionHouseFrame=nil
GetNumFactions=nil GetFactionInfo=nil GetNumTradeSkills=nil GetTradeSkillLine=nil GetTradeSkillInfo=nil
ns.db.scan[ns.RealmKey()]=sc
ns.db.locNames=nil
end

-- ===== writ faction hidden in a collapsed reputation category: found by ID (English client) =====
if ns.EnglishClient() then
ns.db.factionIDs=nil
C_Reputation={GetFactionDataByIndex=function(i) if i==1 then return {name="Classic", factionID=1} end end,
  GetFactionDataByID=function(id) if id==2586 then return {name="Azeroth Commerce Authority", factionID=2586, reaction=5, currentStanding=4500, currentReactionThreshold=3000, nextReactionThreshold=9000} end end}
local label,v,max=ns.FactionStanding()
ok(label~=nil and v==1500 and max==6000,"faction trouvee par identifiant (categorie repliee)")
ok(ns.db.factionIDs and ns.db.factionIDs["Azeroth Commerce Authority"]==2586,"identifiant de la faction appris")
local calls=0
C_Reputation.GetFactionDataByID=function(id) calls=calls+1 if id==2586 then return {name="Azeroth Commerce Authority", reaction=5, currentStanding=4500, currentReactionThreshold=3000, nextReactionThreshold=9000} end end
ns.FactionStanding()
ok(calls==1,"ensuite lu directement par son identifiant")
C_Reputation=nil ns.db.factionIDs=nil
end

-- ===== 0.1.0 learned "the location marked on your map" as a turn-in place: cleaned =====
do
local w=ns.WritInfo("Craftsman's Writ: Mana Potion")
w.dest="the location marked on your map. This writ must be in your possession to complete the transaction"
local _,_,src=ns.WritDestination("Craftsman's Writ: Mana Potion")
ok(w.dest==nil and src~="quest","destination parasite nettoyee")
ok(not ns.BuildExport():find("location marked",1,true),"export sans destination parasite")
Q={{questID=921, title="Deliver 2 Mana Potion", obj={{text="Mana Potion: 0/2", type="item", numRequired=2, numFulfilled=0}}}}
GetQuestLogQuestText=function() return "desc", "Deliver the potions to the location marked on your map. This writ must be in your possession to complete the transaction." end
ns.ScanQuestLog()
ok(ns.WritInfo("Craftsman's Writ: Mana Potion").dest==nil,"texte de quete 'location marked' non retenu")
Q={} ns.ScanQuestLog()
end

-- ===== options page =====
ok(settingsLog.frame ~= nil, "page de reglages enregistree")
if not LEGACY then ok(settingsLog.name=="WritPrice" and settingsLog.added~=nil, "categorie Settings") else ok(settingsLog.frame.name=="WritPrice","categorie legacy") end
inCombat=true SlashCmdList.WRITPRICE("options") inCombat=false
ok(settingsLog.opened==nil and count(Lc.OPT_COMBAT)>=1, "pas d'ouverture en combat")
SlashCmdList.WRITPRICE("config")
ok(settingsLog.opened==(LEGACY and settingsLog.frame or 42), "/writs config ouvre la page")
local panel=settingsLog.frame
local nFrames=#frames
panel:Show()
local n1=#frames
panel:Hide() panel:Show()
ok(#frames==n1 and n1>nFrames, "page construite une seule fois")
local function findText(t) for _,f in ipairs(frames) do if f._text==t then return f end end end
local function checkFor(key)
  -- the label FontString's parent button sits right of its check box: find the check box anchored before it
  local label=findText(Lc[key]) return label
end
-- language radios
SlashCmdList.WRITPRICE("lang fr")
ok(findText(ns.LOCALES.frFR.OPT_MINIMAP_SHOW)~=nil, "page retraduite en francais")
SlashCmdList.WRITPRICE("lang auto")
ok(findText(Lc.OPT_MINIMAP_SHOW)~=nil, "page retraduite en langue auto")
-- scale slider
WritPriceOptionsScale:SetValue(80)
ok(ns.db.scale==0.8, "curseur echelle -> 80 %")
WritPriceOptionsScale:SetValue(100)
ok(ns.db.scale==nil, "curseur echelle -> 100 % (defaut)")
-- goal box
WritPriceOptionsGoal._text="750" WritPriceOptionsGoal._scripts.OnEnterPressed(WritPriceOptionsGoal)
ok(ns.GetGoal()==750, "champ objectif 750")
WritPriceOptionsGoal._text="0" WritPriceOptionsGoal._scripts.OnEnterPressed(WritPriceOptionsGoal)
ok(ns.db.goal==0, "champ objectif 0")
ns.db.goal=nil
-- check boxes: click the label buttons by text
local function clickLabel(key)
  for _,f in ipairs(frames) do
    if f._kind=="Button" and f._scripts.OnClick then
      for _,g in ipairs(frames) do if g._text==Lc[key] and g._parentBtn==f then f._scripts.OnClick(f) return true end end
    end
  end
end
-- simpler: find the CheckButton created just before each label and toggle via the settings directly
ns.db.tooltip=false
GameTooltip._lines={} ns.lastWrit=nil
GameTooltip.GetItem=function() return W.."Mana Potion" end
GameTooltip._scripts.OnTooltipSetItem(GameTooltip)
ok(ns.lastWrit==W.."Mana Potion" and #GameTooltip._lines==0, "infobulles desactivees : pas de lignes, lastWrit appris")
GameTooltip._scripts.OnTooltipCleared(GameTooltip)
ns.db.tooltip=nil
GameTooltip._scripts.OnTooltipSetItem(GameTooltip)
ok(#GameTooltip._lines>3, "infobulles reactivees")
GameTooltip._scripts.OnTooltipCleared(GameTooltip)
-- AH button visibility
AuctionHouseFrame=CreateFrame("Frame")
ns.db.ahButton=false timers={}
fire("AUCTION_HOUSE_SHOW")
runTimers()
ok(not WritPriceScanButton._shown, "bouton HV masque (meme apres les timers)")
ns.db.ahButton=nil ns.UpdateAHButtonVisibility()
ok(WritPriceScanButton._shown, "bouton HV reaffiche")
-- clear prices
for _,f in ipairs(frames) do if f._text==Lc.OPT_BTN_CLEAR then f:Click() end end
ok(lastPopup and lastPopup.which=="WRITPRICE_CLEAR", "bouton effacer -> confirmation")
ok(StaticPopupDialogs.WRITPRICE_CLEAR.text==Lc.POPUP_CLEAR, "texte de confirmation")
local nWrits=0 for _ in pairs(ns.db.writs) do nWrits=nWrits+1 end
StaticPopupDialogs.WRITPRICE_CLEAR.OnAccept()
local nWrits2=0 for _ in pairs(ns.db.writs) do nWrits2=nWrits2+1 end
ok(ns.CurrentScan()==nil and nWrits2==nWrits and nWrits>0, "prix effaces, writs conserves")
ns.db.scan[ns.RealmKey()]=sc
-- open window from the page
for _,f in ipairs(frames) do if f._text==Lc.OPT_BTN_OPEN then f:Click() end end
ok(WritPriceFrame._shown and WritPriceFrame._strata=="DIALOG", "fenetre ouverte au-dessus des reglages")
WritPriceFrame:Hide()
ok(WritPriceFrame._strata=="HIGH", "strate normale apres fermeture")

-- ===== minimap icon =====
ok(WritPriceMinimapButton~=nil and WritPriceMinimapButton._parent==Minimap, "icone minicarte creee")
local function pos() local p=WritPriceMinimapButton._point return p[4], p[5], p[2] end
ns.db.minimap.minimapPos=0 ns.PlaceMinimapButton()
local x,y,rel=pos() ok(math.abs(x-75)<0.01 and math.abs(y)<0.01 and rel==Minimap, "angle 0 -> (75,0)")
ns.db.minimap.minimapPos=90 ns.PlaceMinimapButton()
x,y=pos() ok(math.abs(x)<0.01 and math.abs(y-75)<0.01, "angle 90 -> (0,75)")
GetMinimapShape=function() return "SQUARE" end
ns.db.minimap.minimapPos=45 ns.PlaceMinimapButton()
x,y=pos() ok(math.abs(x-75)<0.01 and math.abs(y-75)<0.01, "minicarte carree, 45 -> coin")
GetMinimapShape=nil
local b=WritPriceMinimapButton
cursorX,cursorY=600,500 b._scripts.OnDragStart(b) b._scripts.OnUpdate(b)
ok(math.abs(ns.db.minimap.minimapPos-0)<0.01, "glisser -> 0")
cursorX,cursorY=500,600 b._scripts.OnUpdate(b) b._scripts.OnDragStop(b)
ok(math.abs(ns.db.minimap.minimapPos-90)<0.01 and b._scripts.OnUpdate==nil, "glisser -> 90, puis arret")
ns.db.minimap.lock=true b._scripts.OnDragStart(b)
ok(b._scripts.OnUpdate==nil, "icone verrouillee : pas de deplacement")
ns.db.minimap.lock=nil
local shownBefore=WritPriceFrame:IsShown()
b._scripts.OnClick(b,"LeftButton") ok(WritPriceFrame:IsShown()~=shownBefore, "clic gauche -> fenetre")
settingsLog.opened=nil b._scripts.OnClick(b,"RightButton") ok(settingsLog.opened~=nil, "clic droit -> reglages")
SlashCmdList.WRITPRICE("minimap") ok(ns.db.minimap.hide==true and not b._shown, "/writs minimap masque")
SlashCmdList.WRITPRICE("minimap") ok(ns.db.minimap.hide==nil and b._shown, "/writs minimap reaffiche")
b._scripts.OnEnter(b) ok(#GameTooltip._lines>=4, "infobulle de l'icone") b._scripts.OnLeave(b)
settingsLog.opened=nil WritPrice_OnAddonCompartmentClick("WritPrice","RightButton")
ok(settingsLog.opened~=nil, "compartiment : clic droit -> reglages")
ok(#unknownCalls==0,"aucune methode d'interface inconnue ("..table.concat(unknownCalls,",")..")")
ok(ns.errorCount==0,"aucune erreur WritPrice ("..ns.errorCount..")")
return table.concat(out,"\n")
''')
print(result)
print("== %s: tous les tests passent" % LOCALE)
