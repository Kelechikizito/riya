// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IYieldAdapter} from "src/interfaces/IYieldAdapter.sol";
// import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title RiyaEscrow
 * @author Kelechi Kizito Ugwu
 * @notice
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

    /**
     * @dev The SafeERC20 library is used to safely handle ERC20 operations to prevent issues with non-standard ERC20 tokens, for example, USDT.
     * @notice This means for every IERC20 token, we can now call the safeTransfer, safeTransferFrom, and safeApprove functions provided by the SafeERC20 library.
     */
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    IERC20 public immutable I_ASSET;
    IYieldAdapter public immutable I_ADAPTER;
    uint256 public immutable I_MIN_DEPOSIT; // @question: what's the essence of this state variable

    /*///////////////////////////////////////////////////////////////////////
                                 EVENTS
    ////////////////////////////////////////////////////////////////////////*/

    /// @notice The event the readability worker proves to the ASC on Creditcoin.
    /// @dev The only event in the system that pairs a user with an amount, and the
    ///      figure carried here becomes their collateral on Creditcoin.
    event TokensDepositedConfirmedByEscrow(
        address indexed user,
        uint256 indexed assets
    );

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
        I_ASSET = IERC20(IYieldAdapter(aaveAdapterAddress).asset()); // @audit
        I_MIN_DEPOSIT = minDeposit;

        // INTERACTIONS
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
        /// @notice This step transfers the tokens from the user to this escrow address
        I_ASSET.safeTransferFrom(msg.sender, address(this), amount);

        /// @notice This step approves the adapter contract to pull tokens from this escrow contract.
        I_ASSET.forceApprove(address(I_ADAPTER), amount);

        /// @notice escrow → adapter → Aave. Your funds(tokens/assets) deposited on aaave
        uint256 assets = I_ADAPTER.deposit(amount);

        // EFFECTS

        emit TokensDepositedConfirmedByEscrow(msg.sender, assets); // @question: wh't the point of the event if the adapter will stilo emeit one?
    }
}
