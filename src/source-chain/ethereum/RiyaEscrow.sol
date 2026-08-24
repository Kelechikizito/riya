// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IYieldAdapter} from "src/interfaces/IYieldAdapter.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract RiyaEscrow is ReentrancyGuard {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error RiyaEscrow__ZeroAddress();
    error RiyaEscrow__ZeroAmount();

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
        I_MIN_DEPOSIT = minDeposit;

        // INTERACTIONS
    }

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
}
