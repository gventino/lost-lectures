# Módulo 04: De Ponta a Ponta

---

## Objetivo

Seguir **um quadro do vídeo** (e um pedaço do áudio) desde o clique em
**Start broadcasting** até a tela de um amigo: descoberta, conexão, protocolo,
os dois pipelines, sincronia de áudio, recuperação de atraso e fim de sessão.

---

## Onde a gente parou

Já sabemos os quatro problemas (descoberta, identidade, transporte e atravessar o NAT,
Network Address Translation) e como o Peeroxide
responde a cada um, no papel. Agora é código rodando.

Personagens deste módulo: **Alice**, que transmite, e **Bob**, que assiste. São os nomes dos
perfis de demonstração do próprio projeto (`just demo`), não da galera.

---

## O mapa completo

```
ALICE (transmite)                                      BOB (assiste)
|                                                                  |
| 1. identidade (certificado + chave)                              |
| 2. porta UDP fixa (ex.: 57728)                                   |
| -------------- 3. anúncio mDNS --------------------------------> |
|    _peeroxide._udp.local.  v=1  name=Alice  fp=<64 hex>          |
|                                                                  |
| <------------- 5. handshake QUIC + TLS 1.3 --------------------- |
| <------------- 6. Hello { versão 3, "Bob" } -------------------- |
| -------------- 7. Welcome { "Alice", áudio: sim } -------------> |
| 8. primeiro espectador: captura e codificação ligam              |
| -------------- 9. stream de áudio (tipo 1) --------------------> |
| -------------- 10. stream de vídeo (tipo 0) -------------------> |
| <------------- RequestKeyframe (quando precisar) --------------- |
|                               ...                                |
| -------------- 11. close code: BroadcastStopped ---------------> |
```

Do lado do Bob: (1) carrega a própria identidade; (4) "Alice 7ECA-C3F0" aparece
na lista, com o anúncio validado; (5) confere SHA-256(cert) == fp; (9) toca o
áudio com atraso calculado; (10) começa num keyframe; (11) mostra "Alice parou
de transmitir".

Vamos passo a passo.

---

## Passos 1 e 2: identidade e porta

Na primeira execução, cada instância gera um **certificado autoassinado** e uma chave
privada, e guarda os dois no diretório de dados (`identity.cert.der`, `identity.key.der`).

- O **ID** de cada peer é o SHA-256 (Secure Hash Algorithm) desse certificado.
  A forma curta, mostrada na interface, são os 8 primeiros dígitos hexadecimais: `7ECA-C3F0`.
- O certificado não vence e não depende de nenhuma autoridade certificadora.
  Ele é a identidade. Apagar os arquivos cria um ID novo.

A porta UDP (User Datagram Protocol) de transmissão é sorteada na primeira vez e depois
**reaproveitada** (`broadcast_port` no `settings.toml`). Assim, um endereço compartilhado
com um amigo continua valendo depois de reiniciar o app.

---

## Passo 3: anunciando no mDNS

O mDNS (Multicast DNS, a versão por multicast do DNS, Domain Name System; RFC 6762) é o mesmo mecanismo que faz impressoras e Chromecasts
aparecerem sozinhos na rede. Com o DNS-SD (DNS-Based Service Discovery, RFC 6763), um
programa anuncia "existe um serviço deste tipo, neste endereço e porta, com estes atributos".

O anúncio do Peeroxide:

| Campo              | Valor                                   | Para quê                                        |
|--------------------|-----------------------------------------|-------------------------------------------------|
| Tipo de serviço    | `_peeroxide._udp.local.`                | Só instâncias do Peeroxide se enxergam          |
| Instância          | 16 primeiros hex do fingerprint         | Nomes únicos mesmo com apelidos repetidos       |
| Porta              | A porta UDP fixa                        | Onde conectar                                   |
| TXT `v`            | `1`                                     | Versão do formato do anúncio                    |
| TXT `name`         | Nome de exibição, sanitizado            | O que aparece na lista                          |
| TXT `fp`           | SHA-256 completo do certificado (64 hex) | **O que a conexão vai exigir**                 |

