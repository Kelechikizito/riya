// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title ILoanLedger
 * @author Kelechi Kizito Ugwu
 * @notice The half of `LoanLedger` that only `RiyaASC` may call — the two mirror
 *         updates driven by proven source-chain events.
 * @dev Deliberately excludes `borrow` and `repay`. Those are the direct user path and
 *      authenticate on `msg.sender`; these two authenticate on the ASC. Keeping the two
 *      surfaces apart at the interface level is what stops one modifier serving both.
 */
interface ILoanLedger {
    /// @notice Credits a proven `RiyaEscrow` deposit as collateral.
    /// @param user The depositor's Ethereum address, reused verbatim on Creditcoin.
    /// @param assets The amount escrowed, in the source asset's own decimals.
    function onDeposit(address user, uint256 assets) external;

    /// @notice Distributes a proven `AaveV4Adapter` harvest across every open position.
    /// @param gross The yield that arrived in the escrow, before the protocol fee.
    function onHarvest(uint256 gross) external;
}
