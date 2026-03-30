# Módulo 05: Traced Events e Transport Layer

---

## Objetivo

Entender como **propagar contexto causal** através de diferentes mecanismos
de transporte (HTTP, Kafka, JSON) - e como encapsular eventos com metadata causal.

---

## O problema da propagação

Ter um Vector Clock rodando dentro de cada serviço **não basta**.
É preciso **enviar e receber** o estado do clock junto com as mensagens.

```
Serviço A                        Serviço B
┌----------┐   Requisição HTTP   ┌----------┐
| Vector   | ------------------> | Vector   |
| Clock    |   + HEADERS com     | Clock    |
| {a:3}    |     causalidade     | {a:?,b:?}|
└----------┘                     └----------┘

Como B sabe o estado de A? → Precisa estar nos headers!
```

---

## TracedEvent: o envelope causal

Um TracedEvent associa **metadata causal** a qualquer evento de domínio:

```
estrutura TracedEvent:
    tipo_evento   : texto              -- ex: "pedido.criado"
    payload       : bytes              -- corpo do evento (opaco para o SDK)
    causalidade   : VectorTimestamp    -- snapshot do vector clock
    id_evento     : texto              -- UUID v7 (ordenável por tempo)
    timestamp_utc : texto (opcional)   -- ISO 8601, apenas informativo
```

### Por que UUID v7?

- UUID v7 é **ordenável por tempo de criação** (timestamp-ordered)
- Útil para indexação e paginação
- A **causalidade real** está no VectorTimestamp, não no UUID

---

## Criando um TracedEvent

```
função CRIAR_EVENTO(tipo, payload, vector_clock):
    retornar TracedEvent {
        tipo_evento:   tipo,
        payload:       payload,
        causalidade:   SNAPSHOT(vector_clock),
        id_evento:     gerar_uuid_v7(),
        timestamp_utc: agora_utc()
    }
```

Exemplo:
```
vc = NOVO_VECTOR_CLOCK("serviço-pedidos", ["pagamento", "estoque"])
TICK(vc)

evento = CRIAR_EVENTO(
    "pedido.criado",
    '{"pedido_id": 42}',
    vc
)
```

---

## Serialização para headers HTTP

```
função EVENTO_PARA_HEADERS(evento):
    retornar {
        "X-Causality-Vector":    serializar_vetor(evento.causalidade),
        "X-Causality-EventId":   evento.id_evento,
        "X-Causality-EventType": evento.tipo_evento,
        "X-Causality-Timestamp": evento.timestamp_utc   -- se presente
    }
```

Exemplo de headers gerados:
```
X-Causality-Vector:    estoque=0,pagamento=0,serviço-pedidos=1
X-Causality-EventId:   019476a0-b1c2-7d3e-a4f5-...
X-Causality-EventType: pedido.criado
```

> O **payload NÃO vai nos headers** - vai no body da requisição.
> Headers carregam apenas metadata causal.

---

## Reconstrução a partir de headers

```
função HEADERS_PARA_EVENTO(headers, payload):
    se "X-Causality-Vector" ausente: retornar ERRO("header ausente")
    se "X-Causality-EventId" ausente: retornar ERRO("header ausente")

    retornar TracedEvent {
        tipo_evento: headers["X-Causality-EventType"],
        payload:     payload,
        causalidade: parsear_vetor(headers["X-Causality-Vector"]),
        id_evento:   headers["X-Causality-EventId"],
        timestamp_utc: headers["X-Causality-Timestamp"]  -- pode ser nulo
    }
```

No serviço que recebe:
```
evento_recebido = HEADERS_PARA_EVENTO(headers_da_requisição, corpo)
RECEBER(meu_clock, evento_recebido.causalidade)
-- Agora meu_clock incorpora o conhecimento causal do remetente
```

---

## A camada de Transport

