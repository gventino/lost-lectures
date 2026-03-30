#set text(font: "New Computer Modern", size: 11pt, lang: "pt")
#set page(margin: 2cm)
#set heading(numbering: "1.1")
#set par(justify: true)

= Módulo 04: Vector Clock


#line(length: 100%, stroke: 0.5pt + luma(200))


== Objetivo


Implementar um *relógio vetorial* que captura a relação causal completa
entre eventos - incluindo a detecção de concorrência.

#line(length: 100%, stroke: 0.5pt + luma(200))


== De Lamport Clock para Vector Clock


#table(
  columns: 3,
  inset: 8pt,
  align: left,
  [*Propriedade*],
  [*Lamport Clock*],
  [*Vector Clock*],
  [Estrutura],
  [1 contador (inteiro)],
  [N contadores (um/proc)],
  [Se `a → b`],
  [`C(a) < C(b)` Sim],
  [`V(a) < V(b)` Sim],
  [Se `C(a) < C(b)`],
  [*Não* implica `a → b`],
  [`V(a) < V(b)` ⟺ `a → b`],
  [Detecta concorrência],
  [Não],
  [Sim],
  [Espaço por mensagem],
  [O(1)],
  [O(N) - N = nº processos],
)


#block(inset: (left: 1em), fill: luma(245), radius: 4pt, width: 100%)[
  *Strong Clock Condition:* `V(a) < V(b)` se e somente se `a → b` Fidge (1988) e Mattern (1989) propuseram esta extensão independentemente. Coulouris et al. (2012) apresentam ambas as formulações na Seção 14.4.
]


#line(length: 100%, stroke: 0.5pt + luma(200))


== Estrutura


Cada processo mantém um vetor com *um contador para cada processo* no sistema:

```
Processo "svc-a" mantém:
  { svc-a: 3, svc-b: 1, svc-c: 0 }
       ^          ^          ^
  meus eventos  último que  nunca vi
                vi de B     nada de C
```


=== Pseudocódigo


```
estrutura VectorClock:
    id_nó    : texto
    vetores  : mapa de (texto → inteiro)     -- um contador por processo
```


```
estrutura VectorTimestamp:
    vetores  : mapa de (texto → inteiro)     -- snapshot imutável
```


#line(length: 100%, stroke: 0.5pt + luma(200))


== As três regras


=== Regra 1: Evento interno (TICK)


Incrementa *apenas* o contador do processo local.

```
função TICK(vc):
    vc.vetores[vc.id_nó] ← vc.vetores[vc.id_nó] + 1
```


=== Regra 2: Envio (ENVIAR)


Incrementa o contador local e envia *todo o vetor* junto com a mensagem.

```
função ENVIAR(vc):
    vc.vetores[vc.id_nó] ← vc.vetores[vc.id_nó] + 1
    retornar cópia(vc.vetores)    -- snapshot completo
```


=== Regra 3: Recebimento (RECEBER)


Para *cada* entrada no vetor, toma o máximo. Depois incrementa o local.

```
função RECEBER(vc, timestamp_recebido):
    para cada nó N em timestamp_recebido:
        vc.vetores[N] ← max(vc.vetores[N], timestamp_recebido[N])
    vc.vetores[vc.id_nó] ← vc.vetores[vc.id_nó] + 1
```


#block(inset: (left: 1em), fill: luma(245), radius: 4pt, width: 100%)[
  Regras definidas em Mattern (1989), Seção 3.1, e equivalentes às formuladas por Fidge (1988). Apresentadas em forma unificada em Coulouris et al. (2012), Figura 14.7.
]


#line(length: 100%, stroke: 0.5pt + luma(200))


== Exemplo visual detalhado


```
     svc-a              svc-b              svc-c
  {a:0,b:0,c:0}     {a:0,b:0,c:0}     {a:0,b:0,c:0}
       |                  |                  |
  TICK |                  |                  |
  {a:1,b:0,c:0}          |                  |
       |                  |                  |
 ENVIAR+----------------> |                  |
  {a:2,b:0,c:0}     RECEBER                 |
       |            max + tick               |
       |            {a:2,b:1,c:0}            |
       |                  |                  |
       |           ENVIAR +----------------> |
       |            {a:2,b:2,c:0}       RECEBER
       |                  |            max + tick
       |                  |            {a:2,b:2,c:1}
       |                  |                  |
  TICK |                  |                  |
  {a:3,b:0,c:0}          |                  |
       |                  |                  |
```


