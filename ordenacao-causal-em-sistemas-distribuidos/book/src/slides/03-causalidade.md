# Módulo 03: Relações de Causalidade

---

## Objetivo

Formalizar as **quatro relações possíveis** entre eventos em sistemas distribuídos
e entender como representá-las e compará-las.

---

## As quatro relações

Dados dois eventos `a` e `b`:

```
┌-----------------+------------------------------------------+--------┐
| Relação         | Significado                              | Símbolo|
+-----------------+------------------------------------------+--------+
| HappensBefore   | a causou b (caminho causal de a → b)     |   →    |
| HappensAfter    | b causou a (caminho causal de b → a)     |   ←    |
| Concurrent      | Nenhum causou o outro (independentes)    |   ∥    |
| Equal           | Mesmo estado causal (mesmo vetor)        |   =    |
└-----------------+------------------------------------------+--------┘
```

> A relação *happens-before* é formalmente definida em Lamport (1978), Definição na p. 559.
> A detecção de concorrência via vector clocks foi introduzida por Fidge (1988)
> e Mattern (1989) independentemente.

---

## Representação

```
enumeração CausalityRelation:
    HAPPENS_BEFORE    -- a → b
    HAPPENS_AFTER     -- b → a
    CONCURRENT        -- a ∥ b
    EQUAL             -- a = b
```

---

## Operações úteis

### INVERSO: inverte a perspectiva

Se A *happens-before* B, do ponto de vista de B, A *happens-after*.

```
função INVERSO(relação):
    se relação = HAPPENS_BEFORE:  retornar HAPPENS_AFTER
    se relação = HAPPENS_AFTER:   retornar HAPPENS_BEFORE
    se relação = CONCURRENT:      retornar CONCURRENT
    se relação = EQUAL:           retornar EQUAL
```

### É_CAUSAL: existe relação de causa-efeito?

```
função É_CAUSAL(relação):
    retornar relação = HAPPENS_BEFORE ou relação = HAPPENS_AFTER
```

### É_CONCORRENTE: são eventos independentes?

```
função É_CONCORRENTE(relação):
    retornar relação = CONCURRENT
```

---

## Propriedades formais

A relação happens-before forma uma **ordem parcial estrita** (Lamport, 1978, p. 559):

| Propriedade      | Definição                                               | Notação             |
|------------------|---------------------------------------------------------|---------------------|
| Irreflexividade  | Um evento não happens-before si mesmo                   | ¬(a → a)            |
| Antissimetria    | Se `a → b`, então ¬(`b → a`)                            | Direção única       |
| Transitividade   | Se `a → b` e `b → c`, então `a → c`                     | Cadeia causal       |

A concorrência é **simétrica**: se `a ∥ b`, então `b ∥ a`.

> "A relação '→' é uma ordem parcial irreflexiva sobre o conjunto de todos
> os eventos no sistema." - Lamport (1978), p. 559.

---

## Antes do algoritmo: um exemplo concreto

Imagine um sistema de e-commerce. Três coisas acontecem:

```
Serviço de Pedidos:     "pedido #42 criado"           (evento e1)
Serviço de Pedidos:     envia notificação → Pagamento  (evento e2)
Serviço de Pagamento:   "pagamento #42 aprovado"       (evento e3)
Serviço de Estoque:     "reserva de estoque #42"       (evento e4)
```

Quais relações existem?

```
e1 → e2   O pedido foi criado antes de notificar (mesmo serviço)
e2 → e3   A notificação causou o processamento do pagamento (mensagem)
e1 → e3   Transitividade: pedido causou pagamento (e1 → e2 → e3)

e4 ∥ e3   Estoque e Pagamento rodaram independentemente - CONCURRENT!
```

**Se e4 ∥ e3**, significa que a reserva de estoque e o pagamento aconteceram
sem coordenação. Se ambos escrevem no mesmo registro do pedido,
temos um **conflito detectável**.

Sem Vector Clock, o log diria "pagamento às 10:30:01, estoque às 10:30:02"
e você assumiria que pagamento veio antes. **Mas isso é coincidência do relógio,
não causalidade.**

---

## Visualizando causalidade

```
Processo P1     Processo P2     Processo P3
    |               |               |
    +-- e1          |               |
    |               |               |
    +-- send ------>+-- e2          |
    |               |               |
    |               +-- send ------>+-- e3
    |               |               |
    +-- e4          |               |
    |               |               |

Relações:
  e1 → e2  (send/receive)
  e2 → e3  (send/receive)
  e1 → e3  (transitividade: e1 → e2 → e3)
  e1 → e4  (mesmo processo, e1 antes de e4)
  e4 ∥ e2  (nenhum causou o outro!)
  e4 ∥ e3  (nenhum causou o outro!)
```

> Diagrama adaptado de Coulouris et al. (2012), Figura 14.5.

---

## O algoritmo de comparação (para Vector Clocks)

Dados dois vetores `V(a)` e `V(b)`:

