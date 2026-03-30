# Ordenação Causal em Sistemas Distribuídos

Em arquiteturas de microsserviços e sistemas orientados a eventos, múltiplos processos geram eventos de forma assíncrona em máquinas distintas. Timestamps de relógio físico (wall clock) não oferecem garantias de ordenação entre máquinas - clock drift, latência de sincronização NTP (Network Time Protocol) e a ausência de um relógio global tornam impossível determinar, apenas por timestamps, se um evento causou outro ou se dois eventos ocorreram de forma independente.

Este material apresenta os mecanismos de ordenação causal propostos por Lamport (1978) e estendidos por Fidge (1988) e Mattern (1989). Começamos pelo Lamport Clock - um contador lógico monotônico por processo que garante ordenação consistente com a causalidade, mas não detecta concorrência. Em seguida, introduzimos o Vector Clock, que captura a relação causal completa entre eventos: happens-before, happens-after e concorrência. A detecção de concorrência é a contribuição central dos vector clocks - permite identificar, sem ambiguidade, quando dois eventos em processos distintos ocorreram sem coordenação, habilitando estratégias explícitas de resolução de conflitos.

Cobrimos também a propagação de contexto causal através de mecanismos de transporte comuns em sistemas distribuídos modernos (headers HTTP, record headers Kafka, payloads JSON), demonstrando que a adoção de relógios lógicos requer modificações mínimas na infraestrutura existente. Os exercícios incluem cenários de debugging com logs fora de ordem, detecção de escritas concorrentes em sistemas multi-réplica, e projeto de causalidade para arquiteturas reais.

O conteúdo é fundamentado nos trabalhos originais de Lamport, Fidge e Mattern, nos livros-texto de Coulouris et al. (2012), Tanenbaum & Van Steen (2017) e Kleppmann (2017), e em sistemas de produção como Amazon Dynamo (DeCandia et al., 2007).

---

## Referências

### Papers fundamentais
1. Lamport, L. (1978). *Time, Clocks, and the Ordering of Events in a Distributed System.* Communications of the ACM, 21(7), 558–565.
2. Fidge, C. (1988). *Timestamps in Message-Passing Systems That Preserve the Partial Ordering.* Proceedings of the 11th Australian Computer Science Conference.
3. Mattern, F. (1989). *Virtual Time and Global States of Distributed Systems.* Parallel and Distributed Algorithms, pp. 215–226.
4. Schwarz, R. & Mattern, F. (1994). *Detecting Causal Relationships in Distributed Computations.* Distributed Computing, 7(3), 149–174.
5. Chandy, K.M. & Lamport, L. (1985). *Distributed Snapshots: Determining Global States of Distributed Systems.* ACM TOCS, 3(1), 63–75.
6. DeCandia, G. et al. (2007). *Dynamo: Amazon's Highly Available Key-value Store.* SOSP '07.

### Livros-texto
7. Coulouris, G., Dollimore, J., Kindberg, T. & Blair, G. (2012). *Distributed Systems: Concepts and Design.* 5th ed. Pearson. Cap. 14.
8. Tanenbaum, A.S. & Van Steen, M. (2017). *Distributed Systems: Principles and Paradigms.* 3rd ed. Pearson. Cap. 6.
9. Kleppmann, M. (2017). *Designing Data-Intensive Applications.* O'Reilly. Caps. 5, 8, 9.

### Leitura complementar
10. Kulkarni, S. et al. (2014). *Logical Physical Clocks and Consistent Snapshots in Globally Distributed Databases.* OPODIS.
11. Shapiro, M. et al. (2011). *Conflict-free Replicated Data Types.* SSS '11.
12. Almeida, P.S., Baquero, C. & Fonte, V. (2008). *Interval Tree Clocks.* OPODIS.
