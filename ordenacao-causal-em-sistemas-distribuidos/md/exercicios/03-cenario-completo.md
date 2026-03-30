# Exercício Final: Cenário Completo

---

## Exercício 3.1: Debugging com causalidade (Médio, 15 min)

Você recebe um ticket de bug:

> "Às vezes o cliente recebe email de confirmação de envio, mas o status
> do pedido ainda mostra 'pagamento pendente' no app."

O sistema tem 4 serviços: Pedidos, Pagamento, Estoque, Notificação.

Logs de produção (ordenados por wall clock):

```
10:30:00.050  notificação:  Email "pedido enviado" disparado para cliente #7
10:30:00.120  pedidos:      Status do pedido #99 atualizado para "enviado"
10:30:00.200  pagamento:    Pagamento #99 aprovado
10:30:00.350  estoque:      Reserva #99 confirmada
```

**Tarefas:**

1. Olhando só o wall clock, qual parece ser a ordem? Faz sentido?

2. Supondo que os serviços usam Vector Clock, os seguintes vetores foram
   registrados junto com cada log:

   ```
   notificação:  {ped:3, pag:2, est:2, not:1}
   pedidos:      {ped:4, pag:0, est:0, not:0}
   pagamento:    {ped:1, pag:3, est:0, not:0}
   estoque:      {ped:3, pag:3, est:2, not:0}
   ```

   Reordene os eventos por causalidade. Qual é a **ordem real**?

3. Compare `pedidos {ped:4,...}` com `notificação {ped:3,...}`.
   São causais ou concorrentes? O que isso explica sobre o bug?

4. Como você corrigiria o sistema? (Dica: a notificação precisa esperar algo.)

<details>
<summary>Resposta</summary>

1. Pelo wall clock: notificação → pedidos → pagamento → estoque.
   Não faz sentido - email antes do pagamento?

2. Usando os vetores para determinar causalidade:
   - pagamento {ped:1, pag:3} - viu 1 evento de pedidos
   - estoque {ped:3, pag:3, est:2} - viu 3 de pedidos E 3 de pagamento
   - notificação {ped:3, pag:2, est:2, not:1} - viu 3 de pedidos, 2 de pagamento, 2 de estoque
   - pedidos {ped:4, pag:0, est:0} - não viu nada de ninguém depois

   Ordem causal: pagamento → estoque → notificação.
   Pedidos (passo 4) é **concorrente** com quase tudo - fez TICK sem receber de ninguém.

3. COMPARAR(pedidos, notificação): ped[ped]=4 > not[ped]=3, mas ped[pag]=0 < not[pag]=2.
   **CONCURRENT!** O update de status do pedido e o email de notificação aconteceram
   independentemente. O email foi disparado por estoque→notificação, mas o status
   no app é atualizado por uma rota separada de pedidos que não esperou a cadeia causal.

4. Correção: o serviço de pedidos precisa **receber** o vetor de estoque (ou notificação)
   antes de atualizar o status para "enviado". Assim, o update de status seria
   causal (happens-after) em relação ao envio, não concorrente.

</details>

---

## Exercício 3.2: Projetando causalidade para seu sistema (Médio, 20 min)

Pense num sistema real que você trabalha (ou num projeto pessoal).
Desenhe o fluxo entre 3-5 serviços/componentes principais.

**Tarefas:**

1. **Mapeie os pontos de comunicação:**
   Liste todas as chamadas HTTP, mensagens Kafka, eventos, etc. entre serviços.

2. **Identifique riscos de concorrência:**
   Onde dois serviços podem modificar o mesmo recurso sem coordenação?
   (Ex: dois handlers atualizando o mesmo registro no banco.)

3. **Escolha o transport:**
   Para cada ponto de comunicação, qual formato de causalidade usaria?

   | Comunicação           | Transport sugerido    | Justificativa               |
   |-----------------------|-----------------------|-----------------------------|
   | HTTP request/response | Texto (header)        | Simples, legível            |
   | Kafka producer/consumer| Binário (msgpack)    | Alto throughput, compacto   |
   | Webhook externo       | JSON (_causality)     | Payload autocontido         |
   | gRPC (Remote Procedure Call) | Binário (metadata)    | Nativo do protocolo         |

4. **Estime o esforço:**
   Quantos endpoints/consumers precisariam de mudança?
   Quanto tempo levaria para adicionar um Lamport Clock básico?

5. **Defina o "mínimo viável":**
   Se pudesse instrumentar só 2 serviços, quais seriam? Por quê?

---

## Exercício 3.3: Conflito no carrinho de compras (Médio, 15 min)

> Inspirado no Amazon Dynamo - DeCandia et al. (2007), Seção 4.4.

Um e-commerce tem dois datacenters (US e EU) com réplicas do carrinho de compras.
O cliente pode acessar qualquer datacenter.

```
Sequência:
1. Cliente adiciona "Livro A" no carrinho (via US)
   US.TICK()  →  {US:1, EU:0}

2. US sincroniza com EU
   ts1 = US.ENVIAR()  →  US = {US:2, EU:0}
   EU.RECEBER(ts1)    →  EU = {US:2, EU:1}

3. Cliente adiciona "Livro B" no carrinho (via EU)
   EU.TICK()  →  EU = {US:2, EU:2}

4. Cliente adiciona "Livro C" no carrinho (via US, sem ter visto passo 3)
   US.TICK()  →  US = {US:3, EU:0}

5. Datacenters tentam sincronizar
```

