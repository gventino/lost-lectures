# Módulo 03: E se Fosse Descentralizado?

---

## Objetivo

Entender o que significa, de verdade, uma aplicação **peer-to-peer** e **sem servidor**,
o que o BitTorrent ensina sobre confiança, onde vídeo ao vivo é diferente de arquivo, e
quais são os **quatro problemas** que qualquer compartilhador de tela P2P precisa resolver.

---

## Onde a gente parou

Três gambiarras, três intermediários desconhecidos. Numa dessas noites, a pergunta
apareceu inteira na minha cabeça:

> Não existe nada **descentralizado, sem servidor, peer-to-peer**, tipo torrent, e **seguro**
> para fazer isso?

Procurei. Achei ferramentas de acesso remoto, apps que dependem de uma conta num serviço,
sites de watch party. Nada que juntasse as quatro palavras. Então comecei a pensar em
como seria.

---

## O que o torrent acertou

O BitTorrent (Cohen, 2003) distribui arquivos enormes sem que ninguém precise confiar
em quem está enviando.

```
                 ┌---------┐
        peça 3 ->| Peer A  |<- peça 1
       ┌-------->└---------┘-------┐
       |                           v
┌---------┐                   ┌---------┐
| Peer D  |<----- peça 2 -----| Peer B  |
└---------┘                   └---------┘
       ^                           |
       └---------┌---------┐<------┘
         peça 4  | Peer C  |  peça 1
                 └---------┘
```

1. O arquivo é dividido em **peças**.
2. O arquivo `.torrent` (ou o magnet link) traz o **hash** de cada peça.
3. Cada peça pode vir de **qualquer peer**, inclusive de um desconhecido.
4. Se o hash não bate, a peça é descartada e baixada de outro.

> **A integridade não depende de quem enviou. Depende de matemática.**
> Um peer malicioso pode no máximo desperdiçar sua banda; não consegue te entregar
> um arquivo alterado.

Guarde essa ideia. Ela é a espinha dorsal deste material.

---

## Como um peer encontra o outro

Distribuir sem servidor é metade do problema. A outra metade é **descoberta**:

| Mecanismo    | Como funciona                                                                | Centralizado? |
|--------------|-------------------------------------------------------------------------------|---------------|
| Tracker      | Um servidor que responde "quem mais tem este arquivo?"                       | Sim           |
| DHT (Distributed Hash Table) | Tabela de hash distribuída (Kademlia): cada peer guarda um pedaço do índice  | Não           |
| PEX (Peer Exchange) | Peers trocam listas de outros peers entre si                                 | Não           |
| Rede local   | Descoberta por multicast no mesmo segmento de rede                           | Não           |

A DHT baseada em Kademlia (Maymounkov & Mazières, 2002) é o que
permite a um magnet link funcionar sem tracker nenhum.

---

## Por que vídeo ao vivo não é um arquivo

A tentação é dizer "é só fazer um torrent da tela". Não é, por quatro motivos:

| Propriedade       | Arquivo via torrent                     | Tela ao vivo                                       |
|-------------------|-----------------------------------------|----------------------------------------------------|
| Existe antes?     | Sim, inteiro                            | Não: é criado quadro a quadro, agora               |
| Dá para ter hash prévio? | Sim, no `.torrent`               | Não: o conteúdo ainda não existe                   |
| Prazo             | Minutos ou horas, tanto faz             | ~150 ms, senão a conversa descola da imagem        |
| Fonte             | Muitos peers têm as peças              | Uma pessoa só tem a tela (1 → N)                   |

O segundo item é o mais importante. Sem hash prévio, a integridade não pode vir do
conteúdo. Ela precisa vir do **canal**: um canal autenticado, em que quem assiste tem
certeza de com quem está falando, e em que qualquer byte alterado no caminho é detectado.

> Trocar "confio no hash da peça" por "confio na chave de quem transmite" é a
> transição de torrent para compartilhamento de tela seguro.

---

## "Sem servidor" quer dizer o quê?

Sem servidor não significa "sem computadores". Significa:

