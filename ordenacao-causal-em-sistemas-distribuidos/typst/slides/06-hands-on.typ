#set text(font: "New Computer Modern", size: 11pt, lang: "pt")
#set page(margin: 2cm)
#set heading(numbering: "1.1")
#set par(justify: true)

= Módulo 06: Hands-on: Exercícios Práticos


#line(length: 100%, stroke: 0.5pt + luma(200))


== Objetivo


Aplicar os conceitos aprendidos através de exercícios práticos, progressivos,
baseados em problemas clássicos de sistemas distribuídos.

#line(length: 100%, stroke: 0.5pt + luma(200))


== Exercício A: Lamport Clock: ordenação de eventos (15 min)


#block(inset: (left: 1em), fill: luma(245), radius: 4pt, width: 100%)[
  Adaptado de Coulouris et al. (2012), Exercise 14.8.
]


Considere o seguinte diagrama de espaço-tempo com três processos:

```
P1          P2          P3
|           |           |
+-- a       |           |
|           |           |
+-- b ----->+-- c       |
|           |           |
|           +-- d ----->+-- e
|           |           |
+-- f       +-- g       |
|           |           |
|◀----------+-- h       +-- i
+-- j       |           |
|           |           |
```


*Tarefas:*

+ Atribua Lamport timestamps a *todos* os eventos (a–j).
+ Identifique *todos os pares* de eventos concorrentes.
+ Dê um exemplo onde `C(x) < C(y)` mas `x` e `y` são concorrentes.
   Isso demonstra a limitação do Lamport Clock.

#line(length: 100%, stroke: 0.5pt + luma(200))


== Exercício B: Vector Clock: detecção de causalidade (20 min)


#block(inset: (left: 1em), fill: luma(245), radius: 4pt, width: 100%)[
  Adaptado de Coulouris et al. (2012), Exercise 14.9, e Tanenbaum & Van Steen (2017), Exercise 6.8.
]


Usando o *mesmo diagrama* do Exercício A, agora com Vector Clocks:

*Tarefas:*

+ Atribua vector timestamps a *todos* os eventos (a–j).
   Use o formato `{P1:x, P2:y, P3:z}`.

+ Para cada par abaixo, determine a relação usando o algoritmo COMPARAR:
  - `(a, c)` = ?
  - `(a, e)` = ?
  - `(f, d)` = ?
  - `(f, i)` = ?
  - `(j, i)` = ?

+ Compare seus resultados com os do Exercício A.
   Em quais pares o Vector Clock fornece informação que o Lamport Clock não fornecia?

#line(length: 100%, stroke: 0.5pt + luma(200))


== Exercício C: Cenário prático: detecção de conflito (15 min)


#block(inset: (left: 1em), fill: luma(245), radius: 4pt, width: 100%)[
  Inspirado no Amazon Dynamo - DeCandia et al. (2007), Seção 4.4.
]


Dois nós de um banco de dados distribuído (réplica US e réplica EU) mantêm
vector clocks para detectar escritas concorrentes:

```
Sequência de eventos:

1. Cliente X escreve valor "v1" na réplica US
   US processa: TICK(vc_us)

2. Réplica US sincroniza com réplica EU
   US: ts = ENVIAR(vc_us)
   EU: RECEBER(vc_eu, ts)

3. Cliente Y escreve valor "v2" na réplica EU
   EU: TICK(vc_eu)

4. Cliente Z escreve valor "v3" na réplica US
   US: TICK(vc_us)

5. Réplicas tentam sincronizar novamente
```


*Tarefas:*

+ Calcule os vector clocks de US e EU após cada passo.
+ No passo 5, determine: a escrita de "v2" (EU) e "v3" (US) são
   causais ou concorrentes?
+ Se forem concorrentes, proponha *duas estratégias* para resolver o conflito.
+ Discuta: por que o Amazon Dynamo usa vector clocks *truncados* em vez de
   vector clocks completos?

#line(length: 100%, stroke: 0.5pt + luma(200))


== Exercício D: Corte consistente (20 min)


#block(inset: (left: 1em), fill: luma(245), radius: 4pt, width: 100%)[
  Baseado em Chandy & Lamport (1985) e apresentado em Coulouris et al. (2012), Seção 14.5 e Exercise 14.12.
]


