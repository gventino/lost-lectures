# Módulo 11: Pela Internet com Headscale

---

## Objetivo

Levar o Peeroxide para fora da rede local sem colocar nenhum servidor no caminho do vídeo:
entender por que um app de LAN (Local Area Network) precisa de uma rede virtual, comparar as
opções, montar uma rede própria com **Headscale** passo a passo, e analisar em quem se passa
a confiar.

---

## Onde a gente parou

O Peeroxide funciona, é seguro no que promete, se atualiza sozinho e é testado. Na rede de casa.

Só que a galera mora em cidades diferentes. Até aqui, eu e um amigo usamos a **Radmin VPN**,
uma "LAN virtual" pronta: funciona, e a descoberta até aparece sozinha. Mas ela é mais um
intermediário de código fechado, justamente o tipo de coisa que este material inteiro
ensinou a questionar.

A pergunta do Módulo 01 volta uma última vez: **dá para atravessar a internet confiando
só na matemática e em quem a gente escolheu?**

---

## Por que um app de LAN precisa de ajuda

| Obstáculo                    | O que acontece                                                                        |
|------------------------------|---------------------------------------------------------------------------------------|
| mDNS (Multicast DNS, Domain Name System) | Usa multicast local (`224.0.0.251`, porta 5353): **não atravessa roteadores**          |
| NAT (Network Address Translation) | Seu PC tem um IP privado; de fora, ninguém chega nele sem uma regra no roteador  |
| CGNAT (Carrier-Grade NAT)    | Muitas operadoras põem um segundo NAT por cima: às vezes nem o roteador tem IP público |
| IPv4 só                      | O Peeroxide ainda não fala IPv6                                                        |

A saída clássica é uma **rede virtual sobreposta** (*overlay*): cada PC ganha um endereço numa
rede compartilhada, e para o Peeroxide é como se todos estivessem no mesmo switch.

---

## As opções de rede virtual

Em todas, alguém coordena; a diferença é quem, e por onde passa o vídeo. Na tabela, VPS é
uma Virtual Private Server (um servidor alugado) e DERP (Designated Encrypted Relay for Packets)
é o relay de último recurso do Tailscale, explicado no próximo slide.

| Opção                       | Quem coordena             | Por onde passa o vídeo                               | Código        | Descoberta mDNS          |
|-----------------------------|---------------------------|------------------------------------------------------|---------------|--------------------------|
| Radmin VPN / Hamachi        | A empresa fornecedora     | Depende do fornecedor                                | Fechado       | Pode funcionar           |
| Tailscale (serviço)         | A Tailscale Inc.          | Direto (WireGuard); relays da Tailscale se preciso   | Clientes abertos, coordenação fechada | Não (sem multicast) |
| **Headscale + clientes Tailscale** | **Você, na sua VPS** | **Direto (WireGuard); seu relay (DERP) se preciso** | **Aberto**    | Não (sem multicast)      |
| WireGuard "na mão" com a VPS no centro | Você             | **Todo quadro passa pela VPS**                       | Aberto        | Não                      |

O WireGuard puro com a VPS no meio (*hub-and-spoke*) é tentador pela simplicidade, mas
transforma a VPS num retransmissor de vídeo: a banda dela vira a soma de todos os streams,
e cada quadro faz uma viagem a mais. O Headscale guarda a VPS para o que ela faz bem:
**coordenar**.

---

## Plano de controle vs. plano de dados

O Tailscale separa duas coisas que costumam vir juntas. O Headscale é uma implementação
aberta e auto-hospedada da parte de **controle**:

```
                  ┌-------------------------------------┐
                  |  VPS: Headscale                     |
                  |   - quem está na rede               |
                  |   - chaves públicas WireGuard       |
                  |   - política (quem fala com quem)   |
                  |   - DERP: relay de último recurso   |
                  └-------+---------------------+-------┘
      plano de controle   |                     |   plano de controle
      (pequeno: chaves,   |                     |   (pequeno)
       endereços)         |                     |
                  ┌-------v-------┐     ┌-------v-------┐
                  |  PC da Alice  |=====|   PC do Bob   |
                  |  100.64.0.1   |     |   100.64.0.2  |
                  └---------------┘     └---------------┘
                   plano de dados: WireGuard direto, PC a PC
                   (o vídeo do Peeroxide vai por aqui)
```

