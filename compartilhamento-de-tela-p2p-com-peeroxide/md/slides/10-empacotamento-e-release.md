# Módulo 10: Empacotamento e Release

---

## Objetivo

Ver como um workspace Rust vira **um único executável que roda em qualquer Windows sem
instalar nada**, como ele é empacotado (inclusive para Linux, dentro de um contêiner),
assinado e publicado, e o que o checklist de release exige antes de apertar o botão,
incluindo o smoke test.

---

## Onde a gente parou

No Módulo 08, o app aprendeu a confiar só em pacotes assinados. No Módulo 09, vimos que o
último teste roda no zip. Falta o elo do meio: **como nasce o zip**.

A exigência da galera era simples: "manda o link, eu baixo, abro e funciona". Sem instalador,
sem "instala o Visual C++ Redistributable", sem "precisa do FFmpeg".

---

## Um executável, sem dependências

Três detalhes transformam `cargo build --release` num `.exe` que roda em qualquer
Windows 10 (2004+) ou 11:

**1. CRT (C runtime) estático** (`.cargo/config.toml`):

```toml
# Link the C runtime statically so the Windows binary runs without the VC++ redistributable.
[target.x86_64-pc-windows-msvc]
rustflags = ["-C", "target-feature=+crt-static"]
```

A libde265 e o OpenH264 são C/C++; sem isso, o executável exigiria o runtime do Visual C++
instalado.

**2. Subsistema gráfico** (`crates/app/src/main.rs`):

```rust
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]
```

Em release, nada de janela de console piscando junto com o app.

**3. Cara de app de verdade** (`crates/app/build.rs`): a crate `winresource` embute o ícone
(o píer em pixel art) e os detalhes de versão que o Explorer, as Propriedades e o Gerenciador
de Tarefas mostram ("Peeroxide", licença Apache 2.0, link do repositório).

Resultado: `target/release/peeroxide.exe`, sozinho, é o app inteiro.

---

## O pacote do Windows

`just package` compila em release e roda `packaging/package-windows.ps1`, que:

1. Lê a versão do `Cargo.toml` do workspace e o commit atual (avisando se há mudanças não
   commitadas, que ficam registradas no próprio pacote).
2. Monta `dist/peeroxide-X.Y.Z-windows-x64/` com:

| Arquivo                    | Conteúdo                                                                 |
|----------------------------|--------------------------------------------------------------------------|
| `peeroxide.exe`            | O app                                                                    |
| `QUICKSTART.txt`           | Guia de primeira execução, com título, versão e **commit** preenchidos    |
| `THIRD-PARTY-NOTICES.txt`  | Avisos de terceiros **mais a licença LGPL-3.0 da libde265**, que precisa viajar com o executável que a contém |

3. Compacta em `peeroxide-X.Y.Z-windows-x64.zip`.
4. **Assina o zip** com a chave de release (pede a senha), gerando o `.minisig`. Sem chave,
   um release de verdade não termina; e a assinatura é conferida contra a chave pública
   que o app carrega.
5. Imprime o começo do SHA-256 (Secure Hash Algorithm) do executável: *"compare on each PC to be sure it's the same build"*.

Builds de teste levam um rótulo (`just package teste`) e ganham outro nome; o atualizador
**nunca** os escolhe.

---

## O pacote do Linux, compilado num contêiner

No Linux, o problema é outro: o binário depende da **glibc** do sistema onde foi compilado.
Compilar num Arch atualizado geraria algo que não roda num Ubuntu de dois anos atrás.

A solução é compilar dentro de um contêiner Debian bookworm (`packaging/Dockerfile.linux`):

```dockerfile
# Debian bookworm's glibc (2.36) and PipeWire headers keep the binary runnable on most
# distributions, and avoid bindgen breakage against very new PipeWire headers
# (libspa 0.8 fails on PipeWire 1.6).
FROM rust:1-bookworm
RUN apt-get update \
    && apt-get install -y --no-install-recommends pkg-config nasm libclang-dev \
        libpipewire-0.3-dev libdbus-1-dev libxkbcommon-dev libwayland-dev libgl1-mesa-dev \
        libasound2-dev
```

