// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {DeploymentRecord} from "script/DeploymentRecord.s.sol";
import {ImpostorEmitter} from "test/mocks/ImpostorEmitter.sol";

/**
 * @title AttackDemo
 * @author Kelechi Kizito Ugwu
 * @notice The Ethereum half of riya's adversarial demo.
 * @dev Deploys a hostile contract and has it emit riya's own events with invented numbers.
 *      Everything here succeeds: the transaction is real, it does not revert, and the log is
 *      genuinely in the block, so Attestcoin will prove it without complaint.
 *
 *      Rejecting it is `RiyaASC`'s job, and `offchain/src/attack.ts` is what carries the proof
 *      across to make it prove that on chain rather than in a test.
 */
contract DeployImpostor is DeploymentRecord {
    function run() external returns (ImpostorEmitter impostor) {
        vm.startBroadcast();
        impostor = new ImpostorEmitter();
        vm.stopBroadcast();

        _record("IMPOSTOR_ADDRESS", address(impostor));
        _save("impostor");

        console2.log("IMPOSTOR_ADDRESS =", address(impostor));
    }
}

/// @notice Emits a forged `TokensHarvested`. Prints the transaction hash to prove.
contract ForgeHarvest is Script {
    function run() external {
        ImpostorEmitter impostor = ImpostorEmitter(vm.envAddress("IMPOSTOR_ADDRESS"));
        uint256 assets = vm.envOr("AMOUNT", uint256(1_000_000e6));

        vm.startBroadcast();
        impostor.forgeHarvest(assets);
        vm.stopBroadcast();

        console2.log("forged a harvest of :", assets);
        console2.log("emitted by          :", address(impostor));
        console2.log("the real adapter is :", vm.envAddress("AAVE_V4_ADAPTER_ADDRESS"));
        console2.log("");
        console2.log("Take the tx hash from the broadcast log above and run:");
        console2.log("  make prove-attack TX=0x...");
    }
}

/// @notice Emits a forged `TokensDepositedConfirmedByEscrow`: collateral from nothing.
contract ForgeDeposit is Script {
    function run() external {
        ImpostorEmitter impostor = ImpostorEmitter(vm.envAddress("IMPOSTOR_ADDRESS"));
        uint256 assets = vm.envOr("AMOUNT", uint256(1_000_000e6));
        address user = vm.envOr("USER", msg.sender);

        vm.startBroadcast();
        impostor.forgeDeposit(user, assets);
        vm.stopBroadcast();

        console2.log("forged collateral of:", assets);
        console2.log("credited to         :", user);
        console2.log("emitted by          :", address(impostor));
        console2.log("the real escrow is  :", vm.envAddress("RIYA_ESCROW_ADDRESS"));
    }
}
