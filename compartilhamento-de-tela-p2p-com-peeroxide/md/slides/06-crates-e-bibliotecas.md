# Módulo 06: Crates e Bibliotecas

---

## Objetivo

Conhecer **cada crate do workspace** e **cada biblioteca externa** que o Peeroxide usa,
organizadas por camada, com o motivo de cada escolha, incluindo as duas partes que
não são Rust: o decodificador **libde265** e o **OpenH264**, ambos compilados para dentro
do executável.

---

## Onde a gente parou

Vimos o que cada botão faz. Agora a pergunta é "com o quê". Um projeto de uma semana
só fica de pé apoiado no trabalho de muita gente, e escolher em quem se apoiar é, de novo,
uma decisão de confiança: cada dependência é código de terceiros rodando no seu PC.

---

## As crates do projeto

Um workspace Cargo (edição 2024 do Rust), com uma crate por responsabilidade (NFR-12):

```
                         ┌------------------┐
                         |  app (peeroxide) |  interface, controlador, pipelines
                         └--------+---------┘
      ┌-----------┬-----------┬---+-------┬------------┬------------┐
      v           v           v           v            v            v
┌----------┐┌----------┐┌----------┐┌-----------┐┌-----------┐┌----------┐
| capture  || codec    || audio    || net       || discovery || update   |
└----------┘└----+-----┘└----------┘└-----------┘└-----------┘└----------┘
                 v
           ┌------------┐
           | de265-sys  |  libde265 (C++), vendorizado
           └------------┘
```

| Crate        | Responsabilidade                                                                     |
|--------------|---------------------------------------------------------------------------------------|
| `capture`    | Listar e capturar monitores e janelas como quadros BGRA; padrão de teste sintético    |
| `codec`      | Canvas fixo (escala + tarjas); vídeo atrás das traits `VideoEncoder`/`VideoDecoder`; áudio atrás de `AudioEncoder`/`AudioDecoder` |
| `de265-sys`  | A libde265 1.1.3 vendorizada, compilada com `cc`, e bindings para a parte da API usada |
| `audio`      | Captura por processo (Windows), lista de apps tocando som, mixer, reprodução, agendador de sincronia |
| `net`        | Identidade, TLS (Transport Layer Security) 1.3 com fingerprint fixado sobre QUIC (transporte criptografado sobre UDP, User Datagram Protocol), protocolo, servidor e cliente |
| `discovery`  | Anúncio e busca via mDNS, com validação de anúncios não confiáveis                    |
| `update`     | Atualização automática: busca, download com limites, assinatura, troca do executável  |
| `app`        | O binário `peeroxide`: interface egui, controlador, máquina de estados do espectador, configurações, logs |

Trocar a interface ou o codec não encosta no código de rede. Cada crate é testada sozinha.

---

## Camada 1: interface

| Biblioteca       | Para quê                                                                  |
|------------------|---------------------------------------------------------------------------|
| `eframe` / `egui` | Interface em modo imediato, multiplataforma, com vários viewports (o mini player) |

O egui redesenha a interface inteira a cada quadro a partir do estado atual. Para um app
cuja tela principal é um vídeo mudando 60 vezes por segundo, isso é natural: não há estado
de widget para sincronizar.

---

## Camada 2: rede e identidade

| Biblioteca    | Para quê                                                                      |
|---------------|-------------------------------------------------------------------------------|
| `tokio`       | Runtime assíncrono: uma tarefa por espectador, timeouts, canais broadcast    |
| `quinn`       | Implementação de QUIC em Rust puro                                           |
| `rustls` + `ring` | TLS 1.3 em Rust; `ring` fornece a criptografia                           |
| `rcgen`       | Gera o certificado autoassinado de cada peer                                 |
| `sha2`        | SHA-256 (Secure Hash Algorithm) do certificado: o ID do peer                 |
| `postcard`    | Serialização compacta das mensagens de controle (`Hello`, `Welcome`)         |
| `strum`       | Enums com valor fixo no fio (close codes, tipos de stream, codecs) via `FromRepr` |
| `mdns-sd`     | Anúncio e busca mDNS (Multicast DNS, Domain Name System)                      |
| `if-addrs`    | Lista os adaptadores de rede para montar as connect strings                  |

