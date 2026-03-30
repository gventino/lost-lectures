#set text(font: "New Computer Modern", size: 11pt, lang: "pt")
#set page(margin: 2cm)
#set heading(numbering: "1.1")
#set par(justify: true)

= Ordenação Causal em Sistemas Distribuídos


#block(inset: (left: 1em), fill: luma(245), radius: 4pt, width: 100%)[
  Aula baseada no paper de Leslie Lamport (1978): *"Time, Clocks, and the Ordering of Events in a Distributed System"*
]


#line(length: 100%, stroke: 0.5pt + luma(200))


== Objetivo da Aula


Ao final desta aula, o aluno será capaz de:

+ Explicar por que relógios físicos (wall clock) não garantem ordenação correta em sistemas distribuídos
+ Implementar um *Lamport Clock* e entender suas limitações
+ Implementar um *Vector Clock* e detectar eventos concorrentes
+ Usar relações de causalidade (happens-before, concurrent) para resolver conflitos
+ Propagar contexto causal através de diferentes transports (HTTP, Kafka, JSON)

#line(length: 100%, stroke: 0.5pt + luma(200))


== Pré-requisitos


- Conceitos básicos de sistemas distribuídos (microserviços, mensageria)
- Familiaridade com Rust (ou linguagem com ownership model)
- Entendimento básico de serialização (JSON, headers HTTP)

#line(length: 100%, stroke: 0.5pt + luma(200))


== Estrutura da Aula


#table(
  columns: 4,
  inset: 8pt,
  align: left,
  [*\#*],
  [*Módulo*],
  [*Duração Sugerida*],
  [*Slides*],
  [01],
  [O Problema da Ordenação],
  [20 min],
  [`slides/01-o-problema.md`],
  [02],
  [Lamport Clock],
  [30 min],
  [`slides/02-lamport-clock.md`],
  [03],
  [Relações de Causalidade],
  [20 min],
  [`slides/03-causalidade.md`],
  [04],
  [Vector Clock],
  [40 min],
  [`slides/04-vector-clock.md`],
  [05],
  [Traced Events e Transport],
  [30 min],
  [`slides/05-traced-events-e-transport.md`],
  [06],
  [Hands-on: Construindo um SDK causal],
  [40 min],
  [`slides/06-hands-on.md`],
)


*Duração total estimada: ~3 horas* (com pausas e exercícios)

#line(length: 100%, stroke: 0.5pt + luma(200))


== Materiais


- `slides/` — Conteúdo teórico e exemplos de código para cada módulo
- `exercicios/` — Exercícios práticos progressivos (do básico ao avançado)
- `diagramas/` — Diagramas ASCII de referência para quadro/projeção

#line(length: 100%, stroke: 0.5pt + luma(200))


== Referências Bibliográficas


=== Papers fundamentais

+ Lamport, L. (1978). *Time, Clocks, and the Ordering of Events in a Distributed System.* Communications of the ACM, 21(7), 558–565.
+ Fidge, C. (1988). *Timestamps in Message-Passing Systems That Preserve the Partial Ordering.* Proceedings of the 11th Australian Computer Science Conference.
+ Mattern, F. (1989). *Virtual Time and Global States of Distributed Systems.* Parallel and Distributed Algorithms, pp. 215–226.
+ Schwarz, R. & Mattern, F. (1994). *Detecting Causal Relationships in Distributed Computations.* Distributed Computing, 7(3), 149–174.
+ Chandy, K.M. & Lamport, L. (1985). *Distributed Snapshots: Determining Global States of Distributed Systems.* ACM TOCS, 3(1), 63–75.
+ DeCandia, G. et al. (2007). *Dynamo: Amazon's Highly Available Key-value Store.* SOSP '07.

=== Livros-texto

+ Coulouris, G., Dollimore, J., Kindberg, T. & Blair, G. (2012). *Distributed Systems: Concepts and Design.* 5th ed. Pearson. Cap. 14.
+ Tanenbaum, A.S. & Van Steen, M. (2017). *Distributed Systems: Principles and Paradigms.* 3rd ed. Pearson. Cap. 6.
+ Kleppmann, M. (2017). *Designing Data-Intensive Applications.* O'Reilly. Caps. 5, 8, 9.

=== Leitura complementar

+ Kulkarni, S. et al. (2014). *Logical Physical Clocks and Consistent Snapshots in Globally Distributed Databases.* OPODIS.
+ Shapiro, M. et al. (2011). *Conflict-free Replicated Data Types.* SSS '11.
+ Almeida, P.S., Baquero, C. & Fonte, V. (2008). *Interval Tree Clocks.* OPODIS.

#line(length: 100%, stroke: 0.5pt + luma(200))


== Projeto de Referência


O SDK `like-a-clockwork` (Rust) implementa todos os conceitos desta aula.
Repositório: `like-a-clockwork/` — specs em `.github/specs/`, planos em `.github/plans/`.
