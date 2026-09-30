# Diagramas de Referência

> Todos os diagramas do material num lugar só, para projeção ou desenho no quadro.

---

## 1. O caminho do vídeo no Discord (Módulo 01)

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

Um operador no meio: um único interruptor.
```

---

## 2. As três gambiarras (Módulo 02)

```
VPN grátis:
  PC da galera ===túnel===> [ VPN de dono desconhecido ] ---> Discord
    vê: destinos, horários, volume, tudo sem TLS

Proxy do Equador (proxy do sistema):
  navegador, banco, email, Steam ---> [ proxy público ] ---> internet
    vê: todos os sites (CONNECT, SNI); lê e altera HTTP puro

Site cheio de anúncio:
  quem transmite <--- página + JS + anúncios ---> [ site ] <--- amigos
    decide: quem entra na sala, que código roda, por onde vai o vídeo

Em comum:  você ---> [ intermediário que você não escolheu ] ---> seus amigos
```

---

## 3. Enxame vs. estrela (Módulo 03)

```
Enxame (torrent)                 Estrela (Peeroxide)

  A <---> B                              ┌--> Amigo 1
  ^ \   / ^                              |
  |   X   |               Quem transmite +--> Amigo 2
  v /   \ v                              |
  C <---> D                              └--> Amigo 3   (até 8)

Integridade por hash de peça      Integridade por canal autenticado
Muitas fontes                     Uma fonte: upload = N x bitrate
```

---

## 4. De ponta a ponta (Módulo 04)

```
ALICE (transmite)                                      BOB (assiste)
|                                                                  |
| 1. identidade (certificado + chave)                              |
| 2. porta UDP fixa (ex.: 57728)                                   |
|                                                                  |
| -------------- 3. anúncio mDNS --------------------------------> |
|    _peeroxide._udp.local.  v=1  name=Alice  fp=<64 hex>          |
|                                              4. valida o anúncio |
|                                                                  |
| <------------- 5. handshake QUIC + TLS 1.3 --------------------- |
|                                      confere SHA-256(cert) == fp |
|                                                                  |
| <------------- 6. Hello { versão 3, "Bob" } -------------------- |
|                                                                  |
| -------------- 7. Welcome { "Alice", áudio: sim } -------------> |
|                                                                  |
| 8. primeiro espectador: captura e codificação ligam              |
|                                                                  |
| -------------- 9. stream de áudio (tipo 1) --------------------> |
|                                                                  |
| -------------- 10. stream de vídeo (tipo 0) -------------------> |
|                                                                  |
| <------------- RequestKeyframe (quando precisar) --------------- |
|                                                                  |
|                               ...                                |
|                                                                  |
| -------------- 11. close code: BroadcastStopped ---------------> |
```

---

## 5. Pipeline de quem transmite (Módulo 04)

```
captura --> slot "último quadro" --> thread do codificador
                                      canvas -> NV12 -> H.265 (GPU)
                                      canvas -> I420 -> H.264 (CPU)
                                              |
                                              v
                              canal broadcast (Tokio, 30 quadros)
                                 |            |            |
                              tarefa       tarefa       tarefa   (uma por
                                                                  espectador)
                                 |            |            |
                              stream QUIC unidirecional por espectador

Espectador atrasado (Lagged) --> espera o próximo keyframe e pede um novo
```

---

## 6. Pipeline de quem assiste (Módulo 04)

```
stream QUIC --> fila (8) --> thread do decodificador --> slot "último quadro"
                              H.265 (libde265)           (imagem RGBA pronta)
                              H.264 (OpenH264)                   |
                                                                 v
                                            textura na GPU (thread da interface)

stream de áudio --> fila --> Opus --> agendador (atrasa o áudio)
                --> ring buffer --> placa de som
```

---

## 7. A conta que dispensa relógios sincronizados (Módulo 04)

```
Δ = diferença desconhecida entre os relógios de Bob e de Alice

atraso_video = t_Bob(exibição) - t_Alice(captura) = d_video + Δ
atraso_audio = t_Bob(chegada)  - t_Alice(captura) = d_audio + Δ
                                                   ---------------