O que o QUIC entrega aqui, em comparação com TCP (Transmission Control Protocol) + TLS:

- **Criptografia obrigatória**: não existe QUIC sem TLS 1.3.
- **Vários streams numa conexão**, sem bloqueio entre eles: um keyframe grande no stream de
  vídeo não atrasa o áudio, que vai no seu próprio stream.
- **Códigos de encerramento da aplicação** nativos: o motivo do fim viaja no próprio protocolo.
- **Uma porta UDP só**, fácil de liberar no firewall e de passar por uma rede virtual.

---

## Camada 3: captura

| Plataforma | Biblioteca          | API do sistema                                                   |
|------------|---------------------|------------------------------------------------------------------|
| Windows    | `windows-capture`   | WGC (Windows Graphics Capture): monitor ou janela, pela API do sistema |
| macOS      | `scap`              | ScreenCaptureKit                                                 |
| Linux      | `scap`              | PipeWire, via xdg-desktop-portal (o diálogo do sistema escolhe a fonte) |

A `scap` está fixada em `=0.0.8` porque o backend de Linux tem um problema conhecido
(pede RGBA ao PipeWire e entra em pânico se recebe), anotado no roadmap para ser corrigido
antes de declarar o Linux suportado.

`rayon` paraleliza as conversões de pixel que se dividem bem, num pool pequeno de propósito
(Módulo 04).

---

## Camada 4: vídeo

| Componente                 | Origem                                        | Linguagem | Papel                               |
|----------------------------|-----------------------------------------------|-----------|-------------------------------------|
| Codificador H.265          | Media Foundation (via crate `windows`), usando o codificador que o driver da placa fornece | Sistema | Codificar na GPU, Graphics Processing Unit (NVIDIA, AMD, Intel) |
| **libde265 1.1.3**         | Vendorizada em `crates/de265-sys`             | C++       | Decodificar H.265 (todas as plataformas) |
| **OpenH264**               | Crate `openh264`, compilada do código-fonte   | C/C++     | Codificar e decodificar H.264       |
| `yuv`                      | Crate                                         | Rust      | BGRA → I420 / NV12                  |
| `fast_image_resize`        | Crate                                         | Rust      | Escalar a captura para o canvas     |

Por que não FFmpeg? O requisito NFR-07 pede **um executável autocontido**, sem instalar
nada à parte. Tudo que decodifica vídeo vai compilado para dentro do `peeroxide.exe`;
o codificador H.265 vem com o driver da placa de vídeo, que já está instalado.

---

## A libde265 em detalhe

Decodificar H.265 em todas as plataformas exigia um decodificador embutido.
A escolha foi a **libde265**, e o jeito de integrá-la diz muito sobre o projeto:

- **Vendorizada** (copiada para o repositório) na versão 1.1.3, sem modificações.
- **Compilada com a crate `cc`**, sem CMake: o `build.rs` lista os mesmos arquivos-fonte
  que o `CMakeLists.txt` original e escreve o `config.h` que o CMake geraria.
- **Sem `bindgen`**: bindings escritos à mão, só para a parte da API que o codec usa
  (o `lib.rs` da crate tem 92 linhas).
- **Kernels SSE4.1** (Streaming SIMD Extensions, instruções vetoriais do x86) compilados com
  SSE4.1 habilitado; `x86/sse.cc` escolhe em tempo de execução. Os kernels AVX2/AVX-512
  (Advanced Vector Extensions) ficaram de fora (a libde265 só os habilita com GCC/Clang).
- **Otimizada até em build de debug**: sem otimização, ela decodifica ~2,5 vezes mais devagar
  (720p: 8,4 ms em vez de 3,2 ms por quadro).

