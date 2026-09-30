# Módulo 02: As Gambiarras

---

## Objetivo

Analisar, uma por uma, as soluções improvisadas que a galera usou depois da suspensão,
desenhar **por onde o tráfego passa** em cada uma e responder, para cada caso,
**quem consegue ver, alterar e desligar**.

---

## Onde a gente parou

O Go Live sumiu, a voz ficou. A galera não desistiu: foi testando o que aparecia
pela frente. Ninguém aqui é bobo. Todo mundo só queria ver um filme junto.

Foram três episódios, cada um pior que o anterior.

> **Aviso:** nenhum site, IP ou serviço real é citado aqui. O ponto não é apontar dedo,
> é aprender a enxergar o caminho dos bytes.

---

## Episódio 1: a VPN grátis

Um amigo achou uma VPN (Virtual Private Network) grátis, dessas que aparecem em listas,
fóruns e lojas de apps, e a galera passou a usá-la para o Discord achar que estava fora
do Brasil.

```
┌-----------┐   túnel    ┌------------------------┐          ┌-----------┐
| PC da     |===========>| Servidor da VPN grátis |--------->| Discord   |
| galera    |            | dono: ???              |          |           |
└-----------┘            | logs: ???              |          └-----------┘
                         | modelo de negócio: ??? |
                         └------------------------┘
```

Funcionou, por um tempo. Até o Discord bloquear a VPN: ela continuava ligada, mas não
servia mais para o que a gente precisava.

---

## Episódio 1: quem vê o quê

Todo o tráfego que entra no túnel sai **pelo servidor de outra pessoa**. E, para isso,
a galera instalou um app de desconhecidos com acesso à rede inteira do PC.

| Poder    | Quem tem                     | Na prática                                                              |
|----------|------------------------------|-------------------------------------------------------------------------|
| Ver      | O operador da VPN            | Destinos, horários, volume; tudo que não estiver criptografado          |
| Alterar  | O operador da VPN            | Pode injetar ou redirecionar tráfego que não esteja protegido por TLS (Transport Layer Security) |
| Desligar | O operador da VPN, ou quem bloqueia a VPN | O Discord bloqueou, e ela parou de servir                  |

O que o TLS do Discord protege: o **conteúdo** das conexões
que já eram criptografadas. O que ele não protege: **quem você é, com quem fala e quando**.

E tem a pergunta que ninguém faz sobre serviço grátis de dono anônimo:
**qual é o modelo de negócio?** Revenda de banda, coleta de dados, máquina usada para outra
coisa. Você não sabe, e esse é o problema.

---

## Episódio 2: o proxy do Equador

Quando a VPN parou de servir, alguém achou uma lista de proxies públicos e configurou o
**proxy do sistema** do Windows (Configurações > Rede e Internet > Proxy) apontando para
um IP no Equador, com confidencialidade que, sendo generoso, era baixa.

```
┌-----------┐          ┌------------------------┐          ┌-----------┐
| Navegador |--------->| Proxy "no Equador"     |--------->| Discord   |
| Discord   |          | dono: ???              |          └-----------┘
| Banco     |--------->|                        |--------->┌-----------┐
| Email     |--------->|                        |--------->| Todo o    |
| Steam     |--------->|                        |--------->| resto     |
└-----------┘          └------------------------┘          └-----------┘
```

Repare no detalhe que muda tudo: o proxy do sistema não vale só para o Discord.
Ele vale para **qualquer programa que respeite a configuração do Windows**.
Navegador, banco, email, loja de jogos: tudo passa a sair por um desconhecido.

---

## Episódio 2: quem vê o quê

Um proxy HTTP (Hypertext Transfer Protocol) funciona de dois jeitos, e os dois contam coisas diferentes:

| Tipo de tráfego | Como passa pelo proxy                     | O que o dono do proxy vê                                    |
|-----------------|-------------------------------------------|-------------------------------------------------------------|
| HTTP puro       | O proxy lê e repassa a requisição inteira | **Tudo**: páginas, formulários, cookies; e pode alterar     |
| HTTPS           | Túnel via `CONNECT host:443`              | O nome do site (no `CONNECT` e no SNI, Server Name Indication), horários e volume |

Resumindo o placar do Episódio 2:

- **Ver:** a lista completa de sites que você visita, em todos os programas.
- **Alterar:** qualquer coisa em HTTP puro. Download sem HTTPS vira loteria.
- **Desligar:** a qualquer momento. Proxies públicos somem, mudam de dono e às vezes são
  máquinas comprometidas de terceiros.

> **O sinal vermelho definitivo:** se algum dia uma dessas soluções pedir para você
> **instalar um certificado** "para funcionar melhor", pare. Com um certificado raiz
> instalado, o intermediário consegue abrir e ler até o seu HTTPS. É um
> man-in-the-middle completo, com a sua assinatura embaixo.

---

## Episódio 3: o site cheio de anúncio

