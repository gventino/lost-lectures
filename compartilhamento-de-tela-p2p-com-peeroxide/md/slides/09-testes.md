# Módulo 09: Testes

---

## Objetivo

Conhecer as camadas de teste do Peeroxide: os **testes automatizados** (inclusive sessões
QUIC reais), o **CI** (Continuous Integration) em três sistemas, os **testes de hardware**
que o CI não consegue rodar, as **ferramentas de diagnóstico**, o **checklist manual** e o
**smoke test** que antecede cada release. E, com a mesma honestidade do Módulo 07, o que
ainda não foi verificado.

---

## Onde a gente parou

A atualização assinada garante que o código que chega na galera é meu. Mas ela tem um efeito
colateral: **um release ruim chega em todo mundo na próxima vez que abrirem o app**.
O `docs/releasing.md` diz isso sem rodeio: *"Only publish what you have tested."*

Então: o que exatamente é testado, e como?

---

## A pirâmide de testes

```
                  ┌-------------------------┐
                  |   Smoke test do release |  o executável do zip, de verdade
                  └-------------------------┘
              ┌-------------------------------------┐
              |   Checklist manual (duas máquinas,  |
              |   Radmin VPN, áudio, mini player)   |
              └-------------------------------------┘
         ┌-----------------------------------------------┐
         |  Testes de hardware: `just test-hw`           |
         |  (GPU, H.265, medições de tempo)              |
         └-----------------------------------------------┘
    ┌---------------------------------------------------------┐
    |  166 testes automatizados: `cargo test --workspace`     |
    |  (inclui sessões QUIC reais em localhost)               |
    └---------------------------------------------------------┘
```

Quanto mais alto, mais caro, mais raro e mais perto do uso real.

---

## A base: 166 testes automatizados

O que eles cobrem, agrupado:

| Área                  | Exemplos                                                                              |
|-----------------------|---------------------------------------------------------------------------------------|
| Protocolo             | Entrada malformada e grande demais, codecs desconhecidos, valores fixos dos close codes, tipos de stream e codecs |
| Identidade            | Persistência da identidade, rejeição de fingerprint                                   |
| **Sessões QUIC reais** | Ordem dos quadros, começar pelo keyframe, motivos de fim, lotação, versão incompatível (inclusive peers 0.3), espectador atrasado, troca de transmissão, peer inalcançável |
| Áudio pela rede       | Em ordem ao lado do vídeo; ausente quando não compartilhado; stream de áudio quebrado **sem derrubar o vídeo** |
| Opus                  | Ida e volta (níveis, estéreo, silêncio), pacotes de lixo, ocultação de perda          |
| Silenciar apps        | Agrupar sessões de áudio por app, quais processos capturar, padrões de apps de voz, o mixer (somas, jitter, buracos, atrasos, limites) |
| Sincronia             | Agendador de reprodução: margem, vídeo mais lento e mais rápido, teto de 200 ms, deriva, buracos |
| Descoberta            | Validação de anúncios, teto da tabela de peers, uma ida e volta mDNS (Multicast DNS) real |
| Atualização           | Contra um GitHub falso local (Módulo 08)                                              |
| Interface e estado    | Máquina de estados do espectador contra o diagrama de casos de uso; regras da tela cheia e do mini player |
| Linha de comando      | Checagem de consistência do `clap`, opções contraditórias recusadas                   |
| Codecs                | Ida e volta H.264; tarjas do canvas; o preset Internet dentro do orçamento com texto rolando; H.265 a partir de um fixture de 24 KB gerado pelo codificador da AMD |

---

## Testes com rede de verdade

Os testes da crate `net` sobem um **servidor QUIC real** (o transporte criptografado sobre UDP,
User Datagram Protocol) em localhost e conectam
espectadores reais. Nada de mock de rede. Um exemplo, completo
(`crates/net/src/tests.rs`):