```toml
# Cargo.toml do workspace
[profile.dev.package.peeroxide-de265-sys]
opt-level = 3
```

A libde265 é **LGPL-3.0**: a licença dela viaja junto com o executável, no
`THIRD-PARTY-NOTICES.txt` de cada release (Módulo 10).

---

## O OpenH264 em detalhe

O H.264 é o plano B: funciona em qualquer máquina, na CPU (Central Processing Unit).

- A crate `openh264` compila a biblioteca da Cisco **a partir do código-fonte**.
- Com o NASM (Netwide Assembler) no `PATH`, ela compila também o assembly SIMD
  (Single Instruction, Multiple Data: uma instrução operando sobre vários valores) e codifica bem mais rápido; sem ele, cai
  silenciosamente para C puro.
- Medido na CPU, a 1080p60 com a tela inteira de texto rolando (o pior caso): só 39 fps
  (21 ms por quadro), contra 5,8 ms por quadro do H.265 na GPU. Por isso o H.265 na GPU
  virou o padrão, e o H.264 ficou como plano B.

---

## Camada 5: áudio

| Biblioteca | Para quê                                                                            |
|------------|-------------------------------------------------------------------------------------|
| `opus-rs`  | Opus em **Rust puro**: sem C, sem CMake                                             |
| `wasapi`   | Captura por processo no Windows (*process loopback*) via WASAPI (Windows Audio Session API) |
| `cpal`     | Reprodução multiplataforma                                                          |
| `rtrb`     | Ring buffer sem locks entre o decodificador e a placa de som                        |
| `windows`  | Enumerar processos (para a lista de apps e as árvores de processos)                 |

A escolha do Opus em Rust puro é de segurança, não só de conveniência: um pacote de áudio
malformado vindo da rede cai num decodificador **sem código C**, rodando na própria thread,
com pânicos capturados. No pior caso, o áudio silencia; o vídeo continua (AC-09).
Ele sobreviveu a um teste com 5.000 pacotes de lixo.

---

## Camada 6: atualização

| Biblioteca       | Para quê                                                                  |
|------------------|---------------------------------------------------------------------------|
| `ureq`           | HTTP (Hypertext Transfer Protocol) síncrono, com `rustls` e o verificador de certificados do sistema |
| `minisign-verify` | Verifica a assinatura Ed25519 (minisign) de cada pacote                  |
| `self-replace`   | Substitui o executável que está rodando                                   |
| `zip` + `flate2` | Abre o pacote e extrai **só** o executável                                |
| `semver`         | Compara versões: só aceita estritamente mais nova                         |
| `serde_json`     | Lê a lista de releases da API do GitHub                                   |

O Módulo 08 conta como essas peças se juntam.

---

## Camada 7: infraestrutura

| Biblioteca              | Para quê                                                         |
|-------------------------|------------------------------------------------------------------|
| `clap`                  | Opções de linha de comando, com checagem de opções contraditórias |
| `serde` + `toml`        | `settings.toml` e `contacts.toml`                                |
| `directories`           | O diretório de dados certo em cada sistema                       |
| `gethostname`           | Nome padrão: o nome do computador                                |
| `tracing` + `tracing-appender` | Logs estruturados, com rotação diária                     |
| `anyhow` / `thiserror`  | Erros com contexto; tipos de erro só onde quem chama age sobre o tipo |
| `crossbeam`             | Canal para acordar o codificador; volume sem locks                |
| `winresource`           | (build) Ícone e detalhes de versão embutidos no `.exe`           |

Sobre erros: quase tudo retorna `anyhow::Result` com contexto ("lendo tal arquivo",
"abrindo tal socket") e é mostrado com `{e:#}`, a cadeia inteira de causas. Erros
tipados (`thiserror`) sobraram só onde quem chama decide algo pelo tipo:
`UpdateError` (qual aviso mostrar), `CaptureError` (fonte que sumiu encerra como "fechada",
não como falha) e `ProtocolError`.

