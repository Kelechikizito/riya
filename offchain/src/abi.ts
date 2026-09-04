// GENERATED FILE — do not edit.
// Produced by `npm run abi` from Foundry's `out/`. Regenerate after any contract change.

export const RIYA_ASC_ABI = [
  {
    "type": "function",
    "name": "I_CHAIN_KEY",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "uint64",
        "internalType": "uint64"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "isConsumed",
    "inputs": [
      {
        "name": "key",
        "type": "bytes32",
        "internalType": "bytes32"
      }
    ],
    "outputs": [
      {
        "name": "",
        "type": "bool",
        "internalType": "bool"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "submit",
    "inputs": [
      {
        "name": "height",
        "type": "uint64",
        "internalType": "uint64"
      },
      {
        "name": "encodedTransaction",
        "type": "bytes",
        "internalType": "bytes"
      },
      {
        "name": "merkleProof",
        "type": "tuple",
        "internalType": "struct INativeQueryVerifier.MerkleProof",
        "components": [
          {
            "name": "root",
            "type": "bytes32",
            "internalType": "bytes32"
          },
          {
            "name": "siblings",
            "type": "tuple[]",
            "internalType": "struct INativeQueryVerifier.MerkleProofEntry[]",
            "components": [
              {
                "name": "hash",
                "type": "bytes32",
                "internalType": "bytes32"
              },
              {
                "name": "isLeft",
                "type": "bool",
                "internalType": "bool"
              }
            ]
          }
        ]
      },
      {
        "name": "continuityProof",
        "type": "tuple",
        "internalType": "struct INativeQueryVerifier.ContinuityProof",
        "components": [
          {
            "name": "lowerEndpointDigest",
            "type": "bytes32",
            "internalType": "bytes32"
          },
          {
            "name": "roots",
            "type": "bytes32[]",
            "internalType": "bytes32[]"
          }
        ]
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "event",
    "name": "ProofConsumed",
    "inputs": [
      {
        "name": "key",
        "type": "bytes32",
        "indexed": true,
        "internalType": "bytes32"
      },
      {
        "name": "action",
        "type": "uint8",
        "indexed": true,
        "internalType": "enum RiyaASC.RiyaASCActions"
      },
      {
        "name": "value",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      }
    ],
    "anonymous": false
  },
  {
    "type": "error",
    "name": "RiyaASC__AlreadyConsumed",
    "inputs": [
      {
        "name": "key",
        "type": "bytes32",
        "internalType": "bytes32"
      }
    ]
  },
  {
    "type": "error",
    "name": "RiyaASC__NoRelevantLog",
    "inputs": []
  },
  {
    "type": "error",
    "name": "RiyaASC__ProofInvalid",
    "inputs": []
  },
  {
    "type": "error",
    "name": "RiyaASC__TxReverted",
    "inputs": [
      {
        "name": "failedTransaction",
        "type": "bytes",
        "internalType": "bytes"
      }
    ]
  },
  {
    "type": "error",
    "name": "RiyaASC__ZeroHeight",
    "inputs": []
  }
] as const;

export const RIYA_ESCROW_ABI = [
  {
    "type": "event",
    "name": "TokensDepositedConfirmedByEscrow",
    "inputs": [
      {
        "name": "user",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      },
      {
        "name": "assets",
        "type": "uint256",
        "indexed": true,
        "internalType": "uint256"
      }
    ],
    "anonymous": false
  }
] as const;

export const AAVE_V4_ADAPTER_ABI = [
  {
    "type": "function",
    "name": "I_MIN_HARVEST",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "harvest",
    "inputs": [],
    "outputs": [
      {
        "name": "assets",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "yieldAccrued",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "event",
    "name": "TokensHarvested",
    "inputs": [
      {
        "name": "caller",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      },
      {
        "name": "assets",
        "type": "uint256",
        "indexed": true,
        "internalType": "uint256"
      }
    ],
    "anonymous": false
  }
] as const;