```rust
#[tokio::test(flavor = "multi_thread")]
async fn wrong_fingerprint_is_rejected() {
    let ts = TestServer::simple(1);
    let client = ViewerClient::new().unwrap();
    let impostor = Identity::generate().unwrap().fingerprint();
    let mut v = TestViewer::watch(&client, ts.addr(), impostor);
    assert_eq!(v.ended().await, SessionEnd::IdentityMismatch);
    assert_eq!(*ts.server.viewers().borrow(), 0);
}
```

O pinning do Módulo 07 em seis linhas: um espectador que espera **outro** fingerprint
termina com `IdentityMismatch`, e o servidor nunca conta um espectador.

Outros nomes da mesma suíte contam a história sozinhos:

```
two_viewers_get_ordered_frames_starting_with_a_keyframe
viewer_limit_rejects_extra_viewers_as_busy
other_protocol_versions_are_refused
lagging_viewer_skips_ahead_to_a_keyframe
switching_broadcasters_moves_the_single_session
a_broken_audio_stream_leaves_video_running
unknown_streams_are_refused_and_video_still_plays
```

---

## Testando com lixo: entrada hostil é o caso normal

Um decodificador recebe bytes de outra máquina. O teste parte do princípio de que eles
podem ser lixo:

- o protocolo recusa quadros acima do limite **antes de alocar**, e codecs desconhecidos;
- o decodificador H.265 sobrevive a entrada de lixo (a libde265 se reinicia depois de um erro);
- o Opus sobrevive a um teste com **5.000 pacotes de lixo**;
- streams inesperados são recusados e o vídeo continua.

Não é fuzzing (que está no roadmap da 1.0, AC-09). Mas é o hábito certo: **testar a porta
que um atacante usaria**.

---

## CI: três sistemas a cada push

O `.github/workflows/ci.yml` roda em Windows, macOS e Linux:

```yaml
- run: cargo fmt --all --check
- run: cargo clippy --workspace --all-targets -- -D warnings
# Hosted runners don't reliably support multicast, so the real mDNS round trip is skipped here.
- run: cargo test --workspace -- --skip announce_is_discovered_and_withdraw_removes_it
```

- **Formatação** conferida; **clippy com avisos virando erros**.
- O teste real de mDNS é pulado no CI porque os runners hospedados não têm multicast confiável.
- Para macOS e Linux, o CI é hoje **a única checagem de compilação** desse código.

> **Honestidade:** o roadmap registra o **BUG-01**: o CI está falhando nas três plataformas.
> Os runners usam um Rust estável mais novo que o do desenvolvimento, e o clippy novo
> passou a apontar um lint na crate `capture`. A correção proposta é corrigir o lint e fixar
> a versão do Rust com um `rust-toolchain.toml`.

Localmente, `just check` roda exatamente o que o CI roda.

---

## O que o CI não consegue testar: `just test-hw`

Alguns testes precisam de uma **placa de vídeo com codificador H.265**, ou medem **tempo**,
e tempo medido em máquina compartilhada de CI não significa nada. Eles ficam marcados como
ignorados, com o motivo escrito:

```rust
#[ignore = "needs a hardware H.265 encoder; run with --ignored"]
#[ignore = "timing; run with --release --ignored --nocapture"]
```

E rodam juntos, em build de release, com:

```sh
just test-hw
# = cargo test --release --workspace -- --ignored --nocapture --skip write_h265_fixture
```

O que eles cobrem: keyframes sob pedido no codificador da GPU (Graphics Processing Unit), ida e volta pela libde265,
entrar num keyframe posterior, o orçamento e a nitidez do preset Internet com texto rolando,
o tempo de codificação a 1080p, e as medições de tempo do canvas e das conversões de pixel.

---

## Ferramentas de diagnóstico

Três ferramentas de desenvolvedor, para olhar um pedaço do sistema isolado:

| Comando              | O que faz                                                                      |
|----------------------|--------------------------------------------------------------------------------|
| `just probe-capture` | Lista as fontes de captura e mede a taxa de quadros de uma delas              |
| `just bench`         | Benchmark do codificador: fonte, duração, preset, `--codec h264\|h265`, `--dump` |
| `just probe-audio`   | Grava uma fonte de áudio em `audio-probe.wav`, lista os apps tocando som, testa silenciar apps |

