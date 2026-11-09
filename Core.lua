-- Mostra o que o treinador da sua classe tem pra você agora e nos próximos níveis,
-- usando a lista do Wowhead (Data.lua). O jogo diz o que você já aprendeu.
local ADDON, ns = ...
local L = ns.L -- textos no idioma do jogo (Locales/*.lua)
local PREFIX = "|cff33ff99" .. L.NAME .. ":|r "
local ICON = "Interface\\Icons\\INV_Misc_Book_09"

local function say(msg) print(PREFIX .. msg) end

-- erro dentro de comando de chat trava a caixa de texto sem mostrar nada; assim ele aparece no chat
local function safe(fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then say("|cffff4444" .. L.ERROR .. "|r " .. tostring(err)) end
end

-- funções antigas que o cliente moderno pode ter removido: usa a que existir
local coinText = (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString) or GetCoinTextureString
  or function(c) return ("%dg %ds %dc"):format(math.floor(c / 10000), math.floor(c / 100) % 100, c % 100) end
local isKnown = IsPlayerSpell or (C_SpellBook and C_SpellBook.IsSpellKnown)
  or function(id) return C_SpellBook.IsSpellInSpellBook(id) end

-- máscara do Wowhead: bit (raceID-1). Aritmética, porque bit.band só vai até 32 bits e as raças novas passam disso.
local function raceOk(mask, raceID)
  if mask == 0 then return true end
  local b = 2 ^ (raceID - 1)
  return mask % (b * 2) >= b
end

local function spellLabel(id)
  local name = C_Spell.GetSpellName(id) or L.SPELL_N:format(id)
  local sub = C_Spell.GetSpellSubtext and C_Spell.GetSpellSubtext(id)
  return (sub and sub ~= "") and (name .. " (" .. sub .. ")") or name
end

-- grimório/treinador de pet ensina o pet; só dá pra conferir no pet que está invocado
local function petKnown(id)
  if C_SpellBook and C_SpellBook.IsSpellKnown and Enum.SpellBookSpellBank then
    return C_SpellBook.IsSpellKnown(id, Enum.SpellBookSpellBank.Pet)
  end
  return IsSpellKnown and IsSpellKnown(id, true)
end

local function hasPetData()
  local _, class = UnitClass("player")
  return ns.Data[class .. "_PET"] ~= nil
end

-- devolve listas {id, lvl, cost} de "agora", "próximas" e "aprendidas", em ordem de nível
-- view: "char" (personagem) ou "pet"
local function collect(level, view)
  local _, class = UnitClass("player")
  local _, _, raceID = UnitRace("player")
  local pet = view == "pet"
  local key = pet and class .. "_PET" or class
  local data = ns.Data[key] or {}
  local fix = EAD_SkillPreviewDB.fix[key] or {} -- correções vistas no treinador
  local out = { now = {}, soon = {}, learned = {} }
  local function add(id, lvl, cost)
    local list
    if isKnown(id) or (pet and petKnown(id)) then list = out.learned
    elseif lvl <= level then list = out.now
    else list = out.soon end
    list[#list + 1] = { id = id, lvl = lvl, cost = cost }
  end
  local seen, extra = {}, false
  for i = 1, #data, 4 do
    local id, lvl, cost, mask = data[i], data[i + 1], data[i + 2], data[i + 3]
    seen[id] = true
    local f = fix[id]
    if f then add(id, f.lvl, f.cost)
    elseif f == nil and raceOk(mask, raceID) then add(id, lvl, cost) end -- false = treinador não oferece
  end
  for id, f in pairs(fix) do
    if f and not seen[id] then add(id, f.lvl, f.cost); extra = true end -- só existe no jogo
  end
  if extra then
    local byLevel = function(a, b) return a.lvl < b.lvl or (a.lvl == b.lvl and a.id < b.id) end
    for _, l in pairs(out) do table.sort(l, byLevel) end
  end
  return out
end

---------------------------------------------------------------- conferência no treinador
local function serviceSpellID(i)
  if C_TooltipInfo and C_TooltipInfo.GetTrainerService then
    local d = C_TooltipInfo.GetTrainerService(i)
    if d and d.id then return d.id end
  end
end

-- Compara o que o treinador oferece com a lista do Wowhead e guarda as diferenças em EAD_SkillPreviewDB.fix
local function checkTrainer()
  if IsTradeskillTrainer and IsTradeskillTrainer() then return end
  local _, class = UnitClass("player")
  local _, _, raceID = UnitRace("player")
  local keys = { class, class .. "_PET" }

  -- índice de tudo que já conhecemos: id -> chave da lista; e nome traduzido -> id, para quando o jogo não der o ID
  local owner, byName = {}, {}
  for _, key in ipairs(keys) do
    local data = ns.Data[key] or {}
    for i = 1, #data, 4 do
      owner[data[i]] = key
      byName[spellLabel(data[i])] = data[i]
    end
    for id in pairs(EAD_SkillPreviewDB.fix[key] or {}) do owner[id] = owner[id] or key end
  end

  local services, votes, maxLvl = {}, {}, 0
  for i = 1, GetNumTrainerServices() do
    local name, rank, kind = GetTrainerServiceInfo(i)
    if name and kind ~= "header" then
      local label = (rank and rank ~= "") and (name .. " (" .. rank .. ")") or name
      -- prefere o ID que já está na lista; o tooltip do pet pode trazer o ID da magia do pet em vez da que o caçador aprende
      local tipID = serviceSpellID(i)
      local id = (tipID and owner[tipID]) and tipID or byName[label] or tipID
      if id then
        local lvl, cost = GetTrainerServiceLevelReq(i) or 0, GetTrainerServiceCost(i) or 0
        services[#services + 1] = { id = id, lvl = lvl, cost = cost }
        if owner[id] then votes[owner[id]] = (votes[owner[id]] or 0) + 1 end
        maxLvl = math.max(maxLvl, lvl)
      end
    end
  end
  if #services == 0 then
    say(L.TRAINER_CHECKED:format(0, 0, 0, 0)) -- diagnóstico: o treinador abriu mas nada foi reconhecido
    return
  end

  -- treinador de classe ou de pet: a lista com mais magias reconhecidas
  local key = (votes[keys[2]] or 0) > (votes[keys[1]] or 0) and keys[2] or keys[1]
  local data = ns.Data[key] or {}
  local base = {}
  for i = 1, #data, 4 do base[data[i]] = { lvl = data[i + 1], cost = data[i + 2], mask = data[i + 3] } end
  EAD_SkillPreviewDB.fix[key] = EAD_SkillPreviewDB.fix[key] or {}
  local fix = EAD_SkillPreviewDB.fix[key]

  local fixed, added, removed, offered = 0, 0, 0, {}
  for _, s in ipairs(services) do
    offered[s.id] = true
    local b = base[s.id]
    if not b then
      if not fix[s.id] then added = added + 1 end
      fix[s.id] = { lvl = s.lvl, cost = s.cost }
    elseif b.lvl ~= s.lvl or b.cost ~= s.cost then
      if not fix[s.id] then fixed = fixed + 1 end
      fix[s.id] = { lvl = s.lvl, cost = s.cost }
    else
      fix[s.id] = nil -- jogo e Wowhead batem
    end
  end
  -- até o maior nível que o treinador mostrou, o que ele não oferece não é de treinador.
  -- Magias que você já sabe ficam de fora: o treinador pode esconder as aprendidas.
  for id, b in pairs(base) do
    if b.lvl <= maxLvl and not offered[id] and raceOk(b.mask, raceID) and fix[id] ~= false
      and not isKnown(id) and not petKnown(id) then
      fix[id] = false
      removed = removed + 1
    end
  end

  say(L.TRAINER_CHECKED:format(#services, fixed, added, removed))
end

-- quantas coisas dá pra comprar agora, somando personagem e pet
local function countNow(level)
  return #collect(level, "char").now + (hasPetData() and #collect(level, "pet").now or 0)
end

---------------------------------------------------------------- tema "EAD"
-- Obsidiana azulada com moldura dourada (pegada do jogo) e um destaque azul-arcano como marca.
local T = {
  bg      = { 0.035, 0.04, 0.06, 0.96 },
  barTop  = { 0.17, 0.14, 0.09, 1 },
  barBot  = { 0.07, 0.07, 0.09, 1 },
  border  = { 0.80, 0.63, 0.30, 1 },
  gold    = { 1.00, 0.82, 0.38 },
  accent  = { 0.28, 0.80, 0.90 },
  text    = { 0.93, 0.91, 0.86 },
  muted   = { 0.58, 0.58, 0.62 },
  now     = { 0.40, 0.92, 0.55 },
  soon    = { 1.00, 0.82, 0.38 },
  learned = { 0.55, 0.55, 0.60 },
}
local WHITE = "Interface\\Buttons\\WHITE8x8"

local function solid(parent, layer, r, g, b, a)
  local t = parent:CreateTexture(nil, layer)
  t:SetColorTexture(r, g, b, a or 1)
  return t
end

local function vgradient(tex, top, bottom)
  tex:SetTexture(WHITE)
  tex:SetGradient("VERTICAL", CreateColor(unpack(bottom)), CreateColor(unpack(top))) -- VERTICAL: 1º é a base
end

---------------------------------------------------------------- painel
local ROW_H = 36
local WIDTH = 362 -- largura útil da lista
local panel = CreateFrame("Frame", "EAD_SkillPreviewPanel", UIParent, "BackdropTemplate")
panel:SetSize(400, 540)
panel:SetPoint("CENTER")
panel:SetFrameStrata("HIGH")
panel:SetBackdrop({
  bgFile = WHITE,
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  edgeSize = 14,
  insets = { left = 3, right = 3, top = 3, bottom = 3 },
})
panel:SetBackdropColor(unpack(T.bg))
panel:SetBackdropBorderColor(unpack(T.border))
panel:SetMovable(true)
panel:EnableMouse(true)
panel:RegisterForDrag("LeftButton")
panel:SetScript("OnDragStart", panel.StartMoving)
panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
panel:SetClampedToScreen(true)
panel:Hide()
tinsert(UISpecialFrames, panel:GetName()) -- fecha com ESC

-- brilho arcano suave descendo do topo
local glow = panel:CreateTexture(nil, "BORDER")
glow:SetPoint("TOPLEFT", 4, -34)
glow:SetPoint("TOPRIGHT", -4, -34)
glow:SetHeight(140)
vgradient(glow, { T.accent[1], T.accent[2], T.accent[3], 0.10 }, { 0, 0, 0, 0 })

-- barra de título
local bar = CreateFrame("Frame", nil, panel)
bar:SetPoint("TOPLEFT", 4, -4)
bar:SetPoint("TOPRIGHT", -4, -4)
bar:SetHeight(30)
local barBg = bar:CreateTexture(nil, "BACKGROUND")
barBg:SetAllPoints()
vgradient(barBg, T.barTop, T.barBot)
local barLine = solid(bar, "ARTWORK", T.border[1], T.border[2], T.border[3], 0.8)
barLine:SetPoint("BOTTOMLEFT")
barLine:SetPoint("BOTTOMRIGHT")
barLine:SetHeight(1)

local logoBorder = solid(bar, "ARTWORK", T.border[1], T.border[2], T.border[3], 1)
logoBorder:SetSize(22, 22)
logoBorder:SetPoint("LEFT", 6, 0)
local logo = bar:CreateTexture(nil, "OVERLAY")
logo:SetSize(20, 20)
logo:SetPoint("CENTER", logoBorder)
logo:SetTexture(ICON)
logo:SetTexCoord(0.07, 0.93, 0.07, 0.93)

panel.title = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
panel.title:SetPoint("LEFT", logoBorder, "RIGHT", 8, 0)
panel.title:SetTextColor(unpack(T.gold))
panel.title:SetText(L.NAME)

local close = CreateFrame("Button", nil, bar, "UIPanelCloseButton")
close:SetSize(26, 26)
close:SetPoint("RIGHT", 0, 0)
close:SetScript("OnClick", function() panel:Hide() end)

-- rodapé com créditos
local footLine = solid(panel, "ARTWORK", T.border[1], T.border[2], T.border[3], 0.35)
footLine:SetPoint("BOTTOMLEFT", 10, 26)
footLine:SetPoint("BOTTOMRIGHT", -10, 26)
footLine:SetHeight(1)
local credits = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
credits:SetPoint("BOTTOM", 0, 9)
credits:SetText(L.CREDITS:format("Oleg") .. "  •  |cff" .. "47cce6" .. "assantech.com.br|r")

local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", 10, -72)
scroll:SetPoint("BOTTOMRIGHT", -22, 32)
local content = CreateFrame("Frame", nil, scroll)
content:SetSize(WIDTH, 1)
scroll:SetScrollChild(content)

-- barra de rolagem fina no tema (sem as setas cinzas do modelo padrão); a roda do mouse continua funcionando
safe(function()
  local sb = scroll.ScrollBar
  if not sb then return end
  for _, k in ipairs({ "ScrollUpButton", "ScrollDownButton" }) do
    if sb[k] then sb[k]:Hide(); sb[k]:SetAlpha(0) end
  end
  for _, region in ipairs({ sb:GetRegions() }) do
    if region:GetObjectType() == "Texture" and region ~= sb:GetThumbTexture() then region:SetAlpha(0) end
  end
  sb:ClearAllPoints()
  sb:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 6, 0)
  sb:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 6, 0)
  sb:SetWidth(5)
  local track = solid(sb, "BACKGROUND", 1, 1, 1, 0.06)
  track:SetAllPoints()
  local thumb = sb:GetThumbTexture()
  thumb:SetColorTexture(T.border[1], T.border[2], T.border[3], 0.85)
  thumb:SetSize(5, 48)
end)

local rows, headers = {}, {}

-- cabeçalho de grupo clicável: faixa colorida, [+/-] título à esquerda, valor total à direita
local function getHeader(i)
  local h = headers[i]
  if h then return h end
  h = CreateFrame("Button", nil, content)
  h:SetSize(WIDTH, 26)
  h.bg = solid(h, "BACKGROUND", 1, 1, 1, 0.05)
  h.bg:SetAllPoints()
  h.strip = solid(h, "ARTWORK", 1, 1, 1, 1)
  h.strip:SetPoint("TOPLEFT")
  h.strip:SetPoint("BOTTOMLEFT")
  h.strip:SetWidth(3)
  h.line = solid(h, "ARTWORK", 1, 1, 1, 0.35)
  h.line:SetPoint("BOTTOMLEFT")
  h.line:SetPoint("BOTTOMRIGHT")
  h.line:SetHeight(1)
  h:SetHighlightTexture(WHITE)
  h:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.05)
  h.toggle = h:CreateTexture(nil, "OVERLAY")
  h.toggle:SetSize(14, 14)
  h.toggle:SetPoint("LEFT", 10, 0)
  h.text = h:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  h.text:SetPoint("LEFT", h.toggle, "RIGHT", 6, 0)
  h.total = h:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  h.total:SetPoint("RIGHT", -8, 0)
  h:SetScript("OnClick", function(self)
    local c = EAD_SkillPreviewDB.collapsed
    c[self.kind] = not c[self.kind]
    safe(panel.Refresh)
  end)
  headers[i] = h
  return h
end

local function getRow(i)
  local r = rows[i]
  if r then return r end
  r = CreateFrame("Button", nil, content)
  r:SetSize(WIDTH, ROW_H - 2)
  r.bg = r:CreateTexture(nil, "BACKGROUND")
  r.bg:SetAllPoints()
  r:SetHighlightTexture(WHITE)
  r:GetHighlightTexture():SetVertexColor(T.accent[1], T.accent[2], T.accent[3], 0.10)
  r.iconBorder = solid(r, "BORDER", 0, 0, 0, 1)
  r.iconBorder:SetSize(30, 30)
  r.iconBorder:SetPoint("LEFT", 6, 0)
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(28, 28)
  r.icon:SetPoint("CENTER", r.iconBorder)
  r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) -- corta a borda padrão do ícone
  r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  r.name:SetPoint("TOPLEFT", r.iconBorder, "TOPRIGHT", 8, -1)
  r.name:SetPoint("RIGHT", -96, 0)
  r.name:SetJustifyH("LEFT")
  r.name:SetWordWrap(false)
  r.level = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  r.level:SetPoint("BOTTOMLEFT", r.iconBorder, "BOTTOMRIGHT", 8, 1)
  r.level:SetTextColor(unpack(T.muted))
  r.price = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.price:SetPoint("RIGHT", -8, 0)
  r:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetSpellByID(self.spellID)
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", GameTooltip_Hide)
  rows[i] = r
  return r
end

function panel:Refresh()
  local level = UnitLevel("player")
  local F = EAD_SkillPreviewDB.filters
  if not hasPetData() then EAD_SkillPreviewDB.view = "char" end
  local view = EAD_SkillPreviewDB.view
  panel.tabs:SetShown(hasPetData())
  for v, b in pairs({ char = panel.tabs.char, pet = panel.tabs.pet }) do
    local on = v == view
    b.line:SetShown(on)
    b.bg:SetColorTexture(on and T.accent[1] or 1, on and T.accent[2] or 1, on and T.accent[3] or 1, on and 0.16 or 0.04)
    b.text:SetTextColor(unpack(on and T.text or T.muted))
  end
  local lists = collect(level, view) -- não chamar de L: L são os textos traduzidos
  local now, soon, learned = lists.now, lists.soon, lists.learned
  local y, nRow, nHead = 0, 0, 0
  local collapsed = EAD_SkillPreviewDB.collapsed
  local function header(text, kind, total, color)
    nHead = nHead + 1
    local h = getHeader(nHead)
    color = color or T.muted
    h.kind = kind
    h:ClearAllPoints()
    h:SetPoint("TOPLEFT", 0, -y - 4)
    h.text:SetText(text)
    h.text:SetTextColor(unpack(color))
    h.strip:SetColorTexture(color[1], color[2], color[3], 1)
    h.line:SetColorTexture(color[1], color[2], color[3], 0.35)
    h.total:SetText(total and total > 0 and coinText(total) or "")
    h.toggle:SetShown(kind ~= nil)
    h.toggle:SetTexture(collapsed[kind] and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
    h:EnableMouse(kind ~= nil)
    h:Show()
    y = y + 32
  end
  -- kind: "now" (destaque verde), "soon" (ícone cinza), "learned" (apagado)
  local function addRows(list, kind)
    for n, e in ipairs(list) do
      nRow = nRow + 1
      local r = getRow(nRow)
      r.spellID = e.id
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", 0, -y)
      r.icon:SetTexture(C_Spell.GetSpellTexture(e.id) or 134400)
      r.icon:SetDesaturated(kind == "soon")
      r:SetAlpha(kind == "learned" and 0.55 or 1)
      r.name:SetText(spellLabel(e.id))
      r.name:SetTextColor(unpack(kind == "now" and T.text or T.muted))
      r.level:SetText(L.LEVEL:format(e.lvl))
      r.price:SetText(e.cost > 0 and coinText(e.cost) or "|cff666666—|r")
      if kind == "now" then
        r.bg:SetColorTexture(T.now[1], T.now[2], T.now[3], n % 2 == 0 and 0.10 or 0.06)
      else
        r.bg:SetColorTexture(1, 1, 1, n % 2 == 0 and 0.035 or 0.01)
      end
      r:Show()
      y = y + ROW_H
    end
  end
  local function section(list, kind, color, title, emptyNote)
    if nHead > 0 then y = y + 8 end
    local total = 0
    for _, e in ipairs(list) do total = total + e.cost end
    local text = ("%s (%d)"):format(title, #list)
    if #list == 0 and emptyNote then text = text .. " |cff999999— " .. emptyNote .. "|r" end
    header(text, kind, total, color)
    if not collapsed[kind] then addRows(list, kind) end
  end

  if F.now then section(now, "now", T.now, L.AVAILABLE, L.NO_NEED) end
  if F.soon then section(soon, "soon", T.soon, L.UPCOMING) end
  if F.learned then section(learned, "learned", T.learned, L.LEARNED) end
  if nHead == 0 then header(L.PICK_FILTER) end

  for i = nRow + 1, #rows do rows[i]:Hide() end
  for i = nHead + 1, #headers do headers[i]:Hide() end
  content:SetHeight(math.max(y, 1))
  panel.title:SetText(L.TITLE_LEVEL:format(L.NAME, level))
end

-- menu "Filtro" com checkboxes (API de menu do cliente moderno)
local filter = CreateFrame("DropdownButton", nil, panel, "WowStyle1FilterDropdownTemplate")
filter:SetPoint("TOPRIGHT", -12, -42)
filter:SetText(L.FILTER)
filter:SetupMenu(function(_, root)
  local F = EAD_SkillPreviewDB.filters
  local function opt(text, key)
    root:CreateCheckbox(text, function() return F[key] end, function()
      F[key] = not F[key]
      safe(panel.Refresh)
    end)
  end
  opt(L.LEARNED, "learned")
  opt(L.AVAILABLE, "now")
  opt(L.UPCOMING_MAX, "soon")
  root:CreateCheckbox(L.ALL, function() return F.learned and F.now and F.soon end, function()
    local v = not (F.learned and F.now and F.soon)
    F.learned, F.now, F.soon = v, v, v
    safe(panel.Refresh)
  end)
end)

-- seletor Personagem | Pet, na mesma linha do Filtro (só aparece pra classe com pet)
panel.tabs = CreateFrame("Frame", nil, panel)
panel.tabs:SetSize(190, 24)
panel.tabs:SetPoint("TOPLEFT", 12, -42)
local function tabButton(text, view, x)
  local b = CreateFrame("Button", nil, panel.tabs)
  b:SetSize(92, 24)
  b:SetPoint("LEFT", x, 0)
  b.bg = solid(b, "BACKGROUND", 1, 1, 1, 0.04)
  b.bg:SetAllPoints()
  b.line = solid(b, "ARTWORK", T.accent[1], T.accent[2], T.accent[3], 1) -- sublinhado da aba ativa
  b.line:SetPoint("BOTTOMLEFT")
  b.line:SetPoint("BOTTOMRIGHT")
  b.line:SetHeight(2)
  b:SetHighlightTexture(WHITE)
  b:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.06)
  b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.text:SetPoint("CENTER", 0, 1)
  b.text:SetText(text)
  b:SetScript("OnClick", function()
    EAD_SkillPreviewDB.view = view
    scroll:SetVerticalScroll(0)
    safe(panel.Refresh)
  end)
  return b
end
panel.tabs.char = tabButton(L.CHARACTER, "char", 0)
panel.tabs.pet = tabButton(L.PET, "pet", 96)

panel:SetScript("OnShow", function() safe(panel.Refresh) end)

local function toggle()
  if panel:IsShown() then panel:Hide() else panel:Show() end
end

---------------------------------------------------------------- botão do minimapa
local mm = CreateFrame("Button", "EAD_SkillPreviewMinimapButton", Minimap)
mm:SetSize(31, 31)
mm:SetFrameStrata("MEDIUM")
mm:SetFrameLevel(8)
mm:RegisterForClicks("LeftButtonUp")
mm:RegisterForDrag("LeftButton")
mm:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
local bg = mm:CreateTexture(nil, "BACKGROUND")
bg:SetSize(20, 20)
bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
bg:SetPoint("TOPLEFT", 7, -5)
local icon = mm:CreateTexture(nil, "ARTWORK")
icon:SetSize(17, 17)
icon:SetTexture(ICON)
icon:SetPoint("TOPLEFT", 7, -6)
local border = mm:CreateTexture(nil, "OVERLAY")
border:SetSize(53, 53)
border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
border:SetPoint("TOPLEFT")

local function placeButton()
  local a = math.rad(EAD_SkillPreviewDB.angle)
  local r = Minimap:GetWidth() / 2 + 5
  mm:ClearAllPoints()
  mm:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

mm:SetScript("OnClick", toggle)
mm:SetScript("OnDragStart", function(self)
  self:SetScript("OnUpdate", function()
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local s = Minimap:GetEffectiveScale()
    EAD_SkillPreviewDB.angle = math.deg(math.atan2(cy / s - my, cx / s - mx))
    placeButton()
  end)
end)
mm:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
mm:SetScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_LEFT")
  GameTooltip:AddLine(L.NAME)
  local n = countNow(UnitLevel("player"))
  GameTooltip:AddLine(n > 0 and ("|cff00ff00" .. L.TT_NOW:format(n) .. "|r") or L.TT_NOTHING, 1, 1, 1)
  GameTooltip:AddLine(L.TT_HINT, 0.6, 0.6, 0.6)
  GameTooltip:Show()
end)
mm:SetScript("OnLeave", GameTooltip_Hide)

---------------------------------------------------------------- eventos
local function announce(level)
  local n = countNow(level)
  if n > 0 then
    say("|cff00ff00" .. L.ANNOUNCE:format(n) .. "|r " .. L.ANNOUNCE_HINT:format("/ead"))
  end
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_LEVEL_UP")
f:RegisterEvent("SPELLS_CHANGED")
f:RegisterUnitEvent("UNIT_PET", "player")
f:RegisterEvent("TRAINER_SHOW")
f:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" and arg1 == ADDON then
    EAD_SkillPreviewDB = EAD_SkillPreviewDB or {}
    EAD_SkillPreviewDB.angle = EAD_SkillPreviewDB.angle or 210
    EAD_SkillPreviewDB.filters = EAD_SkillPreviewDB.filters or { now = true, soon = true, learned = false, pet = true }
    EAD_SkillPreviewDB.collapsed = EAD_SkillPreviewDB.collapsed or {}
    EAD_SkillPreviewDB.view = EAD_SkillPreviewDB.view or "char"
    EAD_SkillPreviewDB.fix = EAD_SkillPreviewDB.fix or {}
    placeButton()
  elseif event == "TRAINER_SHOW" then
    -- mostra também indisponíveis e já aprendidas, senão o treinador esconde parte da lista
    safe(function()
      if SetTrainerServiceTypeFilter then
        for _, t in ipairs({ "available", "unavailable", "used" }) do SetTrainerServiceTypeFilter(t, 1) end
      end
      if ExpandTrainerSkillLine then ExpandTrainerSkillLine(0) end
    end)
    C_Timer.After(0.5, function()
      safe(checkTrainer)
      if panel:IsShown() then safe(panel.Refresh) end
    end)
  elseif event == "PLAYER_LEVEL_UP" then
    safe(announce, arg1) -- arg1 é o nível novo; UnitLevel ainda pode estar no antigo
  elseif event == "PLAYER_LOGIN" then
    C_Timer.After(3, function() safe(announce, UnitLevel("player")) end) -- espera o grimório carregar
  elseif (event == "SPELLS_CHANGED" or event == "UNIT_PET") and panel:IsShown() then
    safe(panel.Refresh) -- aprendeu algo ou trocou de pet com o painel aberto
  end
end)

SLASH_EADSKILLPREVIEW1 = "/ead"
SlashCmdList.EADSKILLPREVIEW = function() safe(toggle) end