- **Plano de controle:** a VPS distribui chaves públicas e endereços. Pouquíssimos dados.
- **Plano de dados:** o túnel WireGuard (Donenfeld, 2017) vai **direto entre os PCs**.
- **DERP**: quando o direto não sai de jeito nenhum,
  os pacotes (ainda cifrados pelo WireGuard) passam por um relay sobre HTTPS.

Detalhe curioso: os endereços da rede ficam em `100.64.0.0/10`, o bloco reservado para
CGNAT pela RFC 6598. O mesmo espaço que a operadora usa para te esconder, o Tailscale usa
para te encontrar.

---

## Como dois PCs atrás de NAT se falam

A técnica clássica (Ford, Srisuresh & Kegel, 2005; Anderson, 2020):

1. Cada PC pergunta a um servidor STUN (Session Traversal Utilities for NAT) "com que IP e
   porta eu apareço lá fora?".
2. A coordenação troca essas respostas entre os dois.
3. Os dois enviam pacotes **um para o outro ao mesmo tempo**. Cada NAT vê um pacote de saída
   e passa a aceitar a resposta: o *hole punching*.
4. Se os dois estiverem atrás de NATs "difíceis", o furo não abre e o tráfego vai pelo DERP.

Com CGNAT, muitas vezes o furo abre mesmo assim. Quando não abre, o DERP garante que funciona,
só que com mais atraso (o relay é sobre TCP, Transmission Control Protocol) e gastando a
banda da VPS. Para vídeo, **direto é o objetivo**; o passo 6 mostra como conferir.

---

## Passo 0: o que você precisa

| Item            | Sugestão                                                                         |
|-----------------|----------------------------------------------------------------------------------|
| VPS             | A menor que houver (1 vCPU, 1 GB de RAM sobra), **numa região em São Paulo**: é onde o DERP vai rodar |
| Sistema         | Ubuntu 22.04+ ou Debian 12+ (exigência do pacote `.deb` oficial)                |
| Domínio         | Um nome (ex.: `headscale.seudominio.com.br`) com registro A apontando para a VPS |
| Na galera       | O cliente oficial do Tailscale em cada PC                                        |

Nos exemplos abaixo, `headscale.seudominio.com.br` e `203.0.113.10` são **exemplos**:
troque pelo seu domínio e pelo IP público da sua VPS.

---

## Passo 1: firewall e SSH

```sh
sudo ufw allow OpenSSH
sudo ufw allow 80/tcp      # validação do Let's Encrypt (HTTP-01)
sudo ufw allow 443/tcp     # Headscale e DERP (HTTPS)
sudo ufw allow 3478/udp    # STUN
sudo ufw enable
```

E SSH (Secure Shell) só com chave: em `/etc/ssh/sshd_config`, `PasswordAuthentication no`,
e `sudo systemctl restart ssh`. Quem controla essa VPS controla quem entra na rede da galera.

---

## Passo 2: instalar o Headscale

Pelo pacote oficial, que já cria o usuário do serviço, a configuração padrão e a unidade
do systemd:

```sh
HEADSCALE_VERSION="X.Y.Z"   # a versão mais recente em github.com/juanfont/headscale/releases
HEADSCALE_ARCH="amd64"
wget --output-document=headscale.deb \
  "https://github.com/juanfont/headscale/releases/download/v${HEADSCALE_VERSION}/headscale_${HEADSCALE_VERSION}_linux_${HEADSCALE_ARCH}.deb"
sudo apt install ./headscale.deb
```

A unidade do systemd já roda o serviço como um usuário sem privilégios, com a única
capacidade extra de abrir portas baixas (`CAP_NET_BIND_SERVICE`), o que permite escutar
direto na 443.

---

## Passo 3: configurar o Headscale

Em `/etc/headscale/config.yaml`, os campos que importam aqui:

```yaml
server_url: https://headscale.seudominio.com.br
listen_addr: 0.0.0.0:443

# Certificado automático (Let's Encrypt), validado pela porta 80
tls_letsencrypt_hostname: headscale.seudominio.com.br
tls_letsencrypt_challenge_type: HTTP-01
tls_letsencrypt_listen: ":http"

prefixes:
  v4: 100.64.0.0/10
  v6: fd7a:115c:a1e0::/48

derp:
  server:
    enabled: true              # o relay DERP embutido, na sua VPS
    region_id: 999
    stun_listen_addr: "0.0.0.0:3478"
    ipv4: 203.0.113.10         # IP público da VPS
  # urls: []                   # descomente para usar SÓ o seu DERP

policy:
  path: /etc/headscale/policy.hujson
```

