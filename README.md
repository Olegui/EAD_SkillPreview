# EAD - Skill Preview

Addon para **World of Warcraft: Forever** que mostra, sem precisar ir ao treinador, quais habilidades da sua classe já estão disponíveis no seu nível e quais vêm nos próximos níveis, com ícone, nível e preço.

*An addon for World of Warcraft: Forever that shows which class abilities you can learn now and at upcoming levels, without visiting the trainer. Available in 11 languages.*

## Funcionalidades

- **Janela própria** com o tema "EAD": abra pelo botão no minimapa ou com `/ead`.
- **Grupos** Disponíveis, Próximas (até o nível máximo) e Já aprendidas, que abrem e fecham com um clique, cada um com o valor total à direita.
- **Filtro** com caixas de marcar para escolher quais grupos aparecem.
- **Habilidades de pet** para caçador (treinador de pet) e bruxo (grimórios), em uma aba separada.
- **Aviso no chat** ao logar e ao subir de nível quando há algo novo para aprender.
- **Conferência automática no treinador:** ao abrir um treinador de classe ou de pet, o addon compara a lista com o que o jogo oferece e corrige níveis e preços. As correções ficam salvas e valem para todos os personagens da mesma classe.
- **11 idiomas:** usa o idioma configurado no jogo (inglês, português do Brasil, alemão, francês, espanhol, italiano, russo, coreano e chinês simplificado e tradicional).

## Instalação

1. Baixe o projeto (botão **Code → Download ZIP**) ou a versão mais recente em **Releases**.
2. Extraia a pasta `EAD_SkillPreview` em:
   ```
   World of Warcraft\_forever_\Interface\AddOns\
   ```
   O nome da pasta precisa ser exatamente `EAD_SkillPreview`.
3. Na tela de personagens, em **AddOns**, confira se **EAD - Skill Preview** está marcado.

## Uso

| Ação | Como |
|---|---|
| Abrir ou fechar a janela | Clique no ícone do livro no minimapa ou digite `/ead` |
| Mover o botão do minimapa | Arraste o ícone pela borda do minimapa |
| Abrir ou fechar um grupo | Clique no título do grupo |
| Ver detalhes de uma habilidade | Passe o mouse sobre a linha |
| Atualizar preços e níveis | Abra o treinador da sua classe (ou de pet) uma vez |

## Estrutura

```
EAD_SkillPreview/
├── EAD_SkillPreview.toc   ficha do addon (nome, descrição, arquivos)
├── Core.lua               janela, filtro, botão do minimapa e conferência no treinador
├── Data.lua               lista de habilidades por classe e de pets
└── Locales/               um arquivo de textos por idioma
```

## Dados

A lista inicial de habilidades vem da seção Forever do [Wowhead](https://www.wowhead.com/forever). Como o banco de dados de lá ainda traz valores de versões antigas do Classic, os preços e níveis são corrigidos pelo próprio jogo quando você abre o treinador.

## Traduções

Cada idioma é um arquivo em `Locales/`. Para corrigir uma tradução, edite o texto entre aspas no arquivo do idioma. O `%d` e o `%s` marcam onde entram números e nomes e precisam continuar no texto. Correções de falantes nativos são bem-vindas.

## Créditos

Desenvolvido por **Oleg** · [assantech.com.br](https://assantech.com.br)

## Licença

[MIT](LICENSE)
