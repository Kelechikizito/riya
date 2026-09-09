// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IChainInfo} from "src/interfaces/IChainInfo.sol";

/**
 * @title MockChainInfo
 * @author Kelechi Kizito Ugwu
 * @notice Stands in for the Chain Info Precompile at `0x0FD3` in tests.
 * @dev `DeployRiyaDestinationChain` asks this what a chain key means before spending gas, so
 *      a local run of that script needs something at the address. The registry is settable so
 *      tests can produce all three answers: the right chain, the wrong chain, and no entry.
 */
contract MockChainInfo {
    IChainInfo.ChainInfo[] private s_chains;

    function addChain(uint64 chainKey, uint64 chainId) external {
        s_chains.push(
            IChainInfo.ChainInfo({chainKey: chainKey, chainId: chainId, chainName: bytes("mock"), chainEncoding: 1})
        );
    }

    function clear() external {
        delete s_chains;
    }

    function get_supported_chains() external view returns (IChainInfo.ChainInfo[] memory) {
        return s_chains;
    }
}
