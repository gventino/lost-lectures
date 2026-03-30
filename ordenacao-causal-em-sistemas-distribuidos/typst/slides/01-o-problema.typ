#set text(font: "New Computer Modern", size: 11pt, lang: "pt")
#set page(margin: 2cm)
#set heading(numbering: "1.1")
#set par(justify: true)

= Módulo 01 — O Problema da Ordenação em Sistemas Distribuídos


#line(length: 100%, stroke: 0.5pt + luma(200))


== Objetivo


Entender por que *não podemos confiar em timestamps físicos* para ordenar eventos
em sistemas distribuídos — e por que isso importa.

#line(length: 100%, stroke: 0.5pt + luma(200))


== O cenário


Imagine três microsserviços:

```
┌---------------┐     ┌---------------┐     ┌---------------┐
| Order Service |---->| Payment Svc   |---->| Inventory Svc |
|  (máquina A)  |     |  (máquina B)  |     |  (máquina C)  |
└---------------┘     └---------------┘     └---------------┘
```


Cada um roda em *máquinas diferentes*, com *relógios diferentes*.

#line(length: 100%, stroke: 0.5pt + luma(200))


== O problema com wall clock


```
Máquina A (relógio adiantado 2s):
  10:00:03.000 — "pedido criado"

Máquina B (relógio correto):
  10:00:01.500 — "pagamento processado"

Máquina C (relógio atrasado 1s):
  10:00:00.200 — "estoque reservado"
```


Pelos timestamps: *estoque foi reservado ANTES do pedido existir* 

Na realidade: pedido → pagamento → estoque (nessa ordem).

#line(length: 100%, stroke: 0.5pt + luma(200))


== Por que isso acontece?


+ *Clock drift* — relógios de hardware derivam ~10-100ms por dia
+ *NTP não é perfeito* — sincronização tem latência e jitter
+ *Sem garantia de precisão* — dois hosts nunca têm exatamente o mesmo tempo
+ *Leap seconds, DST, fusos* — complicam ainda mais

#block(inset: (left: 1em), fill: luma(245), radius: 4pt, width: 100%)[
  *Não existe um "relógio global" em sistemas distribuídos.*
]


#line(length: 100%, stroke: 0.5pt + luma(200))


== Consequências reais — isso acontece no SEU projeto


=== Cenário 1: "O log mentiu"


Você recebe um alerta: "notificação enviada antes do pedido ser confirmado."
Abre o Kibana, filtra por timestamp, e realmente parece que a notificação
veio primeiro. Você gasta *dois dias* investigando um bug que não existe.
Os logs só estão *fora de ordem* porque as máquinas têm relógios diferentes.

=== Cenário 2: "O dado sumiu"


Dois microsserviços atualizam o saldo de um cliente quase ao mesmo tempo.
Um debita, outro credita. Com last-write-wins baseado em timestamp,
o crédito é silenciosamente *sobrescrito* pelo débito — porque a máquina
do débito tinha o relógio 50ms adiantado. Ninguém percebe até o cliente reclamar.

=== Cenário 3: "O replay deu diferente"


Você reconstrói o estado do sistema a partir do event store (event sourcing).
Em staging, o resultado é diferente de produção. Por quê? Porque os eventos
chegaram em *ordem diferente*, e sem causalidade explícita, não há como
saber a ordem "correta".

=== Cenário 4: "O teste passou, mas em produção..."


O integration test passa porque tudo roda na mesma máquina (mesmo relógio).
Em produção, com latência de rede variável, os serviços processam em ordens
que o teste nunca exercitou. *Race condition invisível.*

#block(inset: (left: 1em), fill: luma(245), radius: 4pt, width: 100%)[
  *Esses problemas não aparecem em monolitos.* Eles surgem quando você distribui — e quanto mais serviços, mais frequentes ficam.
]


#line(length: 100%, stroke: 0.5pt + luma(200))


== Isso acontece no seu projeto?


Pergunte-se:

- Você já filtrou logs por timestamp e a ordem não fazia sentido?
- Você já teve um bug que "não reproduz local" mas acontece em produção?
- Você usa `ORDER BY created_at` em eventos de diferentes serviços?
- Você resolve conflitos com "o último timestamp ganha"?
- Seus testes de integração rodam em uma máquina só?