O SDK é **agnóstico a frameworks**. Não depende de bibliotecas HTTP, Kafka ou gRPC.
Trabalha com tipos genéricos:

```
┌-----------------------------------------------------┐
|                    Camada de Transport               |
+-----------------+------------------+----------------+
| Texto           | Binário          | JSON           |
| mapa de         | mapa de          | objeto JSON    |
| (texto → texto) | (texto → bytes)  |                |
+-----------------+------------------+----------------+
| Headers HTTP    | Kafka rec. hdrs  | Payload JSON   |
| gRPC ASCII meta | gRPC binary meta | com _causality |
└-----------------+------------------+----------------┘
```

> O princípio é: o SDK converte entre seus tipos e representações genéricas.
> O usuário faz a ponte entre a representação genérica e o framework específico.

---

## Na prática: é mais fácil do que parece

### Quanto muda na sua request HTTP?

```
ANTES:
    POST /api/orders
    Content-Type: application/json
    Authorization: Bearer eyJ...
    { "product_id": 42 }

DEPOIS:
    POST /api/orders
    Content-Type: application/json
    Authorization: Bearer eyJ...
    X-Causality-Vector: order-svc=3,payment-svc=1     ← SÓ ISSO
    { "product_id": 42 }
```

**Um header a mais.** Menor que o Authorization. Menor que um cookie de sessão.

### Quanto código por serviço?

```
No startup do serviço:
    meu_clock ← NOVO_VECTOR_CLOCK(meu_id, lista_de_peers)

No envio de cada request/mensagem (1 linha):
    INJETAR_VETOR(headers, ENVIAR(meu_clock))

No recebimento de cada request/mensagem (2 linhas):
    vetor ← EXTRAIR_VETOR(headers)
    se vetor ≠ NENHUM: RECEBER(meu_clock, vetor)
```

**3 linhas de lógica por ponto de integração.** Menos que configurar retry,
circuit breaker, ou rate limiting - e com benefício imediato para debugging.

### O que você ganha de volta?

| Investimento                       | Retorno                                     |
|------------------------------------|---------------------------------------------|
| 1 header por request               | Logs com ordenação causal confiável         |
| ~3 linhas por endpoint             | Detecção automática de race conditions      |
| 1 mapa por serviço                 | Event replay determinístico                 |
| Nenhuma dependência de infra nova  | "Este bug é conflito" em vez de mistério    |

> **É mais simples que configurar NTP corretamente - e mais confiável.**
> Mais barato que distributed tracing, mais informativo que correlation IDs,
> e complementar a ambos.

---

## Text Transport (HTTP, gRPC ASCII)

```
função INJETAR_VETOR_TEXTO(headers, vector_timestamp):
    headers["X-Causality-Vector"] ← serializar_vetor(vector_timestamp)
    -- formato: "nó_a=3,nó_b=1,nó_c=5" (chaves em ordem lexicográfica)

função EXTRAIR_VETOR_TEXTO(headers):
    se "X-Causality-Vector" ausente em headers:
        retornar NENHUM     -- não é erro, apenas ausência
    senão:
        retornar parsear_vetor(headers["X-Causality-Vector"])
```

Exemplo de integração com um framework HTTP:
```
-- Enviando (qualquer cliente HTTP)
headers_causais = {}
INJETAR_VETOR_TEXTO(headers_causais, ENVIAR(meu_clock))
para cada (chave, valor) em headers_causais:
    adicionar_header_à_requisição(chave, valor)

-- Recebendo (qualquer servidor HTTP)
headers = converter_headers_da_requisição_para_mapa()
vetor = EXTRAIR_VETOR_TEXTO(headers)
se vetor ≠ NENHUM:
    RECEBER(meu_clock, vetor)
```

---

## Binary Transport (Kafka, gRPC binary)

