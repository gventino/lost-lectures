# Exercícios — Vector Clock

---

## Exercício 2.1 — Detectando o conflito invisível (Fácil, 10 min)

Dois microsserviços gerenciam o perfil de um usuário. Ambos podem receber
updates de clientes diferentes:

```
Serviço "profile-us" (datacenter US):
    Recebe do cliente Alice: "nome = João Silva"
    TICK(vc_us)  →  vc_us = {us:1, eu:0}

Serviço "profile-eu" (datacenter EU):
    Recebe do cliente Bob: "nome = João S."
    TICK(vc_eu)  →  vc_eu = {us:0, eu:1}
```

**Tarefas:**

1. Determine `COMPARAR(vc_us, vc_eu)`. São causais ou concorrentes?

2. Se usássemos **last-write-wins com wall clock**, qual nome "ganharia"?
   Isso seria correto?

3. Se usássemos **Lamport Clock** em vez de Vector Clock, conseguiríamos
   detectar o conflito? Por quê?

4. Proponha **duas estratégias** para resolver esse conflito em produção.

<details>
<summary>Resposta</summary>

1. **CONCURRENT** — us[us]=1 > eu[us]=0, mas us[eu]=0 < eu[eu]=1. Incomparáveis.

2. Depende de qual máquina tem o relógio "na frente". Não é correto — a
   "vitória" depende de clock drift, não de lógica de negócio.

3. **Não.** Lamport Clock poderia dar LC=1 a ambos, mas mesmo que diferissem,
   `C(a) < C(b)` não implica causalidade. Não há como distinguir concorrência
   de coincidência numérica.

4. Estratégias:
   - **Retornar ambos ao cliente:** "Alice escreveu X, Bob escreveu Y — qual manter?"
     (como o Amazon Dynamo faz com o carrinho de compras)
   - **Regra de negócio:** merge dos campos (se um mudou nome e outro mudou email,
     não há conflito real). Ou: nome mais longo vence, ou mais recente por UUID v7.

</details>

---

## Exercício 2.2 — Simulando o fluxo de um pedido (Médio, 15 min)

Simule o fluxo completo com 3 serviços: Pedidos (P), Pagamento (G), Estoque (E).

```
Fluxo:
1. P cria pedido                  →  P.TICK()
2. P notifica G (HTTP)            →  ts1 = P.ENVIAR()
3. P notifica E (Kafka)           →  ts2 = P.ENVIAR()
4. G recebe e processa pagamento  →  G.RECEBER(ts1), G.TICK()
5. G notifica E (Kafka)           →  ts3 = G.ENVIAR()
6. E recebe de P                  →  E.RECEBER(ts2)
7. E recebe de G                  →  E.RECEBER(ts3)
8. E reserva estoque              →  E.TICK()
```

**Tarefas:**

Preencha o vetor de cada serviço após cada passo:

| Passo | P                  | G                  | E                  |
|-------|--------------------|--------------------|--------------------|
| 0     | {P:0, G:0, E:0}   | {P:0, G:0, E:0}   | {P:0, G:0, E:0}   |
| 1     |                    |                    |                    |
| 2     |                    |                    |                    |
| 3     |                    |                    |                    |
| 4     |                    |                    |                    |
| 5     |                    |                    |                    |
| 6     |                    |                    |                    |
| 7     |                    |                    |                    |
| 8     |                    |                    |                    |

Depois responda:

- A mensagem ts2 (de P para E) e ts3 (de G para E) são causais ou concorrentes?
- Estoque (final) sabe que Pagamento existiu? Como?
- Pedidos (final) sabe o que aconteceu em Estoque?

<details>
<summary>Resposta</summary>

| Passo | P                  | G                  | E                  |
|-------|--------------------|--------------------|--------------------|
| 0     | {P:0, G:0, E:0}   | {P:0, G:0, E:0}   | {P:0, G:0, E:0}   |
| 1     | {P:1, G:0, E:0}   | —                  | —                  |
| 2     | {P:2, G:0, E:0}   | —                  | —                  |
| 3     | {P:3, G:0, E:0}   | —                  | —                  |
| 4     | —                  | {P:2, G:2, E:0}   | —                  |
| 5     | —                  | {P:2, G:3, E:0}   | —                  |
| 6     | —                  | —                  | {P:3, G:0, E:1}   |
| 7     | —                  | —                  | {P:3, G:3, E:2}   |
| 8     | —                  | —                  | {P:3, G:3, E:3}   |

- ts2 = {P:3, G:0, E:0} vs ts3 = {P:2, G:3, E:0}: **CONCURRENT**.
  ts2[P]=3 > ts3[P]=2, mas ts2[G]=0 < ts3[G]=3. São mensagens independentes
  (Pedidos mandou as duas sem esperar resposta de ninguém entre elas).

- Sim! E[G]=3, logo Estoque sabe que Pagamento fez 3 operações.
  O vetor carrega o "conhecimento causal transitivo".

- Não. P termina com {P:3, G:0, E:0}. P não recebeu nenhuma mensagem de E ou G
  depois das notificações — não sabe o que aconteceu downstream.

</details>

---

## Exercício 2.3 — Adicionando ao seu middleware (Médio, 15 min)

No Exercício 1.2, você adicionou Lamport Clock ao middleware.
Agora faça o upgrade para Vector Clock.

**Tarefas:**

1. Modifique o pseudocódigo do middleware para usar Vector Clock em vez de
   Lamport Clock. Quais mudanças são necessárias?

