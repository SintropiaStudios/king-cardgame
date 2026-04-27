# Contribuindo para o Ecossistema King

Bem-vindo! Estamos entusiasmados com o seu interesse em contribuir para o King.

O King foi projetado como um ecossistema de jogo de cartas de protocolo aberto e agnóstico a linguagem. Devido a essa natureza poliglota, nossa filosofia de contribuição pode ser um pouco diferente daquela com a qual você está acostumado.

Antes de enviar um Pull Request ou abrir uma issue, reserve um momento para ler este guia para entender nossa visão e como você pode causar o melhor impacto.

## Nossa Filosofia: Expandir, Não Mudar

O objetivo principal deste repositório é servir como a **Implementação de Referência** para o Protocolo King. Ele contém o servidor autoritativo em Haskell, a documentação oficial do protocolo e os clientes de referência básicos (Python, Rust, C#, Node.js).

**Incentivamos fortemente a expansão do ecossistema em vez de construir diretamente no núcleo.** O que isso significa para você?
1. **Use este repositório como referência:** Em vez de adicionar uma nova interface massiva ou um agente de IA altamente complexo diretamente neste repositório, incentivamos você a construí-lo em seu próprio repositório independente usando sua tecnologia preferida.
2. **Construa em torno do protocolo:** Escreva um cliente em uma linguagem que ainda não suportamos. Construa um bot de machine learning. Crie um rastreador de torneios baseado na web. O protocolo ZeroMQ (ZMQ) é completamente aberto para você se conectar.
3. **Graduação para o Núcleo:** Se você construir um cliente, servidor ou ferramenta que ganhe tração significativa da comunidade e prove sua estabilidade, os mantenedores podem entrar em contato para incorporá-lo oficialmente ao repositório principal ou à organização oficial do King.

## Como Você Pode Contribuir Diretamente

Embora incentivemos a expansão externa, aceitamos de braços abertos contribuições diretas para este repositório nas seguintes áreas:

### 1. Documentação e Guias do Protocolo
O ecossistema é tão bom quanto sua documentação. Contribuições que esclareçam a API ZMQ, adicionem diagramas de sequência, corrijam erros de digitação ou forneçam tutoriais de "Primeiros Passos" para novas linguagens são altamente valorizadas.

### 2. Fortalecimento do Servidor de Referência (Haskell)
O servidor Haskell é o guardião das regras autoritativas para a Versão 1 do Protocolo. Aceitamos PRs que:
* Corrijam bugs de conformidade com o protocolo.
* Melhorem o tratamento de casos extremos e a estabilidade da conexão.
* Aumentem a cobertura de testes para a lógica do servidor.

### 3. Correções de Bugs em Clientes de Referência
Se você encontrar um bug em um dos clientes de referência existentes (Rust, Python, Node.js, C#) que o impeça de interpretar corretamente o protocolo, abra uma issue ou envie uma correção. *(Nota: Geralmente não aceitamos excesso de funcionalidades (feature bloat) para clientes de referência; eles devem permanecer mínimos e legíveis para fins educacionais).*

## Enviando um Relatório de Bug

Ao abrir uma issue para relatar um bug, forneça o máximo de contexto possível para que possamos reproduzi-lo:
* **O Componente:** Você está relatando um problema com o servidor Haskell, um cliente de referência específico ou a documentação do protocolo?
* **Passos para Reproduzir:** Um guia passo a passo claro para acionar o bug.
* **Comportamento Esperado vs. Real:** O que aconteceu e o que você esperava que acontecesse com base no protocolo?
* **Logs e Rastreios:** Inclua as mensagens (payloads) brutas do ZMQ que levaram ao erro.

## Processo de Pull Request

Se você estiver enviando uma correção ou atualização de documentação para este repositório, siga estes passos:

1. **Faça um fork do repositório** e crie sua branch a partir da `master`.
2. **Mantenha o foco:** Certifique-se de que seu PR faça uma coisa específica. Não misture atualizações de documentação com correções de lógica do servidor.
3. **Teste suas alterações:** Se estiver modificando o servidor Haskell, certifique-se de que todos os testes de conformidade passem e que ele ainda consiga completar uma partida com sucesso contra os bots de referência.
4. **Atualize a documentação:** Se você alterar qualquer comportamento relacionado às mensagens ZMQ, **deve** atualizar a documentação do protocolo correspondente no mesmo PR.
5. **Assine o CLA:** (Se aplicável no futuro, você poderá ser solicitado a assinar um Contrato de Licença de Colaborador).

## Código de Conduta

Ao participar deste projeto, você concorda em cumprir nosso [Código de Conduta](CODE_OF_CONDUCT.md). Estamos empenhados em fornecer um ambiente acolhedor e inspirador para todos os desenvolvedores, independentemente de sua formação ou nível de experiência.

---

Obrigado por nos ajudar a construir o ecossistema definitivo de jogo de cartas de código aberto. Mal podemos esperar para ver o que você vai construir!