> **Detalhe importante:** o peer só é anunciado **enquanto está transmitindo** (AC-06).
> Quem só assiste é invisível na rede.

---

## Passo 4: quem ouve, desconfia

O mDNS não tem autenticação: qualquer aparelho na rede pode anunciar qualquer coisa.
Então Bob trata cada anúncio como **entrada não confiável** (AC-08):

- versão diferente de `1`: descartado;
- `fp` que não tem exatamente 64 dígitos hexadecimais: descartado;
- porta zero: descartado;
- endereços: só IPv4;
- nome: sanitizado e limitado;
- no máximo **64 peers** na tabela; o resto é ignorado.

E o mais importante: o anúncio **só aponta** para um fingerprint. Quem garante que
do outro lado está mesmo o dono daquele fingerprint é o passo 5.

---

## Passo 5: QUIC com o certificado fixado

Bob abre uma conexão QUIC (RFC 9000) com Alice. QUIC roda sobre UDP e já nasce com
TLS 1.3 (Transport Layer Security, RFC 8446) embutido (RFC 9001): não existe QUIC sem criptografia.

Não há autoridade certificadora. Em vez disso, Bob **fixa** (*pinning*) o certificado:

1. Alice apresenta o certificado dela no handshake.
2. Bob calcula `SHA-256(certificado)` e compara com o `fp` do anúncio (ou da connect string).
3. Se for diferente: handshake abortado, **"Identity check failed"**.
4. Se for igual, o TLS ainda exige que Alice **assine** o handshake com a chave privada
   daquele certificado. Copiar o certificado de alguém não basta: é preciso ter a chave.

O Módulo 07 mostra o código. Por ora, o que importa:
**a partir daqui, tudo que trafega é cifrado e autenticado.**

---

## Passos 6 e 7: o protocolo de controle

Bob abre um stream bidirecional de controle. As mensagens são curtas, serializadas com
`postcard` e prefixadas pelo tamanho:

```
Bob   -> Alice:  Hello { version: 3, viewer_name: "Bob" }
Alice -> Bob:    Welcome { broadcaster_name: "Alice", audio: true }
Bob   -> Alice:  RequestKeyframe            (sempre que precisar)
```

- **`version`**: o protocolo está na versão 3 (a 2 trouxe áudio, a 3 trouxe H.265).
  Versões incompatíveis recebem uma mensagem clara, não um erro obscuro de handshake:
  o identificador ALPN (Application-Layer Protocol Negotiation), `peeroxide/1`, nunca
  muda justamente para que peers antigos cheguem até a checagem de versão.
- **`audio`**: fixo para a transmissão inteira; Bob já sabe se deve esperar um stream de áudio.
- **Lotação**: se Alice já tem 8 espectadores, a conexão é fechada com o código `Busy`.

---

## Passo 8: só captura quando alguém assiste

Enquanto ninguém está assistindo, **nada é capturado nem codificado**.
Transmitir sem espectador custa praticamente zero de CPU (Central Processing Unit)
e, de quebra, não existe tela capturada "à toa" na memória.

Quando Bob chega, a captura liga e o codificador recebe um pedido de **keyframe**.

> Um **keyframe** (quadro-chave, ou IDR, Instantaneous Decoder Refresh) é um quadro
> completo, decodificável sozinho. Os quadros seguintes guardam só **diferenças** em
> relação aos anteriores. Por isso, um espectador só consegue começar a assistir a partir
> de um keyframe.

---

## O pipeline de quem transmite

