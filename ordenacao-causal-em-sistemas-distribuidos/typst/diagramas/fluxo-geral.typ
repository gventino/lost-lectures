#set text(font: "New Computer Modern", size: 11pt, lang: "pt")
#set page(margin: 2cm)
#set heading(numbering: "1.1")
#set par(justify: true)

= Diagramas de Referência


#block(inset: (left: 1em), fill: luma(245), radius: 4pt, width: 100%)[
  Use estes diagramas para projeção ou desenho no quadro.
]


#line(length: 100%, stroke: 0.5pt + luma(200))


== 1. Problema do Wall Clock


```
Máquina A              Máquina B              Máquina C
(+2s drift)            (correto)              (-1s drift)

10:00:03 - pedido      10:00:01 - pagamento   10:00:00 - estoque
  criado                 processado              reservado

Pela ordem dos timestamps:  C → B → A  (ERRADO!)
Pela ordem real:             A → B → C  (CORRETO!)
```


#line(length: 100%, stroke: 0.5pt + luma(200))


== 2. Relação Happens-Before


```
P1          P2          P3
|           |           |
+-- a       |           |
|           |           |
+-- send -->+-- b       |
|    (a→b)  |           |
|           +-- send -->+-- c
|           |    (b→c)  |
|           |           |
+-- d       |           |
|           |           |

a → b  (mensagem)
b → c  (mensagem)
a → c  (transitividade)
a → d  (mesmo processo)
d ∥ b  (concorrentes!)
d ∥ c  (concorrentes!)
```


#line(length: 100%, stroke: 0.5pt + luma(200))


== 3. Lamport Clock — Fluxo


```
P1 (clock)    P2 (clock)    P3 (clock)
   0              0              0
   |              |              |
   1 - tick       |              |
   |              |              |
   2 - send ----> 3 - recv      |
   |              |              |
   |              4 - tick       |
   |              |              |
   |              5 - send ----> 6 - recv
   |              |              |
   3 - tick       |              |
   |              |              |
```


#line(length: 100%, stroke: 0.5pt + luma(200))


== 4. Vector Clock — Fluxo


```
P1                P2                P3
{1:0,2:0,3:0}    {1:0,2:0,3:0}    {1:0,2:0,3:0}
     |                 |                 |
tick |                 |                 |
{1:1,2:0,3:0}         |                 |
     |                 |                 |
send +---------------->|                 |
{1:2,2:0,3:0}    recv |                 |
     |            {1:2,2:1,3:0}         |
     |                 |                 |
     |            send +---------------->|
     |            {1:2,2:2,3:0}    recv |
     |                 |            {1:2,2:2,3:1}
     |                 |                 |
tick |                 |                 |
{1:3,2:0,3:0}         |                 |
     |                 |                 |

P1 vs P3:
  P1[1]=3 > P3[1]=2  mas  P1[2]=0 < P3[2]=2
  → CONCURRENT ∥
```


#line(length: 100%, stroke: 0.5pt + luma(200))


== 5. Algoritmo de Comparação


```
     V(a) vs V(b)
         |
    ┌----+----┐
    | Para    |
    | cada i: |
    |         |
    | a[i]>b[i]? --> a_leq_b = false
    | b[i]>a[i]? --> b_leq_a = false
    └----+----┘
         |
  ┌------+--------------┐
  |      |              |
  ▼      ▼              ▼
a≤b  &&  b≤a         a≤b  &&  ¬b≤a       ¬a≤b  &&  b≤a       ¬a≤b  &&  ¬b≤a
  |                      |                   |                    |
  ▼                      ▼                   ▼                    ▼
EQUAL              HAPPENS_BEFORE       HAPPENS_AFTER         CONCURRENT
  =                      →                   ←                    ∥
```


#line(length: 100%, stroke: 0.5pt + luma(200))


== 6. Fork-Join


```
        ┌--- B ---┐
A ------+         +---- D
        └--- C ---┘

A.tick() → A.send()-->B.receive() → B.tick() → B.send()--┐
                  └-->C.receive() → C.tick() → C.send()--+
                                                          ▼
                                                    D.receive(B)
                                                    D.receive(C)

B ∥ C  (processaram independentemente)
A → B, A → C, A → D  (causal)
B → D, C → D  (causal)
```


#line(length: 100%, stroke: 0.5pt + luma(200))


== 7. Arquitetura do Transport Layer


```
┌---------------------------------------------┐
|              like-a-clockwork               |
|                                             |
|  LamportClock --> LamportTimestamp          |
|  VectorClock --> VectorTimestamp            |
|  TracedEvent                                |
|       |                                     |
|       ▼                                     |
|  ┌--------------------------------------┐   |
|  |          Transport Layer             |   |
|  +------------+-----------+-------------+   |
|  |   Text     |  Binary   |    JSON     |   |
|  | HashMap    | HashMap   | serde_json  |   |
|  | <Str,Str>  | <Str,u8>  | ::Value     |   |
|  └-----+------+-----+-----+------+------┘   |
|        |            |            |           |
└--------+------------+------------+-----------┘
         |            |            |
         ▼            ▼            ▼
     HTTP/gRPC    Kafka/gRPC    REST API
     (headers)    (rec. hdrs)   (body JSON)
```

