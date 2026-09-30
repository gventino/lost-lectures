# Módulo 07: Por que é Seguro (e Onde Ainda Não é)

---

## Objetivo

Aplicar ao Peeroxide a mesma régua usada nas gambiarras: um **modelo de ameaças com STRIDE**,
o código que sustenta cada defesa, e uma lista honesta do que **ainda não** está protegido.

---

## Onde a gente parou

Nas gambiarras, a resposta para "em quem você está confiando?" era sempre "não sei".
Agora eu tenho a obrigação de responder melhor, e de mostrar a conta.

A regra que guia este módulo:

> **Confie na matemática, não no intermediário.**

Na prática: nenhuma defesa do Peeroxide depende de alguém no meio do caminho se
comportar bem. Quando depende de algo, depende de criptografia, e isso é dito.

---

## STRIDE em uma tabela

STRIDE (Shostack, 2014) é um jeito sistemático de não esquecer categorias de ameaça:

| Letra | Ameaça                  | Pergunta                                     | Propriedade violada |
|-------|-------------------------|----------------------------------------------|---------------------|
| S     | Spoofing                | Alguém pode se passar por outro?             | Autenticidade       |
| T     | Tampering               | Alguém pode alterar dados?                   | Integridade         |
| R     | Repudiation             | Alguém pode negar o que fez?                 | Responsabilização   |
| I     | Information Disclosure  | Alguém pode ver o que não devia?             | Confidencialidade   |
| D     | Denial of Service       | Alguém pode derrubar o serviço?              | Disponibilidade     |
| E     | Elevation of Privilege  | Alguém pode ganhar poder que não tinha?      | Autorização         |

O projeto tem 13 casos de abuso catalogados (AC-01 a AC-13) em `docs/abuse-cases.md`.
Como não há servidor central, **quase todas as ameaças vêm de outros aparelhos na mesma rede**.

---

## S: quem é você? (AC-01)

**O ataque:** alguém na rede anuncia um "Alice" falso via mDNS (Multicast DNS) e passa conteúdo
dele para Bob.

**A defesa, em três camadas:**

1. **Identidade = chave.** Cada peer tem um certificado autoassinado, e o ID é o SHA-256
   (Secure Hash Algorithm) desse certificado (`crates/net/src/identity.rs`):

   ```rust
   /// SHA-256 of a peer's certificate (DER). Doubles as the stable peer id.
   pub struct Fingerprint([u8; 32]);

   impl Fingerprint {
       pub fn of(cert_der: &[u8]) -> Self {
           Self(Sha256::digest(cert_der).into())
       }
   }
   ```

2. **Pinning no handshake.** Bob não aceita "um certificado válido". Aceita **aquele**
   certificado (próximo slide).
3. **TOFU** (Trust On First Use) na interface: nomes repetidos ganham ⚠; um contato salvo
   aparecendo com outro ID ganha ⚠ vermelho.

---

## O verificador que recusa todo mundo, menos um

Em vez de validar uma cadeia até uma autoridade certificadora, o cliente usa um verificador
próprio que só aceita o certificado cujo hash é o esperado (`crates/net/src/tls.rs`, resumido):

```rust
impl ServerCertVerifier for PinnedVerifier {
    fn verify_server_cert(
        &self,
        end_entity: &CertificateDer<'_>,
        /* intermediários, nome, OCSP e horário: ignorados */
    ) -> Result<ServerCertVerified, rustls::Error> {
        if Fingerprint::of(end_entity) == self.expected {
            Ok(ServerCertVerified::assertion())
        } else {
            self.mismatch.store(true, Ordering::Relaxed);  // "Identity check failed"
            Err(rustls::Error::InvalidCertificate(
                CertificateError::ApplicationVerificationFailure,
            ))
        }
    }
    // verify_tls13_signature: delegado ao rustls, sem atalhos
}
```

Duas coisas precisam ser verdade para Bob aceitar a conexão:

| Checagem                                | Quem faz                       | O que impede                              |
|-----------------------------------------|--------------------------------|-------------------------------------------|
| `SHA-256(certificado) == fingerprint`   | `verify_server_cert`           | Apresentar outro certificado              |
| Assinatura do handshake com a chave privada | `verify_tls13_signature` (rustls) | Apresentar o certificado **copiado** de Alice sem ter a chave |

E só TLS (Transport Layer Security) 1.3: a configuração não aceita versões anteriores.

---

## De onde vem o fingerprint esperado?

| Fonte               | Confiável?                                                                        |
|---------------------|-----------------------------------------------------------------------------------|
| Anúncio mDNS        | Não autenticado: qualquer um anuncia qualquer coisa. Mas **só aponta**; quem garante é o handshake |
| Connect string      | Tão confiável quanto o canal por onde chegou (o grupo de mensagens da galera)      |
| Contato salvo       | Aprendido na primeira conexão e lembrado: o modelo TOFU                            |