Agora compare:
- svc-a `{a:3,b:0,c:0}` vs svc-c `{a:2,b:2,c:1}`
- a[a]=3 #sym.gt c[a]=2, mas a[b]=0 #sym.lt c[b]=2 → *Concurrent!* Sim

#block(inset: (left: 1em), fill: luma(245), radius: 4pt, width: 100%)[
  Diagrama adaptado de Tanenbaum & Van Steen (2017), Figura 6.14.
]


#line(length: 100%, stroke: 0.5pt + luma(200))


== Operações adicionais


=== SNAPSHOT: captura sem modificar


```
função SNAPSHOT(vc):
    retornar cópia(vc.vetores)    -- NÃO incrementa nenhum contador
```


Útil para anexar metadata causal a eventos sem alterar o clock.

=== MERGE: combina sem incrementar


```
função MERGE(vc_a, vc_b):
    para cada nó N em (chaves de vc_a ∪ chaves de vc_b):
        resultado[N] ← max(vc_a[N], vc_b[N])
    -- NÃO incrementa nenhum contador local
```


Útil para *agregadores* que reconstroem estado causal global.
Note: MERGE é *comutativo* - `MERGE(A,B) = MERGE(B,A)`.

=== CONSULTAR: valor de um nó


```
função CONSULTAR(vc, id_nó):
    retornar vc.vetores[id_nó] ou 0 se ausente
```


#line(length: 100%, stroke: 0.5pt + luma(200))


== Sistema aberto vs. fechado


O Vector Clock suporta *sistema aberto*: processos podem entrar e sair.

```
-- svc-a não conhece svc-d inicialmente
vc_a.vetores = { svc-a: 2, svc-b: 1 }

-- svc-d envia mensagem com timestamp { svc-d: 3 }
RECEBER(vc_a, { svc-d: 3 })

-- Agora vc_a contém svc-d automaticamente:
vc_a.vetores = { svc-a: 3, svc-b: 1, svc-d: 3 }
```


#block(inset: (left: 1em), fill: luma(245), radius: 4pt, width: 100%)[
  Em sistemas grandes, esta propriedade é essencial. Tanenbaum & Van Steen (2017) discutem as implicações na Seção 6.2.2.
]


#line(length: 100%, stroke: 0.5pt + luma(200))


== Trade-offs


#table(
  columns: 2,
  inset: 8pt,
  align: left,
  [*Vantagem*],
  [*Desvantagem*],
  [Detecta concorrência],
  [Tamanho O(N) por mensagem],
  [Relação causal completa],
  [N = número de processos no sistema],
  [Strong Clock Condition],
  [Não escala para milhares de nós],
  [Sem falsos positivos/negativos],
  [Mais complexo que Lamport Clock],
)


=== Quando o tamanho é problema?


- Até ~100 processos: praticamente irrelevante
- 100–1000: mensurável, mas geralmente aceitável
- 1000+: considere *versioned vector clocks* ou *interval tree clocks*

#block(inset: (left: 1em), fill: luma(245), radius: 4pt, width: 100%)[
  Kleppmann (2017) discute alternativas como *dotted version vectors* e *interval tree clocks* no Cap. 5, pp. 184–186. O Amazon Dynamo usa vector clocks truncados para lidar com escala - vide DeCandia et al. (2007), Seção 4.4.
]


#line(length: 100%, stroke: 0.5pt + luma(200))


== Na prática: o bug que você levou 3 dias para achar


=== O cenário


Serviço A e Serviço B atualizam o perfil de um usuário. Em produção,
de vez em quando o nome do usuário "reverte" para um valor antigo.
Os logs mostram timestamps muito próximos. Last-write-wins não resolveu.
Ninguém consegue reproduzir localmente.

=== Sem Vector Clock