---

## A regra geral: Rust onde der, C só onde precisa

| Parte                         | Linguagem    | Por quê                                              |
|-------------------------------|--------------|------------------------------------------------------|
| Rede, TLS, protocolo          | Rust         | É a parte exposta a qualquer um na rede              |
| Validação de anúncios         | Rust         | Entrada não confiável por definição                  |
| Opus                          | Rust         | Entrada não confiável; existe opção em Rust puro     |
| Decodificação de vídeo        | **C / C++**  | libde265 e OpenH264 são bibliotecas maduras em C/C++ |
| Codificação na GPU            | API do sistema | O driver da placa faz o trabalho                   |

O workspace inteiro compila com o lint `unsafe_code = "warn"`, e `unsafe` aparece em
apenas quatro arquivos, todos na fronteira com código de fora: os bindings da libde265,
o wrapper do decodificador H.265, o codificador via Media Foundation (COM, Component
Object Model) e a enumeração de processos do Windows.

> **A parte em C é exatamente o ponto fraco declarado:** um stream malicioso mirando
> um bug de memória no decodificador é o caso de abuso AC-09. O Módulo 07 volta nele.

---

## Licenças e patentes

| Componente    | Situação                                                                              |
|---------------|---------------------------------------------------------------------------------------|
| Peeroxide     | Apache-2.0                                                                            |
| libde265      | LGPL-3.0; a licença acompanha cada release                                            |
| OpenH264      | Compilado do código-fonte, o que **não** é coberto pela licença de patentes da Cisco (que vale só para o binário pré-compilado dela). Ok para uso pessoal; distribuição ampla pede o binário da Cisco (roadmap 0.9) |
| H.265         | Vários pools de patentes, sem equivalente à licença gratuita da Cisco. Os codificadores das GPUs são licenciados pelos fabricantes; o decodificador embutido, não. Ok para uso pessoal; distribuição ampla pede análise (roadmap 0.9) |

Documentado no README e no roadmap, sem letras miúdas.

---

## Discussão

- Vendorizar a libde265 facilita o build e garante a versão. Qual é o custo em
  manutenção de segurança?
- Um decodificador em Rust puro eliminaria o AC-09? Ou só reduziria a superfície?
- Quando vale a pena escrever bindings à mão em vez de usar `bindgen`?
- Por que é razoável deixar o tipo de erro genérico (`anyhow`) na maior parte do código?

---

## Resumo

| Camada          | Principais peças                                                   |
|-----------------|--------------------------------------------------------------------|
| Interface       | eframe / egui                                                      |
| Rede            | tokio, quinn, rustls + ring, rcgen, sha2, postcard, strum, mdns-sd |
| Captura         | windows-capture (WGC); scap (ScreenCaptureKit, PipeWire)           |
| Vídeo           | Media Foundation (H.265 na GPU), libde265 (C++), OpenH264, yuv, fast_image_resize |
| Áudio           | opus-rs (Rust puro), wasapi, cpal, rtrb                            |
| Atualização     | ureq, minisign-verify, self-replace, zip, semver                   |
| Infraestrutura  | clap, serde/toml, directories, tracing, anyhow/thiserror, crossbeam |

---

## Próximo episódio

Chegou a hora da pergunta do Módulo 01, agora aplicada ao próprio Peeroxide:
em quem você está confiando quando compartilha sua tela com ele? E, tão importante quanto,
onde ele **ainda não** merece essa confiança?

---

## Referências deste módulo

- Peeroxide, `Cargo.toml` do workspace e de cada crate; README - seção "Architecture"
- Peeroxide, `crates/de265-sys/vendor/VENDORED.md` e `crates/de265-sys/build.rs`
- Sullivan et al. (2012). *Overview of the HEVC Standard.*
- Valin, Vos & Terriberry (2012), RFC 6716 - Opus
- Iyengar & Thomson (2021), RFC 9000 - Seções 2 e 3 (streams)
