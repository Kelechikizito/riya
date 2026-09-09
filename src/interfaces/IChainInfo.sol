// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title IChainInfo
 * @author Kelechi Kizito Ugwu
 * @notice The Chain Info Precompile at `0x0FD3`, which answers what Creditcoin knows about
 *         the chains it can read.
 * @dev Only `get_supported_chains` is declared; the worker reaches the rest of the
 *      precompile through the SDK. Signature and field order match `chain_info.json` in
 *      the Gluwa USC SDK, and the snake_case name is the precompile's own. Renaming it
 *      breaks the selector.
 */
interface IChainInfo {
    /// @param chainKey Creditcoin's identifier for the source chain. Registry-local, so
    ///        the same chain has different keys on Creditcoin Testnet and Mainnet.
    /// @param chainId The source chain's real EVM chain id. The value that does not move.
    /// @param chainName Human-readable label, returned as raw bytes.
    /// @param chainEncoding Transaction encoding version used when decoding proofs.
    struct ChainInfo {
        uint64 chainKey;
        uint64 chainId;
        bytes chainName;
        uint8 chainEncoding;
    }

    /// @notice Every source chain this Creditcoin network can currently read.
    function get_supported_chains() external view returns (ChainInfo[] memory chains);
}
