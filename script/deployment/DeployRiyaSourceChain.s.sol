// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {AaveV4Adapter} from "src/adapters/AaveV4Adapter.sol";
import {RiyaEscrow} from "src/source-chain/ethereum/RiyaEscrow.sol";
import {IAaveV4Spoke} from "src/interfaces/IAaveV4Spoke.sol";

/**
 * @title DeployRiyaSourceChain
 * @author Kelechi Kizito Ugwu
 * @notice Deploys riya's two Ethereum contracts — `AaveV4Adapter` and `RiyaEscrow`.
 * @dev The pair is circular at deploy time: the adapter's constructor needs the escrow's
 *      address, and the escrow's constructor calls back into the adapter for `asset()`.
 *      A CREATE address is `keccak(deployer, nonce)` and nothing else, so the escrow's
 *      address is computed before it exists and handed to the adapter. Both sides stay
 *      `immutable` — no setter, no owner, nothing to misconfigure after the fact.
 *
 *      This MUST be one script. Splitting it in two breaks the nonce prediction.
 */
contract DeployRiyaSourceChain is Script {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @dev The escrow did not land where it was predicted, so the adapter is pointed at
    ///      an address with no code on it. Reverting here voids the whole deployment.
    error DeployRiyaSourceChain__PredictionMissed(address predicted, address actual);

    /*//////////////////////////////////////////////////////////////
                              CONFIGURATION
    //////////////////////////////////////////////////////////////*/

    /// @dev TODO: real Sepolia Spoke. Move these to a HelperConfig once the chain is picked.
    address private constant SPOKE = address(0);

    /// @dev TODO: the reserve id of the USDC market on `SPOKE`.
    uint256 private constant RESERVE_ID = 0;

    /// @notice Smallest harvest worth paying Ethereum gas for. 10 USDC (6 decimals).
    /// @dev This is the keeper's schedule, not just a floor — it harvests when yield crosses it.
    uint256 private constant MIN_HARVEST = 10e6;

    /// @notice Smallest deposit worth a Creditcoin proof. 100 USDC (6 decimals).
    /// @dev Guards the worker's CTC balance, not the escrow. Every deposit costs a proof.
    uint256 private constant MIN_DEPOSIT = 100e6;

    /*//////////////////////////////////////////////////////////////
                                 SCRIPT
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deploys the adapter and the escrow, wired to each other.
     * @dev Read the nonce BEFORE broadcasting, and let nothing else send a transaction from
     *      this key until the run finishes — a shifted nonce points the adapter at nothing.
     *      Use a dedicated deploy key for exactly this reason.
     * @return adapter The strategy leg, supplying to Aave.
     * @return escrow The custody leg, and the only contract users touch.
     */
    function run() external returns (AaveV4Adapter adapter, RiyaEscrow escrow) {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        // The adapter takes this nonce; the escrow takes the one after it.
        uint256 nonce = vm.getNonce(deployer);
        address predictedEscrow = vm.computeCreateAddress(deployer, nonce + 1);

        vm.startBroadcast(deployerKey);

        // Trusts the prediction — `predictedEscrow` has no code yet.
        adapter = new AaveV4Adapter(predictedEscrow, IAaveV4Spoke(SPOKE), RESERVE_ID, MIN_HARVEST);

        // Calls `adapter.asset()`, so the adapter must already exist. It does.
        escrow = new RiyaEscrow(address(adapter), MIN_DEPOSIT);

        vm.stopBroadcast();

        // The prediction is load-bearing, so prove it rather than assume it.
        if (address(escrow) != predictedEscrow) {
            revert DeployRiyaSourceChain__PredictionMissed(predictedEscrow, address(escrow));
        }

        console2.log("deployer :", deployer);
        console2.log("adapter  :", address(adapter));
        console2.log("escrow   :", address(escrow));
    }
}