```
┌-----------┐   ┌--------------┐   ┌---------------------------------------┐
| Captura   |-->| Slot "último |-->| Thread do codificador                 |
| (thread   |   | quadro"      |   |  canvas (escala + letterbox)          |
| própria)  |   | (só o mais   |   |  -> NV12 -> H.265 na GPU              |
└-----------┘   | recente)     |   |  ou -> I420 -> H.264 (OpenH264, CPU)  |
                └--------------┘   └------------------┬--------------------┘
                                                      v
                         ┌--------------------------------------------┐
                         | Canal broadcast (Tokio), buffer de 30      |
                         └------┬-------------------┬-----------------┘
                                v                   v
                        ┌---------------┐   ┌---------------┐
                        | Tarefa do Bob |   | Tarefa do ... |   uma por espectador
                        └-------┬-------┘   └-------┬-------┘
                                v                   v
                        stream QUIC unidirecional  (tipo 0 = vídeo)
```

- **Slot "último quadro":** se o codificador estiver ocupado, quadros antigos são
  substituídos, não enfileirados. Fila de vídeo ao vivo é atraso acumulado.
- **Canvas fixo:** o tamanho é decidido quando a captura começa. Redimensionar a janela
  compartilhada gera tarjas (*letterbox*), não uma mudança de resolução no meio do stream.
- **NV12 e I420** são formatos YUV (luminância + crominância) que os codificadores esperam;
  a captura entrega BGRA (azul, verde, vermelho, alfa).

---

## Cada quadro no fio

Cada quadro de vídeo viaja com um cabeçalho fixo de 22 bytes (little-endian),
seguido do vídeo codificado em formato Annex-B:

| Bytes   | Campo            | Para quê                                                   |
|---------|------------------|------------------------------------------------------------|
| 0..8    | `seq`            | Número de sequência                                        |
| 8..16   | `capture_time_us`| Instante da captura, em microssegundos, no relógio de Alice |
| 16      | `keyframe`       | 1 se é um quadro-chave                                     |
| 17..21  | `len`            | Tamanho do quadro (rejeitado acima de 8 MiB, antes de alocar) |
| 21      | `codec`          | 0 = H.264, 1 = H.265                                       |

O codec viaja **em todo quadro**, não uma vez por sessão. Se o codificador da GPU (Graphics
Processing Unit) falhar
no meio da transmissão, Alice troca para H.264 e Bob troca de decodificador no próximo
keyframe, sem reconectar.

---

## O pipeline de quem assiste

```
stream QUIC --> fila limitada (8) --> thread do decodificador
 (vídeo)                              H.265 (libde265) ou H.264 (OpenH264)
                                      -> imagem RGBA já pronta
                                                  |
                                                  v
                                      slot "último quadro"
                                                  |
                                                  v
                                      textura na GPU (a thread da
                                      interface só faz upload)
```

A imagem RGBA é montada **na thread do decodificador**. A thread da interface (egui) só
envia a textura para a GPU. Resultado: a interface continua
fluida mesmo decodificando 1080p a 60 quadros por segundo (NFR-09).

---

## O áudio, e o problema dos dois relógios

O áudio segue um caminho paralelo:

```
captura (WASAPI loopback) -> quadros de 20 ms -> Opus
   (128 kbps; 64 kbps no preset Internet)
   -> canal broadcast -> stream QUIC próprio (tipo 1), enviado ANTES do vídeo
   -> fila -> decodificador Opus -> agendador de reprodução
   -> ring buffer -> placa de som
```

Cada pacote de áudio tem um cabeçalho de 18 bytes: `seq`, `capture_time_us` e o tamanho
(no máximo 4 KiB). O WASAPI (Windows Audio Session API) é a API de áudio do Windows.

**O problema:** como tocar o áudio em sincronia com o vídeo, se os relógios de Alice e
de Bob não concordam? (Se você leu a aula de
[Ordenação Causal](../../ordenacao-causal-em-sistemas-distribuidos/), já sabe: relógios de
máquinas diferentes nunca concordam.)

---

## A diferença que se cancela

Seja `Δ` a diferença desconhecida entre os relógios de Bob e de Alice. Para o vídeo que está
na tela e para o áudio que acabou de chegar, Bob calcula:

