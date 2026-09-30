# Módulo 08: Atualização Segura

---

## Objetivo

Entender como o Peeroxide **se atualiza sozinho** sem se tornar a porta de entrada mais fácil
para um ataque: assinatura com chave offline, regras contra replay e downgrade, limites de
tamanho, extração controlada e falha segura.

---

## Onde a gente parou

O Módulo 07 fechou a rede. Mas existe um caminho que não passa por ela: **a própria atualização**.

Desde a versão 0.5, o Peeroxide faz como o Discord e a Steam: ao abrir, procura uma versão
nova, baixa, troca o próprio executável e reinicia. Isso resolveu um problema real (a galera
sempre na mesma versão, sem ninguém baixar zip à mão). E criou outro:

> **Quem conseguir fazer o app aceitar uma atualização falsa executa código no PC de
> todo mundo que usa o Peeroxide.** (AC-12)

É o ataque de cadeia de suprimentos em miniatura. Este módulo é sobre fechá-lo.

---

## Os atacantes possíveis

| Atacante                                         | O que tenta                                                           |
|--------------------------------------------------|-----------------------------------------------------------------------|
| Quem invadir a conta do GitHub                   | Publicar um release com um executável malicioso                       |
| Quem estiver no meio do download                 | Trocar o arquivo em trânsito (Wi-Fi hostil, inspeção de HTTPS)        |
| Quem tiver um pacote **antigo e legítimo**       | Servi-lo como se fosse o novo (replay) ou forçar uma versão velha com bug conhecido (downgrade) |
| Quem montar um zip malicioso                     | Escrever arquivos fora da pasta do app (*zip slip*)                   |
| Quem só quiser atrapalhar                        | Servir um arquivo gigante, ou nunca responder                         |

---

## O fluxo completo

```
 Peeroxide abre
      |
      v
┌------------------------------┐  só HTTPS, certificados do sistema,
| GET /releases (API GitHub)   |  resposta limitada a 1 MiB
└--------------+---------------┘
               v
┌------------------------------┐  ignora rascunhos; versão ESTRITAMENTE maior;
| Escolher o release           |  precisa ter peeroxide-X.Y.Z-<plataforma>.zip
└--------------+---------------┘  E o .minisig correspondente
               v
┌------------------------------┐  assinatura: até 4 KiB; pacote: até 200 MiB,
| Baixar assinatura e pacote   |  com o tamanho exato listado pelo GitHub;
└--------------+---------------┘  barra de progresso e botão Skip
               v
┌------------------------------┐  chave pública EMBUTIDA no executável;
| Verificar (minisign/Ed25519) |  comentário assinado precisa ser
└--------------+---------------┘  "file:peeroxide-X.Y.Z-<plataforma>.zip"
               v
┌------------------------------┐  extrai SÓ o executável (um e só um no zip),
| Extrair                      |  com nome fixo; caminhos do zip nunca
└--------------+---------------┘  são usados
               v
┌------------------------------┐  self-replace: troca o .exe em uso;
| Instalar e reiniciar         |  reinicia com as mesmas opções e mostra
└------------------------------┘  "Updated to X.Y.Z"

 Qualquer erro em qualquer passo: a versão instalada fica intacta
 e o app abre normalmente.
```

---

## A peça central: uma chave que nunca sai de casa

Cada pacote de release é assinado com **minisign** (Denis), que usa assinaturas Ed25519.

- A **chave secreta** fica num arquivo protegido por senha, **só na máquina de quem publica**
  (`~/.peeroxide/release.key`), com backup offline. Nunca no repositório, nunca no GitHub.
  Hoje, nem num servidor de CI (Continuous Integration): assinar no CI, com a chave como
  segredo, é uma possibilidade discutida no roadmap para a 0.9.
- A **chave pública** é compilada para dentro do app (`crates/update/src/verify.rs`):

```rust
/// The release public key compiled into the app (`just release-keygen` writes it).
const BUILT_IN: &str = include_str!("../release-key.pub");
```

Consequência direta:

> **Mesmo quem invadir a conta do GitHub não consegue empurrar código para ninguém.**
> Pode publicar o que quiser; sem a chave, a assinatura não confere e o pacote é descartado.