Se respondeu *sim* a qualquer uma, você tem o problema.
A boa notícia: a solução é *surpreendentemente simples*.

#line(length: 100%, stroke: 0.5pt + luma(200))


== A pergunta certa


Em vez de perguntar *"quando aconteceu?"* (wall clock), devemos perguntar:

#block(inset: (left: 1em), fill: luma(245), radius: 4pt, width: 100%)[
  *"O evento A causou o evento B, ou eles aconteceram independentemente?"*
]


Isso é a *relação happens-before (→)* de Lamport.

#line(length: 100%, stroke: 0.5pt + luma(200))


== A relação happens-before (→)


Definição (Lamport, 1978):

O evento `a` *happens-before* o evento `b` (escrito `a → b`) se:

+ `a` e `b` são eventos no *mesmo processo* e `a` ocorre antes de `b`, *OU*
+ `a` é o *envio* de uma mensagem e `b` é o *recebimento* dessa mensagem, *OU*
+ Existe um evento `c` tal que `a → c` e `c → b` (*transitividade*)

Se nem `a → b` nem `b → a`, então `a` e `b` são *concorrentes* (`a ∥ b`).

#line(length: 100%, stroke: 0.5pt + luma(200))


== Ordem parcial vs. ordem total


#table(
  columns: 3,
  inset: 8pt,
  align: left,
  [*Conceito*],
  [*Definição*],
  [*Exemplo*],
  [Ordem parcial],
  [Nem todo par de eventos é comparável],
  [`a ∥ b` — incomparáveis],
  [Ordem total],
  [Todo par de eventos tem uma ordem definida],
  [`a < b` ou `b < a` sempre],
)


A relação happens-before é uma *ordem parcial*.
Eventos concorrentes não têm ordem definida — e *tudo bem*.

#line(length: 100%, stroke: 0.5pt + luma(200))


== O que vamos construir


Dois mecanismos para capturar essa causalidade sem depender de wall clock:

+ *Lamport Clock* — ordem total consistente com causalidade (simples, mas não detecta concorrência)
+ *Vector Clock* — captura a relação causal completa (detecta concorrência!)

#block(inset: (left: 1em), fill: luma(245), radius: 4pt, width: 100%)[
  *Spoiler:* a implementação inteira de um Lamport Clock cabe em ~15 linhas de pseudocódigo. A de um Vector Clock, em ~30. A propagação é um header HTTP extra ou um campo JSON. Não é rocket science — é uma das melhores relações custo/benefício em engenharia de sistemas distribuídos.
]


#line(length: 100%, stroke: 0.5pt + luma(200))


== Discussão


- Vocês já tiveram problemas com logs fora de ordem em produção?
- Como vocês resolvem conflitos de escrita hoje? Last-write-wins? Merge manual?
- Alguém já usou tracing distribuído (Jaeger, Zipkin)? Ele resolve o problema de causalidade?

#block(inset: (left: 1em), fill: luma(245), radius: 4pt, width: 100%)[
  Kleppmann (2017) discute extensivamente o problema de "The Trouble with Distributed Systems" no Cap. 8 de *Designing Data-Intensive Applications*, pp. 287–296.
]


#line(length: 100%, stroke: 0.5pt + luma(200))


== Resumo


#table(
  columns: 2,
  inset: 8pt,
  align: left,
  [*Conceito*],
  [*O que é*],
  [Wall clock],
  [Tempo físico — não confiável entre máquinas],
  [Clock drift],
  [Diferença acumulada entre relógios de hardware],
  [Happens-before (→)],
  [Relação causal entre eventos],
  [Concorrência (∥)],
  [Eventos sem relação causal — independentes],
  [Ordem parcial],
  [Nem todo par é comparável — e isso é informação útil],
)


#line(length: 100%, stroke: 0.5pt + luma(200))


== Referências deste módulo


- Lamport (1978), Seção 1 — "Introduction" e Seção 2 — "The Partial Ordering"
- Coulouris et al. (2012), Seção 14.1 — "Introduction to time and global states"
- Kleppmann (2017), Cap. 8 — "The Trouble with Distributed Systems"
- Tanenbaum & Van Steen (2017), Seção 6.1 — "Clock Synchronization"