```
atraso_video = t_Bob(exibição) - t_Alice(captura) = d_video + Δ
atraso_audio = t_Bob(chegada)  - t_Alice(captura) = d_audio + Δ

atraso_video - atraso_audio = d_video - d_audio       <-- Δ some
```

Bob não sabe `Δ`, e não precisa: a **diferença** entre os dois atrasos não depende dele.

Com isso, o agendador **atrasa o áudio, nunca o vídeo**, até alinhar os dois, somando uma
margem de pelo menos **40 ms** contra variação de rede (*jitter*). Deriva e buracos são
absorvidos com pequenos saltos ou silêncios. A meta (NFR-13) segue os limites de percepção
da ITU-R BT.1359: áudio entre ~45 ms adiantado e ~125 ms atrasado em relação à imagem.

Medido com o padrão de teste na mesma máquina: o áudio toca ~64 ms depois do vídeo
(20 ms do quadro Opus + 40 ms de margem).

---

## Quando alguém fica para trás

Se a rede de Bob engasga, a tarefa dele fica atrasada em relação ao canal broadcast.
Em vez de acumular atraso, ela **pula para o próximo keyframe** (trecho real de
`crates/net/src/server.rs`):

```rust
Err(broadcast::error::RecvError::Lagged(skipped)) => {
    tracing::debug!(skipped, "viewer lagging; skipping to next keyframe");
    waiting_for_keyframe = true;
    (shared.on_keyframe)();   // pede um keyframe ao codificador
}
```

Keyframes são produzidos **sob demanda**: quando um espectador entra, quando fica para
trás, ou quando relata erro de decodificação. Nada de keyframe a cada N segundos
gastando banda à toa.

> Um espectador lento nunca atrasa os outros: cada um tem a sua tarefa e o seu stream.

---

## Passo 11: como uma sessão termina

O motivo do fim viaja como **código de encerramento da aplicação** no QUIC:

| Código | Nome               | O que Bob vê                                     |
|--------|--------------------|--------------------------------------------------|
| 0      | `ViewerLeft`       | (Bob saiu por conta própria)                     |
| 1      | `BroadcastStopped` | Alice parou de transmitir                        |
| 2      | `SourceClosed`     | "The shared window was closed"                   |
| 3      | `Busy`             | Lotado (8 espectadores)                          |
| 4      | `VersionMismatch`  | "incompatible version"                           |
| 5      | `ProtocolError`    | Algo chegou malformado                           |

Esses números **nunca mudam**: peers antigos dependem deles.

E se Alice simplesmente travar ou perder a conexão? O QUIC envia keep-alive a cada 1 s e
desiste após 5 s de silêncio. Bob volta para a lista em ~6 s.

---

## Quem roda onde

| Trabalho                        | Onde roda                                               |
|---------------------------------|---------------------------------------------------------|
| Captura de vídeo                | Thread própria                                          |
| Codificação de vídeo            | Thread própria (acordada via canal `crossbeam` quando pausada) |
| Codificação de áudio            | Thread própria                                          |
| Decodificação de vídeo          | Thread própria, que também monta a imagem RGBA          |
| Decodificação de áudio          | Thread própria                                          |
| Rede (QUIC, mDNS)               | Runtime Tokio                                           |
| Conversões de pixel paralelizáveis | Pool `rayon` dimensionado: 1 thread no Windows, 2 nos outros |
| Interface                       | Thread principal (egui)                                 |

Por que um pool `rayon` tão pequeno? Porque o padrão (uma thread por núcleo) **gastava mais
CPU do que economizava** em tarefas de poucos milissegundos. Compartilhar uma janela caiu de
68–100% para 29–36% de um núcleo depois do ajuste.

---

## Os números

Medidos na máquina de desenvolvimento (Windows 11, CPU de 12 threads, Radeon RX 6600),
com as duas pontas na mesma máquina:

