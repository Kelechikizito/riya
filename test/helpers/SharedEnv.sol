// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title SharedEnv
 * @author Kelechi Kizito Ugwu
 * @notice The source-chain addresses every test writes into `RIYA_ESCROW_ADDRESS` and
 *         `AAVE_V4_ADAPTER_ADDRESS`.
 * @dev `vm.setEnv` writes the process environment, which is shared, while `forge test` runs
 *      test contracts in parallel. Two suites setting the same variable to different values
 *      race, and the one asserting on it fails intermittently with no other symptom.
 *
 *      Both variables are read by name from `HelperConfigDestination`, so the names cannot
 *      differ per suite. Every suite therefore writes the same values from here, and the race
 *      becomes harmless because either writer leaves the environment correct.
 *
 *      If you add a suite that sets either variable, use these constants.
 */
library SharedEnv {
    /// @dev `RiyaEscrow` on Ethereum, as far as any test is concerned.
    address internal constant ESCROW = 0x00000000000000000000000000000000000e5c20;

    /// @dev `AaveV4Adapter` on Ethereum.
    address internal constant ADAPTER = 0x0000000000000000000000000000000000ada97e;

    /// @dev Written to `PRIVATE_KEY` by every suite that runs a deploy script, for the same
    ///      reason the addresses are shared.
    uint256 internal constant DEPLOYER_KEY = 0xA11CE;
}
