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
  ComplianceUnit,
  LogicInput,
  DiscoveryPayload,
  ExternalPayload,
  ApplicationPayload,
  CommitmentTreeRoot,
  ForwarderCall,
  handlerContext,
  ProtocolAdapter_TransactionExecuted_event,
  ProtocolAdapter_ActionExecuted_event,
  ProtocolAdapter_ResourcePayload_event,
  ProtocolAdapter_DiscoveryPayload_event,
  ProtocolAdapter_ExternalPayload_event,
  ProtocolAdapter_ApplicationPayload_event,
  ProtocolAdapter_CommitmentTreeRootAdded_event,
  ProtocolAdapter_ForwarderCallExecuted_event,
} from "generated";

import { safeDecodeResourceBlob } from "./decoders/ResourceDecoder";
import {
  decodeExecuteCalldata,
  isExecuteCalldata,
} from "./decoders/ActionDecoder";
import type { Action as DecodedAction } from "./types";

// ============================================
// Type Aliases
// ============================================

type TransactionExecutedArgs = {
  event: ProtocolAdapter_TransactionExecuted_event;
  context: handlerContext;
};

type ActionExecutedArgs = {
  event: ProtocolAdapter_ActionExecuted_event;
  context: handlerContext;
};

type ResourcePayloadArgs = {
  event: ProtocolAdapter_ResourcePayload_event;
  context: handlerContext;
};

type DiscoveryPayloadArgs = {
  event: ProtocolAdapter_DiscoveryPayload_event;
  context: handlerContext;
};

type ExternalPayloadArgs = {
  event: ProtocolAdapter_ExternalPayload_event;
  context: handlerContext;
};

type ApplicationPayloadArgs = {
  event: ProtocolAdapter_ApplicationPayload_event;
  context: handlerContext;
};

type CommitmentTreeRootAddedArgs = {
  event: ProtocolAdapter_CommitmentTreeRootAdded_event;
  context: handlerContext;
};

type ForwarderCallExecutedArgs = {
  event: ProtocolAdapter_ForwarderCallExecuted_event;
  context: handlerContext;
};

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

/**
 * Creates a compliance unit identifier.
 */
function createComplianceUnitId(
  actionId: string,
  index: number
): string {
  return `${actionId}_compliance_${index}`;
}

/**
 * Creates a logic input identifier.
 */
function createLogicInputId(actionId: string, index: number): string {
  return `${actionId}_logic_${index}`;
}

// ============================================
// Calldata Decoding Cache
// ============================================
// Cache decoded calldata by txHash to avoid re-decoding for each ActionExecuted event
// within the same EVM transaction.
const decodedCalldataCache = new Map<
  string,
  {
    actions: DecodedAction[];
    deltaProof: string;
    aggregationProof: string;
  }
>();

/**
 * Get decoded transaction data from cache or decode from calldata.
 */
function getDecodedTransaction(
  txHash: string,
  input: string | undefined
): {
  actions: DecodedAction[];
  deltaProof: string;
  aggregationProof: string;
} | null {
  // Check cache first
  const cached = decodedCalldataCache.get(txHash);
  if (cached) {
    return cached;
  }

  // Try to decode calldata
  if (!input || !isExecuteCalldata(input)) {
    return null;
  }

  const result = decodeExecuteCalldata(input);
  if (!result.success) {
    console.log(`Failed to decode calldata for tx ${txHash}: ${result.error}`);
    return null;
  }

  // Cache the result
  const decoded = {
    actions: result.transaction.actions,
    deltaProof: result.transaction.deltaProof,
    aggregationProof: result.transaction.aggregationProof,
  };
  decodedCalldataCache.set(txHash, decoded);

  return decoded;
}

/**
 * Clear cache entry after transaction is fully processed.
 */
function clearDecodedCache(txHash: string): void {
  decodedCalldataCache.delete(txHash);
}

// ============================================
// TransactionExecuted Handler
// ============================================
// This event fires LAST in the transaction, after all payload events.
// It provides the authoritative list of tags and their consumed/created status.