Um atacante na rede consegue anunciar "Alice" **com o fingerprint dele**. A conexão funciona,
mas o ID na tela é outro. É aí que entra o TOFU: ⚠ para nome duplicado, ⚠ vermelho para
contato conhecido com ID novo. O que ele **não** consegue é anunciar "Alice" com o fingerprint
**da Alice** e completar a conexão: falta a chave privada.

> TOFU é o mesmo modelo do SSH (Secure Shell) na primeira conexão com um servidor.
> Wendlandt et al. (2008) discutem suas forças e fraquezas: o elo fraco é a primeira vez.

---

## T e I: alterar e espiar (AC-03, AC-05)

**O ataque:** alguém na mesma rede (ARP spoofing, Address Resolution Protocol, num Wi-Fi mal
isolado) se coloca no meio e lê ou altera os quadros.

**A defesa:** todo o tráfego é QUIC com TLS 1.3, que usa AEAD (Authenticated Encryption with
Associated Data): cada pacote é cifrado **e** autenticado. Um pacote alterado falha na
verificação e é descartado. **Nada** trafega em claro: nem vídeo, nem áudio, nem nomes,
nem mensagens de controle.

Compare com o Episódio 2 do Módulo 02: lá, quem estava no meio lia seus destinos e podia
alterar HTTP puro. Aqui, quem está no meio vê **pacotes UDP (User Datagram Protocol) cifrados indo de um IP para outro**.
Consegue inferir que há uma transmissão, e o volume. Não consegue ver o conteúdo.

---

## R: quem fez o quê? (AC-04)

Sem servidor, não há log central. Então cada ponta guarda o seu:
**logs de sessão com rotação diária**, dos dois lados, com início e fim de transmissões,
espectadores (nome e endereço), sessões e motivos de encerramento, e cada atualização
e cada verificação de assinatura que falhou.

---

## D: derrubar (AC-07, AC-08)

Todo byte que chega da rede é **não confiável até prova em contrário**:

| Limite                                        | Valor                 | Checado                   |
|-----------------------------------------------|-----------------------|---------------------------|
| Mensagem de controle                          | 64 KiB                | **Antes** de alocar       |
| Quadro de vídeo                               | 8 MiB                 | **Antes** de alocar       |
| Pacote de áudio                               | 4 KiB                 | **Antes** de alocar       |
| Espectadores por transmissão                  | 8                     | No aceite (`Busy`)        |
| Streams que quem transmite pode abrir         | 2 (vídeo e áudio)     | Configuração do QUIC      |
| Streams que quem assiste pode abrir           | Nenhum unidirecional  | Configuração do QUIC      |
| Handshake e primeira mensagem                 | Timeout de 5 s        | Por conexão               |
| Peers na tabela de descoberta                 | 64                    | Anúncios excedentes ignorados |

Os anúncios mDNS são validados (versão, fingerprint de 64 hex, porta, IPv4, nome sanitizado).
E o QUIC descarta pacotes não autenticados de forma barata.

---

## E: capturar mais do que devia (AC-10, AC-11)

Um compartilhador de tela é, por definição, um programa com permissão para ver sua tela.
A defesa é **nunca capturar mais do que foi escolhido, no nível da API do sistema**:

- Janela é capturada pela API de captura de janela, **nunca** recortando a tela inteira.
- O som de uma janela é o da árvore de processos daquele app, pela API de loopback
  por processo, **nunca** filtrando o som do sistema inteiro.
- **O microfone nunca é capturado.**
- Áudio vem desligado, é escolhido por transmissão, e a interface diz exatamente o que
  vai junto. Apps de voz ficam de fora por padrão.
- **Nada é capturado enquanto ninguém assiste.**

---

## A lista honesta: onde ainda não é seguro

| Lacuna                                 | Situação hoje                                                                 | Plano |
|----------------------------------------|-------------------------------------------------------------------------------|-------|
| **AC-02: quem assiste não é autenticado** | Qualquer um que alcance sua porta na rede **pode assistir, e ouvir**, enquanto você transmite | 0.7: ver quem está assistindo, expulsar, aprovar/negar, senha opcional, TLS mútuo |
| **AC-09: decodificadores em C/C++**     | OpenH264 e libde265 rodam dentro do processo; um stream malicioso mirando um bug de memória é o risco | 1.0: fuzzing dos parsers e decodificação num processo separado e restrito |
| Pre-alpha                              | Mudanças incompatíveis entre versões; pouco testado fora do Windows 11        | 0.8, 1.0 |
| Executável sem assinatura de código    | O Windows mostra o aviso do SmartScreen na primeira instalação                | 0.9   |
| AC-13: checagem de atualização          | O GitHub fica sabendo seu IP e a versão do app, uma vez por abertura          | `--no-update` desliga |