A chave atual tem o ID `1FAB31191B660C70`.

---

## Replay: a assinatura precisa dizer "para qual arquivo"

Uma assinatura válida prova "este arquivo foi assinado pela chave". Não prova "este arquivo
é a versão 0.6.1". Um atacante poderia pegar o pacote **legítimo** da 0.5.0, com a assinatura
**legítima** dela, e publicá-lo com o nome da 0.7.0.

Por isso a assinatura carrega um **comentário assinado** (*trusted comment*), que faz parte
do que é assinado e não pode ser editado:

```rust
pub fn trusted_comment_for(file_name: &str) -> String {
    format!("file:{file_name}")
}

// em verify_file:
let expected = trusted_comment_for(expected_name);
if signature.trusted_comment() != expected {
    return Err(UpdateError::Verification(format!(
        "signed for \"{}\", expected \"{expected}\"",
        signature.trusted_comment()
    )));
}
```

O pacote da 0.5.0 diz `file:peeroxide-0.5.0-windows-x64.zip`. Servido como 0.7.0, não confere.

---

## Downgrade: só para frente

A escolha do release (`crates/update/src/select.rs`) segue regras simples:

- rascunhos são ignorados;
- a versão da tag, sem rótulos (`v0.6.1-pre-alpha` vira `0.6.1`), precisa ser
  **estritamente maior** que a instalada;
- precisa existir o pacote **e** a assinatura, com os nomes exatos da plataforma;
- entre os candidatos, vence o de maior versão.

Nunca se volta para uma versão mais antiga, nem que ela seja legítima e assinada.

---

## Zip slip: o nome quem decide é o app

Um zip pode conter entradas com caminhos como `../../Windows/System32/algo.dll`.
Extrair "o zip" confiando nesses caminhos é uma vulnerabilidade clássica.

O Peeroxide não extrai o zip. Ele procura **uma e só uma** entrada cujo nome final seja
`peeroxide.exe` (ou `peeroxide` no Linux) e escreve o conteúdo dela num caminho que **ele**
escolhe (`peeroxide.update.exe`, ao lado do executável atual). Zero ou duas entradas com esse
nome: pacote recusado. Executável acima de 256 MiB: recusado.

```rust
/// Writes the package's executable to `dest`. The package's own paths are never used for
/// writing, so a crafted archive can't place files anywhere else.
pub fn extract_exe(zip_path: &Path, dest: &Path) -> Result<(), UpdateError> { ... }
```

E a ordem importa: **nada é extraído antes de a assinatura conferir**.

---

## Transporte: HTTPS de verdade

- Só HTTPS. HTTP puro é recusado, com uma exceção: `127.0.0.1` e `localhost`, para o
  servidor de teste local (Módulo 10).
- HTTPS continua HTTPS através de redirecionamentos.
- Certificados verificados com o repositório do **sistema operacional** (o que também
  funciona quando um antivírus inspeciona HTTPS).
- Limites de tamanho em tudo que é baixado, e o pacote precisa ter **exatamente** o tamanho
  que o GitHub listou.

O HTTPS protege o transporte. A assinatura protege **o conteúdo**, independentemente de
quem entregou. São duas camadas porque cada uma falha de um jeito diferente.

---

## Falhar aberto: nunca atrapalhar

Uma atualização que impede o app de abrir é um ataque de negação de serviço feito por você mesmo.
O requisito NFR-14 exige o contrário:

| Situação                                  | O que acontece                                                   |
|-------------------------------------------|------------------------------------------------------------------|
| Sem internet, ou GitHub fora do ar        | O app abre em até ~5 s, com um aviso discreto                    |
| Rate limit da API                         | Tenta de novo na próxima abertura                                |
| Download lento                            | Botão **Skip** abre o app na hora                                |
| Assinatura inválida                       | Pacote descartado, versão atual intacta, aviso na tela e no log  |
| Pasta sem permissão de escrita (Program Files) | Aviso com o link da página de download                      |
| Duas instâncias abrindo juntas            | Um arquivo de trava; a segunda não tenta atualizar (trava velha de mais de 10 min é ignorada) |