Um *corte* em um sistema distribuído é um conjunto de eventos, um prefixo
por processo. Um corte é *consistente* se para todo evento `e` no corte,
todos os eventos que *happen-before* `e` também estão no corte.

Dado o diagrama:

```
P1:  --a------b------c------d--
              |               ▲
              ▼               |
P2:  --e------f------g------h--
                     |
                     ▼
P3:  --i------j------k------l--
```


*Tarefas:*

+ O corte C1 = {a,b | e,f | i,j} é consistente? Justifique usando vector clocks.
+ O corte C2 = {a,b,c | e,f | i,j,k} é consistente? Justifique.
+ Encontre o *menor corte consistente* que inclui o evento `g`.
+ Explique: por que cortes consistentes são importantes para snapshots distribuídos?

#block(inset: (left: 1em), fill: luma(245), radius: 4pt, width: 100%)[
  Dica: um corte é consistente se e somente se não existe uma mensagem que "cruza" o corte de trás para frente (enviada depois do corte, recebida antes).
]


#line(length: 100%, stroke: 0.5pt + luma(200))


== Exercício E: Cenário completo: e-commerce (30 min)


#block(inset: (left: 1em), fill: luma(245), radius: 4pt, width: 100%)[
  Síntese dos conceitos. Adaptado de cenários em Kleppmann (2017), Cap. 9.
]


Sistema com 4 microsserviços: Pedidos, Pagamento, Estoque, Envio.

```
┌----------┐     ┌----------┐     ┌----------┐     ┌----------┐
| Pedidos  |---->|Pagamento |---->| Estoque  |---->|  Envio   |
└----------┘     └----------┘     └----------┘     └----------┘
      |                                 ▲
      └---------------------------------┘
             (também notifica diretamente)
```


Pedidos notifica Pagamento (HTTP) e Estoque (Kafka) ao mesmo tempo.
Pagamento, quando termina, notifica Estoque (Kafka).
Estoque, quando tem tudo pronto, notifica Envio (HTTP).

*Tarefas:*

+ *Modelagem:* Crie os 4 vector clocks e simule todo o fluxo.
   Mostre o vetor de cada serviço após cada operação.

+ *Análise:* Estoque recebe de Pedidos e de Pagamento.
   A mensagem de Pagamento é causal em relação à de Pedidos?
   (Dica: Pagamento recebeu de Pedidos antes de enviar para Estoque.)

+ *Transport:* Para cada comunicação, indique qual formato de transport usar
   (texto/binário/JSON) e justifique.

+ *Tolerância a falhas:* Se Pagamento cair e nunca responder,
   Estoque recebe só de Pedidos. O sistema ainda funciona? A causalidade
   fica comprometida?

+ *Reflexão:* Compare esta abordagem com trace IDs do OpenTelemetry.
   O que vector clocks adicionam que trace IDs não oferecem?

#line(length: 100%, stroke: 0.5pt + luma(200))


== Discussão final


+ *Escalabilidade:* Se tivéssemos 50 microsserviços, o tamanho do vector clock
   seria um problema? O que fazer?

+ *Alternativas:* Pesquise sobre *Hybrid Logical Clocks* (Kulkarni et al., 2014).
   Qual a vantagem sobre vector clocks puros?

+ *Na prática:* Vocês conhecem sistemas reais que usam vector clocks?
   (Amazon Dynamo, Riak, Voldemort, CockroachDB...)

#line(length: 100%, stroke: 0.5pt + luma(200))


== O que fazer segunda-feira de manhã


Você não precisa implementar tudo de uma vez. Comece pequeno:

=== Semana 1: Lamport Clock nos logs


```
1. Adicione um contador inteiro a cada serviço
2. Passe o valor num header HTTP (X-Causality-Lamport: svc-name:42)
3. No recebimento: max(local, recebido) + 1
4. Inclua o valor no log estruturado de cada request
```


*Resultado:* Logs que você pode ordenar por causalidade, não por wall clock.
Já resolve o problema de "o log mentiu" do Módulo 01.

=== Semana 2: Vector Clock nos serviços críticos