ProtocolAdapter.TransactionExecuted.handler(
  async ({ event, context }: TransactionExecutedArgs) => {
    const txId = createTransactionId(event.chainId, event.transaction.hash);
    const txHash = event.transaction.hash;

    // Try to decode calldata for proofs
    // Note: event.transaction.input is available because we added "input" to field_selection
    const txInput = (event.transaction as { hash: string; input?: string })
      .input;
    const decoded = getDecodedTransaction(txHash, txInput);

    // Create Transaction entity (Anoma Transaction)
    const txEntity: Transaction = {
      id: txId,
      blockNumber: event.block.number,
      logIndex: event.logIndex,
      txHash: txHash,
      timestamp: event.block.timestamp,
      chainId: event.chainId,
      contractAddress: event.srcAddress,
      tags: event.params.tags,
      logicRefs: event.params.logicRefs,
      deltaProof: decoded?.deltaProof,
      aggregationProof: decoded?.aggregationProof,
    };

    context.Transaction.set(txEntity);

    // Build a map from nullifier/commitment to compliance unit ID for linking resources
    // This requires looking at all compliance units from all actions
    const nullifierToComplianceUnit = new Map<string, string>();
    const commitmentToComplianceUnit = new Map<string, string>();
    const tagToLogicInput = new Map<string, string>();

    if (decoded) {
      for (let actionIndex = 0; actionIndex < decoded.actions.length; actionIndex++) {
        const action = decoded.actions[actionIndex];
        // We need to find the action ID - it's based on actionTreeRoot which we can compute
        // For now, we'll iterate through actions and match by index
        // The ActionExecuted events have already created Action entities

        // Get all actions for this transaction to find the matching actionId
        // Since we can't easily query by transaction here, we'll construct the ID
        // based on the pattern used in ActionExecuted handler

        // Compliance units
        for (let cuIndex = 0; cuIndex < action.complianceVerifierInputs.length; cuIndex++) {
          const cu = action.complianceVerifierInputs[cuIndex];
          // We need the actionId to construct compliance unit ID
          // The ActionExecuted handler uses: `${txId}_${actionTreeRoot}`
          // We don't have actionTreeRoot here directly, so we'll use action index
          // This means we need to update how we track this...

          // For now, store by nullifier/commitment directly
          nullifierToComplianceUnit.set(
            cu.instance.consumed.nullifier.toLowerCase(),
            `action_${actionIndex}_compliance_${cuIndex}`
          );
          commitmentToComplianceUnit.set(
            cu.instance.created.commitment.toLowerCase(),
            `action_${actionIndex}_compliance_${cuIndex}`
          );
        }

        // Logic inputs - map tag to logic input
        for (let liIndex = 0; liIndex < action.logicVerifierInputs.length; liIndex++) {
          const li = action.logicVerifierInputs[liIndex];
          tagToLogicInput.set(
            li.tag.toLowerCase(),
            `action_${actionIndex}_logic_${liIndex}`
          );
        }
      }
    }

    // Update/Create Resource entities for each tag
    // Tags are in alternating order: consumed (nullifier), created (commitment), ...
    for (let index = 0; index < event.params.tags.length; index++) {
      const tag = event.params.tags[index];
      const isConsumed = index % 2 === 0;
      const resourceId = createResourceId(event.chainId, tag);
      const logicRef = event.params.logicRefs[index];
      const tagLower = tag.toLowerCase();

      // Find linked compliance unit and logic input
      let consumedInComplianceUnit_id: string | undefined;
      let createdInComplianceUnit_id: string | undefined;
      let logicInput_id: string | undefined;

      if (isConsumed) {
        // This is a nullifier - look up in nullifier map
        const cuKey = nullifierToComplianceUnit.get(tagLower);
        if (cuKey) {
          // Need to construct full ID with actual action ID
          // For now we mark this as a placeholder to be updated
          consumedInComplianceUnit_id = undefined; // Will be set by linking phase
        }
      } else {
        // This is a commitment - look up in commitment map
        const cuKey = commitmentToComplianceUnit.get(tagLower);
        if (cuKey) {
          createdInComplianceUnit_id = undefined; // Will be set by linking phase
        }
      }

      // Logic input by tag
      const liKey = tagToLogicInput.get(tagLower);
      if (liKey) {
        logicInput_id = undefined; // Will be set by linking phase
      }

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
          // Keep existing links if already set
          logicInput_id: existingResource.logicInput_id || logicInput_id,
          consumedInComplianceUnit_id:
            existingResource.consumedInComplianceUnit_id ||
            consumedInComplianceUnit_id,
          createdInComplianceUnit_id:
            existingResource.createdInComplianceUnit_id ||
            createdInComplianceUnit_id,
        };
        context.Resource.set(updatedResource);
      } else {
        // Create new resource (ResourcePayload may not have fired yet or at all)
        const resourceEntity: Resource = {
          id: resourceId,
          tag: tag,
          index: index,
          blobIndex: undefined,
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
          logicInput_id: logicInput_id,
          consumedInComplianceUnit_id: consumedInComplianceUnit_id,
          createdInComplianceUnit_id: createdInComplianceUnit_id,
        };
        context.Resource.set(resourceEntity);
      }
    }

    // Clear the cache after processing is complete
    clearDecodedCache(txHash);
  }
);

