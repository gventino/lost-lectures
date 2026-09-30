# Módulo 01: A Morte do Compartilhamento de Tela

---

## Objetivo

Entender **o que se perdeu** quando o vídeo do Discord foi suspenso no Brasil, olhar
para isso como engenheiro (onde o vídeo passava, quem controlava o caminho) e formular
a pergunta que guia todo o resto deste material.

---

## Onde a gente estava

Toda noite, o mesmo canal de voz.

- Alguém abre o jogo e compartilha a tela.
- Alguém transmite o episódio novo da série do momento.
- Alguém compartilha um vídeo do YouTube de três minutos que leva a uma discussão de
  mais de uma hora.

A galera mora em cidades diferentes. O Discord era menos um aplicativo e mais um
**lugar**: a sala de estar de quem não mora perto.

O que fazia aquilo funcionar tinha nome:

| Recurso          | O que faz                                                        |
|------------------|------------------------------------------------------------------|
| Go Live          | Transmite uma tela ou uma janela para quem está no canal         |
| Chamada de vídeo | Câmera ao vivo, em conversa privada, em grupo ou em canal de voz |
| Canal de voz     | Áudio em tempo real, sempre aberto, entra e sai quem quiser      |

---

## O que mudou em 17 de agosto de 2026

Segundo a Central de Ajuda do próprio Discord:

- A ANPD (Autoridade Nacional de Proteção de Dados) ordenou a suspensão do **Go Live** e do
  **chat de vídeo em tempo real** para usuários no Brasil, a partir de **17 de agosto de 2026**.
- A ordem vale para mensagens diretas, grupos, canais de voz e canais Stage.
- A ordem está ligada a uma investigação no âmbito do **ECA Digital** (Estatuto Digital
  da Criança e do Adolescente).
- **Voz e mensagens não foram afetadas.**
- O Discord não informa uma data para os recursos voltarem.

| Recurso                             | Situação no Brasil |
|-------------------------------------|--------------------|
| Mensagens de texto                  | Funciona           |
| Canais de voz e chamadas de áudio   | Funciona           |
| Go Live (compartilhar tela)         | Suspenso           |
| Assistir ao Go Live de outra pessoa | Suspenso           |
| Chamadas de vídeo (câmera)          | Suspenso           |

> Fonte: Discord, *Por que os recursos de vídeo estão indisponíveis no Brasil no momento*,
> [Central de Ajuda](https://support.discord.com/hc/pt-br/articles/42704051358359-Por-que-os-recursos-de-v%C3%ADdeo-est%C3%A3o-indispon%C3%ADveis-no-Brasil-no-momento).

---

## O que fez falta de verdade

A voz continuou. Dava para conversar, rir, se xingar (com carinho, óbvio).
O que sumiu foi uma coisa bem específica:

> **A tela de uma pessoa chegando na tela de todas as outras, ao mesmo tempo.**

Parece pouco. Não é. Sem isso, a watch party vira "dá play no 3, 2, 1... já?
o meu ainda tá carregando", e o jogo vira narração de rádio.

---

## Por onde o vídeo passava

No Go Live, o vídeo não vai direto do seu PC para o PC dos seus amigos.
Ele sobe para a infraestrutura do Discord, e de lá é distribuído para quem está assistindo:

```
┌------------┐                                 ┌------------┐
| Quem       |                                 | Amigo 1    |
| transmite  |---->┌-------------------┐------>└------------┘
└------------┘     |    Servidores     |       ┌------------┐
                   |    do Discord     |------>| Amigo 2    |
                   └-------------------┘       └------------┘
                             |                 ┌------------┐
                             └---------------->| Amigo 3    |
                                               └------------┘
```

Essa arquitetura tem vantagens enormes:

- **Você só faz upload uma vez**, não importa quantas pessoas assistem.
- **Atravessar NAT (Network Address Translation) não é problema seu**: todo mundo fala com
  o servidor, e o servidor fala com todo mundo.
- **Conta, amigos, permissões e moderação** ficam num lugar só.

E tem uma consequência arquitetural simples:

> **Quando todo o vídeo passa por um único operador, a existência do recurso depende de
> uma única decisão desse operador**, seja ela técnica, comercial ou jurídica.

Não é um defeito do Discord. É uma propriedade de qualquer sistema centralizado.

---

## A pergunta certa

A tentação, depois do dia 17, era perguntar **"qual app substitui o Discord?"**.

Essa pergunta leva direto a qualquer coisa que funcione, e funcionar é fácil de testar.
A pergunta que importa é outra:

> **"Em quem você está confiando quando compartilha sua tela?"**

Sua tela mostra suas conversas, suas abas, suas notificações, às vezes seu banco.
Toda solução de compartilhamento coloca alguém entre você e seus amigos, e esse alguém
recebe três poderes:

| Poder              | Pergunta                                       | Propriedade de segurança |
|--------------------|------------------------------------------------|--------------------------|
| Ver                | Quem consegue assistir ao que eu transmito?    | Confidencialidade        |
| Alterar            | Quem consegue mexer no que chega aos outros?   | Integridade              |
| Desligar           | Quem consegue impedir que funcione?            | Disponibilidade          |

Esse trio (confidencialidade, integridade, disponibilidade) é a base de praticamente
qualquer análise de segurança (Kurose & Ross, 2021, Seção 8.1).

---

## O placar de confiança

Ao longo deste material, cada solução testada ganha uma linha nesta tabela.
A primeira é o próprio Discord:

| Solução | Quem carrega o vídeo  | Quem consegue ver         | Em quem você confia                                      | Custo  | Se cair...           |
|---------|-----------------------|---------------------------|----------------------------------------------------------|--------|----------------------|
| Discord | Servidores do Discord | Quem está no canal        | Uma empresa conhecida, com termos, política e endereço   | Grátis | Ninguém transmite    |

Guarde esse formato. Nos próximos módulos, ele vai ficando bem mais feio antes de melhorar.

---

## Discussão

- Quais serviços do seu dia a dia dependem de um único operador para funcionar?
  O que acontece com você se ele sair do ar amanhã?
- "Confiança" é binária? Dá para confiar em alguém para uma coisa (carregar bytes)
  e não para outra (ver o conteúdo)?
- Se você tivesse que escolher entre **confidencialidade** e **disponibilidade** numa watch
  party entre amigos, qual sacrificaria primeiro? E numa chamada de trabalho?

---

## Resumo

| Conceito                 | O que é                                                                 |
|--------------------------|-------------------------------------------------------------------------|
| Go Live                  | Transmissão de tela do Discord, suspensa no Brasil desde 17/08/2026     |
| Arquitetura centralizada | Todo o vídeo passa por um operador; simples, mas com um único interruptor |
| Confidencialidade        | Quem consegue ver                                                       |
| Integridade              | Quem consegue alterar                                                   |
| Disponibilidade          | Quem consegue desligar                                                  |
| Placar de confiança      | A tabela que acompanha cada solução daqui em diante                     |

---

## Próximo episódio

A galera não ia ficar sem watch party. O que veio a seguir foi criatividade pura,
disposição de sobra e segurança nenhuma.

---

## Referências deste módulo

- Discord (2026). *Por que os recursos de vídeo estão indisponíveis no Brasil no momento.* Central de Ajuda do Discord.
- Kurose & Ross (2021), Seção 8.1 - "What Is Network Security?"
- Shostack (2014), Cap. 1 - "Dive In and Threat Model!"
