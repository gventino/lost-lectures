#set text(font: "New Computer Modern", size: 11pt, lang: "pt")
#set page(margin: 2cm)
#set heading(numbering: "1.1")
#set par(justify: true)

= Módulo 02: Lamport Clock


#line(length: 100%, stroke: 0.5pt + luma(200))


== Objetivo


Implementar um *relógio lógico de Lamport* e entender suas regras,
propriedades e limitações.

#line(length: 100%, stroke: 0.5pt + luma(200))


== O que é um Lamport Clock?


Um *contador monotônico* (inteiro que só cresce) por processo.

- Não mede tempo real - mede *ordem lógica*
- Garante: se `a → b`, então `C(a) < C(b)`
- *Não* garante o inverso: `C(a) < C(b)` não significa que `a → b`

#block(inset: (left: 1em), fill: luma(245), radius: 4pt, width: 100%)[
  Referência: Lamport, L. (1978), Seção 2 - "The Partial Ordering", pp. 559–560.
]


#line(length: 100%, stroke: 0.5pt + luma(200))


== As três regras (do paper original)


=== Regra 1: Evento interno


Antes de qualquer evento, incrementa o clock.

```
t ← t + 1
```


=== Regra 2: Envio de mensagem


Incrementa o clock e anexa o valor à mensagem.

```
t ← t + 1
enviar(mensagem, t)
```


=== Regra 3: Recebimento de mensagem


Ao receber uma mensagem com timestamp `t_msg`:

```
t ← max(t_local, t_msg) + 1
```


#block(inset: (left: 1em), fill: luma(245), radius: 4pt, width: 100%)[
  Estas são as condições IR1 e IR2 definidas em Lamport (1978), p. 560.
]


#line(length: 100%, stroke: 0.5pt + luma(200))


== Exemplo visual


```
Processo A          Processo B          Processo C
    |                   |                   |
    +- tick (1)         |                   |
    |                   |                   |
    +- send ----------> +- receive          |
    |  t=2              |  max(0,2)+1 = 3   |
    |                   |                   |
    |                   +- tick (4)          |
    |                   |                   |
    |                   +- send ----------> +- receive
    |                   |  t=5              |  max(0,5)+1 = 6
    |                   |                   |
    +- tick (3)         |                   |
    |                   |                   |
```


A → B: `C(A_send) = 2 < C(B_receive) = 3` Sim
B → C: `C(B_send) = 5 < C(C_receive) = 6` Sim

#line(length: 100%, stroke: 0.5pt + luma(200))


== Pseudocódigo: Estrutura


```
estrutura LamportClock:
    id_nó    : texto       -- identificador do processo
    tempo    : inteiro     -- contador lógico, inicia em 0
```


```
estrutura LamportTimestamp:
    id_nó    : texto
    tempo    : inteiro
```


#line(length: 100%, stroke: 0.5pt + luma(200))


== Pseudocódigo: Operações


```
função NOVO_CLOCK(id_nó):
    retornar LamportClock { id_nó: id_nó, tempo: 0 }

função TICK(clock):
    clock.tempo ← clock.tempo + 1
    retornar clock.tempo

função ENVIAR(clock):
    clock.tempo ← clock.tempo + 1
    retornar LamportTimestamp { id_nó: clock.id_nó, tempo: clock.tempo }

função RECEBER(clock, timestamp):
    clock.tempo ← max(clock.tempo, timestamp.tempo) + 1
    retornar clock.tempo
```


#line(length: 100%, stroke: 0.5pt + luma(200))


== Timestamp: Serialização e ordenação


*Serialização texto:* `"nome-do-processo:42"`

*Ordem total determinística:*
```
função COMPARAR(ts_a, ts_b):
    se ts_a.tempo ≠ ts_b.tempo:
        retornar comparar_inteiros(ts_a.tempo, ts_b.tempo)
    senão:
        retornar comparar_texto(ts_a.id_nó, ts_b.id_nó)   -- desempate lexicográfico
```


#block(inset: (left: 1em), fill: luma(245), radius: 4pt, width: 100%)[
  A ordem total é definida em Lamport (1978), Seção 3 - "Ordering the Events Totally", p. 561. O desempate por identificador do processo garante que dois timestamps distintos nunca são considerados "iguais".
]


#line(length: 100%, stroke: 0.5pt + luma(200))


== Propriedades garantidas


=== Clock Condition (Condição do Relógio)


#block(inset: (left: 1em), fill: luma(245), radius: 4pt, width: 100%)[
  Se `a → b`, então `C(a) < C(b)`
]


Eventos causalmente relacionados são sempre ordenados corretamente.

=== Monotonicidade


