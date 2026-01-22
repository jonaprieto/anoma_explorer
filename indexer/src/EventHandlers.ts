/**
 * Event handlers for Anoma Protocol Adapter events.
 *
 * PA-EVM Event Order (within same EVM transaction):
 * 1. ResourcePayload/DiscoveryPayload/ExternalPayload/ApplicationPayload (per resource)
 * 2. ForwarderCallExecuted (if external calls exist)
 * 3. CommitmentTreeRootAdded
 * 4. ActionExecuted (per action)
 * 5. TransactionExecuted (once at the end)
 *
 * Tag Index Convention (from TransactionExecuted):
 * - Even indices (0, 2, 4...): consumed resources (nullifiers)
 * - Odd indices (1, 3, 5...): created resources (commitments)
 */

import {
  ProtocolAdapter,
  Transaction,
  Resource,
  Action,
  DiscoveryPayload,
  ExternalPayload,
  ApplicationPayload,
  CommitmentTreeRoot,
  ForwarderCall,
} from "generated";

import { safeDecodeResourceBlob } from "./decoders/ResourceDecoder";

// ============================================
// Helper Functions
// ============================================

/**
 * Creates a unique event identifier from event metadata.
 */
function createEventId(event: {
  chainId: number;
  block: { number: number };
  logIndex: number;
  srcAddress: string;
}): string {
  return `${event.chainId}_${event.block.number}_${event.logIndex}_${event.srcAddress}`;
}

/**
 * Creates a transaction identifier using the EVM transaction hash.
 * All events within the same EVM transaction share the same hash,
 * allowing proper correlation between TransactionExecuted, ResourcePayload, etc.
 */
function createTransactionId(chainId: number, txHash: string): string {
  return `${chainId}_${txHash}`;
}

/**
 * Creates a resource identifier from chain and tag.
 * Tags are globally unique (cryptographic commitments/nullifiers).
 */
function createResourceId(chainId: number, tag: string): string {
  return `${chainId}_${tag}_resource`;
}

// ============================================
// TransactionExecuted Handler
// ============================================
// This event fires LAST in the transaction, after all payload events.
// It provides the authoritative list of tags and their consumed/created status.

ProtocolAdapter.TransactionExecuted.handler(async ({ event, context }) => {
  const txId = createTransactionId(event.chainId, event.transaction.hash);

  // Create Transaction entity (Anoma Transaction)
  const txEntity: Transaction = {
    id: txId,
    blockNumber: event.block.number,
    logIndex: event.logIndex,
    txHash: event.transaction.hash,
    timestamp: event.block.timestamp,
    chainId: event.chainId,
    contractAddress: event.srcAddress,
    tags: event.params.tags,
    logicRefs: event.params.logicRefs,
    // Proofs would come from calldata decoding (future)
    deltaProof: undefined,
    aggregationProof: undefined,
  };

  context.Transaction.set(txEntity);

  // Update/Create Resource entities for each tag
  // Tags are in alternating order: consumed (nullifier), created (commitment), ...
  for (let index = 0; index < event.params.tags.length; index++) {
    const tag = event.params.tags[index];
    const isConsumed = index % 2 === 0;
    const resourceId = createResourceId(event.chainId, tag);
    const logicRef = event.params.logicRefs[index];

    // Check if resource already exists (created by earlier ResourcePayload event)
    const existingResource = await context.Resource.get(resourceId);

    if (existingResource) {
      // Update existing resource with authoritative isConsumed and index from TransactionExecuted
      const updatedResource: Resource = {
        ...existingResource,
        index: index,
        isConsumed: isConsumed,
        transaction_id: txId,
        logicRef: logicRef || existingResource.logicRef,
      };
      context.Resource.set(updatedResource);
    } else {
      // Create new resource (ResourcePayload may not have fired yet or at all)
      const resourceEntity: Resource = {
        id: resourceId,
        tag: tag,
        index: index,
        isConsumed: isConsumed,
        blockNumber: event.block.number,
        chainId: event.chainId,
        rawBlob: "",
        decodingStatus: "pending",
        decodingError: undefined,
        transaction_id: txId,
        logicRef: logicRef || undefined,
        labelRef: undefined,
        valueRef: undefined,
        nullifierKeyCommitment: undefined,
        nonce: undefined,
        randSeed: undefined,
        quantity: undefined,
        ephemeral: undefined,
        logicInput_id: undefined,
        consumedInComplianceUnit_id: undefined,
        createdInComplianceUnit_id: undefined,
      };
      context.Resource.set(resourceEntity);
    }
  }
});

// ============================================
// ActionExecuted Handler
// ============================================
// ActionExecuted fires BEFORE TransactionExecuted but AFTER payload events.

ProtocolAdapter.ActionExecuted.handler(async ({ event, context }) => {
  const txId = createTransactionId(event.chainId, event.transaction.hash);
  // Use txHash + actionTreeRoot for unique action ID since multiple actions can be in one tx
  const actionId = `${txId}_${event.params.actionTreeRoot}`;

  const actionEntity: Action = {
    id: actionId,
    index: 0, // Would need calldata to determine action index within transaction
    actionTreeRoot: event.params.actionTreeRoot,
    tagCount: Number(event.params.actionTagCount),
    blockNumber: event.block.number,
    chainId: event.chainId,
    timestamp: event.block.timestamp,
    transaction_id: txId,
  };

  context.Action.set(actionEntity);
});

// ============================================
// ResourcePayload Handler
// ============================================
// ResourcePayload fires BEFORE TransactionExecuted.
// We create/update the Resource but isConsumed will be set correctly by TransactionExecuted later.