- **Nenhum servidor meu (ou de terceiros) no caminho do vídeo.**
- **Nenhuma conta**, nenhum cadastro, nenhum login.
- **Nenhuma sala pública**: não existe um lugar onde desconhecidos encontram sua transmissão.

O vídeo vai do PC de quem transmite para o PC de quem assiste. Ponto.

---

## Os quatro problemas a resolver

Qualquer compartilhador de tela P2P precisa resolver:

| # | Problema                    | Pergunta                                            | Torrent                     |
|---|-----------------------------|-----------------------------------------------------|-----------------------------|
| 1 | Descoberta                  | Como eu acho quem está transmitindo?                | Tracker, DHT, PEX           |
| 2 | Identidade                  | Como eu sei que é quem diz ser?                     | Hash do conteúdo            |
| 3 | Transporte e codificação    | Como mover 30 a 60 quadros por segundo sem atraso?  | TCP (Transmission Control Protocol) ou uTP (Micro Transport Protocol), peças |
| 4 | Atravessar NAT (Network Address Translation) | Como chegar num PC atrás do roteador de casa? | UPnP (Universal Plug and Play), hole punching |

O NAT é o motivo de o seu PC não ter um endereço público:
o roteador compartilha um único IP entre todos os aparelhos da casa, e muitas operadoras
ainda colocam um segundo NAT por cima, o CGNAT (Carrier-Grade NAT). Ford, Srisuresh &
Kegel (2005) descrevem as técnicas clássicas para dois peers se falarem mesmo assim.

---

## Nasce o Peeroxide

O nome junta **peer** (par, como em peer-to-peer) com **oxide** (óxido, ferrugem:
o projeto é em Rust, e a comunidade Rust chama reescrever algo na linguagem de
"oxidar"). O logo é um píer enferrujado em pixel art ligando telas. Píer, peer: soa parecido, sacou?

Como o Peeroxide responde aos quatro problemas:

| # | Problema                 | Resposta do Peeroxide                                                             | Módulo |
|---|--------------------------|-----------------------------------------------------------------------------------|--------|
| 1 | Descoberta               | mDNS (Multicast DNS, Domain Name System) na rede local; *connect string* quando o multicast não chega | 04, 05 |
| 2 | Identidade               | ID = SHA-256 (Secure Hash Algorithm) do certificado; TLS (Transport Layer Security) 1.3 com o certificado fixado (*pinning*) | 07     |
| 3 | Transporte e codificação | QUIC (transporte criptografado sobre UDP, User Datagram Protocol), H.265 na GPU (Graphics Processing Unit) ou H.264 na CPU (Central Processing Unit), áudio em Opus | 04, 06 |
| 4 | Atravessar NAT           | Delegado a uma rede virtual: Radmin VPN, Hamachi ou, melhor, Headscale            | 11     |

---

## Sendo honesto: o Peeroxide não é um "torrent de vídeo"

Duas diferenças importantes em relação ao BitTorrent, e ambas são escolhas:

1. **Topologia em estrela, não enxame.** Quem transmite envia uma cópia para cada pessoa
   que assiste (até 8). Não há repasse entre espectadores. Mais simples, menor latência,
   e nenhum espectador vira intermediário da tela de outra pessoa.
2. **Sem DHT, sem descoberta global.** O Peeroxide só procura na rede local (ou na rede
   virtual em que você estiver). Não existe um índice mundial de transmissões. Isso
   é proposital: **ninguém de fora encontra sua tela por acaso**.

```
Enxame (torrent)                 Estrela (Peeroxide)

  A <---> B                              ┌--> Amigo 1
  ^ \   / ^                              |
  |   X   |               Quem transmite +--> Amigo 2
  v /   \ v                              |
  C <---> D                              └--> Amigo 3
```

O preço da estrela é o upload: 5 pessoas assistindo = 5 cópias saindo do seu PC.
O Módulo 04 faz essa conta.

---

## Antes do código, os requisitos

