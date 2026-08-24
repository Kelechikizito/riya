// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title IAaveV4Spoke
/// @notice The subset of Aave V4's `ISpoke` that the source-chain escrow actually uses.
/// @dev Aave V4 replaces V3's `Pool` with a `Spoke` that routes user actions to a
///      liquidity `Hub`, and addresses a market by a numeric `reserveId` rather than
///      by the underlying's address.
///
///      This is declared locally rather than imported from `lib/aave-v4` on purpose.
///      Aave V4 imports its own tree with root-absolute `src/...` paths; the compiler
///      can be told to resolve those with a context remapping, but `forge lint` cannot,
///      so importing their sources directly costs us the linter across the whole
///      project. Mirroring the handful of selectors we call keeps both working.
///
///      Kept in sync with aave/aave-v4 @ v0.5.11. If that pin moves, re-check
///      `lib/aave-v4/src/spoke/interfaces/ISpoke.sol` against this file — in
///      particular the field layout of `Reserve`, which is ABI-decoded here.
interface IAaveV4Spoke {
    /*//////////////////////////////////////////////////////////////
                                 TYPES
    //////////////////////////////////////////////////////////////*/

    /// @notice Reserve data as stored by the Spoke.
    /// @dev Mirrors `ISpoke.Reserve`. `hub` and `flags` are widened to plain value
    ///      types; ABI tuple encoding pads every field to a word, so decoding matches.
    struct Reserve {
        address underlying;
        address hub;
        uint16 assetId;
        uint8 decimals;
        uint24 collateralRisk;
        uint8 flags;
        uint32 dynamicConfigKey;
    }

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Supplies an amount of underlying asset of the specified reserve.
    /// @dev The Spoke pulls the underlying from the caller, so prior approval is required.
    /// @param reserveId The reserve identifier.
    /// @param amount The amount of asset to supply.
    /// @param onBehalfOf The owner of the position to add supply shares to.
    /// @return The amount of shares supplied, and the amount of assets supplied.
    function supply(uint256 reserveId, uint256 amount, address onBehalfOf) external returns (uint256, uint256);

    /// @notice Withdraws a specified amount of underlying asset from the given reserve.
    /// @dev An amount greater than the maximum withdrawable signals a full withdrawal.
    /// @dev The caller receives the underlying withdrawn.
    /// @param reserveId The reserve identifier.
    /// @param amount The amount of asset to withdraw.
    /// @param onBehalfOf The owner of the position to remove supply shares from.
    /// @return The amount of shares withdrawn, and the amount of assets withdrawn.
    function withdraw(uint256 reserveId, uint256 amount, address onBehalfOf) external returns (uint256, uint256);

    /// @notice Returns the reserve struct data in storage.
    /// @dev Reverts if the reserve is not listed.
    /// @param reserveId The reserve identifier.
    /// @return The reserve struct.
    function getReserve(uint256 reserveId) external view returns (Reserve memory);

    /// @notice Returns the underlying assets a user has supplied to a reserve.
    /// @dev This grows as interest accrues, which is what makes it the yield measure.
    /// @param reserveId The reserve identifier.
    /// @param user The position owner.
    /// @return The amount of underlying supplied.
    function getUserSuppliedAssets(uint256 reserveId, address user) external view returns (uint256);
}