> **Trate toda transmissão como visível e audível para todos na mesma rede.**
> Na LAN (Local Area Network) de casa, isso é a sua família. Num Wi-Fi público, é qualquer um.
> Numa rede virtual como a do Módulo 11, é quem você colocou nela, e isso passa a ser
> um controle de acesso de verdade.

Sobre o AC-09, o que já existe: o decodificador Opus é Rust puro, na própria thread, com
pânicos capturados; a libde265 se reinicia depois de um erro; entrada de lixo é testada nos
dois codecs. Mas nada disso substitui fuzzing e isolamento, e o README diz isso.

---

## O placar de confiança, completo

| Solução             | Quem carrega o vídeo              | Quem consegue ver                         | Em quem você confia                         | Custo                    | Se cair...                  |
|---------------------|-----------------------------------|-------------------------------------------|---------------------------------------------|--------------------------|-----------------------------|
| Discord             | Servidores do Discord             | Quem está no canal                        | Uma empresa conhecida                       | Grátis                   | Ninguém transmite           |
| VPS grátis          | Discord, via máquina de um estranho | + o operador da VPS                     | Um desconhecido anônimo                     | "Grátis"                 | Caiu. Várias vezes          |
| Proxy do Equador    | Discord, via proxy público        | + o dono do proxy, para todos os apps     | Um desconhecido, com todo o seu tráfego     | "Grátis"                 | Some sem aviso              |
| Site com anúncio    | O site (talvez)                   | O site, e quem ele quiser                 | O site, os anunciantes e os scripts deles   | Sua atenção e seus dados | A sala acaba                |
| O ideal             | Os PCs da galera, direto          | Só quem você escolher                     | Na criptografia, e nos seus amigos          | Zero                     | Só aquela transmissão para  |
| **Peeroxide (LAN)** | **Os PCs, direto (QUIC + TLS 1.3)** | **Quem alcança sua porta na rede (até a 0.7)** | **Criptografia; ID fixado; TOFU; libde265 e OpenH264** | **Zero**        | **Só aquela transmissão para** |

A distância entre "O ideal" e "Peeroxide (LAN)" tem nome e número: **AC-02** e **AC-09**.
E estão no roadmap.

---

## Discussão

- O TOFU falha exatamente na primeira conexão. Como a galera pode tornar essa primeira
  vez mais segura? (Dica: onde a connect string foi enviada?)
- Por que é aceitável, no pre-alpha, que qualquer um na rede possa assistir? Em que
  redes isso deixa de ser aceitável?
- Isolar a decodificação num processo separado resolve o AC-09 por completo?
  O que ainda sobraria?
- Um observador na rede vê "pacotes UDP cifrados entre dois IPs". Que informação ainda
  dá para extrair disso?

---

## Resumo

| Ameaça (STRIDE)        | Defesa no Peeroxide                                            | Status       |
|------------------------|----------------------------------------------------------------|--------------|
| Spoofing de quem transmite | ID = SHA-256 do certificado; pinning; TOFU na interface    | Feito        |
| Spoofing de quem assiste   | TLS mútuo e aprovação                                      | 0.7          |
| Tampering              | AEAD do QUIC/TLS 1.3; pacotes alterados descartados            | Feito        |
| Repudiation            | Logs de sessão dos dois lados                                  | Feito        |
| Information Disclosure | Tudo cifrado; anúncio só durante a transmissão; áudio opt-in   | Feito, exceto AC-02 |
| Denial of Service      | Limites antes de alocar; teto de espectadores e peers; timeouts | Feito        |
| Elevation of Privilege | Captura restrita pela API do sistema; Opus em Rust puro        | Decodificadores de vídeo: 1.0 |

---

## Próximo episódio

Existe uma ameaça que nenhuma dessas defesas cobre: e se o ataque vier **dentro do próprio
Peeroxide**? Um app que se atualiza sozinho executa, por definição, código novo baixado da
internet. No próximo módulo: como garantir que esse código é meu.

---

## Referências deste módulo

- Shostack (2014), Cap. 3 - "STRIDE"
- Peeroxide, `docs/abuse-cases.md` e README - seção "Security"
- Peeroxide, `crates/net/src/identity.rs` e `crates/net/src/tls.rs`
- Rescorla (2018), RFC 8446 - Seção 4.4.3 ("Certificate Verify")
- Wendlandt, Andersen & Perrig (2008). *Perspectives* (TOFU)
- Thomson & Turner (2021), RFC 9001 - Seção 5 (proteção de pacotes no QUIC)
