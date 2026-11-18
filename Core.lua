-- Mostra o que o treinador da sua classe tem pra você agora e nos próximos níveis,
-- usando a lista do Wowhead (Data.lua). O jogo diz o que você já aprendeu.
local ADDON, ns = ...
local L = ns.L -- textos no idioma do jogo (Locales/*.lua)
local PREFIX = "|cff33ff99" .. L.NAME .. ":|r "
local ICON = "Interface\\AddOns\\EAD_SkillPreview\\Art\\Icon"

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

-- nomes de todas as magias que o personagem conhece (grimório); vazio se a API não existir
local function knownSpellNames()
  local names = {}
  if not (C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and Enum.SpellBookSpellBank) then return names end
  local bank = Enum.SpellBookSpellBank.Player
  local future = Enum.SpellBookItemType and Enum.SpellBookItemType.FutureSpell
  for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
    local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
    if info then
      for slot = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
        local item = C_SpellBook.GetSpellBookItemInfo(slot, bank)
        if item and item.name and item.itemType ~= future then names[item.name] = true end
      end
    end
  end
  return names
end

-- chave do personagem para o que é por personagem (o resto é compartilhado por classe)
local function charKey()
  local key = UnitName("player") .. "-" .. GetRealmName()
  EAD_SkillPreviewDB.learned[key] = EAD_SkillPreviewDB.learned[key] or {}
  return key
end

---------------------------------------------------------------- profissões
-- Perícia atual numa profissão (nil se o personagem não a tem). O Forever mistura cliente moderno com conteúdo
-- clássico, então tenta as três formas que o jogo já teve de informar isso.
local function profSkill(prof)
  local T = C_TradeSkillUI
  if T and T.GetProfessionInfoBySkillLineID then
    local p = T.GetProfessionInfoBySkillLineID(prof)
    if p and (p.maxSkillLevel or 0) > 0 then return p.skillLevel end
  end
  if GetProfessions and GetProfessionInfo then
    for n = 1, select("#", GetProfessions()) do
      local i = select(n, GetProfessions())
      if i then
        local _, _, rank, _, _, _, line = GetProfessionInfo(i)
        if line == prof then return rank end
      end
    end
  end
  if GetNumSkillLines and GetSkillLineInfo then
    -- shortcut: compara pelo nome da magia de Aprendiz; falha se o jogo der à perícia um nome diferente do da magia
    local name = C_Spell.GetSpellName(ns.ProfSpell[prof])
    for i = 1, GetNumSkillLines() do
      local n, header, _, rank = GetSkillLineInfo(i)
      if not header and n == name then return rank end
    end
  end
end

-- profissões que o personagem tem, em ordem fixa (IDs da linha de perícia)
local function playerProfs()
  local list = {}
  for prof in pairs(ns.Prof) do
    if profSkill(prof) then list[#list + 1] = prof end
  end
  table.sort(list)
  return list
end

local function recipeKnown(id, learnedHere)
  if isKnown(id) or learnedHere[id] then return true end
  if C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo then
    local ok, r = pcall(C_TradeSkillUI.GetRecipeInfo, id)
    return ok and r and r.learned or false
  end
  return false
end

-- Janela de profissão aberta (API clássica): anota as receitas que ela lista, para quando o jogo não
-- responde por IsPlayerSpell para receitas.
local function scanRecipes()
  local learnedHere = EAD_SkillPreviewDB.learned[charKey()]
  local function scan(count, link)
    if not (count and link) then return end
    for i = 1, count() do
      local l = link(i)
      local id = l and tonumber(l:match("enchant:(%d+)"))
      if id then learnedHere[id] = true end
    end
  end
  scan(GetNumTradeSkills, GetTradeSkillRecipeLink)
  scan(GetNumCrafts, GetCraftRecipeLink)
end

-- mesmas listas de collect(), para uma profissão; lvl é a perícia exigida e src a origem (ver Professions.lua)
local function collectProf(prof)
  local skill = profSkill(prof) or 0
  local data = ns.Prof[prof] or {}
  local fix = EAD_SkillPreviewDB.fix[prof] or {} -- vistas no treinador: valem como receita de treinador
  local confirmed = EAD_SkillPreviewDB.seen[prof] or {}
  local learnedHere = EAD_SkillPreviewDB.learned[charKey()]
  local trainerOnly = EAD_SkillPreviewDB.filters.trainerOnly
  -- desconto de reputação deste personagem, em %, visto no treinador da profissão (o arquivo guarda o preço cheio)
  local pct = (EAD_SkillPreviewDB.discount[charKey()] or {})[prof] or 100
  local out = { now = {}, soon = {}, learned = {} }
  local function add(id, lvl, cost, src, item, icon)
    if trainerOnly and src ~= 6 then return end
    local list = recipeKnown(id, learnedHere) and out.learned or (lvl <= skill and out.now or out.soon)
    list[#list + 1] = { id = id, lvl = lvl, cost = math.floor(cost * pct / 100), src = src, item = item, icon = icon,
      checked = fix[id] ~= nil or confirmed[id] == true }
  end
  local seen = {}
  for i = 1, #data, 5 do
    local id = data[i]
    local f = fix[id]
    seen[id] = true
    if f then add(id, f.lvl, f.cost, 6, data[i + 4])
    else add(id, data[i + 1], data[i + 2], data[i + 3], data[i + 4]) end
  end
  for id, f in pairs(fix) do
    if not seen[id] then add(id, f.lvl, f.cost, 6, nil, f.icon) end -- só existe no jogo
  end
  local bySkill = function(a, b) return a.lvl < b.lvl or (a.lvl == b.lvl and a.id < b.id) end
  for _, l in pairs(out) do table.sort(l, bySkill) end
  return out
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
  local confirmed = EAD_SkillPreviewDB.seen[key] or {} -- preços que já batiam no treinador
  local learnedHere = EAD_SkillPreviewDB.learned[charKey()] -- o que o treinador mostrou como aprendido
  local out = { now = {}, soon = {}, learned = {} }
  local function add(id, lvl, cost)
    local list
    if isKnown(id) or (pet and petKnown(id)) or learnedHere[id] then list = out.learned
    elseif lvl <= level then list = out.now
    else list = out.soon end
    -- checked: preço confirmado num treinador (corrigido ou igual ao do Wowhead); senão é estimativa
    list[#list + 1] = { id = id, lvl = lvl, cost = cost, checked = fix[id] ~= nil or confirmed[id] == true }
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

  -- Habilidades de talento: o grau 1 vem do talento e o treinador só vende os graus seguintes (lista em Data.lua).
  -- Se o personagem não conhece nenhuma magia com esse nome, o talento não foi escolhido: marca, tira do total
  -- e joga para o fim de "agora".
  local known = not pet and knownSpellNames()
  if known and next(known) then
    for _, k in ipairs({ "now", "soon" }) do
      local normal, locked = {}, {}
      for _, e in ipairs(out[k]) do
        local n = C_Spell.GetSpellName(e.id)
        if ns.TalentRanks[e.id] and n and not known[n] then
          e.talent = true
          table.insert(locked, e)
        else
          table.insert(normal, e)
        end
      end
      if k == "now" then for _, e in ipairs(locked) do table.insert(normal, e) end; out[k] = normal end
    end
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
        index = i,
        name = name,
        rank = rank,
        label = (rank and rank ~= "") and (name .. " (" .. rank .. ")") or name,
        tipID = tipID,
        used = kind == "used",
        icon = kind == a and b or nil, -- só no formato do Forever
        lvl = GetTrainerServiceLevelReq(i) or 0,
        cost = GetTrainerServiceCost(i) or 0,
      }
    end
  end
  return list
end

-- Treinador de profissão: corrige perícia e preço das receitas e anota as já aprendidas. Não remove nada:
-- cada treinador só ensina até um grau, e o que ele não oferece pode vir de outro treinador, vendedor ou drop.
local function checkProfTrainer(silent)
  -- /ead scan: cópia bruta do que o treinador devolve, por NPC, para regerar Professions.lua fora do jogo
  -- (fica nas SavedVariables depois de um /reload). reaction: 5 amistoso ... 8 exaltado.
  if EAD_SkillPreviewDB.scanOn then
    local npc = UnitName("npc") or "?"
    local dump = { reaction = UnitReaction("npc", "player") }
    for i = 1, GetNumTrainerServices() do
      dump[i] = {
        info = { GetTrainerServiceInfo(i) },
        id = serviceSpellID(i),
        cost = (GetTrainerServiceCost(i)),
        lvl = GetTrainerServiceLevelReq(i),
        skill = GetTrainerServiceSkillReq and { GetTrainerServiceSkillReq(i) } or nil,
        icon = GetTrainerServiceIcon and GetTrainerServiceIcon(i) or nil,
        item = GetTrainerServiceItemLink and GetTrainerServiceItemLink(i) or nil,
      }
    end
    EAD_SkillPreviewDB.scan[npc] = dump
    if not silent then say(("scan: %d serviço(s) de %s gravado(s)."):format(#dump, npc)) end
  end

  local base, byLabel = {}, {}
  for prof, data in pairs(ns.Prof) do
    for i = 1, #data, 5 do
      local id = data[i]
      base[id] = { prof = prof, lvl = data[i + 1], cost = data[i + 2], src = data[i + 3] }
      local label = spellLabel(id)
      byLabel[label] = byLabel[label] or id
    end
  end
  -- a profissão do treinador é a da maioria das receitas reconhecidas
  local raw, ids, votes = readServices(), {}, {}
  for k, s in ipairs(raw) do
    local id = (s.tipID and base[s.tipID] and s.tipID) or byLabel[s.label] or s.tipID
    ids[k] = id
    local b = id and base[id]
    if b then votes[b.prof] = (votes[b.prof] or 0) + 1 end
  end
  local prof, best = nil, 0
  for p, v in pairs(votes) do
    if v > best then prof, best = p, v end
  end
  if not prof then
    if not silent then say(L.TRAINER_CHECKED:format(#raw, 0, 0, 0)) end
    return
  end
  local DB = EAD_SkillPreviewDB
  DB.fix[prof] = DB.fix[prof] or {}
  DB.seen[prof] = DB.seen[prof] or {}
  local key = charKey()
  local fix, seen, learnedHere = DB.fix[prof], DB.seen[prof], DB.learned[key]
  -- Desconto de reputação: o jogo cobra o preço cheio vezes 95/90/85/80%, arredondado para baixo. A razão sai da
  -- receita mais cara reconhecida (menos erro de arredondamento) e vale para as que este treinador não mostra.
  local pct, top = 100, 0
  for k, s in ipairs(raw) do
    local b = ids[k] and base[ids[k]]
    if b and b.prof == prof and b.src == 6 and b.cost > top and not s.used then
      top, pct = b.cost, math.floor(s.cost / b.cost * 20 + 0.5) * 5
    end
  end
  if pct < 50 or pct > 100 then pct = 100 end -- razão absurda: o preço do arquivo é que está errado
  DB.discount[key] = DB.discount[key] or {}
  DB.discount[key][prof] = pct
  local fixed, added = 0, 0
  for k, s in ipairs(raw) do
    local id = ids[k]
    local b = id and base[id]
    if id and (not b or b.prof == prof) then
      local _, req
      if GetTrainerServiceSkillReq then _, req = GetTrainerServiceSkillReq(s.index) end
      req = tonumber(req) or 0
      if req <= 0 then req = b and b.lvl or 1 end -- o jogo não informou: mantém a perícia do Wowhead
      local full = math.ceil(s.cost * 100 / pct) -- preço cheio que, com o desconto, dá exatamente o cobrado
      if s.used then
        learnedHere[id] = true
      elseif not b then
        if not fix[id] then added = added + 1 end
        fix[id] = { lvl = req, cost = full, icon = s.icon }
      elseif b.src ~= 6 or b.lvl ~= req or math.floor(b.cost * pct / 100) ~= s.cost then
        if not fix[id] then fixed = fixed + 1 end
        fix[id] = { lvl = req, cost = full }
      else
        fix[id] = nil
        seen[id] = true
      end
    end
  end
  if not silent then say(L.TRAINER_CHECKED:format(#raw, fixed, added, 0)) end
end

-- Compara o que o treinador oferece com a lista do Wowhead e guarda as diferenças em EAD_SkillPreviewDB.fix
-- silent: relê sem escrever no chat (usado a cada mudança na janela, como uma compra)
local function checkTrainer(silent)
  if IsTradeskillTrainer and IsTradeskillTrainer() then return checkProfTrainer(silent) end
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
  EAD_SkillPreviewDB.seen[key] = EAD_SkillPreviewDB.seen[key] or {}
  local seen = EAD_SkillPreviewDB.seen[key]

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
        seen[id] = true -- preço conferido no treinador
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
  local n = 0
  for _, e in ipairs(collect(level, "char").now) do
    if not e.talent then n = n + 1 end -- talento não escolhido não conta
  end
  if hasPetData() then
    for _, e in ipairs(collect(level, "pet").now) do
      if not e.teach then n = n + 1 end -- "ensinar ao pet" não é compra no treinador
    end
  end
  return n
end

---------------------------------------------------------------- temas
-- Cores fixas (significado das linhas) e a cor de destaque, que vem do tema.
local T = {
  accent  = { 0.28, 0.80, 0.90 },
  text    = { 0.93, 0.91, 0.86 },
  muted   = { 0.58, 0.58, 0.62 },
  now     = { 0.40, 0.92, 0.55 },
  soon    = { 1.00, 0.82, 0.38 },
  learned = { 0.55, 0.55, 0.60 },
  teach   = { 1.00, 0.60, 0.25 }, -- caçador comprou, pet ainda não aprendeu
  talent  = { 0.66, 0.55, 0.85 }, -- depende de um talento que não foi escolhido
}
local WHITE = "Interface\\Buttons\\WHITE8x8"

-- Um tema por classe: a arte pintada da janela inteira e a cor de destaque da classe.
-- Art/<art>.tga sai de art-src/ com tools/make_art.py.
-- `list` é o miolo escuro do quadro de conteúdo, medido em cada arte: x0, y0, x1, y1 em % da imagem.
-- `foot` é o centro da faixa livre do rodapé, entre os enfeites dos cantos: x, y em % da imagem.
-- `title` é a placa do título: centro x, y e meia largura do miolo, em % da imagem.
-- As outras peças (título, abas, filtro, busca, fechar) ficam no mesmo lugar em todas.
local THEMES = {
  WARRIOR = { art = "Warrior", accent = { 0.78, 0.61, 0.43 }, list = { 13.4, 29.5, 86.4, 83.5 }, foot = { 46, 91.7 }, title = { 49.5, 9.25, 20 } }, -- base curta: escudo no canto
  PALADIN = { art = "Paladin", accent = { 0.96, 0.55, 0.73 }, list = { 13.0, 29.2, 87.3, 83.5 }, foot = { 50, 90.6 }, title = { 51, 9.85, 26 } }, -- base curta: livro e escudo; à esquerda, o estandarte
  HUNTER  = { art = "Hunter",  accent = { 0.67, 0.83, 0.45 }, list = { 17.4, 32.3, 82.4, 87.5 }, foot = { 50.8, 91.5 }, title = { 50.4, 9.4, 27 } },
  ROGUE   = { art = "Rogue",   accent = { 1.00, 0.96, 0.41 }, list = { 15.6, 28.2, 84.2, 85.3 }, foot = { 50, 90.9 }, title = { 51.2, 9.4, 26 } },
  PRIEST  = { art = "Priest",  accent = { 0.92, 0.92, 0.96 }, list = { 19.6, 30.0, 80.1, 86.0 }, foot = { 50, 91.9 }, title = { 51, 9.0, 26 } },
  SHAMAN  = { art = "Shaman",  accent = { 0.30, 0.62, 1.00 }, list = { 19.9, 30.2, 79.9, 84.5 }, foot = { 50.4, 91.0 }, title = { 50.2, 8.9, 20 } }, -- azul da classe clareado para leitura
  MAGE    = { art = "Mage",    accent = { 0.41, 0.80, 0.94 }, list = { 17.2, 29.3, 82.8, 87.0 }, foot = { 48, 91.4 }, title = { 50.6, 9.0, 27 } },
  WARLOCK = { art = "Warlock", accent = { 0.58, 0.51, 0.79 }, list = { 16.1, 29.2, 83.7, 85.5 }, foot = { 49, 90.5 }, title = { 50.4, 9.6, 27 } },
  DRUID   = { art = "Druid",   accent = { 1.00, 0.49, 0.04 }, list = { 16.7, 30.2, 83.0, 85.2 }, foot = { 46, 91.7 }, title = { 52.7, 9.75, 24 } },
}
local ART = "Interface\\AddOns\\EAD_SkillPreview\\Art\\"

-- Tema do personagem: o que ele escolheu ou, sem escolha, o da própria classe.
local function themeKey()
  local _, class = UnitClass("player")
  local saved = EAD_SkillPreviewDB and EAD_SkillPreviewDB.themes and EAD_SkillPreviewDB.themes[charKey()]
  return THEMES[saved] and saved or (THEMES[class] and class) or "WARRIOR"
end

local function solid(parent, layer, r, g, b, a)
  local t = parent:CreateTexture(nil, layer)
  t:SetColorTexture(r, g, b, a or 1)
  return t
end

---------------------------------------------------------------- painel
local ROW_H = 36
local WIDTH = 330 -- largura útil da lista; cada tema ajusta (applyTheme)
local PW, PH = 495, 660 -- a imagem inteira, enfeites incluídos (proporção 3:4)
local panel = CreateFrame("Frame", "EAD_SkillPreviewPanel", UIParent)
panel:SetSize(PW, PH)
panel:SetPoint("CENTER")
panel:SetFrameStrata("HIGH")
panel:SetHitRectInsets(PW * 0.04, PW * 0.07, PH * 0.04, PH * 0.06) -- a margem transparente em volta não pega clique
panel:SetMovable(true)
panel:EnableMouse(true)
panel:RegisterForDrag("LeftButton")
panel:SetScript("OnDragStart", panel.StartMoving)
panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
panel:SetClampedToScreen(true)
panel:Hide()
tinsert(UISpecialFrames, panel:GetName()) -- fecha com ESC

-- Posiciona uma peça sobre a arte: retângulo em % da imagem, a partir do canto superior esquerdo.
local function place(f, x0, y0, x1, y1)
  f:ClearAllPoints()
  f:SetPoint("TOPLEFT", panel, "TOPLEFT", PW * x0 / 100, -PH * y0 / 100)
  f:SetPoint("BOTTOMRIGHT", panel, "TOPLEFT", PW * x1 / 100, -PH * y1 / 100)
end

panel.art = panel:CreateTexture(nil, "BACKGROUND")
panel.art:SetAllPoints() -- a textura 512x1024 é a imagem inteira espremida; aqui volta à proporção da janela

-- Linhas, abas, cabeçalhos e a placa dos créditos são recortes da própria arte do tema, para tudo ter a mesma pintura.
-- O "campo" é o campo de busca: pontas arredondadas + miolo esticado (a ponta direita é a esquerda espelhada, sem a lupa).
local PILL = { 10.9, 20.9, 89.1, 25.65 } -- campo de busca, no mesmo lugar nas nove artes: x0, y0, x1, y1 em %
local CAP = 5 -- largura da ponta arredondada do campo, em % da imagem
local function crop(tex, x0, y0, x1, y1)
  tex:SetTexture(ART .. THEMES[themeKey()].art)
  tex:SetTexCoord(x0 / 100, x1 / 100, y0 / 100, y1 / 100)
end
-- Três texturas que desenham um campo do tamanho de `parent` (altura `h`); `blend` "ADD" para o brilho.
local function newPill(parent, layer, h, blend)
  local p = { parent:CreateTexture(nil, layer), parent:CreateTexture(nil, layer), parent:CreateTexture(nil, layer) }
  local capW = PW * CAP / 100 * h / (PH * (PILL[4] - PILL[2]) / 100) -- ponta na proporção da altura
  p[1]:SetPoint("TOPLEFT")
  p[1]:SetPoint("BOTTOMLEFT")
  p[1]:SetWidth(capW)
  p[3]:SetPoint("TOPRIGHT")
  p[3]:SetPoint("BOTTOMRIGHT")
  p[3]:SetWidth(capW)
  p[2]:SetPoint("TOPLEFT", p[1], "TOPRIGHT")
  p[2]:SetPoint("BOTTOMRIGHT", p[3], "BOTTOMLEFT")
  if blend then for i = 1, 3 do p[i]:SetBlendMode(blend) end end
  -- as pontas recortam a moldura em volta do campo; a máscara deixa só a parte redonda (Art/PillCap*, de make_art.py)
  if parent.CreateMaskTexture then
    for i, file in pairs({ [1] = "PillCapL", [3] = "PillCapR" }) do
      local m = parent:CreateMaskTexture()
      m:SetTexture(ART .. file, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
      m:SetAllPoints(p[i])
      p[i]:AddMaskTexture(m)
    end
  end
  p.capW = capW
  return p
end
-- Recorta o campo da arte do tema atual; cor e opacidade opcionais (o brilho usa a cor da classe).
local function dressPill(p, r, g, b, a)
  crop(p[1], PILL[1], PILL[2], PILL[1] + CAP, PILL[4])
  crop(p[2], 30, PILL[2], 60, PILL[4])
  crop(p[3], PILL[1] + CAP, PILL[2], PILL[1], PILL[4])
  for i = 1, 3 do p[i]:SetVertexColor(r or 1, g or 1, b or 1, a or 1) end
end
local function dressRow(r)
  local a = T.accent
  dressPill(r.pill)
  dressPill(r.glow, a[1], a[2], a[3], 0.9) -- o aro do campo acende na cor da classe
  for i = 1, 3 do r.wash[i]:SetColorTexture(a[1], a[2], a[3], 0.16) end -- e o miolo ganha um véu da mesma cor
end
local function dressHeader(h)
  crop(h.bg, 22, 15.6, 52, 18.4) -- miolo da faixa das abas
end

-- título, centrado na placa vazia da arte (applyTheme põe na placa de cada tema)
panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
panel.title:SetWordWrap(false)
panel.title:SetText(L.NAME)

-- fechar: o botão redondo já está pintado; aqui só a área de clique e o brilho
local close = CreateFrame("Button", nil, panel)
place(close, 83.5, 7, 90.5, 12)
close:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
close:GetHighlightTexture():SetDesaturated(true) -- o brilho padrão é azul; sem cor ele aceita o vermelho
close:GetHighlightTexture():SetVertexColor(1, 0.12, 0.08)
close:SetScript("OnClick", function() panel:Hide() end)

-- créditos na faixa do rodapé
panel.creditBox = CreateFrame("Frame", nil, panel)
panel.creditBox:SetHeight(20)
panel.creditBox.pill = newPill(panel.creditBox, "BACKGROUND", 20)
panel.credits = panel.creditBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
panel.credits:SetPoint("CENTER")
panel.credits:SetTextColor(0.86, 0.84, 0.78)

local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")

-- busca em tempo real, no campo comprido pintado na arte (a lupa fica à direita, fora da área de texto)
panel.search = CreateFrame("EditBox", nil, panel)
place(panel.search, 14, 21, 82, 25.5)
panel.search:SetFontObject("GameFontHighlightSmall")
panel.search:SetAutoFocus(false)
local searchHint = panel.search:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
searchHint:SetPoint("LEFT")
searchHint:SetText(L.SEARCH)
panel.search:SetScript("OnTextChanged", function(self)
  searchHint:SetShown(self:GetText() == "")
  scroll:SetVerticalScroll(0)
  safe(panel.Refresh)
end)
panel.search:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
panel.search:SetScript("OnEnterPressed", panel.search.ClearFocus)

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
  sb:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 4, 0)
  sb:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 4, 0)
  sb:SetWidth(5)
  local track = solid(sb, "BACKGROUND", 1, 1, 1, 0.06)
  track:SetAllPoints()
  panel.thumb = sb:GetThumbTexture()
  panel.thumb:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.85)
  panel.thumb:SetSize(5, 48)
end)

local rows, headers = {}, {}

-- cabeçalho de grupo clicável: faixa colorida, [+/-] título à esquerda, valor total à direita
local function getHeader(i)
  local h = headers[i]
  if h then return h end
  h = CreateFrame("Button", nil, content)
  h:SetSize(WIDTH, 26)
  h.bg = h:CreateTexture(nil, "BACKGROUND")
  h.bg:SetAllPoints()
  dressHeader(h)
  h.tint = h:CreateTexture(nil, "BORDER") -- véu na cor do grupo, sumindo para a direita
  h.tint:SetTexture(WHITE)
  h.tint:SetAllPoints()
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
  h.toggle:SetSize(12, 12)
  h.toggle:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow") -- aponta para a direita; girada, para baixo
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
  r.pill = newPill(r, "BACKGROUND", ROW_H - 2)
  r.glow = newPill(r, "HIGHLIGHT", ROW_H - 2, "ADD")
  r.wash = newPill(r, "HIGHLIGHT", ROW_H - 2, "ADD")
  dressRow(r)
  r.iconBorder = solid(r, "ARTWORK", 0, 0, 0, 1)
  r.iconBorder:SetSize(26, 26)
  r.iconBorder:SetPoint("LEFT", 14, 0)
  r.icon = r:CreateTexture(nil, "OVERLAY")
  r.icon:SetSize(24, 24)
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
  r.price:SetPoint("RIGHT", -14, 0)
  r:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetSpellByID(self.spellID)
    if self.talent then
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine(L.TALENT_HINT, T.talent[1], T.talent[2], T.talent[3], true)
    end
    if self.estimated then
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine(L.PRICE_ESTIMATED, T.muted[1], T.muted[2], T.muted[3], true)
    end
    if self.teach then
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine(L.TEACH_PET_HINT, T.teach[1], T.teach[2], T.teach[3], true)
    end
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", GameTooltip_Hide)
  -- Shift+clique (a tecla de link do jogo): põe o link da habilidade/receita no chat, abrindo a caixa se preciso
  r:SetScript("OnClick", function(self)
    if not IsModifiedClick("CHATLINK") then return end
    safe(function()
      local link = (C_Spell.GetSpellLink and C_Spell.GetSpellLink(self.spellID)) or (GetSpellLink and GetSpellLink(self.spellID))
      if not link then return end
      local insert = (ChatFrameUtil and ChatFrameUtil.InsertLink) or ChatEdit_InsertLink
      if not (insert and insert(link)) then
        local open = (ChatFrameUtil and ChatFrameUtil.OpenChat) or ChatFrame_OpenChat
        if open then open(link) end
      end
    end)
  end)
  rows[i] = r
  return r
end

function panel:Refresh()
  local level = UnitLevel("player")
  local F = EAD_SkillPreviewDB.filters
  local profs = playerProfs()
  local view = EAD_SkillPreviewDB.view
  local isProf = type(view) == "number" -- aba de profissão: view é o ID da linha de perícia
  if (isProf and not tContains(profs, view)) or (view == "pet" and not hasPetData()) then
    view, isProf = "char", false
    EAD_SkillPreviewDB.view = view
  end
  panel.tabs:SetShown(hasPetData() or #profs > 0)
  panel.tabs.pet:SetShown(hasPetData())
  -- um botão com o ícone de cada profissão, depois das abas de texto
  local buttons = { panel.tabs.char, panel.tabs.pet }
  for i, prof in ipairs(profs) do
    local b = panel.profTab(i)
    b.view = prof
    b.tip = C_Spell.GetSpellName(ns.ProfSpell[prof])
    b.icon:SetTexture(C_Spell.GetSpellTexture(ns.ProfSpell[prof]) or 134400)
    b:SetPoint("LEFT", (hasPetData() and 160 or 80) + (i - 1) * 28, 0)
    b:Show()
    buttons[#buttons + 1] = b
  end
  for i = #profs + 1, #panel.tabs.prof do panel.tabs.prof[i]:Hide() end
  for _, b in ipairs(buttons) do
    local on = b.view == view
    local dim = on and 1 or 0.55
    if b.icon then -- profissão: só o ícone, com aro na cor da classe quando ativa
      b.ring:SetColorTexture(on and T.accent[1] or 0, on and T.accent[2] or 0, on and T.accent[3] or 0, on and 1 or 0.7)
    else
      dressPill(b.pill, dim, dim, dim)
      dressPill(b.glow, T.accent[1], T.accent[2], T.accent[3], on and 0.9 or 0)
    end
    b.text:SetTextColor(unpack(on and T.text or T.muted))
    if b.icon then b.icon:SetDesaturated(not on) end
  end
  local lists = isProf and collectProf(view) or collect(level, view) -- não chamar de L: L são os textos traduzidos
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
  local function header(text, kind, total, color, estimated)
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
    h.total:SetText(total and total > 0 and ((estimated and "|cff999999~|r " or "") .. coinText(total)) or "")
    h.total:SetAlpha(estimated and 0.5 or 1)
    h.toggle:SetShown(kind ~= nil)
    h.toggle:SetRotation(collapsed[kind] and 0 or -math.pi / 2)
    h.toggle:SetVertexColor(color[1], color[2], color[3])
    h.tint:SetGradient("HORIZONTAL", CreateColor(color[1], color[2], color[3], 0.30), CreateColor(color[1], color[2], color[3], 0))
    h:EnableMouse(kind ~= nil)
    h:Show()
    y = y + 32
  end
  -- kind: "now" (destaque verde), "soon" (ícone cinza), "learned" (apagado)
  local function addRows(list, kind)
    for _, e in ipairs(list) do
      nRow = nRow + 1
      local r = getRow(nRow)
      r.spellID, r.teach, r.talent = e.id, e.teach, e.talent
      r.estimated = e.cost > 0 and not e.checked and not e.teach and not e.talent
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", 0, -y)
      -- receita de profissão: o ícone é o do item criado (a magia da receita tem um ícone genérico)
      local itemIcon = e.item and e.item > 0 and C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(e.item)
      r.icon:SetTexture(e.icon or itemIcon or C_Spell.GetSpellTexture(e.id) or 134400)
      r.icon:SetDesaturated(kind == "soon" or e.talent)
      r:SetAlpha(kind == "learned" and 0.55 or 1)
      r.name:SetText(spellLabel(e.id))
      r.name:SetTextColor(unpack(kind == "now" and not e.talent and T.text or T.muted))
      if e.talent then
        r.level:SetText(L.LEVEL:format(e.lvl) .. "  •  " .. L.TALENT_REQUIRED)
        r.level:SetTextColor(unpack(T.talent))
      elseif e.teach then
        r.level:SetText(L.TEACH_PET)
        r.level:SetTextColor(unpack(T.teach))
      elseif e.src then -- receita de profissão: perícia exigida e, se não for de treinador, de onde vem
        r.level:SetText(L.SKILL:format(e.lvl) .. (SRC[e.src] and ("  •  " .. SRC[e.src]) or ""))
        r.level:SetTextColor(unpack(T.muted))
      else
        r.level:SetText(L.LEVEL:format(e.lvl))
        r.level:SetTextColor(unpack(T.muted))
      end
      r.price:SetAlpha((r.estimated or e.talent) and 0.5 or 1) -- estimativa: preço inteiro apagado, moedas incluídas
      if e.cost <= 0 then
        r.price:SetText("|cff666666—|r")
      elseif r.estimated then
        r.price:SetText("|cff999999~|r " .. coinText(e.cost)) -- veio do Wowhead, ainda não conferido
      else
        r.price:SetText(coinText(e.cost))
      end
      r:Show()
      y = y + ROW_H
    end
  end
  local function section(list, kind, color, title, emptyNote)
    if nHead > 0 then y = y + 8 end
    local total = 0
    local estimated = false
    for _, e in ipairs(list) do
      if not e.talent then
        total = total + e.cost
        if e.cost > 0 and not e.checked and not e.teach then estimated = true end
      end
    end
    local text = ("%s (%d)"):format(title, #list)
    if #list == 0 and emptyNote then text = text .. " |cff999999— " .. emptyNote .. "|r" end
    header(text, kind, total, color, estimated)
    if not collapsed[kind] then addRows(list, kind) end
  end

  if F.now then section(now, "now", T.now, L.AVAILABLE, L.NO_NEED) end
  if F.soon then section(soon, "soon", T.soon, L.UPCOMING) end
  if F.learned then section(learned, "learned", T.learned, L.LEARNED) end
  if nHead == 0 then header(L.PICK_FILTER) end

  for i = nRow + 1, #rows do rows[i]:Hide() end
  for i = nHead + 1, #headers do headers[i]:Hide() end
  content:SetHeight(math.max(y, 1))
  if isProf then
    panel.title:SetText(("%s: %s %d"):format(L.NAME, C_Spell.GetSpellName(ns.ProfSpell[view]) or "", profSkill(view) or 0))
  else
    panel.title:SetText(L.TITLE_LEVEL:format(L.NAME, level))
  end
end

-- menu "Filtro" com checkboxes (API de menu do cliente moderno)
-- sem modelo: o campo com a seta já está pintado na arte; aqui só o texto e a área de clique
local filter = CreateFrame("DropdownButton", nil, panel)
place(filter, 69, 14.5, 89, 19.5)
filter.wash = newPill(filter, "HIGHLIGHT", PH * 0.05, "ADD") -- brilho redondo como o campo pintado (cor em applyTheme)
local filterText = filter:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
filterText:SetPoint("LEFT", 12, 0)
filterText:SetText(L.FILTER)
filter:SetupMenu(function(_, root)
  -- o jogo monta o menu já na criação do botão, antes de as configurações salvas carregarem
  if not EAD_SkillPreviewDB then return end
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
  opt(L.TRAINER_ONLY, "trainerOnly") -- abas de profissão: esconde receitas de vendedor, missão e drop
  -- tema da janela: um por classe, com o nome da classe no idioma do jogo
  local themes = root:CreateButton(L.THEME)
  local items = {}
  for key in pairs(THEMES) do items[#items + 1] = { key, (LOCALIZED_CLASS_NAMES_MALE or {})[key] or key } end
  table.sort(items, function(x, y) return x[2] < y[2] end) -- ordem alfabética no idioma do jogo
  for _, item in ipairs(items) do
    local key = item[1]
    themes:CreateRadio(item[2], function() return themeKey() == key end, function() panel.SetTheme(key) end)
  end
end)

-- seletor Personagem | Pet | profissões, na mesma linha do Filtro
panel.tabs = CreateFrame("Frame", nil, panel)
panel.tabs:SetSize(190, 24)
panel.tabs:SetPoint("TOPLEFT", PW * 0.115, -PH * 0.145 - 4) -- dentro da faixa vazia da arte
local function tabButton(text, view, x)
  local b = CreateFrame("Button", nil, panel.tabs)
  b.view = view
  b:SetSize(76, 24)
  b:SetPoint("LEFT", x, 0)
  if text ~= "" then
    b.pill = newPill(b, "BACKGROUND", 24)
    b.glow = newPill(b, "BORDER", 24, "ADD")
  else
    b.ring = solid(b, "BACKGROUND", 0, 0, 0, 0.7)
    b.ring:SetAllPoints()
  end
  b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.text:SetPoint("CENTER", 0, 1)
  b.text:SetText(text)
  b:SetScript("OnClick", function(self)
    EAD_SkillPreviewDB.view = self.view
    scroll:SetVerticalScroll(0)
    safe(panel.Refresh)
  end)
  return b
end
panel.tabs.char = tabButton(L.CHARACTER, "char", 0)
panel.tabs.pet = tabButton(L.PET, "pet", 80)

-- aba de profissão: só o ícone, com o nome no tooltip (Refresh define view, ícone e posição)
panel.tabs.prof = {}
function panel.profTab(i)
  local b = panel.tabs.prof[i]
  if b then return b end
  b = tabButton("", nil, 0)
  b:SetSize(24, 24)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetPoint("TOPLEFT", 2, -2)
  b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
  b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine(self.tip or "")
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", GameTooltip_Hide)
  panel.tabs.prof[i] = b
  return b
end

-- Veste a janela com o tema do personagem: arte, cor de destaque e a área da lista medida nessa arte.
local function applyTheme()
  local th = THEMES[themeKey()]
  local a, l = th.accent, th.list
  T.accent = a
  for i = 1, 3 do filter.wash[i]:SetColorTexture(a[1], a[2], a[3], 0.16) end
  panel.art:SetTexture(ART .. th.art)
  panel.title:SetTextColor(a[1], a[2], a[3])
  if panel.thumb then panel.thumb:SetColorTexture(a[1], a[2], a[3], 0.85) end
  place(scroll, l[1] + 1.2, l[2] + 1, l[3] - 3, l[4] - 1) -- folga da moldura; à direita cabe a barra de rolagem
  WIDTH = PW * (l[3] - l[1] - 4.2) / 100
  content:SetWidth(WIDTH)
  for _, r in ipairs(rows) do
    r:SetWidth(WIDTH)
    dressRow(r)
  end
  local hex = ("|cff%02x%02x%02x"):format(math.floor(a[1] * 255), math.floor(a[2] * 255), math.floor(a[3] * 255))
  panel.credits:SetText(L.CREDITS:format(hex .. "Oleg|r") .. " " .. hex .. "• assantech.com.br|r")
  dressPill(panel.creditBox.pill)
  panel.creditBox:SetWidth(panel.credits:GetStringWidth() + 2 * panel.creditBox.pill.capW)
  panel.creditBox:ClearAllPoints()
  panel.creditBox:SetPoint("CENTER", panel, "TOPLEFT", PW * th.foot[1] / 100, -PH * th.foot[2] / 100)
  local ti = th.title
  place(panel.title, ti[1] - ti[3], ti[2] - 2.3, ti[1] + ti[3], ti[2] + 2.3)
  for _, h in ipairs(headers) do
    h:SetWidth(WIDTH)
    dressHeader(h)
  end
end

function panel.SetTheme(key)
  EAD_SkillPreviewDB.themes[charKey()] = key
  safe(applyTheme)
  safe(panel.Refresh)
end

panel:SetScript("OnShow", function() safe(applyTheme); safe(panel.Refresh) end)

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
local function fillTooltip(tt)
  tt:AddLine(L.NAME)
  local n = countNow(UnitLevel("player"))
  tt:AddLine(n > 0 and ("|cff00ff00" .. L.TT_NOW:format(n) .. "|r") or L.TT_NOTHING, 1, 1, 1)
  tt:AddLine(L.TT_HINT, 0.6, 0.6, 0.6)
end
mm:SetScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_LEFT")
  fillTooltip(GameTooltip)
  GameTooltip:Show()
end)
mm:SetScript("OnLeave", GameTooltip_Hide)

-- Com a LibDBIcon carregada por outro addon, o botão passa a ser o dela: coletores de botões do minimapa
-- (como a bolsa do FlareUI) só desenham no padrão deles os botões registrados nessa biblioteca.
-- shortcut: a biblioteca não vem embutida; sem outro addon que a traga fica o botão próprio acima. Embutir se
-- alguém pedir o ícone padronizado sem ter outro addon com ela.
local function useLibDBIcon()
  local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
  local DBI = LibStub and LibStub("LibDBIcon-1.0", true)
  if not (LDB and DBI) then return end
  local object = LDB:NewDataObject(ADDON, {
    type = "launcher",
    label = L.NAME,
    icon = ICON,
    OnClick = function() safe(toggle) end,
    OnTooltipShow = fillTooltip,
  })
  -- mesma convenção de ângulo (graus) do botão próprio
  EAD_SkillPreviewDB.minimap = EAD_SkillPreviewDB.minimap or { minimapPos = EAD_SkillPreviewDB.angle % 360 }
  DBI:Register(ADDON, object, EAD_SkillPreviewDB.minimap)
  mm:Hide()
end

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
-- eventos de profissão mudam de nome entre versões do cliente, e registrar um que não existe dá erro
for _, e in ipairs({ "TRADE_SKILL_SHOW", "CRAFT_SHOW", "SKILL_LINES_CHANGED" }) do pcall(f.RegisterEvent, f, e) end
f:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" and arg1 == ADDON then
    EAD_SkillPreviewDB = EAD_SkillPreviewDB or {}
    EAD_SkillPreviewDB.angle = EAD_SkillPreviewDB.angle or 210
    EAD_SkillPreviewDB.filters = EAD_SkillPreviewDB.filters or { now = true, soon = true, learned = false, pet = true }
    EAD_SkillPreviewDB.collapsed = EAD_SkillPreviewDB.collapsed or {}
    EAD_SkillPreviewDB.view = EAD_SkillPreviewDB.view or "char"
    EAD_SkillPreviewDB.fix = EAD_SkillPreviewDB.fix or {}
    EAD_SkillPreviewDB.learned = EAD_SkillPreviewDB.learned or {}
    EAD_SkillPreviewDB.seen = EAD_SkillPreviewDB.seen or {} -- preços conferidos que já batiam com o Wowhead
    EAD_SkillPreviewDB.petSpell = EAD_SkillPreviewDB.petSpell or {} -- magia do caçador -> magia no livro do pet
    EAD_SkillPreviewDB.scan = EAD_SkillPreviewDB.scan or {} -- cópia bruta dos treinadores de profissão (/ead scan)
    EAD_SkillPreviewDB.discount = EAD_SkillPreviewDB.discount or {} -- personagem -> profissão -> % do preço cheio
    EAD_SkillPreviewDB.themes = EAD_SkillPreviewDB.themes or {} -- personagem -> tema escolhido (sem escolha: o da classe)
    -- v7: correções de profissão guardavam o preço já com desconto; agora o desconto é aplicado na hora de mostrar
    if (EAD_SkillPreviewDB.fixVersion or 1) < 7 then
      for _, t in ipairs({ EAD_SkillPreviewDB.fix, EAD_SkillPreviewDB.seen }) do
        for k in pairs(t) do
          if type(k) == "number" then t[k] = nil end
        end
      end
    end
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
    EAD_SkillPreviewDB.fixVersion = 7
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
    safe(useLibDBIcon) -- aqui todos os addons já carregaram, inclusive o que traz a biblioteca
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
  elseif event == "TRADE_SKILL_SHOW" or event == "CRAFT_SHOW" then
    C_Timer.After(0.5, function()
      safe(scanRecipes)
      if panel:IsShown() then safe(panel.Refresh) end
    end)
  elseif (event == "SPELLS_CHANGED" or event == "UNIT_PET" or event == "PET_BAR_UPDATE"
    or event == "SKILL_LINES_CHANGED") and panel:IsShown() then
    safe(panel.Refresh) -- aprendeu algo, trocou de pet ou o pet aprendeu algo com o painel aberto
  end
end)

SLASH_EADSKILLPREVIEW1 = "/ead"
-- /ead debug: com um treinador aberto, mostra no chat o que o jogo devolve de cada serviço (para diagnosticar o Forever)
local function debugTrainer()
  local n = GetNumTrainerServices and GetNumTrainerServices() or 0
  say(("debug: %d serviço(s), npc=%s"):format(n, tostring(UnitExists("npc"))))
  for prof, spell in pairs(ns.ProfSpell) do
    print(("  profissão %d %s: perícia=%s"):format(prof, tostring(C_Spell.GetSpellName(spell)), tostring(profSkill(prof))))
  end
  if n > 0 and GetTrainerServiceSkillReq then print("  perícia exigida do 1º serviço:", GetTrainerServiceSkillReq(1)) end
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
  if msg == "debug" then safe(debugTrainer)
  elseif msg == "scan" then -- liga/desliga a gravação bruta dos treinadores de profissão (para atualizar Professions.lua)
    EAD_SkillPreviewDB.scanOn = not EAD_SkillPreviewDB.scanOn
    say("scan " .. (EAD_SkillPreviewDB.scanOn and "ON" or "OFF"))
  else safe(toggle) end
end