```
1. Escolha 3-5 serviços com mais problemas de race condition
2. Troque o Lamport Clock por Vector Clock entre eles
3. Adicione um alerta simples: se COMPARAR = CONCURRENT em escritas
   no mesmo recurso → logar como warning
```


*Resultado:* Detecção automática de conflitos. Aquele bug intermitente
de "dado sumiu" agora aparece no log com "escrita concorrente detectada".

=== Semana 3: TracedEvent no event store


```
1. Envolva seus eventos de domínio em TracedEvent
2. Persista o VectorTimestamp junto com cada evento
3. Use COMPARAR para validar a ordem ao fazer replay
```


*Resultado:* Event sourcing com ordenação causal garantida.

=== O mínimo viável


Se você fizer *apenas a Semana 1*, já terá mais informação causal do que
99% dos sistemas em produção hoje. É um investimento de *~1 hora* de
implementação que economiza *dias* de debugging.

#block(inset: (left: 1em), fill: luma(245), radius: 4pt, width: 100%)[
  *Não espere ter o sistema perfeito para começar.* Um Lamport Clock básico nos logs já é transformador. Vector Clock é o upgrade natural quando você precisar detectar conflitos.
]


#line(length: 100%, stroke: 0.5pt + luma(200))


== Resumo da aula


#table(
  columns: 2,
  inset: 8pt,
  align: left,
  [*Módulo*],
  [*O que aprendemos*],
  [01],
  [Wall clock não funciona → precisamos de relógios lógicos],
  [02],
  [Lamport Clock: simples, ordem total, não detecta ∥],
  [03],
  [CausalityRelation: →, ←, ∥, = - as 4 relações possíveis],
  [04],
  [Vector Clock: completo, detecta ∥, mas O(N) por mensagem],
  [05],
  [TracedEvent + Transport: propagação agnóstica a framework],
  [06],
  [Hands-on: exercícios clássicos e cenários práticos],
)


#line(length: 100%, stroke: 0.5pt + luma(200))


== Para ir além


- Ler o paper original: Lamport (1978) - 8 páginas, surpreendentemente acessível
- *CRDTs* - Conflict-free Replicated Data Types (Shapiro et al., 2011)
- *Hybrid Logical Clocks* - Kulkarni et al. (2014)
- *Interval Tree Clocks* - Almeida et al. (2008)
- *Designing Data-Intensive Applications* - Kleppmann (2017), Caps. 5, 8, 9

#line(length: 100%, stroke: 0.5pt + luma(200))


== Referências completas da aula


+ Lamport, L. (1978). *Time, Clocks, and the Ordering of Events in a Distributed System.* Communications of the ACM, 21(7), 558–565.
+ Fidge, C. (1988). *Timestamps in Message-Passing Systems That Preserve the Partial Ordering.* Proceedings of the 11th Australian Computer Science Conference.
+ Mattern, F. (1989). *Virtual Time and Global States of Distributed Systems.* Parallel and Distributed Algorithms, pp. 215–226.
+ Schwarz, R. & Mattern, F. (1994). *Detecting Causal Relationships in Distributed Computations: In Search of the Holy Grail.* Distributed Computing, 7(3), 149–174.
+ Chandy, K.M. & Lamport, L. (1985). *Distributed Snapshots: Determining Global States of Distributed Systems.* ACM TOCS, 3(1), 63–75.
+ DeCandia, G. et al. (2007). *Dynamo: Amazon's Highly Available Key-value Store.* SOSP '07.
+ Coulouris, G., Dollimore, J., Kindberg, T. & Blair, G. (2012). *Distributed Systems: Concepts and Design.* 5th ed. Pearson. Cap. 14.
+ Tanenbaum, A.S. & Van Steen, M. (2017). *Distributed Systems: Principles and Paradigms.* 3rd ed. Pearson. Cap. 6.
+ Kleppmann, M. (2017). *Designing Data-Intensive Applications.* O'Reilly. Caps. 5, 8, 9.
+ Kulkarni, S. et al. (2014). *Logical Physical Clocks and Consistent Snapshots in Globally Distributed Databases.* OPODIS.
+ Shapiro, M. et al. (2011). *Conflict-free Replicated Data Types.* SSS '11.
+ Almeida, P.S., Baquero, C. & Fonte, V. (2008). *Interval Tree Clocks.* OPODIS.
