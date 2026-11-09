-- Espanhol da Espanha e do México usam o mesmo arquivo.
local _, ns = ...
local loc = GetLocale()
if loc ~= "esES" and loc ~= "esMX" then return end
local L = ns.L

L.ERROR = "error:"
L.SPELL_N = "hechizo n.º %d"
L.TRAINER_CHECKED = "Instructor revisado: %d leída(s), %d corregida(s), %d nueva(s), %d que el instructor no ofrece."
L.LEVEL = "Nivel %d"
L.AVAILABLE = "Disponibles"
L.UPCOMING = "Próximas"
L.LEARNED = "Ya aprendidas"
L.NO_NEED = "no hace falta ir al instructor"
L.PICK_FILTER = "Marca algo en el filtro."
L.TITLE_LEVEL = "%s — nivel %d"
L.FILTER = "Filtro"
L.UPCOMING_MAX = "Próximas (hasta el nivel máximo)"
L.ALL = "Todas las habilidades"
L.CHARACTER = "Personaje"
L.PET = "Mascota"
L.TT_NOW = "%d para aprender ahora"
L.TT_NOTHING = "Nada nuevo en el instructor"
L.TT_HINT = "Clic: abrir  •  Arrastrar: mover"
L.ANNOUNCE = "%d habilidad(es) para aprender en el instructor."
L.ANNOUNCE_HINT = "Haz clic en el icono del minimapa o escribe %s."
L.CREDITS = "Desarrollado por %s"
L.TEACH_PET = "Comprada, pero tu mascota aún no la aprendió"
L.TEACH_PET_HINT = "Usa Entrenar bestia para enseñársela a tu mascota."
L.SEARCH = "Buscar"