Antes da primeira linha de Rust, o projeto começou por documentos
([no repositório](https://github.com/gventino/peeroxide/tree/main/docs)):

| Documento                    | Exemplos                                                                                 |
|------------------------------|------------------------------------------------------------------------------------------|
| Requisitos funcionais (FR)   | FR-01 descoberta de peers; FR-06 assistir a uma transmissão por vez; FR-09 vários espectadores |
| Requisitos não funcionais (NFR) | NFR-01 latência abaixo de ~150 ms; NFR-08 descoberta sem configuração; NFR-10 confidencialidade; NFR-11 autenticidade |
| Casos de uso (UC)            | Transmitir, assistir, trocar de transmissão, atualizar                                   |
| Casos de abuso (AC)          | AC-01 a AC-13, organizados por STRIDE (Módulo 07)                                        |

---

## O placar de confiança

Antes de ver como ficou, vale escrever como **deveria** ser:

| Solução             | Quem carrega o vídeo              | Quem consegue ver                         | Em quem você confia                         | Custo                    | Se cair...                  |
|---------------------|-----------------------------------|-------------------------------------------|---------------------------------------------|--------------------------|-----------------------------|
| Discord             | Servidores do Discord             | Quem está no canal                        | Uma empresa conhecida                       | Grátis                   | Ninguém transmite           |
| VPN grátis          | Discord, via servidor de um estranho | + o operador da VPN                    | Um desconhecido anônimo                     | "Grátis"                 | Bloqueada pelo Discord      |
| Proxy do Equador    | Discord, via proxy público        | + o dono do proxy, para todos os apps     | Um desconhecido, com todo o seu tráfego     | "Grátis"                 | Some sem aviso              |
| Site com anúncio    | O site (talvez)                   | O site, e quem ele quiser                 | O site, os anunciantes e os scripts deles   | Sua atenção e seus dados | A sala acaba                |
| **O ideal**         | **Os PCs da galera, direto**      | **Só quem você escolher**                 | **Na sua rede, seja ela LAN (Local Area Network) ou VLAN (LAN virtual), e na criptografia**      | **Zero**                 | **Só aquela transmissão para** |

---

## Discussão

- O que você perde ao trocar a topologia em estrela por um enxame? E o que ganha?
- Descoberta global (DHT) seria útil para compartilhar tela entre amigos? Que riscos traria?
- O torrent protege integridade, mas não confidencialidade: qualquer peer do enxame sabe
  o que você está baixando. Isso importa para compartilhamento de tela?

---

## Resumo

| Conceito              | O que é                                                                  |
|-----------------------|--------------------------------------------------------------------------|
| Peer-to-peer          | Os dados vão direto entre os participantes                               |
| Sem servidor          | Nenhum intermediário no caminho do vídeo, nenhuma conta, nenhuma sala pública |
| Hash por peça         | Integridade que independe de quem enviou (torrent)                        |
| Canal autenticado     | Integridade para conteúdo que ainda não existe (vídeo ao vivo)            |
| DHT / Kademlia        | Descoberta descentralizada em escala global                               |
| NAT / CGNAT           | Por que seu PC não é alcançável diretamente pela internet                 |
| Estrela vs. enxame    | O Peeroxide envia uma cópia por espectador, sem repasse                   |

---

## Próximo episódio

Chega de teoria. No próximo módulo, a gente segue um único quadro do vídeo, do momento
em que alguém clica em **Start broadcasting** até ele aparecer na tela de um amigo.

---

## Referências deste módulo

- Cohen (2003). *Incentives Build Robustness in BitTorrent.*
- Maymounkov & Mazières (2002). *Kademlia.*
- Ford, Srisuresh & Kegel (2005). *Peer-to-Peer Communication Across Network Address Translators.*
- Kurose & Ross (2021), Seção 2.5 - "Peer-to-Peer File Distribution" e Seção 2.6 - "Video Streaming and Content Distribution Networks"
- Tanenbaum & Van Steen (2017), Seção 2.3 - "System architecture" (arquiteturas descentralizadas e P2P)
- Peeroxide, `docs/functional-requirements.md`, `docs/non-functional-requirements.md`, `docs/use-cases.md`