Sobre o `urls: []`: por padrão, o Headscale soma o seu DERP aos relays públicos gratuitos do
Tailscale. Esvaziar a lista deixa só o seu, e a documentação avisa que isso cria um ponto
único de falha. Como o conteúdo é cifrado de qualquer jeito, manter os dois é razoável.

```sh
sudo systemctl restart headscale
sudo systemctl status headscale
```

---

## Passo 4: usuário, chaves de acesso e política

```sh
sudo headscale users create galera
sudo headscale users list      # anote o ID do usuário
sudo headscale preauthkeys create --user <ID> --expiration 1h
```

Uma chave por pessoa, de **uso único** (o padrão; `--reusable` existe, e não é para isto) e
com validade curta. Mande cada uma **no privado**.

A política, em `/etc/headscale/policy.hujson` (HuJSON: JSON com comentários):

```jsonc
{
  // Só a galera fala com a galera.
  // Sem política nenhuma, o Headscale libera tudo entre todos os nós.
  "grants": [
    { "src": ["galera@"], "dst": ["galera@"], "ip": ["*"] }
  ]
}
```

```sh
sudo systemctl reload headscale
```

Com uma política carregada, tudo que não foi liberado é negado. Se um dia a rede tiver outras
máquinas (um servidor de casa, um NAS, Network-Attached Storage), elas ficam fora do alcance
da galera sem nenhum esforço extra.

---

## Passo 5: cada PC entra na rede

**Windows** (depois de instalar o Tailscale), no PowerShell:

```powershell
tailscale up --login-server https://headscale.seudominio.com.br --authkey <CHAVE>
```

E, no ícone do Tailscale na bandeja: Preferences > **Run unattended**, para a rede continuar
de pé mesmo sem ninguém logado. Sem chave, `tailscale login --login-server <URL>` abre o
navegador e o registro é aprovado no servidor.

**Linux:**

```sh
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up --login-server https://headscale.seudominio.com.br --authkey <CHAVE>
```

Na VPS, confira quem entrou:

```sh
sudo headscale nodes list
```

---

## Passo 6: a conexão é direta ou pelo relay?

```sh
tailscale status
# 100.64.0.2   pc-do-bob   galera   windows   active; direct 198.51.100.7:41641, ...
# 100.64.0.3   pc-da-carol galera   linux     active; relay "headscale", ...

tailscale ping 100.64.0.2
# pong from pc-do-bob (100.64.0.2) via DERP(headscale) in 31ms
# pong from pc-do-bob (100.64.0.2) via 198.51.100.7:41641 in 12ms
```

- `direct` / `via <ip>:<porta>`: o furo abriu. É o que você quer para vídeo.
- `relay` / `via DERP(...)`: funciona, com mais atraso e usando a banda da VPS.
  Costuma melhorar depois do primeiro `tailscale ping`; se não, o NAT de alguém é "difícil".

---

## Passo 7: o Peeroxide na rede nova

1. Quem transmite escolhe o preset **Internet / VPN · 720p · 24 fps** (teto de 2 Mbps).
2. **Start broadcasting** > **Copy connect string** > escolhe o adaptador do Tailscale
   (o endereço `100.x`).
3. Manda a string no grupo. Quem vai assistir cola em **Connect manually**.
4. Pronto: a pessoa fica em **Saved**. Como a porta é fixa, da próxima vez é um clique.

Três detalhes:

- **A descoberta automática não funciona aqui:** a rede do Tailscale não carrega multicast.
  A connect string é necessária **uma vez** por pessoa.
- **Firewall do Windows:** adaptadores virtuais costumam ser classificados como rede
  **Pública**. No prompt do firewall, marque Privada **e** Pública.
- **Transmitindo do Linux:** libere a porta UDP (User Datagram Protocol) do Peeroxide (o número depois do `:` na connect
  string), por exemplo `sudo ufw allow <porta>/udp`.

---

## Em quem você confia agora?

As camadas de um quadro de vídeo atravessando a internet:

```
┌--------------------------------------------------------------------------┐
| UDP pela internet: IP público de casa -> IP público do amigo             |
|  ┌--------------------------------------------------------------------┐  |
|  | WireGuard: cifrado com as chaves dos dois PCs (ChaCha20-Poly1305)  |  |
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
```

