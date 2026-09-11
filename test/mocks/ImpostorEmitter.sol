// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title ImpostorEmitter
 * @author Kelechi Kizito Ugwu
 * @notice A hostile contract that emits riya's events with numbers it made up.
 * @dev Event signatures are public. Anyone can deploy this, emit
 *      `TokensHarvested(address,uint256)` with a value of one billion dollars, and obtain a
 *      perfectly valid Attestcoin proof for it: the transaction really happened, it really
 *      succeeded, and the log really is in that block. Every cryptographic check passes.
 *
 *      `log.address_` is the one field that cannot be forged, and `RiyaASC._dispatch` pins it
 *      against `I_ADAPTER_CONTRACT` and `I_ESCROW_CONTRACT`. This contract exists to prove
 *      that pin is load-bearing rather than decorative, on a live chain rather than in a unit
 *      test. See `make attack`.
 *
 *      It also emits a decoy first. Reverting on an unrecognised emitter would turn the very
 *      guard above into a censorship vector: anyone could prefix a decoy to a genuine
 *      transaction and make the real event permanently unprovable. `RiyaASC` skips rather than
 *      reverts, and `attackDecoy` demonstrates why that matters.
 */
contract ImpostorEmitter {
    /// @dev Byte-for-byte the signatures `AaveV4Adapter` and `RiyaEscrow` emit.
    event TokensHarvested(address indexed caller, uint256 indexed assets);
    event TokensDepositedConfirmedByEscrow(address indexed user, uint256 indexed assets);

    /// @notice Claims a harvest that never happened. `RiyaASC` must reject it.
    function forgeHarvest(uint256 assets) external {
        emit TokensHarvested(msg.sender, assets);
    }

    /// @notice Claims collateral that was never escrowed. `RiyaASC` must reject it.
    function forgeDeposit(address user, uint256 assets) external {
        emit TokensDepositedConfirmedByEscrow(user, assets);
    }
}