```
Log do serviço A:  10:30:00.123 - atualizou nome para "João Silva"
Log do serviço B:  10:30:00.125 - atualizou nome para "João S."
```


Parece que B veio depois. Mas na máquina de A o relógio estava 50ms adiantado.
Na verdade, as escritas foram *simultâneas* (concorrentes). Você nunca descobre.

=== Com Vector Clock


```
Serviço A: {A:5, B:2}  - atualizou nome para "João Silva"
Serviço B: {A:3, B:4}  - atualizou nome para "João S."

COMPARAR → CONCURRENT!  
```


O Vector Clock te diz na hora: *isso é um conflito, não uma sequência*.
Agora você pode: alertar, logar, mergear, ou retornar ao usuário.

#block(inset: (left: 1em), fill: luma(245), radius: 4pt, width: 100%)[
  *3 dias de debugging → 0 dias.* Essa é a proposta de valor.
]


#line(length: 100%, stroke: 0.5pt + luma(200))


== Exercício guiado (10 min)


Simule no papel com 3 processos (P1, P2, P3):

```
1. P1.TICK()                        → P1 = {P1:1, P2:0, P3:0}
2. P2.TICK()                        → P2 = {P1:0, P2:1, P3:0}
3. P1.ENVIAR() → P3.RECEBER()      → P1 = {P1:2, P2:0, P3:0}
                                      P3 = {P1:2, P2:0, P3:1}
4. P2.ENVIAR() → P3.RECEBER()      → P2 = {P1:0, P2:2, P3:0}
                                      P3 = {P1:2, P2:2, P3:2}
5. P1.TICK()                        → P1 = {P1:3, P2:0, P3:0}
```


*Perguntas:*
+ Qual a relação entre P1 (final) e P3 (final)?
+ Qual a relação entre P2 (final) e P3 (final)?
+ P3 "sabe" que P1 e P2 existiram?

*Respostas:*
+ *Concurrent* - P1[P1]=3 #sym.gt P3[P1]=2, mas P1[P2]=0 #sym.lt P3[P2]=2
+ *HappensBefore* - P2 ≤ P3 em todas as dimensões, com P1 e P3 estritamente menor
+ Sim! P3 tem {P1:2, P2:2, P3:2} - sabe que viu 2 eventos de P1 e 2 de P2

#block(inset: (left: 1em), fill: luma(245), radius: 4pt, width: 100%)[
  Exercício adaptado de Tanenbaum & Van Steen (2017), Exercícios do Cap. 6.
]


#line(length: 100%, stroke: 0.5pt + luma(200))


== Resumo


#table(
  columns: 2,
  inset: 8pt,
  align: left,
  [*Conceito*],
  [*Descrição*],
  [Vector Clock],
  [Vetor de contadores, um por processo],
  [Strong Clock Cond.],
  [`V(a) < V(b)` ⟺ `a → b`],
  [TICK],
  [Incrementa só o local],
  [ENVIAR],
  [TICK + snapshot completo do vetor],
  [RECEBER(ts)],
  [Max element-wise + incrementa local],
  [COMPARAR],
  [Compara dois vetores → relação de causalidade],
  [SNAPSHOT],
  [Cópia imutável sem alterar o clock],
  [MERGE],
  [Combina vetores sem incrementar (para agregadores)],
  [Trade-off],
  [Detecta tudo, mas é O(N) por mensagem],
)


#line(length: 100%, stroke: 0.5pt + luma(200))


== Referências deste módulo


- Fidge, C. (1988). *Timestamps in Message-Passing Systems That Preserve the Partial Ordering.*
- Mattern, F. (1989). *Virtual Time and Global States of Distributed Systems.* Seções 3–4.
- Tanenbaum & Van Steen (2017), Seção 6.2.2 - "Vector Clocks"
- Coulouris et al. (2012), Seção 14.4 - "Logical time and logical clocks", Figuras 14.7–14.8
- DeCandia et al. (2007). *Dynamo: Amazon's Highly Available Key-value Store.* Seção 4.4.
- Kleppmann (2017), Caps. 5 e 8 - vector clocks em aplicações reais