// ============================================
// ActionExecuted Handler
// ============================================
// ActionExecuted fires BEFORE TransactionExecuted but AFTER payload events.
// We decode the calldata here to create ComplianceUnit and LogicInput entities.

ProtocolAdapter.ActionExecuted.handler(
  async ({ event, context }: ActionExecutedArgs) => {
    const txId = createTransactionId(event.chainId, event.transaction.hash);
    const txHash = event.transaction.hash;
    // Use txHash + actionTreeRoot for unique action ID since multiple actions can be in one tx
    const actionId = `${txId}_${event.params.actionTreeRoot}`;

    // Try to decode calldata to get action details
    const txInput = (event.transaction as { hash: string; input?: string })
      .input;
    const decoded = getDecodedTransaction(txHash, txInput);

    // Find which action index this is by matching actionTreeRoot
    // For now, we'll try to match by index since we process actions in order
    let actionIndex = 0;
    let decodedAction: DecodedAction | null = null;

    if (decoded) {
      // Try to find the action by comparing actionTreeRoot
      // The actionTreeRoot is computed from the action data
      // Since we can't easily compute it here, we'll use the order of ActionExecuted events
      // by tracking how many we've seen for this transaction

      // Simple approach: assume actions are processed in order
      // Count existing actions for this transaction
      // Note: This is a limitation - we're assuming sequential processing
      // A more robust solution would compute the actionTreeRoot from decoded data

      // For now, we'll iterate and pick the first action that hasn't been assigned
      // Since ActionExecuted events come in order, this should work
      for (let i = 0; i < decoded.actions.length; i++) {
        const potentialAction = decoded.actions[i];
        // Check if this action's tag count matches
        if (
          potentialAction.logicVerifierInputs.length ===
          Number(event.params.actionTagCount)
        ) {
          // Likely match - use this action
          decodedAction = potentialAction;
          actionIndex = i;
          break;
        }
      }

      // If no match by tag count, just use index 0 (fallback)
      if (!decodedAction && decoded.actions.length > 0) {
        decodedAction = decoded.actions[0];
        actionIndex = 0;
      }
    }

    // Create Action entity
    const actionEntity: Action = {
      id: actionId,
      index: actionIndex,
      actionTreeRoot: event.params.actionTreeRoot,
      tagCount: Number(event.params.actionTagCount),
      blockNumber: event.block.number,
      chainId: event.chainId,
      timestamp: event.block.timestamp,
      transaction_id: txId,
    };

    context.Action.set(actionEntity);

    // Create ComplianceUnit entities from decoded action
    if (decodedAction) {
      for (
        let cuIndex = 0;
        cuIndex < decodedAction.complianceVerifierInputs.length;
        cuIndex++
      ) {
        const cu = decodedAction.complianceVerifierInputs[cuIndex];
        const complianceUnitId = createComplianceUnitId(actionId, cuIndex);

        // Find resources by nullifier/commitment
        const consumedResourceId = createResourceId(
          event.chainId,
          cu.instance.consumed.nullifier
        );
        const createdResourceId = createResourceId(
          event.chainId,
          cu.instance.created.commitment
        );

        // Try to get existing resources to link
        const consumedResource = await context.Resource.get(consumedResourceId);
        const createdResource = await context.Resource.get(createdResourceId);

        const complianceEntity: ComplianceUnit = {
          id: complianceUnitId,
          index: cuIndex,
          proof: cu.proof || undefined,
          consumedNullifier: cu.instance.consumed.nullifier,
          consumedLogicRef: cu.instance.consumed.logicRef,
          consumedCommitmentTreeRoot: cu.instance.consumed.commitmentTreeRoot,
          createdCommitment: cu.instance.created.commitment,
          createdLogicRef: cu.instance.created.logicRef,
          unitDeltaX: cu.instance.unitDeltaX,
          unitDeltaY: cu.instance.unitDeltaY,
          action_id: actionId,
          consumedResource_id: consumedResource ? consumedResourceId : undefined,
          createdResource_id: createdResource ? createdResourceId : undefined,
        };

        context.ComplianceUnit.set(complianceEntity);

        // Update resources with compliance unit links if they exist
        if (consumedResource) {
          const updatedResource: Resource = {
            ...consumedResource,
            consumedInComplianceUnit_id: complianceUnitId,
          };
          context.Resource.set(updatedResource);
        }

        if (createdResource) {
          const updatedResource: Resource = {
            ...createdResource,
            createdInComplianceUnit_id: complianceUnitId,
          };
          context.Resource.set(updatedResource);
        }
      }

      // Create LogicInput entities from decoded action
      for (
        let liIndex = 0;
        liIndex < decodedAction.logicVerifierInputs.length;
        liIndex++
      ) {
        const li = decodedAction.logicVerifierInputs[liIndex];
        const logicInputId = createLogicInputId(actionId, liIndex);

        // Determine if consumed based on index (even = consumed, odd = created)
        const isConsumed = liIndex % 2 === 0;

        // Find resource by tag
        const resourceId = createResourceId(event.chainId, li.tag);
        const resource = await context.Resource.get(resourceId);

        const logicEntity: LogicInput = {
          id: logicInputId,
          index: liIndex,
          tag: li.tag,
          verifyingKey: li.verifyingKey,
          isConsumed: isConsumed,
          proof: li.proof || undefined,
          resourcePayloadCount: li.appData.resourcePayload.length,
          discoveryPayloadCount: li.appData.discoveryPayload.length,
          externalPayloadCount: li.appData.externalPayload.length,
          applicationPayloadCount: li.appData.applicationPayload.length,
          action_id: actionId,
          resource_id: resource ? resourceId : undefined,
        };

        context.LogicInput.set(logicEntity);

        // Update resource with logic input link if it exists
        if (resource) {
          const updatedResource: Resource = {
            ...resource,
            logicInput_id: logicInputId,
          };
          context.Resource.set(updatedResource);
        }
      }
    }
  }
);

