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

-- chave do personagem para o que é por personagem (o resto é compartilhado por classe)
local function charKey()
  local key = UnitName("player") .. "-" .. GetRealmName()
  EAD_SkillPreviewDB.learned[key] = EAD_SkillPreviewDB.learned[key] or {}
  return key
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
  local learnedHere = EAD_SkillPreviewDB.learned[charKey()] -- o que o treinador mostrou como aprendido
  local out = { now = {}, soon = {}, learned = {} }
  local function add(id, lvl, cost)
    local list
    if isKnown(id) or (pet and petKnown(id)) or learnedHere[id] then list = out.learned
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
  -- Caçador: comprar no treinador de pet não ensina o pet; isso é feito depois no Treinamento de Feras.
  -- O grau mais alto comprado de cada habilidade que o pet invocado ainda não sabe volta para "agora", com aviso.
  local petSpell = EAD_SkillPreviewDB.petSpell
  if pet and class == "HUNTER" and UnitExists("pet") then
    local top = {}
    for _, e in ipairs(out.learned) do
      local n = C_Spell.GetSpellName(e.id) or e.id
      if not top[n] or e.lvl > top[n].lvl then top[n] = e end
    end
    local keep = {}
    for _, e in ipairs(out.learned) do
      local p = petSpell[e.id] -- magia equivalente no livro do pet (vista no tooltip do treinador)
      if top[C_Spell.GetSpellName(e.id) or e.id] == e and p and not petKnown(p) then
        e.teach, e.cost = true, 0
        table.insert(out.now, e)
        extra = true
      else
        keep[#keep + 1] = e
      end
    end
    out.learned = keep
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
-- silent: relê sem escrever no chat (usado a cada mudança na janela, como uma compra)
local function checkTrainer(silent)
  if IsTradeskillTrainer and IsTradeskillTrainer() then return end
  local _, class = UnitClass("player")
  local _, _, raceID = UnitRace("player")
  local keys = { class, class .. "_PET" }

  -- índices por lista. O jogo nem sempre devolve o mesmo ID que o Wowhead, nem tem o texto do grau carregado,
  -- então a magia do treinador é procurada por: nome+grau, nome+nível, nome+nº do grau (só pets) e, por fim, ID.
  local owner, ownerByName, idx = {}, {}, {}
  for _, key in ipairs(keys) do
    local ix = { label = {}, lvl = {}, ord = {} }
    idx[key] = ix
    local data, count = ns.Data[key] or {}, {}
    for i = 1, #data, 4 do
      local id, lvl = data[i], data[i + 1]
      owner[id] = key
      ix.label[spellLabel(id)] = id
      local n = C_Spell.GetSpellName(id)
      if n then
        ownerByName[n] = ownerByName[n] or key
        ix.lvl[n .. "@" .. lvl] = ix.lvl[n .. "@" .. lvl] or id
        -- Data.lua vem em ordem de nível: 1ª ocorrência = grau 1 (ou o grau de FirstRank), e assim por diante
        count[n] = ns.FirstRank[id] or ((count[n] or 0) + 1)
        ix.ord[n .. "#" .. count[n]] = id
      end
    end
  end

  local function match(key, s)
    local ix = idx[key]
    local rn = s.rank and tonumber(s.rank:match("%d+"))
    -- nº do grau só nos pets: nas classes o grau 1 de nível 1 não está na lista, e a contagem sairia deslocada
    return ix.label[s.label]
      or (s.lvl > 0 and ix.lvl[s.name .. "@" .. s.lvl])
      or (rn and key:find("_PET$") and ix.ord[s.name .. "#" .. rn])
      or (s.tipID and owner[s.tipID] == key and s.tipID)
      or s.tipID
  end

  local function readServices()
    local list = {}
    for i = 1, GetNumTrainerServices() do
      local name, a, b = GetTrainerServiceInfo(i)
      -- Classic: nome, grau, situação. Forever: nome, situação, ícone (sem o grau).
      local rank, kind
      if a == "available" or a == "unavailable" or a == "used" or a == "header" then kind = a
      else rank, kind = a, b end
      local tipID = serviceSpellID(i)
      if (not rank or rank == "") and tipID and C_Spell.GetSpellSubtext then rank = C_Spell.GetSpellSubtext(tipID) end
      if name and kind ~= "header" then
        list[#list + 1] = {
          name = name,
          rank = rank,
          label = (rank and rank ~= "") and (name .. " (" .. rank .. ")") or name,
          tipID = tipID,
          used = kind == "used",
          lvl = GetTrainerServiceLevelReq(i) or 0,
          cost = GetTrainerServiceCost(i) or 0,
        }
      end
    end
    return list
  end

  local learnedHere = EAD_SkillPreviewDB.learned[charKey()]

  -- Treinamento de Bestas (caçador ensinando o pet): usa a mesma janela de treinador, mas sem NPC e com custo em
  -- pontos de treinamento. Não é treinador; só serve para saber o que o caçador já comprou.
  local petSpell = EAD_SkillPreviewDB.petSpell
  if not UnitExists("npc") or UnitIsUnit("npc", "pet") then
    for _, s in ipairs(readServices()) do
      local id = match(keys[2], s)
      if id and owner[id] == keys[2] then
        learnedHere[id] = true
        if s.tipID and s.tipID ~= id then petSpell[id] = s.tipID end
      end
    end
    return
  end

  -- 1ª passada: lê o treinador e vota se ele é de classe ou de pet, pelo nome da magia (mais confiável que o ID)
  local raw, votes, maxLvl = readServices(), {}, 0
  for _, s in ipairs(raw) do
    local who = ownerByName[s.name] or (s.tipID and owner[s.tipID])
    if who then votes[who] = (votes[who] or 0) + 1 end
    maxLvl = math.max(maxLvl, s.lvl)
  end
  local key
  if (votes[keys[2]] or 0) > (votes[keys[1]] or 0) then key = keys[2]
  elseif (votes[keys[1]] or 0) > 0 then key = keys[1] end
  if not key then
    -- nada reconhecido: melhor não gravar nada do que jogar magias na lista errada
    if not silent then say(L.TRAINER_CHECKED:format(#raw, 0, 0, 0)) end
    return
  end

  local data = ns.Data[key] or {}
  local base = {}
  for i = 1, #data, 4 do base[data[i]] = { lvl = data[i + 1], cost = data[i + 2], mask = data[i + 3] } end
  EAD_SkillPreviewDB.fix[key] = EAD_SkillPreviewDB.fix[key] or {}
  local fix = EAD_SkillPreviewDB.fix[key]

  -- 2ª passada: acha cada magia na lista escolhida e compara
  local fixed, added, removed, offered = 0, 0, 0, {}
  for _, s in ipairs(raw) do
    local id = match(key, s)
    if id then
      offered[id] = true
      -- treinador de pet: o tooltip traz a magia do livro do pet, usada para saber se o pet já aprendeu
      if key == keys[2] and s.tipID and s.tipID ~= id then petSpell[id] = s.tipID end
      local b = base[id]
      if s.used then
        learnedHere[id] = true -- já aprendida: o treinador mostra nível 0, então não serve para corrigir nível/preço
      elseif not b then
        if not fix[id] then added = added + 1 end
        fix[id] = { lvl = s.lvl, cost = s.cost }
      elseif b.lvl ~= s.lvl or b.cost ~= s.cost then
        if not fix[id] then fixed = fixed + 1 end
        fix[id] = { lvl = s.lvl, cost = s.cost }
      else
        fix[id] = nil -- jogo e Wowhead batem
      end
    end
  end
  -- até o maior nível que o treinador mostrou, o que ele não oferece não é de treinador.
  -- Magias que você já sabe ficam de fora: o treinador pode esconder as aprendidas.
  for id, b in pairs(base) do
    if b.lvl <= maxLvl and not offered[id] and raceOk(b.mask, raceID) and fix[id] ~= false
      and not isKnown(id) and not petKnown(id) and not learnedHere[id] then
      fix[id] = false
      removed = removed + 1
    end
  end

  if not silent then say(L.TRAINER_CHECKED:format(#raw, fixed, added, removed)) end
end

-- quantas coisas dá pra comprar agora, somando personagem e pet
local function countNow(level)
  local n = #collect(level, "char").now
  if hasPetData() then
    for _, e in ipairs(collect(level, "pet").now) do
      if not e.teach then n = n + 1 end -- "ensinar ao pet" não é compra no treinador
    end
  end
  return n
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
  teach   = { 1.00, 0.60, 0.25 }, -- caçador comprou, pet ainda não aprendeu
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
panel:SetSize(400, 570)
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
scroll:SetPoint("TOPLEFT", 10, -102)

-- busca em tempo real, logo abaixo das abas
panel.search = CreateFrame("EditBox", nil, panel, "SearchBoxTemplate")
panel.search:SetPoint("TOPLEFT", 18, -72)
panel.search:SetPoint("TOPRIGHT", -14, -72)
panel.search:SetHeight(22)
panel.search:SetAutoFocus(false)
if panel.search.Instructions then panel.search.Instructions:SetText(L.SEARCH) end
panel.search:HookScript("OnTextChanged", function()
  scroll:SetVerticalScroll(0)
  safe(panel.Refresh)
end)
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
  r.level:SetPoint("RIGHT", -60, 0) -- o aviso de pet é longo: corta com "..." antes do preço
  r.level:SetJustifyH("LEFT")
  r.level:SetWordWrap(false)
  r.level:SetTextColor(unpack(T.muted))
  r.price = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.price:SetPoint("RIGHT", -8, 0)
  r:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetSpellByID(self.spellID)
    if self.teach then
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine(L.TEACH_PET_HINT, T.teach[1], T.teach[2], T.teach[3], true)
    end
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
  -- busca: mantém só as habilidades cujo nome contém o texto digitado (sem diferenciar maiúsculas)
  local q = panel.search and panel.search:GetText():lower() or ""
  if q ~= "" then
    for k, list in pairs(lists) do
      local keep = {}
      for _, e in ipairs(list) do
        if spellLabel(e.id):lower():find(q, 1, true) then keep[#keep + 1] = e end
      end
      lists[k] = keep
    end
  end
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
      r.spellID, r.teach = e.id, e.teach
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", 0, -y)
      r.icon:SetTexture(C_Spell.GetSpellTexture(e.id) or 134400)
      r.icon:SetDesaturated(kind == "soon")
      r:SetAlpha(kind == "learned" and 0.55 or 1)
      r.name:SetText(spellLabel(e.id))
      r.name:SetTextColor(unpack(kind == "now" and T.text or T.muted))
      if e.teach then
        r.level:SetText(L.TEACH_PET)
        r.level:SetTextColor(unpack(T.teach))
      else
        r.level:SetText(L.LEVEL:format(e.lvl))
        r.level:SetTextColor(unpack(T.muted))
      end
      r.price:SetText(e.cost > 0 and coinText(e.cost) or "|cff666666—|r")
      if e.teach then
        r.bg:SetColorTexture(T.teach[1], T.teach[2], T.teach[3], n % 2 == 0 and 0.12 or 0.08)
      elseif kind == "now" then
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

local trainerPending = false
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_LEVEL_UP")
f:RegisterEvent("SPELLS_CHANGED")
f:RegisterUnitEvent("UNIT_PET", "player")
f:RegisterEvent("TRAINER_SHOW")
f:RegisterEvent("TRAINER_UPDATE")
f:RegisterEvent("PET_BAR_UPDATE")
f:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" and arg1 == ADDON then
    EAD_SkillPreviewDB = EAD_SkillPreviewDB or {}
    EAD_SkillPreviewDB.angle = EAD_SkillPreviewDB.angle or 210
    EAD_SkillPreviewDB.filters = EAD_SkillPreviewDB.filters or { now = true, soon = true, learned = false, pet = true }
    EAD_SkillPreviewDB.collapsed = EAD_SkillPreviewDB.collapsed or {}
    EAD_SkillPreviewDB.view = EAD_SkillPreviewDB.view or "char"
    EAD_SkillPreviewDB.fix = EAD_SkillPreviewDB.fix or {}
    EAD_SkillPreviewDB.learned = EAD_SkillPreviewDB.learned or {}
    EAD_SkillPreviewDB.petSpell = EAD_SkillPreviewDB.petSpell or {} -- magia do caçador -> magia no livro do pet
    -- v2: magias do treinador de pet gravadas na lista do personagem; v3: Treinamento de Bestas lido como
    -- treinador (pontos de treinamento virando cobre); v4: magias de pet não associadas; v5: situação lida na posição errada (tudo virava aprendido). Descarta as correções e reconfere no próximo treinador.
    if (EAD_SkillPreviewDB.fixVersion or 1) < 5 then
      EAD_SkillPreviewDB.fix = {}
      EAD_SkillPreviewDB.learned = {}
      EAD_SkillPreviewDB.fixVersion = 5
    end
    -- v6: graus do Rosnar contados a partir do 1 (o Grau 2 virava o Grau 4); só as marcações de aprendido estavam erradas
    if EAD_SkillPreviewDB.fixVersion < 6 then
      EAD_SkillPreviewDB.learned = {}
      EAD_SkillPreviewDB.fixVersion = 6
    end
    placeButton()
  elseif event == "TRAINER_SHOW" then
    -- mostra também indisponíveis e já aprendidas, senão o treinador esconde parte da lista
    safe(function()
      if SetTrainerServiceTypeFilter then
        -- o Forever pede verdadeiro/falso; versões antigas aceitavam 1
        for _, t in ipairs({ "available", "unavailable", "used" }) do
          if not pcall(SetTrainerServiceTypeFilter, t, true) then pcall(SetTrainerServiceTypeFilter, t, 1) end
        end
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
  elseif event == "TRAINER_UPDATE" and not trainerPending then
    -- comprou no treinador ou ensinou o pet no Treinamento de Feras: relê em silêncio e atualiza.
    -- A janela dispara vários avisos seguidos; junta tudo numa leitura só.
    trainerPending = true
    C_Timer.After(0.3, function()
      trainerPending = false
      safe(checkTrainer, true)
      if panel:IsShown() then safe(panel.Refresh) end
    end)
  elseif (event == "SPELLS_CHANGED" or event == "UNIT_PET" or event == "PET_BAR_UPDATE") and panel:IsShown() then
    safe(panel.Refresh) -- aprendeu algo, trocou de pet ou o pet aprendeu algo com o painel aberto
  end
end)

SLASH_EADSKILLPREVIEW1 = "/ead"
-- /ead debug: com um treinador aberto, mostra no chat o que o jogo devolve de cada serviço (para diagnosticar o Forever)
local function debugTrainer()
  local n = GetNumTrainerServices and GetNumTrainerServices() or 0
  say(("debug: %d serviço(s), npc=%s"):format(n, tostring(UnitExists("npc"))))
  local kinds = {}
  for i = 1, n do
    local name, rank, kind = GetTrainerServiceInfo(i) -- no Forever: nome, situação, ícone
    kinds[tostring(kind)] = (kinds[tostring(kind)] or 0) + 1
    if i <= 8 then
      print(("  %d) %s | %s | kind=%s | lvl=%s | custo=%s | id=%s"):format(i, tostring(name), tostring(rank),
        tostring(kind), tostring(GetTrainerServiceLevelReq(i)), tostring((GetTrainerServiceCost(i))),
        tostring(serviceSpellID(i))))
    end
  end
  for k, v in pairs(kinds) do print(("  kind %s: %d"):format(k, v)) end
end

SlashCmdList.EADSKILLPREVIEW = function(msg)
  if msg == "debug" then safe(debugTrainer) else safe(toggle) end
end
