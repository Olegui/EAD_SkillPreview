-- Textos padrão (inglês). Os outros arquivos desta pasta só sobrescrevem o que muda no idioma do jogo.
-- Para traduzir para um idioma novo: copie ptBR.lua, troque o código do idioma e os textos, e adicione o arquivo no .toc.
local _, ns = ...
ns.L = {
  NAME = "EAD - Skill Preview", -- nome da marca: igual em todos os idiomas
  ERROR = "error:",
  SPELL_N = "spell #%d",
  TRAINER_CHECKED = "trainer checked: %d read, %d corrected, %d new, %d not offered by the trainer.",
  LEVEL = "Level %d",
  AVAILABLE = "Available",
  UPCOMING = "Upcoming",
  LEARNED = "Already learned",
  NO_NEED = "no need to visit the trainer",
  PICK_FILTER = "Check something in the Filter.",
  TITLE_LEVEL = "%s — level %d",
  FILTER = "Filter",
  UPCOMING_MAX = "Upcoming (up to max level)",
  ALL = "All abilities",
  CHARACTER = "Character",
  PET = "Pet",
  TT_NOW = "%d to learn now",
  TT_NOTHING = "Nothing new at the trainer",
  TT_HINT = "Click: open  •  Drag: move",
  ANNOUNCE = "%d ability(ies) to learn at the trainer.",
  ANNOUNCE_HINT = "Click the minimap icon or type %s.",
  CREDITS = "Developed by %s",
  TEACH_PET = "Bought, but your pet has not learned it yet",
  TEACH_PET_HINT = "Use Beast Training to teach it to your pet.",
  SEARCH = "Search",
}