// ============================================
// ResourcePayload Handler
// ============================================
// ResourcePayload fires BEFORE TransactionExecuted.
// We create/update the Resource but isConsumed will be set correctly by TransactionExecuted later.

ProtocolAdapter.ResourcePayload.handler(
  async ({ event, context }: ResourcePayloadArgs) => {
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
        blobIndex: Number(event.params.index),
        rawBlob: event.params.blob,
        decodingStatus: decoded.status,
        decodingError: decoded.error || undefined,
        logicRef: decoded.resource?.logicRef || existingResource.logicRef,
        labelRef: decoded.resource?.labelRef || undefined,
        valueRef: decoded.resource?.valueRef || undefined,
        nullifierKeyCommitment:
          decoded.resource?.nullifierKeyCommitment || undefined,
        nonce: decoded.resource?.nonce || undefined,
        randSeed: decoded.resource?.randSeed || undefined,
        quantity: decoded.resource?.quantity || undefined,
        ephemeral: decoded.resource?.ephemeral ?? undefined,
      };
      context.Resource.set(updatedResource);
    } else {
      // Create new resource - isConsumed will be updated by TransactionExecuted
      // Use index 0 as placeholder (Tag Index will be set by TransactionExecuted)
      const resourceEntity: Resource = {
        id: resourceId,
        tag: event.params.tag,
        index: 0, // Placeholder
        blobIndex: Number(event.params.index),
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
        nullifierKeyCommitment:
          decoded.resource?.nullifierKeyCommitment || undefined,
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
  }
);

// ============================================
// DiscoveryPayload Handler
// ============================================

ProtocolAdapter.DiscoveryPayload.handler(
  async ({ event, context }: DiscoveryPayloadArgs) => {
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
  }
);

// ============================================
// ExternalPayload Handler
// ============================================

ProtocolAdapter.ExternalPayload.handler(
  async ({ event, context }: ExternalPayloadArgs) => {
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
  }
);

// ============================================
// ApplicationPayload Handler
// ============================================

ProtocolAdapter.ApplicationPayload.handler(
  async ({ event, context }: ApplicationPayloadArgs) => {
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
  }
);

// ============================================
// CommitmentTreeRootAdded Handler
// ============================================

ProtocolAdapter.CommitmentTreeRootAdded.handler(
  async ({ event, context }: CommitmentTreeRootAddedArgs) => {
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
  }
);

// ============================================
// ForwarderCallExecuted Handler
// ============================================

ProtocolAdapter.ForwarderCallExecuted.handler(
  async ({ event, context }: ForwarderCallExecutedArgs) => {
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
  }
);