**Tarefas:**

1. No passo 5, determine: `COMPARAR(US, EU)` = ?

2. O carrinho de US tem {A, C}. O carrinho de EU tem {A, B}.
   São concorrentes. Qual deveria ser o resultado do merge?

3. O Amazon Dynamo retorna **ambas as versões** ao cliente e pede para
   a aplicação fazer o merge. Por que não fazer merge automático?

4. Para o caso do carrinho de compras, a Amazon usa **união dos itens**
   como estratégia de merge. Quando isso pode dar errado?
   (Dica: e se o cliente **removeu** um item?)

<details>
<summary>Resposta</summary>

1. US = {US:3, EU:0}, EU = {US:2, EU:2}.
   US[US]=3 > EU[US]=2, mas US[EU]=0 < EU[EU]=2.
   **CONCURRENT.**

2. O merge correto é {A, B, C} - união dos dois carrinhos.
   Livro A estava em ambos (não duplica). B e C são adições concorrentes.

3. Merge automático nem sempre é possível. Para carrinhos, união funciona.
   Para um campo "nome de usuário", qual valor é o "correto"? Depende
   da semântica do dado. A aplicação tem contexto que o banco não tem.

4. Se o cliente removeu Livro A via US (carrinho US = {C}), mas EU ainda tem {A, B},
   o merge por união restaura A: {A, B, C}. O delete é "perdido".
   Solução: usar **tombstones** (marcadores de deleção) em vez de remover.

   É por isso que o Amazon Dynamo mudou para usar CRDTs (OR-Set, Observed-Remove Set) em versões
   mais recentes - CRDTs tratam remoções corretamente.

</details>

---

## Exercício 3.4: Quiz de encerramento (Rápido, 5 min)

Responda sem consultar os slides. Se acertar 5/6, você entendeu a aula.

1. Um Lamport Clock pode detectar que dois eventos são concorrentes? (S/N)

2. Qual a regra de recebimento do Lamport Clock?
   (a) `t ← t + 1`
   (b) `t ← max(t, t_recebido) + 1`
   (c) `t ← t_recebido + 1`

3. Num Vector Clock com 5 serviços, quantos inteiros são enviados por mensagem?

4. Se `V(a) = {X:3, Y:1}` e `V(b) = {X:2, Y:4}`, qual a relação?
   (a) a → b
   (b) b → a
   (c) a ∥ b
   (d) a = b

5. Para propagar causalidade numa request HTTP, o que é necessário?
   (a) Um banco de dados compartilhado
   (b) NTP sincronizado em todos os servidores
   (c) Um header a mais na request
   (d) Um serviço de coordenação central

6. MERGE e RECEBER fazem o mesmo cálculo (max element-wise).
   Qual a diferença?

<details>
<summary>Respostas</summary>

1. **N** - Lamport Clock impõe ordem total. Eventos concorrentes recebem
   timestamps comparáveis (um < outro), mas isso é coincidência, não causalidade.

2. **(b)** - `t ← max(t, t_recebido) + 1`

3. **5** - Um inteiro por processo no sistema.

4. **(c) a ∥ b** - a[X]=3 > b[X]=2, mas a[Y]=1 < b[Y]=4. Incomparáveis.

5. **(c)** - Um header a mais. Ex: `X-Causality-Vector: svc-a=3,svc-b=1`

6. RECEBER **incrementa** o contador local após o max (é um evento - "recebi algo").
   MERGE **não incrementa** (é uma combinação passiva - "agreguei dois snapshots").

</details>

---

## Para ir além (referências acadêmicas)

- **Broadcast causal:** Birman & Joseph (1987). Implemente uma regra de entrega
  que garante que mensagens são entregues na ordem causal, mesmo quando chegam
  fora de ordem na rede. Coulouris et al. (2012), Seção 15.4.3.

- **Snapshot distribuído:** Chandy & Lamport (1985). Simule o algoritmo de
  snapshot usando markers. Verifique que o snapshot resultante corresponde
  a um corte consistente usando vector clocks. Coulouris et al. (2012),
  Exercise 14.14.

- **Sistemas reais com vector clocks:** Pesquise e compare como Amazon Dynamo,
  Riak (dotted version vectors), CockroachDB (Hybrid Logical Clocks), e
  Cassandra (wall clock LWW) resolvem conflitos de escrita. Quais trade-offs
  cada um fez? DeCandia et al. (2007), Taft et al. (2020), Lakshman & Malik (2010).

---

## Referências

- Birman, K. & Joseph, T. (1987). *Reliable Communication in the Presence of Failures.* ACM TOCS, 5(1), 47–76.
- Chandy, K.M. & Lamport, L. (1985). *Distributed Snapshots.* ACM TOCS, 3(1), 63–75.
- DeCandia, G. et al. (2007). *Dynamo: Amazon's Highly Available Key-value Store.* SOSP '07.
- Kleppmann, M. (2017). *Designing Data-Intensive Applications.* O'Reilly. Caps. 5, 8, 9.
- Coulouris, G. et al. (2012). *Distributed Systems.* 5th ed. Exercises 14.12–14.14.
- Taft, R. et al. (2020). *CockroachDB: The Resilient Geo-Distributed SQL Database.* SIGMOD.
- Lakshman, A. & Malik, P. (2010). *Cassandra: A Decentralized Structured Storage System.* LADIS.