atraso_video - atraso_audio                      = d_video - d_audio

Ação: atrasar o áudio (nunca o vídeo) + margem de jitter >= 40 ms
```

---

## 8. Handshake com certificado fixado (Módulo 07)

```
Bob sabe: fp esperado (do anúncio, da connect string ou do contato salvo)

Alice --- Certificate (cert) -----------------------> Bob
                                                     SHA-256(cert) == fp ?
                                                     não: "Identity check failed"
Alice --- CertificateVerify (assinado c/ a chave) --> Bob
                                                     assinatura válida?
                                                     não: handshake abortado
Alice <== canal QUIC + TLS 1.3 (AEAD) =============> Bob

Copiar o certificado não basta: é preciso ter a chave privada.
```

---

## 9. Atualização segura (Módulo 08)

```
abrir o app
   |
   v
GET releases (HTTPS, <= 1 MiB) --falha--> abre normalmente em ~5 s
   |
   v
escolher: não-rascunho, versão > atual, zip + .minisig da plataforma
   |                                        --nada--> "up to date"
   v
baixar .minisig (<= 4 KiB) e zip (<= 200 MiB, tamanho exato)  [Skip]
   |
   v
minisign com a chave embutida + comentário "file:<nome exato>"
   |                                        --falha--> descarta, avisa
   |
   v
extrair SÓ o executável (um e só um), para um caminho escolhido pelo app
   |
   v
self-replace --> reiniciar com as mesmas opções --> "Updated to X.Y.Z"
```

---

## 10. Do código ao release (Módulo 10)

```
main (docs em dia) --> subir versão --> just check --> just package
                                                            |
                          build release, zip, quickstart c/ commit,
                          avisos (LGPL da libde265), assinatura minisign
                                                            |
                                                            v
                                     smoke test: transmitir e assistir,
                                     com som, usando o exe de dist/
                                                            |
                                                            v
                           just serve-release: um GitHub de mentira;
                           a versão antiga se atualiza sozinha?
                                                            |
                                                            v
          just publish <-- notas + checksums <-- tag <------┘
          (gh release create --verify-tag --prerelease)

Linux: o mesmo, com o build dentro de um contêiner Debian bookworm.
```

---

## 11. Plano de controle vs. plano de dados (Módulo 11)

```
                  ┌-------------------------------------┐
                  |  VPS: Headscale                     |
                  |   quem está na rede, chaves,        |
                  |   política, DERP (último recurso)   |
                  └-------+---------------------+-------┘
       controle (pequeno) |                     | controle (pequeno)
                  ┌-------v-------┐     ┌-------v-------┐
                  |  PC da Alice  |=====|   PC do Bob   |
                  |  100.64.0.1   |     |   100.64.0.2  |
                  └---------------┘     └---------------┘
                     dados: WireGuard direto (o vídeo vai aqui)
```

---

## 12. As camadas de um quadro na internet (Módulo 11)

```
┌--------------------------------------------------------------------------┐
| UDP pela internet: IP público de casa -> IP público do amigo             |
|  ┌--------------------------------------------------------------------┐  |
|  | WireGuard: cifrado com as chaves dos dois PCs                      |  |
|  |  ┌--------------------------------------------------------------┐  |  |
|  |  | UDP 100.64.0.1 -> 100.64.0.2, porta do Peeroxide             |  |  |
|  |  |  ┌--------------------------------------------------------┐  |  |  |
|  |  |  | QUIC + TLS 1.3, certificado de quem transmite fixado   |  |  |  |
|  |  |  |  ┌--------------------------------------------------┐  |  |  |  |
|  |  |  |  | H.265 / H.264 + Opus                             |  |  |  |  |
|  |  |  |  └--------------------------------------------------┘  |  |  |  |
|  |  |  └--------------------------------------------------------┘  |  |  |
|  |  └--------------------------------------------------------------┘  |  |
|  └--------------------------------------------------------------------┘  |
└--------------------------------------------------------------------------┘

VPS invadida: tira o WireGuard, encontra QUIC/TLS fixado. Não lê, não altera,
não se passa por quem transmite. Pode entrar como mais um espectador (AC-02,
até a 0.7).
```