Para desligar: `--no-update`, ou `PEEROXIDE_NO_UPDATE=1`. Builds de desenvolvimento
(`cargo run`) nunca se atualizam.

---

## E se a chave vazar, ou sumir?

| Evento                | Procedimento (`docs/releasing.md`)                                                        |
|-----------------------|--------------------------------------------------------------------------------------------|
| Chave perdida         | Gerar outra, publicar, e todo mundo instala **uma vez à mão**; depois volta a ser automático |
| Chave vazada          | O mesmo, **imediatamente**, e avisar a galera para não confiar em atualizações até instalar a nova versão à mão |

Não existe "recuperar" uma chave de assinatura. Por isso o backup (arquivo + senha,
em lugar seguro) é parte do processo, não um detalhe.

---

## O que o GitHub fica sabendo (AC-13)

Uma requisição por abertura, com o User-Agent `Peeroxide/<versão>`. Ou seja: **seu IP e a
versão do app**. Nada de nome, ID, contatos ou configurações.

Detalhe que o caso de abuso registra: numa rede virtual (Radmin VPN, Tailscale), esse é o
seu IP **real** de internet, não o da rede virtual.

---

## Testado contra um GitHub de mentira

A crate `update` é testada contra um **servidor local que finge ser o GitHub**:

- escolha do release: o mais novo, pré-releases incluídas; rascunhos, versões iguais ou
  menores, pacotes sem assinatura e outras plataformas ignorados;
- assinaturas: válida, adulterada, chave errada, **reaproveitada com outro nome**,
  comentário assinado editado;
- pacote: extrair o executável, recusar zips sem nenhum ou com vários, e caminhos que
  tentam escapar da pasta;
- comportamento: limites de tamanho, Skip, rate limit, servidor mudo (5 s), segunda
  instância, URLs inseguras.

E à mão, numa máquina: a 0.4.99 se atualizou para a 0.5.0 em ~2 s e reiniciou mostrando
"Updated to 0.5.0"; um pacote adulterado foi recusado e o app abriu na versão antiga.

---

## Discussão

- Por que a chave de assinatura **não** deve ficar num segredo do CI, mesmo que isso
  tornasse o release mais cômodo? Quando valeria a pena mudar isso?
- HTTPS já garante que o arquivo veio do GitHub. Por que isso não basta?
- O comentário assinado resolve o replay de nome. Que outro ataque de replay ainda seria
  possível se a regra "estritamente mais nova" não existisse?
- "Falhar aberto" é sempre a escolha certa? Em que tipo de software você preferiria
  "falhar fechado"?

---

## Resumo

| Ameaça                                  | Defesa                                                        |
|-----------------------------------------|---------------------------------------------------------------|
| Conta do GitHub invadida                | Assinatura minisign com chave offline; chave pública embutida |
| Man-in-the-middle no download           | HTTPS com certificados do sistema **e** assinatura            |
| Replay de pacote antigo com nome novo   | Comentário assinado `file:<nome exato>`                       |
| Downgrade                               | Só versões estritamente maiores                               |
| Zip slip                                | Extrai só o executável, com nome escolhido pelo app, depois da verificação |
| Arquivo gigante ou servidor mudo        | Limites de tamanho e timeouts; Skip                            |
| Atualização que impede o app de abrir   | Falha aberta em ~5 s; versão atual sempre intacta             |

---

## Próximo episódio

Assinar o release garante que o código é meu. Não garante que o código **funciona**.
No próximo módulo: como o Peeroxide é testado, do teste unitário ao smoke test antes de
cada publicação.

---

## Referências deste módulo

- Denis, F. *Minisign.*
- Peeroxide, `crates/update/src/` (`lib.rs`, `select.rs`, `verify.rs`, `install.rs`, `github.rs`, `download.rs`)
- Peeroxide, `docs/releasing.md` e `docs/abuse-cases.md` (AC-12, AC-13)
- Peeroxide, `docs/non-functional-requirements.md` (NFR-14, NFR-15)
- Shostack (2014), Cap. 3 - "STRIDE" (Tampering e Elevation of Privilege)
