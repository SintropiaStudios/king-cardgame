# King: Um Ecossistema Aberto de Jogo de Cartas Multiplayer

[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Protocol](https://img.shields.io/badge/Protocol-ZMQ-green.svg)](protocol/)

King é um jogo de vazas altamente estratégico, construído sobre um protocolo de comunicação aberto e agnóstico a linguagem. Este repositório serve como a implementação de referência para o ecossistema **Public King**, apresentando um servidor autoritativo e uma diversidade de clientes e agentes de IA.

## 🃏 O Jogo

As regras básicas do jogo podem ser consultadas na [Wikipédia](https://en.wikipedia.org/wiki/King_(card_game)).

Em sua essência, King é um jogo de objetivos em constante mudança. Uma partida é dividida em duas fases:
1.  **Rodadas Negativas (Penalidades):** Os jogadores buscam evitar fazer vazas, pegar copas ou o Rei de Copas para não perder pontos.
2.  **Rodadas Positivas (Lances):** Os jogadores fazem lances e competem para garantir pontos através de jogo estratégico.

### As Regras de Engajamento (O "Aloja")
Esta implementação segue um conjunto de regras refinado e focado na agência do jogador, baseado em extensa experiência de jogo nas residências estudantis (o "Aloja"). As principais mudanças em relação ao King tradicional incluem:
*   **Escolha Dinâmica de Rodadas:** Removemos a sequência rígida e tradicional de mãos. Os jogadores têm liberdade absoluta para escolher qual mão jogar com base em suas cartas iniciais.
*   **Lances Estritos:** Resoluções precisas de lances e mecânicas de descarte sutis (especialmente para o Rei de Copas) transformam cada partida em uma batalha de planejamento estrutural.
*   **Estratégia do Rei:** Na mão de "No King of Hearts" (ou simplesmente "King"), o jogador não é obrigado a jogar o Rei de Copas quando a rodada inicia com Copas, a menos que seja sua única opção de descarte.

## 🏗️ Arquitetura & Protocolo

O Public King foi projetado para ser um playground poliglota. O servidor e os clientes se comunicam através de um protocolo formalizado baseado em **ZeroMQ (ZMQ)**, permitindo que qualquer pessoa construa seu próprio cliente ou agente de IA em qualquer linguagem.

### Estrutura do Repositório
*   `protocol/`: Especificação formal do protocolo ZMQ.
*   `src/haskell/`: O servidor de jogo autoritativo (Haskell).
*   `src/python/`: Implementação de referência da lógica, servidor e bots básicos.
*   `src/cpp/`: Clientes de alta performance (Console e Vulkan/3D).
*   `src/csharp/`: Clientes gráficos em .NET e MonoGame.
*   `src/nodejs/`: Implementação de cliente para web.
*   `src/rust/`: Cliente experimental em Rust.

## 🚀 Como Começar

### Requisitos
*   **Python:** 3.8+ (para lógica principal e scripts de referência).
*   **ZeroMQ:** Necessário para a comunicação entre todas as implementações.
*   **Ferramentas por linguagem:** GHC/Cabal (Haskell), CMake (C++), Node/NPM, etc.

### Executando a Referência em Python
1.  Navegue até `src/python/common` e garanta que as dependências estejam instaladas.
2.  Inicie o servidor: `python src/python/server/server.py`
3.  Conecte um bot: `python src/python/bot/random_bot.py`

## 🎓 As Origens: O "Aloja"

King é mais do que um exercício de arquitetura de protocolo; carrega uma profunda marca pessoal. Este conjunto de regras específico foi forjado no "Aloja" (abreviação de Alojamento), uma residência estudantil onde um grupo dedicado de jogadores transformou o jogo em uma cultura de rivalidade estratégica. Como homenagem a essas raízes, os oponentes de IA que você enfrenta carregam os nomes dos próprios personagens que definiram aquela época.

## 🤝 Contribuições

Contribuições de todos os tipos são bem-vindas! Seja uma nova implementação de cliente, correções no servidor Haskell ou melhorias na documentação do protocolo.

*Veja o [CONTRIBUTING.br.md](CONTRIBUTING.br.md) para detalhes.*

---

**Nota sobre Licenciamento:** A maior parte dos ativos e código é fornecida sob a licença MIT. Alguns ativos gráficos nas implementações de clientes são usados com permissão ou como placeholders (veja os READMEs internos dos clientes para avisos específicos).