```
função INJETAR_VETOR_BINÁRIO(headers, vector_timestamp):
    headers["causality-vc"] ← msgpack_serializar(vector_timestamp)
    -- msgpack: formato binário compacto

função EXTRAIR_VETOR_BINÁRIO(headers):
    se "causality-vc" ausente em headers:
        retornar NENHUM
    senão:
        retornar msgpack_deserializar(headers["causality-vc"])
```

### Por que msgpack para binário?

- **Mais compacto** que JSON para dados numéricos
- **Mais rápido** de serializar/deserializar
- Ideal para cenários de **alto throughput** (Kafka com milhares de msgs/s)

---

## JSON Transport (payload embutido)

Para quando a causalidade deve ir **dentro** do payload JSON:

```
função INJETAR_CAUSALIDADE_JSON(clock, payload_json):
    payload_json["_causality"] ← {
        "vector":     clock.vetores,
        "event_id":   gerar_uuid_v7(),
        "event_type": tipo_do_evento
    }
    retornar payload_json

função EXTRAIR_CAUSALIDADE_JSON(json):
    causalidade ← json["_causality"]
    remover json["_causality"]
    retornar (json, causalidade.vector)
```

Exemplo de payload enriquecido:
```json
{
  "pedido_id": 42,
  "status": "criado",
  "_causality": {
    "vector": { "svc-pedidos": 3, "svc-pagamento": 1 },
    "event_id": "019476a0-b1c2-7d3e-...",
    "event_type": "pedido.criado"
  }
}
```

---

## Tabela de referência dos formatos

| Transport | Chave/Header               | Formato                        |
|-----------|---------------------------|--------------------------------|
| HTTP      | `X-Causality-Lamport`     | `id_nó:timestamp`              |
| HTTP      | `X-Causality-Vector`      | `nó_a=3,nó_b=1,nó_c=5`        |
| HTTP      | `X-Causality-EventId`     | UUID v7                        |
| HTTP      | `X-Causality-EventType`   | texto                          |
| Kafka     | `causality-vc`            | msgpack bytes                  |
| Kafka     | `causality-lc`            | UTF-8 bytes                    |
| JSON      | `_causality`              | objeto embutido no payload     |

---

## Exercício rápido (5 min)

Dado o seguinte fluxo:

1. **Serviço de Pedidos** cria um pedido e injeta causalidade nos headers HTTP
2. **Serviço de Pagamento** recebe, extrai o vector clock, atualiza o clock local, processa e envia para Kafka
3. **Serviço de Estoque** consome do Kafka, extrai do record header

**Pergunta:** Quais funções de transport cada serviço usa?

**Resposta:**
1. Pedidos: `INJETAR_VETOR_TEXTO` (HTTP saída)
2. Pagamento: `EXTRAIR_VETOR_TEXTO` (HTTP entrada) + `INJETAR_VETOR_BINÁRIO` (Kafka saída)
3. Estoque: `EXTRAIR_VETOR_BINÁRIO` (Kafka entrada)

> Este padrão de propagação cross-transport é discutido no contexto de
> *context propagation* em sistemas de observabilidade.
> Vide Sigelman et al. (2010), "Dapper, a Large-Scale Distributed Systems Tracing Infrastructure".

---

## Resumo

| Conceito          | Descrição                                               |
|-------------------|---------------------------------------------------------|
| TracedEvent       | Envelope: evento + metadata causal                      |
| Text transport    | Headers HTTP como mapa texto→texto                      |
| Binary transport  | Record headers como mapa texto→bytes (msgpack)          |
| JSON transport    | Campo `_causality` embutido no payload JSON             |
| Agnóstico         | SDK não depende de frameworks - trabalha com tipos std  |

---

## Referências deste módulo

- Sigelman et al. (2010). *Dapper, a Large-Scale Distributed Systems Tracing Infrastructure.* Google.
- Coulouris et al. (2012), Seção 14.5 - "Global states and consistent cuts"
- Kleppmann (2017), Cap. 8 - propagação de contexto em sistemas distribuídos