A última fase: um site de watch party e compartilhamento de tela direto no navegador.
Sem instalar nada, sem configurar nada. Só um pouquinho de anúncio. Ou muito.

```
┌-----------┐   página + JavaScript    ┌---------------------------┐
| Quem      |<-------------------------| Site de watch party       |
| transmite |                          |  - sala e convites        |
|           |---- tela (via site?) --->|  - anúncios de terceiros  |
└-----------┘                          |  - scripts de rastreio    |
                                       └---------------------------┘
┌-----------┐   página + JavaScript                 |
| Amigos    |<--------------------------------------┘
|           |<------------- tela ------------------ (direto? pelo servidor deles?)
└-----------┘
```

O navegador até pergunta o que você quer compartilhar, e essa parte é honesta.
O problema está em todo o resto da página.

---

## Episódio 3: quem vê o quê

| Risco                  | O que acontece                                                                 |
|------------------------|--------------------------------------------------------------------------------|
| Malvertising           | Anúncios que redirecionam para golpe ou tentam empurrar malware                |
| Botões falsos          | "Baixe o player", "Permita notificações", "Seu PC está infectado"              |
| Rastreamento           | Scripts de terceiros montando um perfil seu (fingerprinting)                   |
| Controle da sala       | Quem entra na sua sala é decidido pelo servidor do site, não por você          |
| Caminho do vídeo       | Pode ir direto entre navegadores ou passar pelos servidores do site; você não sabe |
| Código que muda        | O site entrega JavaScript novo **a cada visita**                               |

O último item é o mais sutil. Mesmo que hoje o vídeo vá direto entre vocês,
**confiar no site é confiar no JavaScript que ele entrega hoje, e no de amanhã**.
Uma linha diferente e sua tela vai para outro lugar.

---

## O placar de confiança

| Solução             | Quem carrega o vídeo              | Quem consegue ver                         | Em quem você confia                         | Custo                    | Se cair...                  |
|---------------------|-----------------------------------|-------------------------------------------|---------------------------------------------|--------------------------|-----------------------------|
| Discord             | Servidores do Discord             | Quem está no canal                        | Uma empresa conhecida                       | Grátis                   | Ninguém transmite           |
| VPN grátis          | Discord, via servidor de um estranho | + o operador da VPN (metadados e mais) | Um desconhecido anônimo                     | "Grátis"                 | Bloqueada pelo Discord      |
| Proxy do Equador    | Discord, via proxy público        | + o dono do proxy, **para todos os apps** | Um desconhecido, com todo o seu tráfego     | "Grátis"                 | Some sem aviso              |
| Site com anúncio    | O site (talvez)                   | O site, e quem ele quiser                 | O site, os anunciantes e os scripts deles   | Sua atenção e seus dados | A sala acaba                |

---

## O que as três têm em comum

As três gambiarras têm a mesma estrutura:

```
Você ---> [ intermediário que você não conhece ] ---> seus amigos
```

E a mesma falha: **toda a segurança depende da boa vontade de alguém que você não escolheu**.
Não existe nenhum mecanismo técnico impedindo o intermediário de olhar, mexer ou desligar.
Existe só a esperança de que ele não queira.

> A pergunta do Módulo 01 ("em quem você está confiando?") tinha, nos três casos,
> a mesma resposta: **"não sei"**.

---

## Discussão

- Já viu alguma dessas gambiarras em uso por seus amigos?
- Por que "é só para ver filme" não diminui o risco do proxy do sistema?
- Um site que é *open source* resolve o problema do "código que muda a cada visita"?
  O que mais seria necessário?
- Em qual das três você teria mais chance de perceber que algo deu errado?

---

## Resumo

| Conceito                  | O que é                                                                     |
|---------------------------|-----------------------------------------------------------------------------|
| VPN de terceiros          | Todo o tráfego sai pelo servidor de outra pessoa                            |
| Proxy do sistema          | Vale para todos os programas, não só para o que você queria                  |
| `CONNECT` e SNI           | Mesmo com HTTPS, o intermediário vê para quais sites você vai               |
| Certificado raiz instalado | Permite ler até o HTTPS; nunca instale um a pedido de um intermediário     |
| Malvertising              | Anúncio usado como vetor de golpe ou malware                                |
| Código entregue pelo site | O comportamento pode mudar a cada visita, sem você saber                    |

---

## Próximo episódio

Depois de mais uma noite fechando anúncio no meio do filme, a pergunta mudou de
"o que mais dá para usar?" para "por que isso precisa de um intermediário?".
Arquivos gigantes circulam há vinte anos sem um servidor no meio. Por que vídeo não?

---

## Referências deste módulo

- Kurose & Ross (2021), Seção 2.2 - "The Web and HTTP" (proxies e caches) e Seção 8.6 - "Securing TCP Connections: TLS"
- Rescorla (2018), RFC 8446 - TLS 1.3 (o que o handshake protege e o que fica visível)
- Shostack (2014), Cap. 3 - "STRIDE"
