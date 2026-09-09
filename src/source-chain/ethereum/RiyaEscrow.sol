// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IYieldAdapter} from "src/interfaces/IYieldAdapter.sol";

/**
 * @title RiyaEscrow
 * @author Kelechi Kizito Ugwu
 * @notice Custody for riya's source-chain deposits. Takes the user's asset, forwards it to
 *         the adapter, and emits the event the readability worker proves on Creditcoin.
 * @dev Holds no balance between calls. Every deposit is forwarded in the same transaction,
 *      so the escrow's own balance is only ever harvested yield awaiting its proof.
 */
contract RiyaEscrow {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error RiyaEscrow__ZeroAddress();
    error RiyaEscrow__ZeroAmount();
    error RiyaEscrow__BelowMinDeposit(uint256 provided, uint256 minimum);

    /*//////////////////////////////////////////////////////////////
                            TYPE DECLARATIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev Non-standard ERC-20s such as USDT do not return a bool, so every transfer here
    ///      goes through SafeERC20.
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    /// @notice The deposit asset, read from the adapter so there is no second copy to
    ///         disagree with.
    IERC20 public immutable I_ASSET;

    IYieldAdapter public immutable I_ADAPTER;

    /// @notice Smallest deposit worth a Creditcoin proof. Guards the worker's CTC, since
    ///         every deposit costs the same to prove whatever its size.
    uint256 public immutable I_MIN_DEPOSIT;

    /*///////////////////////////////////////////////////////////////////////
                                 EVENTS
    ////////////////////////////////////////////////////////////////////////*/

    /// @notice The event the readability worker proves to the ASC on Creditcoin.
    /// @dev The only event pairing a user with an amount. This figure becomes their
    ///      collateral on Creditcoin.
    event TokensDepositedConfirmedByEscrow(address indexed user, uint256 indexed assets);

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor(address aaveAdapterAddress, uint256 minDeposit) {
        // CHECKS
        if (aaveAdapterAddress == address(0)) {
            revert RiyaEscrow__ZeroAddress();
        }
        if (minDeposit == 0) {
            revert RiyaEscrow__ZeroAmount();
        }

        // EFFECTS
        I_ADAPTER = IYieldAdapter(aaveAdapterAddress);
        I_ASSET = IERC20(IYieldAdapter(aaveAdapterAddress).asset());
        I_MIN_DEPOSIT = minDeposit;
    }

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function deposit(uint256 amount) external {
        _deposit(amount);
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function _deposit(uint256 amount) internal {
        // CHECKS
        if (amount == 0) {
            revert RiyaEscrow__ZeroAmount();
        }
        if (amount < I_MIN_DEPOSIT) {
            revert RiyaEscrow__BelowMinDeposit(amount, I_MIN_DEPOSIT);
        }

        // INTERACTIONS
        I_ASSET.safeTransferFrom(msg.sender, address(this), amount);
        I_ASSET.forceApprove(address(I_ADAPTER), amount);

        // escrow -> adapter -> Aave, all in this transaction.
        uint256 assets = I_ADAPTER.deposit(amount);

        // Emits `assets` as Aave confirmed it, not `amount` as requested.
        emit TokensDepositedConfirmedByEscrow(msg.sender, assets);
    }
}