O clock nunca regride. TICK, ENVIAR e RECEBER sempre aumentam o valor.

=== Limitação fundamental


#block(inset: (left: 1em), fill: luma(245), radius: 4pt, width: 100%)[
  `C(a) < C(b)` *NÃO* implica que `a → b`
]


Dois eventos independentes podem ter timestamps com `C(a) < C(b)` por acaso.
O Lamport Clock *não detecta concorrência*.

#block(inset: (left: 1em), fill: luma(245), radius: 4pt, width: 100%)[
  Como Lamport nota no paper: "o fato de C(a) #sym.lt C(b) não significa que a → b" (Lamport, 1978, p. 560). Esta é a motivação para Vector Clocks.
]


#line(length: 100%, stroke: 0.5pt + luma(200))


== Quando usar Lamport Clock?


#table(
  columns: 2,
  inset: 8pt,
  align: left,
  [*Cenário*],
  [*Lamport Clock serve?*],
  [Ordenar logs de forma consistente],
  [Sim],
  [Sequenciar eventos em um event store],
  [Sim],
  [Detectar escritas concorrentes (conflitos)],
  [Não],
  [Saber se dois eventos são independentes],
  [Não],
  [Implementar exclusão mútua distribuída],
  [Sim (vide paper)],
)


#line(length: 100%, stroke: 0.5pt + luma(200))


== Na prática: o que muda no seu dia a dia


=== Antes (sem Lamport Clock)


```
[2024-01-15 10:30:00.123] order-service:   Pedido #42 criado
[2024-01-15 10:30:00.089] payment-service: Pagamento #42 aprovado
[2024-01-15 10:30:00.201] inventory-svc:   Estoque #42 reservado
```


Pagamento antes do pedido? Relógios dessincronizados. Não dá para confiar.

=== Depois (com Lamport Clock)


```
[LC=1] order-service:   Pedido #42 criado
[LC=2] payment-service: Pagamento #42 aprovado     ← recebeu LC=1, fez max(0,1)+1=2
[LC=3] inventory-svc:   Estoque #42 reservado      ← recebeu LC=2, fez max(0,2)+1=3
```


Ordem garantida: 1 #sym.lt 2 #sym.lt 3. *Sem ambiguidade, sem depender de NTP.*

=== Custo de adoção


- *Um inteiro a mais* por serviço (o contador)
- *Um header a mais* por request (`X-Causality-Lamport: order-service:42`)
- *Três linhas de lógica* por request (tick no envio, max+1 no recebimento)

#block(inset: (left: 1em), fill: luma(245), radius: 4pt, width: 100%)[
  É mais simples que configurar o NTP corretamente - e mais confiável.
]


#line(length: 100%, stroke: 0.5pt + luma(200))


== Exercício rápido (5 min)


Dados três processos A, B, C, simule no papel:

+ A faz TICK (A=1)
+ A faz ENVIAR para B (A=2, msg carrega t=2)
+ B faz RECEBER (B = max(0,2)+1 = 3)
+ C faz TICK (C=1)
+ B faz ENVIAR para C (B=4, msg carrega t=4)
+ C faz RECEBER (C = max(1,4)+1 = 5)

*Pergunta:* C sabe que A existiu? Qual o clock de C agora?

*Resposta:* C tem clock=5. A causalidade A→B→C está refletida no valor.
Mas C *não sabe* diferenciar se o evento de A aconteceu antes ou concorrente
ao tick que C fez no passo 4.

#block(inset: (left: 1em), fill: luma(245), radius: 4pt, width: 100%)[
  Este exercício é adaptado de Coulouris et al. (2012), Seção 14.4, Figura 14.6.
]


#line(length: 100%, stroke: 0.5pt + luma(200))


== Resumo


#table(
  columns: 2,
  inset: 8pt,
  align: left,
  [*Conceito*],
  [*Descrição*],
  [Lamport Clock],
  [Contador monotônico por processo],
  [TICK],
  [Evento interno: `t ← t + 1`],
  [ENVIAR],
  [Envio: `t ← t + 1`, retorna timestamp],
  [RECEBER(ts)],
  [Recebimento: `t ← max(t, ts) + 1`],
  [Clock Condition],
  [Se `a → b`, então `C(a) < C(b)`],
  [Limitação],
  [Não detecta concorrência],
  [Próximo passo],
  [Vector Clock resolve essa limitação],
)


#line(length: 100%, stroke: 0.5pt + luma(200))


== Referências deste módulo


- Lamport (1978), Seções 2–3, pp. 559–561
- Coulouris et al. (2012), Seção 14.4 "Logical time and logical clocks"
- Tanenbaum & Van Steen (2017), Seção 6.2 "Logical Clocks"
