// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {console2} from "forge-std/console2.sol";

import {DeploymentRecord} from "script/DeploymentRecord.s.sol";

import {LoanLedger} from "src/destination-chain/LoanLedger.sol";
import {RiyaASC} from "src/destination-chain/RiyaASC.sol";
import {RiyaUSD} from "src/destination-chain/RiyaUSD.sol";
import {IChainInfo} from "src/interfaces/IChainInfo.sol";
import {HelperConfigDestination} from "script/HelperConfigDestination.s.sol";

/**
 * @title DeployRiyaDestinationChain
 * @author Kelechi Kizito Ugwu
 * @notice Deploys riya's three Creditcoin contracts: `RiyaUSD`, `RiyaASC` and `LoanLedger`.
 * @dev The three are circular, so the ledger's address is computed before it exists, the
 *      same way `DeployRiyaSourceChain` handles the escrow/adapter pair. Every pin is
 *      `immutable`, so a wrong address is permanent.
 *
 *      This MUST be one script. Splitting it breaks the nonce prediction.
 *
 *      Run `DeployRiyaSourceChain` first: `RIYA_ESCROW_ADDRESS` and
 *      `AAVE_V4_ADAPTER_ADDRESS` are its output.
 */
contract DeployRiyaDestinationChain is DeploymentRecord {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @dev The token and the ASC are now pinned to an address with no code on it.
    error DeployRiyaDestinationChain__PredictionMissed(address predicted, address actual);

    /// @dev Almost always a testnet key used against Mainnet, or the reverse.
    error DeployRiyaDestinationChain__UnknownChainKey(uint64 chainKey);

    /// @dev The key resolves, but to the wrong chain. Deploys cleanly, then reads the
    ///      wrong chain forever.
    error DeployRiyaDestinationChain__ChainKeyMismatch(uint64 chainKey, uint64 expected, uint64 actual);

    /*//////////////////////////////////////////////////////////////
                          CONSTANTS & STATE
    //////////////////////////////////////////////////////////////*/

    /// @dev The Chain Info Precompile. Same address on every Creditcoin network.
    IChainInfo private constant CHAIN_INFO = IChainInfo(0x0000000000000000000000000000000000000fD3);

    /*//////////////////////////////////////////////////////////////
                                 SCRIPT
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deploys the token, the ASC and the ledger, wired to each other.
     * @dev Read the nonce BEFORE broadcasting, and let nothing else send from this key
     *      until the run finishes. Use a dedicated deploy key.
     * @return riyaUSD The borrowable dollar.
     * @return asc The proof gate.
     * @return ledger The position, the credit score and the borrow limit.
     * @return helperConfig The per-chain parameters used, so tests can reuse them.
     */
    function run()
        external
        returns (RiyaUSD riyaUSD, RiyaASC asc, LoanLedger ledger, HelperConfigDestination helperConfig)
    {
        helperConfig = new HelperConfigDestination();
        (uint64 chainKey, uint64 sourceChainId, address escrow, address adapter) = helperConfig.activeNetworkConfig();

        // Before spending gas, not after. The key is immutable once the ASC is deployed.
        _assertChainKey(chainKey, sourceChainId);

        address deployer = _broadcaster();

        // The token takes this nonce, the ASC the one after, the ledger the one after that.
        // Count deployments between the prediction and the ledger, not contracts in the system.
        uint256 nonce = vm.getNonce(deployer);
        address predictedLedger = vm.computeCreateAddress(deployer, nonce + 2);

        vm.startBroadcast();

        // Both trust the prediction; `predictedLedger` has no code yet.
        riyaUSD = new RiyaUSD(predictedLedger);
        asc = new RiyaASC(chainKey, escrow, adapter, predictedLedger);

        // Real addresses on both arguments; nothing predicted.
        ledger = new LoanLedger(address(asc), riyaUSD);

        vm.stopBroadcast();

        _assertPrediction(predictedLedger, address(ledger));

        _record("RIYA_USD_ADDRESS", address(riyaUSD));
        _record("RIYA_ASC_ADDRESS", address(asc));
        _record("LOAN_LEDGER_ADDRESS", address(ledger));
        _record("CHAIN_KEY", uint256(chainKey));
        _save("destination");

        console2.log("deployer  :", deployer);
        console2.log("riyaUSD   :", address(riyaUSD));
        console2.log("asc       :", address(asc));
        console2.log("ledger    :", address(ledger));
        console2.log("chainKey  :", chainKey);
        console2.log("escrow    :", escrow);
        console2.log("adapter   :", adapter);
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @dev A shifted nonce does not fail loudly. It deploys a token and an ASC pinned to an
    ///      address with no code, both of which look healthy until the first real proof.
    function _assertPrediction(address predicted, address actual) internal pure {
        if (actual != predicted) revert DeployRiyaDestinationChain__PredictionMissed(predicted, actual);
    }

    /**
     * @notice Proves the chain key resolves to the source chain the escrow actually lives on.
     * @dev `RiyaASC` rejects a zero key but cannot tell 1 from 3, and the value is
     *      immutable. The registry is per-network, so the only reliable check is to ask
     *      this network what the key means and compare against a chain id, which never moves.
     * @param chainKey The key about to be handed to `RiyaASC`.
     * @param expected The EVM chain id it must resolve to.
     */
    function _assertChainKey(uint64 chainKey, uint64 expected) internal view {
        IChainInfo.ChainInfo[] memory chains = CHAIN_INFO.get_supported_chains();

        for (uint256 i = 0; i < chains.length; i++) {
            if (chains[i].chainKey != chainKey) continue;

            if (chains[i].chainId != expected) {
                revert DeployRiyaDestinationChain__ChainKeyMismatch(chainKey, expected, chains[i].chainId);
            }
            return;
        }

        revert DeployRiyaDestinationChain__UnknownChainKey(chainKey);
    }
}