`just release-portable` roda o `cargo build --release --locked` dentro dele, com o código
e o cache do Cargo montados como volumes. O `package-linux.sh` faz o resto, espelhando o script
do Windows: quickstart, avisos de terceiros com a licença da libde265, zip, assinatura, hash.

O pacote Linux de 0.6.1 roda em distribuições com glibc 2.35 ou mais nova (Ubuntu 22.04,
Debian 12, Fedora, Arch...).

---

## O checklist de release

Do `docs/releasing.md`, na ordem:

| # | Passo                          | Por quê                                                                  |
|---|--------------------------------|--------------------------------------------------------------------------|
| 1 | Tudo na `main`, docs incluídas | README, roadmap, requisitos e a seção "NEW" do quickstart vão juntos     |
| 2 | Subir a versão                 | `Cargo.toml` do workspace, `Cargo.lock` junto, commit `Release X.Y.Z`    |
| 3 | `just check`                   | Formatação, clippy, todos os testes                                      |
| 4 | `just package`                 | Build, zip e assinatura                                                  |
| 5 | **Smoke test**                 | O executável de `dist/`: alguém transmite, alguém assiste, **com som**   |
| 6 | Testar a atualização localmente | Um GitHub de mentira na própria máquina (próximo slide)                 |
| 7 | Tag                            | `vX.Y.Z-pre-alpha`, anotada, enviada ao GitHub                           |
| 8 | Notas de release               | Modelo fixo, com os **checksums SHA-256** do zip e do executável         |
| 9 | `just publish notas.md`        | Cria o pré-release com o zip **e** a assinatura                          |
| 10 | Conferir                      | Abrir uma versão antiga instalada: ela deve se atualizar sozinha         |

O passo 9 usa o GitHub CLI: `gh release create <tag> <zip> <sig> --verify-tag --prerelease`.
No Linux, o mesmo comando só **adiciona** o pacote Linux a um release que já existe.

---

## Um GitHub falso para testar: `just serve-release`

Testar a atualização publicando no GitHub de verdade seria entregar um teste para a galera.
Então o projeto tem um servidor que **finge ser o GitHub** na máquina local:

```sh
just serve-release dist/peeroxide-X.Y.Z-windows-x64.zip
```

Depois, copia-se uma versão **antiga** para uma pasta qualquer e ela é aberta apontando para
esse servidor:

```sh
PEEROXIDE_UPDATE_URL=http://127.0.0.1:8765/releases
```

(Essa é a única situação em que o atualizador aceita HTTP sem S: endereço local.)

O esperado: a versão antiga encontra a nova, baixa, verifica, troca, reinicia e mostra
"Updated to X.Y.Z". Foi assim que a primeira atualização foi validada antes de existir
qualquer release com atualizador.

---

## Regras que não se quebram

| Regra                                        | Por quê                                                              |
|----------------------------------------------|----------------------------------------------------------------------|
| **Nunca substituir os arquivos de uma versão publicada** | Quem já baixou tem outro arquivo; conserte com uma versão nova |
| **Nunca publicar build de teste no GitHub**  | Os testadores instalariam; teste com `serve-release`                  |
| Nomes exatos: `peeroxide-X.Y.Z-<plataforma>.zip` e `.minisig` | É o que o atualizador procura, e o que o comentário assinado nomeia |
| Todo release tem pacote Linux                | Cópias Linux só se atualizam a partir de releases que tenham `linux-x64` |

---

## Checksums: confira você mesmo

As notas de cada release trazem os SHA-256. Da 0.6.1, por exemplo:

```
peeroxide-0.6.1-windows-x64.zip
  D50A4AC6126B6D2CDEE95E74EDF62CAF014C6D20E471D1F58ADA227B7E23D858
peeroxide.exe (dentro dele)
  1E48D3A659C4BFD4D00106492505CEA78F5E903AADD8F6E7AFE297A066750169
```

Para conferir no Windows: `Get-FileHash <arquivo> -Algorithm SHA256`. No Linux: `sha256sum <arquivo>`.
Quem instala pela atualização automática não precisa: a assinatura já faz essa checagem,
com uma garantia mais forte (quem assinou, não só "o arquivo é este").

---

## O aviso do SmartScreen

O executável **não tem assinatura de código** (Authenticode). Na primeira vez que alguém
roda uma cópia baixada, o Windows mostra "Windows protected your PC".

- O aviso só aparece para arquivos com a marca "baixado da internet". Antes de descompactar:
  botão direito no zip > Propriedades > marcar **Desbloquear** > OK. Ou: Mais informações >
  Executar assim mesmo.
- **Atualizações instaladas pelo próprio app não carregam essa marca**: o aviso aparece
  uma única vez por pessoa.

Resolver de vez exige um certificado de assinatura de código. As opções levantadas no
roadmap (0.9), em setembro de 2026:

| Opção                               | Situação                                                                  |
|-------------------------------------|---------------------------------------------------------------------------|
| Azure Artifact Signing (Microsoft)  | Só para pessoas físicas nos EUA ou no Canadá; fora de alcance             |
| Certum Open Source Code Signing     | ~US$ 50–70/ano, para desenvolvedores open source, com verificação de identidade |
| SignPath Foundation                 | Gratuito para open source; exige builds feitos pelo CI (Continuous Integration) e aprovação por release |

E um detalhe que o roadmap registra: desde 2024, nenhum certificado dá confiança instantânea
ao SmartScreen; a reputação ainda se constrói com downloads.

---

## Discussão

- Por que o zip de um release leva o **commit** dentro do quickstart? Quando isso ajuda?
- Compilar dentro de um contêiner antigo parece um retrocesso. Que problema de
  portabilidade isso resolve que compilar "no sistema mais novo possível" não resolve?
- "Nunca substituir os arquivos de uma versão publicada": que ataque, ou que confusão,
  essa regra evita?
- Assinatura de código (Authenticode) e assinatura minisign protegem contra as mesmas coisas?

---

## Resumo

| Peça                        | O que faz                                                              |
|-----------------------------|------------------------------------------------------------------------|
| CRT estático                | O `.exe` roda sem o runtime do Visual C++                              |
| Subsistema gráfico          | Sem janela de console em release                                       |
| `winresource`               | Ícone e detalhes de versão no executável                               |
| `package-windows.ps1`       | Quickstart com commit, avisos com a LGPL, zip, assinatura, hash        |
| Contêiner bookworm          | Binário Linux que roda com glibc 2.35+                                 |
| Checklist de release        | Da versão ao `just publish`, com smoke test e teste local da atualização |
| `serve-release`             | Um GitHub de mentira para testar a atualização sem publicar nada       |
| SmartScreen                 | Um aviso por pessoa até existir assinatura de código (0.9)             |

---

## Próximo episódio

Tudo funciona, assinado e testado. Na rede de casa. Só que a galera mora em cidades
diferentes. Último módulo: levar o Peeroxide para a internet sem colocar ninguém no
caminho do vídeo.

---

## Referências deste módulo

- Peeroxide, `docs/releasing.md`, `packaging/` (`package-windows.ps1`, `package-linux.sh`, `Dockerfile.linux`, `QUICKSTART.txt`)
- Peeroxide, `.cargo/config.toml`, `crates/app/build.rs`, `Justfile`
- Peeroxide, `docs/roadmap.md` - seção 0.9 (distribuição e assinatura de código)
- Peeroxide, notas do release [v0.6.1-pre-alpha](https://github.com/gventino/peeroxide/releases/tag/v0.6.1-pre-alpha)