ProtocolAdapter.ResourcePayload.handler(async ({ event, context }) => {
  const resourceId = createResourceId(event.chainId, event.params.tag);
  const txId = createTransactionId(event.chainId, event.transaction.hash);

  // Decode the blob
  const decoded = safeDecodeResourceBlob(event.params.blob);

  // Check if resource already exists
  const existingResource = await context.Resource.get(resourceId);

  if (existingResource) {
    // Update existing resource with decoded data (preserve isConsumed if already set)
    const updatedResource: Resource = {
      ...existingResource,
      rawBlob: event.params.blob,
      decodingStatus: decoded.status,
      decodingError: decoded.error || undefined,
      logicRef: decoded.resource?.logicRef || existingResource.logicRef,
      labelRef: decoded.resource?.labelRef || undefined,
      valueRef: decoded.resource?.valueRef || undefined,
      nullifierKeyCommitment: decoded.resource?.nullifierKeyCommitment || undefined,
      nonce: decoded.resource?.nonce || undefined,
      randSeed: decoded.resource?.randSeed || undefined,
      quantity: decoded.resource?.quantity || undefined,
      ephemeral: decoded.resource?.ephemeral ?? undefined,
    };
    context.Resource.set(updatedResource);
  } else {
    // Create new resource - isConsumed will be updated by TransactionExecuted
    // Use index from event (blob index) temporarily, will be corrected by TransactionExecuted
    const resourceEntity: Resource = {
      id: resourceId,
      tag: event.params.tag,
      index: Number(event.params.index), // This is blob index, not tag index
      isConsumed: false, // Placeholder - will be set correctly by TransactionExecuted
      blockNumber: event.block.number,
      chainId: event.chainId,
      rawBlob: event.params.blob,
      decodingStatus: decoded.status,
      decodingError: decoded.error || undefined,
      transaction_id: txId,
      logicRef: decoded.resource?.logicRef || undefined,
      labelRef: decoded.resource?.labelRef || undefined,
      valueRef: decoded.resource?.valueRef || undefined,
      nullifierKeyCommitment: decoded.resource?.nullifierKeyCommitment || undefined,
      nonce: decoded.resource?.nonce || undefined,
      randSeed: decoded.resource?.randSeed || undefined,
      quantity: decoded.resource?.quantity || undefined,
      ephemeral: decoded.resource?.ephemeral ?? undefined,
      logicInput_id: undefined,
      consumedInComplianceUnit_id: undefined,
      createdInComplianceUnit_id: undefined,
    };
    context.Resource.set(resourceEntity);
  }
});

// ============================================
// DiscoveryPayload Handler
// ============================================

ProtocolAdapter.DiscoveryPayload.handler(async ({ event, context }) => {
  const eventId = createEventId(event);
  const resourceId = createResourceId(event.chainId, event.params.tag);

  const entity: DiscoveryPayload = {
    id: eventId,
    tag: event.params.tag,
    index: Number(event.params.index),
    blob: event.params.blob,
    deletionCriterion: undefined, // Would need to decode from blob structure
    blockNumber: event.block.number,
    chainId: event.chainId,
    timestamp: event.block.timestamp,
    resource_id: resourceId,
  };

  context.DiscoveryPayload.set(entity);
});

// ============================================
// ExternalPayload Handler
// ============================================

ProtocolAdapter.ExternalPayload.handler(async ({ event, context }) => {
  const eventId = createEventId(event);

  const entity: ExternalPayload = {
    id: eventId,
    tag: event.params.tag,
    index: Number(event.params.index),
    blob: event.params.blob,
    deletionCriterion: undefined,
    blockNumber: event.block.number,
    chainId: event.chainId,
    timestamp: event.block.timestamp,
  };

  context.ExternalPayload.set(entity);
});

// ============================================
// ApplicationPayload Handler
// ============================================

ProtocolAdapter.ApplicationPayload.handler(async ({ event, context }) => {
  const eventId = createEventId(event);
  const resourceId = createResourceId(event.chainId, event.params.tag);

  const entity: ApplicationPayload = {
    id: eventId,
    tag: event.params.tag,
    index: Number(event.params.index),
    blob: event.params.blob,
    deletionCriterion: undefined,
    blockNumber: event.block.number,
    chainId: event.chainId,
    timestamp: event.block.timestamp,
    resource_id: resourceId,
  };

  context.ApplicationPayload.set(entity);
});

// ============================================
// CommitmentTreeRootAdded Handler
// ============================================

ProtocolAdapter.CommitmentTreeRootAdded.handler(async ({ event, context }) => {
  const eventId = createEventId(event);

  // Use a deterministic index based on the root value for consistency
  // In practice, roots are added sequentially per transaction
  const entity: CommitmentTreeRoot = {
    id: eventId,
    root: event.params.root,
    blockNumber: event.block.number,
    txHash: event.transaction.hash,
    timestamp: event.block.timestamp,
    chainId: event.chainId,
    index: 0, // Index within transaction - would need state tracking for global index
  };

  context.CommitmentTreeRoot.set(entity);
});

// ============================================
// ForwarderCallExecuted Handler
// ============================================

ProtocolAdapter.ForwarderCallExecuted.handler(async ({ event, context }) => {
  const eventId = createEventId(event);

  const entity: ForwarderCall = {
    id: eventId,
    forwarderAddress: event.params.untrustedForwarder,
    input: event.params.input,
    output: event.params.output,
    blockNumber: event.block.number,
    txHash: event.transaction.hash,
    timestamp: event.block.timestamp,
    chainId: event.chainId,
  };

  context.ForwarderCall.set(entity);
});
