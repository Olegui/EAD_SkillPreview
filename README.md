# EAD - Skill Preview

**[English](#english)** · **[Português](#português)**

---

## English

An addon for **World of Warcraft: Forever** that shows, without visiting the trainer, which class abilities you can already learn at your level and what is coming in the next levels, with icon, required level and price.

### Features

- **Themed window**, opened from the minimap button or with `/ead`. Nine hand-painted themes, one per class: the window starts in your class's theme and you can pick another under **Filter → Theme**.
- **Groups:** Available, Upcoming (up to max level) and Already learned, each one collapsible and with its total cost on the right.
- **Filter** with checkboxes to choose which groups are shown.
- **Pet abilities** for Hunters (pet trainer) and Warlocks (demon grimoires), in their own tab.
- **Professions:** one tab per profession your character has, with every recipe grouped by the skill you have now. Shows required skill, trainer price and, for the rest, where it comes from (vendor, quest, drop). The Filter can show trainer recipes only.
- **Chat reminder** when you log in or level up and there is something new to learn.
- **Self-correcting data:** when you open a class or pet trainer, the addon compares its list with what the game offers and fixes levels and prices. Fixes are saved and shared by all your characters of the same class.
- **11 languages:** follows your game language (English, Brazilian Portuguese, German, French, Spanish, Italian, Russian, Korean, Simplified and Traditional Chinese).

### Installation

1. Download the latest version from **Releases** (or **Code → Download ZIP**).
2. Extract the `EAD_SkillPreview` folder into:
   ```
   World of Warcraft\_forever_\Interface\AddOns\
   ```
   The folder name must be exactly `EAD_SkillPreview`.
3. On the character screen, open **AddOns** and make sure **EAD - Skill Preview** is enabled.

### Usage

| Action | How |
|---|---|
| Open / close the window | Click the addon icon on the minimap or type `/ead` |
| Move the minimap button | Drag it around the minimap border |
| Collapse / expand a group | Click the group title |
| See spell details | Hover the row |
| Link an ability or recipe in chat | Shift-click the row |
| Update prices and levels | Open your class, pet or profession trainer once |
| See a profession | Click its icon next to the Character tab |

### Project structure

```
EAD_SkillPreview/
├── EAD_SkillPreview.toc   addon manifest (name, description, files)
├── Core.lua               window, filter, minimap button and trainer check
├── Data.lua               ability list per class and for pets
├── Professions.lua        recipe list per profession
└── Locales/               one text file per language
```

### Data

The initial ability list comes from the Forever section of [Wowhead](https://www.wowhead.com/forever). Since some values there still come from older Classic versions, prices and levels are corrected by the game itself when you open the trainer.

### Translations

Each language is a file in `Locales/`. To fix a translation, edit the quoted text in that language's file. `%d` and `%s` mark where numbers and names go and must stay in the text. Corrections from native speakers are very welcome.

---

## Português

Addon para **World of Warcraft: Forever** que mostra, sem precisar ir ao treinador, quais habilidades da sua classe já estão disponíveis no seu nível e quais vêm nos próximos níveis, com ícone, nível necessário e preço.

### Funcionalidades

- **Janela com tema próprio**, aberta pelo botão do minimapa ou com `/ead`. São nove temas pintados, um por classe: a janela abre no tema da sua classe e dá para escolher outro em **Filtro → Tema**.
- **Grupos:** Disponíveis, Próximas (até o nível máximo) e Já aprendidas, cada um podendo ser minimizado e com o valor total à direita.
- **Filtro** com caixas de marcar para escolher quais grupos aparecem.
- **Habilidades de pet** para caçador (treinador de pet) e bruxo (grimórios de demônio), em uma aba própria.
- **Profissões:** uma aba para cada profissão do personagem, com todas as receitas agrupadas pela perícia que você tem agora. Mostra a perícia exigida, o preço no treinador e, nas demais, de onde vem (vendedor, missão, drop). O Filtro pode mostrar só as de treinador.
- **Aviso no chat** ao logar e ao subir de nível quando há algo novo para aprender.
- **Dados que se corrigem sozinhos:** ao abrir um treinador de classe ou de pet, o addon compara a lista com o que o jogo oferece e corrige níveis e preços. As correções ficam salvas e valem para todos os personagens da mesma classe.
- **11 idiomas:** segue o idioma configurado no jogo (inglês, português do Brasil, alemão, francês, espanhol, italiano, russo, coreano e chinês simplificado e tradicional).

### Instalação

1. Baixe a versão mais recente em **Releases** (ou em **Code → Download ZIP**).
2. Extraia a pasta `EAD_SkillPreview` em:
   ```
   World of Warcraft\_forever_\Interface\AddOns\
   ```
   O nome da pasta precisa ser exatamente `EAD_SkillPreview`.
3. Na tela de personagens, em **AddOns**, confira se **EAD - Skill Preview** está marcado.

### Uso

| Ação | Como |
|---|---|
| Abrir / fechar a janela | Clique no ícone do addon no minimapa ou digite `/ead` |
| Mover o botão do minimapa | Arraste o ícone pela borda do minimapa |
| Abrir / fechar um grupo | Clique no título do grupo |
| Ver detalhes de uma habilidade | Passe o mouse sobre a linha |
| Linkar uma habilidade ou receita no chat | Shift+clique na linha |
| Atualizar preços e níveis | Abra o treinador da sua classe, de pet ou de profissão uma vez |
| Ver uma profissão | Clique no ícone dela ao lado da aba Personagem |

### Estrutura

```
EAD_SkillPreview/
├── EAD_SkillPreview.toc   ficha do addon (nome, descrição, arquivos)
├── Core.lua               janela, filtro, botão do minimapa e conferência no treinador
├── Data.lua               lista de habilidades por classe e de pets
├── Professions.lua        lista de receitas por profissão
└── Locales/               um arquivo de textos por idioma
```

### Dados

A lista inicial de habilidades vem da seção Forever do [Wowhead](https://www.wowhead.com/forever). Como o banco de dados de lá ainda traz valores de versões antigas do Classic, os preços e níveis são corrigidos pelo próprio jogo quando você abre o treinador.

### Traduções

Cada idioma é um arquivo em `Locales/`. Para corrigir uma tradução, edite o texto entre aspas no arquivo do idioma. O `%d` e o `%s` marcam onde entram números e nomes e precisam continuar no texto. Correções de falantes nativos são bem-vindas.

---

## Credits / Créditos

Developed by / Desenvolvido por **Oleg** · [assantech.com.br](https://assantech.com.br)

## License / Licença

[MIT](LICENSE)