| Quem                    | O que vê                                                                         |
|-------------------------|----------------------------------------------------------------------------------|
| Sua operadora           | Pacotes UDP cifrados entre dois IPs; horários e volume                           |
| A VPS (plano de controle) | Quem está na rede, quando está online, chaves públicas, IPs públicos, a política |
| O DERP (se usado)       | Pacotes WireGuard cifrados e o volume                                            |
| Alguém fora da rede     | Nada: não tem endereço na rede, e a política barra                               |
| Alguém da galera        | Pode assistir enquanto você transmite (é o objetivo)                             |

---

## E se a VPS for invadida?

É a pergunta certa, porque a VPS passou a ser a peça central de confiança. O que um invasor
com controle total do Headscale consegue:

1. **Colocar um nó novo na rede e liberar o acesso dele.** Esse nó alcança sua porta e
   **consegue assistir** enquanto você transmite: é o AC-02, que só fecha na 0.7 (aprovar
   quem assiste, TLS mútuo). Até lá, o alarme é o contador **"N viewers"** ao lado do LIVE:
   se a galera é três e aparecem quatro, tem alguém a mais.
2. **Mentir sobre as chaves WireGuard** e se colocar no meio do túnel. Aí ele tira a camada
   do WireGuard e encontra... QUIC com TLS (Transport Layer Security) 1.3, fixado no certificado de quem transmite.
   **Não consegue ler, nem alterar, nem se passar por quem transmite.** Pode derrubar pacotes,
   ou se conectar como mais um espectador, que é o item 1.
3. O Tailscale tem um recurso para exatamente esse cenário (Tailnet Lock: os nós só aceitam
   chaves assinadas por nós confiáveis), mas ele **não aparece** na lista de recursos
   suportados pelo Headscale.

> **A VPS decide quem entra na rede. Ela não decide o que você vê, nem consegue ver o que
> você transmite.** É a separação entre "carregar os bytes" e "ver o conteúdo" que o Módulo 01
> perguntou se era possível.

---

## Checklist de segurança da VPS

- [ ] SSH só com chave; `PasswordAuthentication no`.
- [ ] Atualizações de segurança automáticas (`unattended-upgrades`).
- [ ] Firewall com só 22/tcp, 80/tcp, 443/tcp e 3478/udp.
- [ ] Headscale sempre na versão mais recente.
- [ ] Chaves pré-autorizadas de uso único e validade curta, enviadas no privado.
- [ ] Uma política carregada, mesmo que a rede seja só da galera.
- [ ] `sudo headscale nodes list` de vez em quando; `sudo headscale nodes delete` no que você
      não reconhecer.
- [ ] Backup de `/var/lib/headscale` (banco SQLite e as chaves privadas do servidor).
- [ ] A porta de métricas fica em `127.0.0.1` (o padrão); não exponha.

E se a VPS simplesmente cair? Pela arquitetura do Tailscale, os túneis já estabelecidos entre
os PCs em geral continuam de pé; o que para é a entrada de nós novos e a propagação de mudanças.

---

## O placar de confiança final

| Solução                    | Quem carrega o vídeo                          | Quem consegue ver                                  | Em quem você confia                                   | Custo                        | Se cair...                        |
|----------------------------|-----------------------------------------------|----------------------------------------------------|-------------------------------------------------------|------------------------------|-----------------------------------|
| Discord                    | Servidores do Discord                         | Quem está no canal                                 | Uma empresa conhecida                                 | Grátis                       | Ninguém transmite                 |
| VPN grátis                 | Discord, via servidor de um estranho          | + o operador da VPN                                | Um desconhecido anônimo                               | "Grátis"                     | Bloqueada pelo Discord            |
| Proxy do Equador           | Discord, via proxy público                    | + o dono do proxy, para todos os apps              | Um desconhecido, com todo o seu tráfego               | "Grátis"                     | Some sem aviso                    |
| Site com anúncio           | O site (talvez)                               | O site, e quem ele quiser                          | O site, os anunciantes e os scripts deles             | Sua atenção e seus dados     | A sala acaba                      |
| O ideal                    | Os PCs da galera, direto                      | Só quem você escolher                              | Na sua rede, seja ela LAN ou VLAN (LAN virtual), e na criptografia                    | Zero                         | Só aquela transmissão para        |
| Peeroxide (LAN)            | Os PCs, direto (QUIC + TLS 1.3)               | Quem alcança sua porta na rede (até a 0.7)         | Criptografia; ID fixado; TOFU; libde265 e OpenH264    | Zero                         | Só aquela transmissão para        |
| **Peeroxide + Headscale**  | **Os PCs, direto (WireGuard + QUIC/TLS); DERP cifrado se preciso** | **A galera, e só quem a sua VPS deixar entrar (até a 0.7)** | **Criptografia; a sua VPS para "quem entra"** | **Uma VPS pequena e um domínio** | **Túneis existentes em geral seguem; ninguém novo entra** |

