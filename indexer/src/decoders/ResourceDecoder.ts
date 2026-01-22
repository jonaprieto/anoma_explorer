/**
 * Decoder for Resource blobs from ResourcePayload events.
 */

import { decodeAbiParameters } from "viem";
import { Resource, DecodedResource } from "../types/Resource";
import { RESOURCE_ABI } from "../utils/abi";

/**
 * Decodes a Resource blob from ABI-encoded bytes.
 *
 * @param blob - The hex-encoded blob from ResourcePayload event
 * @returns DecodedResource with status and optional error
 */
export function decodeResourceBlob(blob: `0x${string}`): DecodedResource {
  try {
    const decoded = decodeAbiParameters(RESOURCE_ABI, blob);
    const resourceTuple = decoded[0] as {
      logicRef: `0x${string}`;
      labelRef: `0x${string}`;
      valueRef: `0x${string}`;
      nullifierKeyCommitment: `0x${string}`;
      nonce: `0x${string}`;
      randSeed: `0x${string}`;
      quantity: bigint;
      ephemeral: boolean;
    };

    return {
      resource: {
        logicRef: resourceTuple.logicRef,
        labelRef: resourceTuple.labelRef,
        valueRef: resourceTuple.valueRef,
        nullifierKeyCommitment: resourceTuple.nullifierKeyCommitment,
        nonce: resourceTuple.nonce,
        randSeed: resourceTuple.randSeed,
        quantity: resourceTuple.quantity,
        ephemeral: resourceTuple.ephemeral,
      },
      status: "success",
    };
  } catch (error) {
    return {
      resource: null,
      status: "failed",
      error: error instanceof Error ? error.message : "Unknown decoding error",
    };
  }
}

/**
 * Safely decodes a Resource blob with input validation.
 *
 * @param blob - The blob string (with or without 0x prefix)
 * @returns DecodedResource with status and optional error
 */
export function safeDecodeResourceBlob(blob: string): DecodedResource {
  // Ensure blob has 0x prefix
  const normalizedBlob = blob.startsWith("0x") ? blob : `0x${blob}`;

  // Validate hex format
  if (!/^0x[0-9a-fA-F]*$/.test(normalizedBlob)) {
    return {
      resource: null,
      status: "failed",
      error: "Invalid hex format",
    };
  }

  // Check minimum length (Resource has 8 fields, needs substantial data)
  if (normalizedBlob.length < 66) {
    // At least one bytes32
    return {
      resource: null,
      status: "failed",
      error: "Blob too short to contain valid Resource data",
    };
  }

  return decodeResourceBlob(normalizedBlob as `0x${string}`);
}