2. O header agora é `X-Causality-Vector: order-svc=3,payment-svc=1`.
   Quanto maior fica o header conforme adicionamos serviços?
   Com 10 serviços, qual o tamanho aproximado?

3. Em quais pontos do seu sistema você adicionaria uma **checagem de concorrência**?
   (Dica: onde dois serviços podem escrever no mesmo recurso.)

4. Escreva o pseudocódigo de uma função `VERIFICAR_CONFLITO` que:
   - Recebe o VectorTimestamp de uma escrita anterior e o VectorTimestamp atual
   - Retorna `true` se são concorrentes (possível conflito)
   - Loga um warning com os dois vetores

<details>
<summary>Resposta</summary>

1. Mudanças:
   - Inicialização: `NOVO_VECTOR_CLOCK("meu-svc", ["svc-a", "svc-b", ...])`
     em vez de `NOVO_CLOCK("meu-svc")`
   - Header: `X-Causality-Vector` em vez de `X-Causality-Lamport`
   - Formato: `svc-a=3,svc-b=1` em vez de `svc-a:42`
   - ENVIAR retorna mapa inteiro em vez de um inteiro
   - RECEBER aceita mapa em vez de inteiro

2. Cada entrada tem ~15-20 chars (ex: "payment-svc=12345").
   Com 10 serviços: ~150-200 bytes. Cabe folgado num header HTTP (limite ~8KB).
   Com 100 serviços: ~1.5-2KB. Ainda ok. Com 1000+: hora de repensar.

3. Pontos de checagem:
   - Antes de UPDATE no banco (comparar vetor da última escrita com o atual)
   - No consumer Kafka quando dois produtores escrevem no mesmo tópico/partição
   - Em APIs de escrita que recebem requests de múltiplos serviços

4. Pseudocódigo:
```
função VERIFICAR_CONFLITO(vetor_anterior, vetor_atual):
    relação ← COMPARAR(vetor_anterior, vetor_atual)
    se relação = CONCURRENT:
        logar("ESCRITA CONCORRENTE DETECTADA")
        logar("  anterior: " + vetor_anterior)
        logar("  atual:    " + vetor_atual)
        retornar verdadeiro
    retornar falso
```

</details>

---

## Exercício 2.4 — Merge vs Receive: quando usar qual? (Rápido, 5 min)

Cenário: você tem um serviço de **monitoramento** que coleta snapshots
dos vector clocks de 10 serviços para montar um dashboard causal.

| Situação                                      | Usar RECEBER ou MERGE? |
|-----------------------------------------------|------------------------|
| Serviço A recebe HTTP request do Serviço B    |                        |
| Consumer Kafka processa mensagem              |                        |
| Dashboard agrega clocks de vários serviços    |                        |
| Serviço reconstrói estado a partir de backup  |                        |
| Health check pega snapshot de outro serviço   |                        |

<details>
<summary>Resposta</summary>

| Situação                                      | Usar RECEBER ou MERGE? | Por quê                                    |
|-----------------------------------------------|------------------------|--------------------------------------------|
| Serviço A recebe HTTP request do Serviço B    | **RECEBER**            | É um evento causal — A recebeu de B        |
| Consumer Kafka processa mensagem              | **RECEBER**            | É um evento causal — consumiu a mensagem   |
| Dashboard agrega clocks de vários serviços    | **MERGE**              | Observador, não participante               |
| Serviço reconstrói estado a partir de backup  | **MERGE**              | Reconstrução, não evento novo              |
| Health check pega snapshot de outro serviço   | **MERGE** (ou nada)    | Observação, não afeta causalidade          |

Regra simples: se **você é participante** da comunicação → RECEBER.
Se **você está observando** → MERGE.

RECEBER incrementa o contador local (cria novo evento).
MERGE só combina (max element-wise, sem incremento).

</details>

---

## Para ir além (referências acadêmicas)

- **Amazon Dynamo e vector clocks truncados:** DeCandia et al. (2007), Seção 4.4.
  Simule o cenário da Figura 3 do paper — 3 nós com escritas concorrentes
  e reconciliação no cliente.

- **Cortes consistentes:** Chandy & Lamport (1985). Use vector clocks para
  verificar se um corte num diagrama de espaço-tempo é consistente.
  Vide Coulouris et al. (2012), Exercise 14.12.

- **Atribuição formal de vector timestamps:** Coulouris et al. (2012),
  Exercise 14.9. Dado um diagrama com 3 processos e 13 eventos, calcule
  todos os vetores e determine todas as relações de causalidade.

- **Comutatividade do merge:** Demonstre formalmente que `MERGE(A, B) = MERGE(B, A)`
  e que `MERGE(MERGE(A, B), C) = MERGE(A, MERGE(B, C))` (associatividade).
  Mattern (1989), Seção 3.

---

## Referências

- Fidge, C. (1988). *Timestamps in Message-Passing Systems That Preserve the Partial Ordering.*
- Mattern, F. (1989). *Virtual Time and Global States of Distributed Systems.*
- Schwarz, R. & Mattern, F. (1994). *Detecting Causal Relationships in Distributed Computations.*
- Chandy, K.M. & Lamport, L. (1985). *Distributed Snapshots.* ACM TOCS, 3(1), 63–75.
- DeCandia, G. et al. (2007). *Dynamo: Amazon's Highly Available Key-value Store.* SOSP '07.
- Coulouris, G. et al. (2012). *Distributed Systems.* 5th ed. Exercises 14.9, 14.12.
- Kleppmann, M. (2017). *Designing Data-Intensive Applications.* Cap. 5, pp. 184–186.