---

## Epílogo

Hoje, a noite da galera ficou assim: **voz no Discord**, que nunca deixou de funcionar,
e **tela no Peeroxide**, com o Discord silenciado no áudio compartilhado para ninguém ouvir
o próprio eco. Nenhum proxy, nenhum site, nenhuma VPN de desconhecido.

O que vem pela frente, segundo o [roadmap](https://github.com/gventino/peeroxide/blob/main/docs/roadmap.md):

| Versão | Objetivo                                                                                   |
|--------|--------------------------------------------------------------------------------------------|
| Agora  | Corrigir os bugs conhecidos (CI verde, contador de fps que cai com tela parada, e outros)  |
| 0.7    | **Controles de privacidade** (AC-02): ver quem assiste, expulsar, aprovar/negar, senha, TLS mútuo |
| 0.8    | macOS e Linux testados de verdade, com áudio e H.265 na GPU (Graphics Processing Unit)                                 |
| 0.9    | Distribuição: instalador, releases pelo CI (Continuous Integration), assinatura de código                           |
| 1.0    | Estável: fuzzing e decodificação isolada (AC-09), política de compatibilidade              |

E, na lista de ideias sem data, uma que fecha o círculo deste material: **descoberta entre
sub-redes e VPNs que bloqueiam multicast**, o que dispensaria até a connect string.

> A pergunta nunca foi "qual app substitui o Discord". Foi **"em quem você está confiando
> quando compartilha sua tela?"**. Agora dá para responder com precisão: nos seus amigos,
> numa VPS que é sua, e na matemática.

---

## Discussão

- A VPS saiu do caminho do vídeo, mas ficou no caminho de "quem entra". Existe um jeito de
  tirá-la também desse papel? O que se perderia?
- Por que não usar só os relays públicos do Tailscale e dispensar o DERP embutido? E o contrário?
- Se o AC-02 fosse resolvido amanhã (TLS mútuo e aprovação), o que mudaria na análise
  "e se a VPS for invadida"?
- O contador "N viewers" é um controle de segurança? Quais são os limites dele?

---

## Resumo

| Conceito                   | O que é                                                                      |
|----------------------------|------------------------------------------------------------------------------|
| Rede sobreposta            | Uma rede virtual em que todos os PCs parecem estar na mesma LAN              |
| Plano de controle          | Quem está na rede e com quais chaves: o Headscale, na sua VPS                |
| Plano de dados             | O túnel WireGuard, direto entre os PCs                                       |
| Hole punching / STUN       | Como dois PCs atrás de NAT abrem caminho um para o outro                     |
| DERP                       | Relay cifrado de último recurso                                              |
| Política (grants)          | Quem fala com quem; sem política, tudo liberado                              |
| Connect string             | Necessária uma vez, porque a rede do Tailscale não carrega multicast         |
| Duas camadas de cifra      | WireGuard por fora, QUIC/TLS 1.3 com certificado fixado por dentro           |

---

## Referências deste módulo

- Headscale. *Documentação oficial*: instalação, TLS, DERP, políticas e conexão de clientes Windows ([headscale.net](https://headscale.net/stable/))
- Donenfeld (2017). *WireGuard: Next Generation Kernel Network Tunnel.*
- Ford, Srisuresh & Kegel (2005). *Peer-to-Peer Communication Across Network Address Translators.*
- Anderson (2020). *How NAT traversal works.* Blog do Tailscale.
- Weil et al. (2012), RFC 6598 - o bloco `100.64.0.0/10`
- Cheshire & Krochmal (2013), RFC 6762 - por que o mDNS fica na rede local
- Peeroxide, README - "Network requirements"; `docs/roadmap.md`
