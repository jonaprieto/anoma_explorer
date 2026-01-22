# Anoma Explorer Indexer

Envio Hyperindex indexer for PA-EVM (Protocol Adapter) events powering the Anoma Explorer.  
It ingests on-chain events, normalises them into typed entities, and exposes a GraphQL API for
querying transactions, resources, actions, and related metadata.

## Prerequisites

- Node.js (LTS)
- `pnpm`
- Network access to the configured GraphQL endpoint

## Setup

Install dependencies, generate types from the GraphQL schema, and build the project:

```bash
pnpm install
pnpm codegen
pnpm build
```

## Commands

| Command        | Description                              |
|----------------|------------------------------------------|
| `pnpm dev`     | Run the indexer in development mode      |
| `pnpm start`   | Run the indexer in production mode       |
| `pnpm test`    | Run tests against the GraphQL endpoint   |
| `pnpm codegen` | Regenerate TypeScript types from schema  |

## GraphQL API

Default GraphQL endpoint:

```text
https://indexer.dev.hyperindex.xyz/d60d83b/v1/graphql
```

You can point the tooling to a different endpoint via environment variables (see Testing).

## Example Queries

### Entity sample (health check)

```graphql
query {
  Transaction(limit: 10) { id txHash }
  Resource(limit: 10) { id tag }
  Action(limit: 10) { id actionTreeRoot }
}
```

### Recent transactions

```graphql
query {
  Transaction(limit: 10, order_by: { blockNumber: desc }) {
    txHash
    blockNumber
    tags
    logicRefs
  }
}
```

### Transaction with resources and actions

```graphql
query {
  Transaction(limit: 1) {
    txHash
    tags
    resources {
      tag
      isConsumed
      logicRef
      quantity
    }
    actions {
      actionTreeRoot
      tagCount
    }
  }
}
```

### Filter resources

Consumed resources (nullifiers):

```graphql
query {
  Resource(where: { isConsumed: { _eq: true } }, limit: 5) {
    tag
    logicRef
    transaction { txHash }
  }
}
```

Created resources (commitments):

```graphql
query {
  Resource(where: { isConsumed: { _eq: false } }, limit: 5) {
    tag
    logicRef
    quantity
  }
}
```

### Commitment tree roots

```graphql
query {
  CommitmentTreeRoot(limit: 10, order_by: { blockNumber: desc }) {
    root
    blockNumber
    txHash
  }
}
```

### Compliance units

```graphql
query {
  ComplianceUnit(limit: 10) {
    id
    consumedNullifier
    createdCommitment
    consumedLogicRef
    createdLogicRef
    unitDeltaX
    unitDeltaY
    action {
      actionTreeRoot
    }
  }
}
```

### Logic inputs

```graphql
query {
  LogicInput(limit: 10) {
    id
    tag
    verifyingKey
    isConsumed
    resourcePayloadCount
    discoveryPayloadCount
    action {
      actionTreeRoot
    }
    resource {
      tag
      isConsumed
    }
  }
}
```

### Actions with compliance and logic details

```graphql
query {
  Action(limit: 5) {
    actionTreeRoot
    tagCount
    complianceUnits {
      consumedNullifier
      createdCommitment
    }
    logicInputs {
      tag
      isConsumed
      verifyingKey
    }
    transaction {
      txHash
    }
  }
}
```

### Debug failed decodes

```graphql
query {
  Resource(where: { decodingStatus: { _eq: "failed" } }) {
    tag
    rawBlob
    decodingError
  }
}
```

## Indexed Events

The indexer consumes the following PA-EVM events and materialises them into entities:

| Event                     | Entity / Entities                                      |
|---------------------------|--------------------------------------------------------|
| `TransactionExecuted`     | `Transaction`, `Resource`                              |
| `ActionExecuted`          | `Action`, `ComplianceUnit`, `LogicInput` (via calldata)|
| `ResourcePayload`         | `Resource` (blob decoding)                             |
| `DiscoveryPayload`        | `DiscoveryPayload`                                     |
| `ExternalPayload`         | `ExternalPayload`                                      |
| `ApplicationPayload`      | `ApplicationPayload`                                   |
| `CommitmentTreeRootAdded` | `CommitmentTreeRoot`                                   |
| `ForwarderCallExecuted`   | `ForwarderCall`                                        |

## Calldata Decoding

The indexer decodes the `execute()` function calldata to extract detailed information not available
in events alone:

- **ComplianceUnit**: Created from `complianceVerifierInputs` in each Action
  - Contains nullifier/commitment pairs, logic refs, delta values, and proofs
- **LogicInput**: Created from `logicVerifierInputs` in each Action
  - Contains tags, verifying keys, app data payload counts, and proofs
- **Transaction proofs**: `deltaProof` and `aggregationProof` are extracted from calldata

This requires the `input` field to be included in `transaction_fields` in the config.

## Tag Index Convention

Tags emitted in `TransactionExecuted` alternate between consumed and created resources:

- Even indices (0, 2, 4, …): consumed resources (nullifiers)
- Odd indices (1, 3, 5, …): created resources (commitments)

This convention is reflected in the `Transaction` and `Resource` entities and should be respected
when interpreting tag sequences.

## Testing

Run the test suite against the GraphQL endpoint:

```bash
# Using the default endpoint
pnpm test

# Using a custom endpoint
ENVIO_GRAPHQL_URL=https://your-endpoint/v1/graphql pnpm test
```

The `ENVIO_GRAPHQL_URL` variable controls which GraphQL instance the tests target, allowing you
to validate the indexer against different deployments (e.g. local, staging, production).