Foi com o `audio-probe` que o "silenciar apps" foi validado antes de existir interface:
dois processos tocando tons diferentes (440 Hz e 880 Hz), silenciando um de cada vez,
os dois, e tirando o silêncio ao vivo. Cada tom sumia e voltava exatamente como esperado.

E para ver tudo junto numa máquina só:

```sh
just demo
# Alice transmite o padrão de teste com som; Bob assiste.
```

---

## O checklist manual

O README mantém um checklist marcado à mão. Alguns itens **feitos**:

- Transmitir um monitor numa máquina e assistir em outra, via mDNS, a ~30 fps.
- Duas máquinas diferentes pela **Radmin VPN**, com descoberta e com connect string.
- Duas máquinas na LAN (Local Area Network) com áudio.
- H.265 na RX 6600 (AMD) a 60 fps, nada descartado.
- Atualização automática com uma chave descartável e um servidor local.
- Mini player dirigido por entrada sintética (Win32): minimizar, arrastar, duplo clique, posição lembrada.

E itens **ainda não verificados à mão**, listados como tal:

- H.265 em placas NVIDIA e Intel; uma máquina sem codificador H.265 caindo para H.264 sozinha.
- Uma sessão longa pela Radmin VPN com o preset Internet.
- Silenciar o Discord numa chamada real, com a galera assistindo de outros PCs.
- macOS e Linux de verdade (o Linux só foi aberto no Arch, com Hyprland e Wayland).

> Um item "construído, mas não verificado" não é escondido: fica numa lista própria no
> roadmap até alguém clicar nele de verdade.

---

## O smoke test

O último degrau acontece **no executável empacotado**, não no código:

> 5. **Smoke test** the exe in `dist/`: a broadcaster and a viewer, with sound.
>
> *(`docs/releasing.md`, passo 5 do checklist de release)*

Por que testar de novo, se tudo passou? Porque o que vai para a galera não é o código,
é **o zip**: com o executável de release, sem console, com CRT (C runtime) estático, com
ícone embutido, com a chave pública compilada. Um erro de empacotamento passa por todos os
166 testes e só aparece aqui.

Logo depois vem o teste da própria atualização, contra um GitHub de mentira na máquina local.
Os dois estão no Módulo 10.

---

## Discussão

- Por que testar rede com QUIC de verdade em localhost, e não com um mock? O que se perde?
- Um teste que depende de tempo passa na sua máquina e falha no CI. De quem é o problema?
- O checklist manual lista o que **não** foi verificado. Qual o valor disso para quem usa?
- Se você só pudesse manter um nível da pirâmide, qual escolheria para um app que se
  atualiza sozinho?

---

## Resumo

| Nível                   | Onde roda                  | O que pega                                          |
|-------------------------|----------------------------|-----------------------------------------------------|
| 166 testes              | Qualquer máquina, CI       | Lógica, protocolo, sessões QUIC, atualização, entrada hostil |
| CI                      | Windows, macOS, Linux      | Formatação, lint, testes; compilação multiplataforma |
| `just test-hw`          | Máquina com GPU            | Codificador H.265, medições de tempo                |
| Diagnóstico e `just demo` | Máquina de desenvolvimento | Uma parte isolada, ou tudo junto numa máquina       |
| Checklist manual        | Duas máquinas, VPN         | O que só aparece no uso real                        |
| Smoke test              | O zip do release           | Erros de empacotamento                              |

---

## Próximo episódio

O smoke test roda no zip. Mas de onde vem o zip? No próximo módulo: como um workspace Rust
vira um único executável sem instalador, assinado, com licenças e checksums, publicado de
um jeito que o próprio app consegue verificar.

---

## Referências deste módulo

- Peeroxide, README - seção "Testing" e "Manual checklist"
- Peeroxide, `docs/roadmap.md` - "Known bugs" (BUG-01) e "Built but not yet verified by hand"
- Peeroxide, `docs/releasing.md` - checklist de release
- Peeroxide, `.github/workflows/ci.yml`, `Justfile`, `crates/net/src/tests.rs`
