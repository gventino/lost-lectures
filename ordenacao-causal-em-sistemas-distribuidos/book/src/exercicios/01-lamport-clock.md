# Exercícios — Lamport Clock

---

## Exercício 1.1 — Ordenando logs de produção (Fácil, 10 min)

Você recebe estes logs de 3 microsserviços. Cada serviço está numa máquina
diferente e os relógios não estão sincronizados.

```
[2024-01-15 10:30:00.450] gateway:     Request POST /orders recebida
[2024-01-15 10:30:00.120] order-svc:   Pedido #42 criado
[2024-01-15 10:30:00.890] order-svc:   Notificação enviada para payment-svc
[2024-01-15 10:30:00.200] payment-svc: Pagamento #42 iniciado
[2024-01-15 10:30:01.100] payment-svc: Pagamento #42 aprovado
[2024-01-15 10:30:00.050] inventory:   Estoque do produto X reservado
```

**Pelo wall clock:** estoque foi reservado antes de tudo (10:30:00.050).
Isso faz sentido? Provavelmente não.

**Tarefas:**

1. Supondo que o fluxo real é: gateway → order-svc → payment-svc, e que
   inventory é notificado por order-svc, atribua Lamport timestamps
   aos 6 eventos usando as 3 regras do algoritmo.

2. Reordene os logs pelo Lamport timestamp. A nova ordem faz mais sentido?

3. Há algum par de eventos cuja ordem o Lamport Clock **não consegue**
   determinar com certeza? Qual e por quê?

<details>
<summary>Resposta</summary>

Lamport timestamps (seguindo o fluxo causal):
```
LC=1  gateway:     Request POST /orders recebida
LC=2  order-svc:   Pedido #42 criado                (recebeu LC=1 do gateway)
LC=3  order-svc:   Notificação enviada para payment  (tick)
LC=4  payment-svc: Pagamento #42 iniciado            (recebeu LC=3)
LC=5  payment-svc: Pagamento #42 aprovado            (tick)
LC=3  inventory:   Estoque reservado                  (recebeu LC=2 de order-svc → max(0,2)+1=3)
```

Nova ordem: gateway(1) → order-criado(2) → order-notif(3) / inventory(3) → payment-inicio(4) → payment-ok(5)

O par **order-notificação (LC=3)** e **inventory (LC=3)** tem o mesmo timestamp.
O Lamport Clock não sabe se um causou o outro ou se são concorrentes.
Com desempate lexicográfico, inventory < order-svc, mas isso é arbitrário.

</details>

---

## Exercício 1.2 — Implementando no seu middleware (Médio, 15 min)

Você tem um middleware HTTP (interceptor de requests) e quer adicionar
Lamport Clock a todas as chamadas entre serviços.

**Pseudocódigo atual do middleware (sem causalidade):**

```
função middleware_envio(request):
    request.headers["X-Request-Id"] ← gerar_uuid()
    retornar enviar(request)

função middleware_recebimento(request):
    request_id ← request.headers["X-Request-Id"]
    logar("recebido request " + request_id)
    retornar processar(request)
```

**Tarefas:**

1. Modifique o pseudocódigo para incluir Lamport Clock.
   Use o header `X-Causality-Lamport` com formato `nome-serviço:timestamp`.

2. Onde você inicializa o clock? (startup do serviço? por request? global?)

3. O clock precisa ser thread-safe? Por quê?

4. Se um serviço recebe requests de clientes externos (sem header de causalidade),
   o que o middleware deve fazer?

<details>
<summary>Resposta</summary>

```
-- No startup do serviço (global, uma vez):
clock ← NOVO_CLOCK("payment-svc")

função middleware_envio(request):
    request.headers["X-Request-Id"] ← gerar_uuid()
    ts ← ENVIAR(clock)    -- tick + snapshot
    request.headers["X-Causality-Lamport"] ← ts.id_nó + ":" + ts.tempo
    retornar enviar(request)

função middleware_recebimento(request):
    request_id ← request.headers["X-Request-Id"]
    header_lc ← request.headers["X-Causality-Lamport"]
    se header_lc ≠ nulo:
        ts ← parsear_timestamp(header_lc)
        RECEBER(clock, ts)
    senão:
        TICK(clock)    -- request externo: apenas incrementa
    logar("recebido request " + request_id + " LC=" + clock.tempo)
    retornar processar(request)
```

2. Inicializa no startup — é global por serviço (1 instância).
3. Sim, precisa de lock/mutex — múltiplas goroutines/threads podem chamar TICK
   simultaneamente. Em linguagens com async, um Mutex simples basta.
4. Request sem header → faz TICK (é um evento interno, não um receive).

</details>

---

## Exercício 1.3 — Verdadeiro ou Falso (Rápido, 5 min)

Para cada afirmação, diga se é **V** ou **F** e justifique em uma frase:

1. Se `C(a) < C(b)`, então o evento `a` causou o evento `b`.
2. Se `a → b`, então `C(a) < C(b)`.
3. Dois eventos em processos diferentes podem ter o mesmo Lamport timestamp.
4. O Lamport Clock pode regredir (diminuir de valor).
5. Se dois serviços nunca se comunicam, seus Lamport Clocks evoluem independentemente.
6. Adicionar Lamport Clock aos headers HTTP aumenta significativamente o tamanho da request.

<details>
<summary>Resposta</summary>

1. **F** — `C(a) < C(b)` é necessário mas não suficiente. Eventos concorrentes podem ter essa relação numérica por coincidência.
2. **V** — Essa é a Clock Condition, garantida pelo algoritmo. (Lamport, 1978, p. 560)
3. **V** — Processos independentes podem fazer TICK e chegar ao mesmo número.
4. **F** — O clock é monotônico. TICK, ENVIAR e RECEBER sempre incrementam.
5. **V** — Cada um incrementa localmente. Sem mensagens, não há sincronização.
6. **F** — É um header de ~20-30 caracteres (ex: "order-svc:1042"). Menor que um cookie.

</details>

---

## Para ir além (referências acadêmicas)

Os exercícios acima cobrem o uso prático. Para aprofundamento teórico:

- **Exclusão mútua de Lamport:** Lamport (1978), Seção 4. Simule o algoritmo
  com 3 processos competindo por um recurso. Vide Coulouris et al. (2012), Seção 15.2.

- **Atribuição formal de timestamps:** Coulouris et al. (2012), Exercise 14.8.
  Dado um diagrama de espaço-tempo com 3 processos e ~10 eventos, atribua
  Lamport timestamps e identifique todas as relações de causalidade.

- **Ordem total e desempate:** Tanenbaum & Van Steen (2017), Seção 6.2.
  Por que a ordem total de Lamport não é única? Quantas ordens totais
  consistentes com a causalidade existem para um dado diagrama?

---

## Referências

- Lamport, L. (1978). *Time, Clocks, and the Ordering of Events in a Distributed System.* Communications of the ACM, 21(7), 558–565.
- Coulouris, G. et al. (2012). *Distributed Systems: Concepts and Design.* 5th ed. Exercises 14.7–14.10.
- Tanenbaum, A.S. & Van Steen, M. (2017). *Distributed Systems.* 3rd ed. Seção 6.2.