```
                           ┌- todos iguais ---------> EQUAL
                           |
V(a) vs V(b) -------------+- a[i] ≤ b[i] ∀i ------> HAPPENS_BEFORE
                           |  (com pelo menos um <)
                           |
                           +- a[i] ≥ b[i] ∀i ------> HAPPENS_AFTER
                           |  (com pelo menos um >)
                           |
                           └- nenhum dos acima -----> CONCURRENT
                              (a[i]<b[i] e a[j]>b[j])
```

### Pseudocódigo

```
função COMPARAR(V_a, V_b):
    a_leq_b ← verdadeiro     -- a[i] ≤ b[i] para todo i?
    b_leq_a ← verdadeiro     -- b[i] ≤ a[i] para todo i?

    para cada nó N em (chaves de V_a ∪ chaves de V_b):
        va ← V_a[N] ou 0 se ausente
        vb ← V_b[N] ou 0 se ausente

        se va > vb:  a_leq_b ← falso
        se vb > va:  b_leq_a ← falso

    se a_leq_b e b_leq_a:     retornar EQUAL
    se a_leq_b e ¬b_leq_a:    retornar HAPPENS_BEFORE
    se ¬a_leq_b e b_leq_a:    retornar HAPPENS_AFTER
    se ¬a_leq_b e ¬b_leq_a:   retornar CONCURRENT
```

> Algoritmo descrito em Mattern (1989), Seção 3, e formalizado em
> Schwarz & Mattern (1994), "Detecting Causal Relationships in Distributed Computations".

---

## Por que "Concurrent" é valioso?

Em sistemas distribuídos, detectar concorrência permite:

- **Detecção de conflitos** - duas escritas simultâneas no mesmo recurso
- **Estratégias de merge** - CRDTs, operational transform
- **Alertas** - "estes dois serviços escreveram ao mesmo tempo"
- **Debugging** - "este bug é um race condition, não um bug de lógica"

> Com Lamport Clock, eventos concorrentes parecem ordenados.
> Com Vector Clock, **sabemos** que não há ordem entre eles.

### O que muda no seu projeto?

Hoje, quando dois serviços escrevem no mesmo recurso "ao mesmo tempo",
você provavelmente usa uma dessas estratégias:

| Estratégia atual          | Problema                                          |
|---------------------------|---------------------------------------------------|
| Last-write-wins (LWW)     | Quem "ganha" depende do clock da máquina          |
| Lock distribuído (Redis)   | Adiciona ponto de falha + latência                |
| Fila única (Kafka)         | Serializa tudo, perde throughput                   |
| Ignorar (...)              | Bug intermitente que ninguém consegue reproduzir   |

Com detecção de causalidade, você ganha uma **quinta opção**: saber quando
o conflito existe e tratá-lo explicitamente - sem lock, sem fila, sem ignorar.

> Kleppmann (2017) discute as implicações práticas em "Designing Data-Intensive
> Applications", Capítulo 5 - "Detecting Concurrent Writes", pp. 184–190.

---

## Exercício rápido (3 min)

Dados os vetores:

```
V(a) = {P1: 3, P2: 2, P3: 1}
V(b) = {P1: 3, P2: 4, P3: 2}
V(c) = {P1: 4, P2: 1, P3: 3}
```

Determine:
1. `COMPARAR(a, b)` = ?
2. `COMPARAR(b, a)` = ?
3. `COMPARAR(a, c)` = ?
4. `COMPARAR(b, c)` = ?

**Respostas:**
1. HAPPENS_BEFORE (a ≤ b em todas as dimensões, com P2 e P3 estritamente menor)
2. HAPPENS_AFTER (inverso do anterior)
3. CONCURRENT (P1: 3<4 mas P2: 2>1)
4. CONCURRENT (P2: 4>1 mas P1: 3<4 e P3: 2<3)

> Exercício adaptado de Coulouris et al. (2012), Exercise 14.9.

---

## Resumo

| Conceito          | Descrição                                           |
|-------------------|-----------------------------------------------------|
| HappensBefore     | Caminho causal de A para B                           |
| HappensAfter      | Caminho causal de B para A                           |
| Concurrent        | Nenhum causou o outro - possível conflito           |
| Equal             | Mesmo estado lógico                                  |
| INVERSO           | Inverte a perspectiva (A↔B)                          |
| COMPARAR          | Algoritmo que compara dois vector timestamps         |

---

## Referências deste módulo

- Lamport (1978), Seção 2 - definição de happens-before
- Fidge, C. (1988). *Timestamps in Message-Passing Systems That Preserve the Partial Ordering.*
- Mattern, F. (1989). *Virtual Time and Global States of Distributed Systems.*
- Schwarz & Mattern (1994). *Detecting Causal Relationships in Distributed Computations.*
- Coulouris et al. (2012), Seção 14.4 - algoritmo de comparação
- Kleppmann (2017), Cap. 8 - implicações práticas