| Cenário                                     | Resultado                                        |
|---------------------------------------------|--------------------------------------------------|
| Captura → quadro decodificado               | 5 ms (padrão de teste), 15–18 ms (monitor), ~40 ms (janela) |
| Descoberta → assistindo                     | ~1,3 s depois de abrir o app                     |
| Transmissão 1080p30 de monitor              | 3,9% da CPU total para quem transmite; 2,3% para quem assiste |
| Codificação 1080p60 H.265 (pior caso)       | 5,8 ms por quadro, a 5,3 Mbps                    |
| Decodificação H.265 1080p (uma thread)      | 8–9 ms                                           |
| Alice para → Bob avisado                    | ~2 ms (normal), ~6 s (travamento)                |

---

## A conta do upload

Na topologia em estrela, quem transmite envia **uma cópia por espectador**. O teto de cada
preset, só de vídeo:

| Preset                       | Teto de vídeo | 3 espectadores | 5 espectadores | 8 espectadores |
|------------------------------|---------------|----------------|----------------|----------------|
| Internet / VPN · 720p · 24 fps | 2 Mbps      | 6 Mbps         | 10 Mbps        | 16 Mbps        |
| 720p · 30 fps                | 4 Mbps        | 12 Mbps        | 20 Mbps        | 32 Mbps        |
| 1080p · 60 fps               | 12 Mbps       | 36 Mbps        | 60 Mbps        | 96 Mbps        |

São tetos: o H.265 envia bem menos quando a imagem é simples (texto rolando no preset
Internet ficou em 1,2 Mbps). Mas planeje pelo teto. Numa rede local, sobra banda.
Pela internet, o upload de casa decide: é por isso que existe o preset **Internet / VPN**.

---

## Discussão

- Por que "atrasar o áudio, nunca o vídeo"? O que aconteceria no caminho inverso?
- O slot "último quadro" descarta quadros de propósito. Em que tipo de conteúdo isso
  seria inaceitável?
- Keyframe sob demanda economiza banda. Qual é o custo quando muitos espectadores entram
  ao mesmo tempo?
- A técnica da "diferença que se cancela" funcionaria se o relógio de Alice andasse mais
  rápido que o de Bob (deriva, não só diferença fixa)? O que o agendador precisa fazer?

---

## Resumo

| Conceito                 | O que é                                                                  |
|--------------------------|--------------------------------------------------------------------------|
| Identidade               | Certificado autoassinado; ID = SHA-256 do certificado                    |
| Anúncio mDNS             | `_peeroxide._udp.local.` com o fingerprint no TXT, só enquanto transmite |
| Pinning                  | A conexão só completa se o certificado bater com o fingerprint esperado  |
| Hello / Welcome          | Versão, nome e se há áudio                                               |
| Slot "último quadro"     | Descartar em vez de enfileirar: latência baixa                           |
| Keyframe sob demanda     | Ao entrar, ao atrasar, ao errar                                          |
| Sincronia A/V            | Atrasar o áudio usando a diferença de atrasos, onde o offset de relógio se cancela |
| Close codes              | O motivo do fim da sessão, com números que nunca mudam                   |

---

## Próximo episódio

Agora que o quadro chegou do outro lado, vamos olhar para o que a galera realmente usa:
cada botão, cada caixinha, e o que acontece por trás de cada um.

---

## Referências deste módulo

- Peeroxide, README - seções "Architecture" e "Performance"
- Peeroxide, `crates/net/src/protocol.rs`, `server.rs`, `client.rs`; `crates/discovery/src/lib.rs`
- Iyengar & Thomson (2021), RFC 9000 - QUIC; Thomson & Turner (2021), RFC 9001 - QUIC-TLS
- Cheshire & Krochmal (2013), RFC 6762 e RFC 6763 - mDNS e DNS-SD
- ITU-R (1998), BT.1359 - sincronia entre som e imagem
- Sullivan et al. (2012) - estrutura de quadros do HEVC (High Efficiency Video Coding)
