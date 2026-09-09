// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IAaveV4Spoke} from "src/interfaces/IAaveV4Spoke.sol";

/**
 * @title MockAaveSpoke
 * @author Kelechi Kizito Ugwu
 * @notice A minimal Aave V4 Spoke for local tests and the Sepolia demo.
 * @dev Aave V4 is deployed on Ethereum Mainnet and nowhere else, so every rehearsal needs
 *      a stand-in. Implements only the four functions `AaveV4Adapter` calls.
 *
 *      Shares are 1:1 with assets, because the adapter only logs the share figure.
 *
 *      Yield does not accrue with time; it arrives via `accrueYield`, funded in real
 *      tokens. A realistic APY puts a $100 deposit years from the $10 harvest floor, and
 *      funding rather than minting keeps riya's rule intact: the money reaches the escrow
 *      before anything is proven.
 */
contract MockAaveSpoke is IAaveV4Spoke {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @dev `AaveV4Adapter`'s constructor relies on this to reject a wrong `reserveId`.
    error MockAaveSpoke__ReserveNotListed(uint256 reserveId);

    error MockAaveSpoke__ZeroAddress();
    error MockAaveSpoke__ZeroAmount();

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event ReserveListed(uint256 indexed reserveId, address indexed underlying);
    event Supplied(uint256 indexed reserveId, address indexed onBehalfOf, uint256 assets);
    event Withdrawn(uint256 indexed reserveId, address indexed onBehalfOf, uint256 assets);
    event YieldAccrued(uint256 indexed reserveId, address indexed onBehalfOf, uint256 assets);

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @dev Starts at 1, so an unset `reserveId` fails rather than resolving to a market.
    uint256 public s_nextReserveId = 1;

    mapping(uint256 reserveId => Reserve reserve) private s_reserves;
    mapping(uint256 reserveId => bool listed) private s_listed;
    mapping(uint256 reserveId => mapping(address user => uint256 assets)) private s_supplied;

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Lists a new reserve over `underlying` and returns its id.
     * @param underlying The reserve's asset. Read back by `AaveV4Adapter` at construction.
     * @return reserveId The new reserve's id, starting at 1.
     * @dev Only `underlying`, `hub` and `decimals` are populated. Nothing reads the rest.
     */
    function listReserve(address underlying) external returns (uint256 reserveId) {
        if (underlying == address(0)) revert MockAaveSpoke__ZeroAddress();

        reserveId = s_nextReserveId++;
        s_reserves[reserveId] = Reserve({
            underlying: underlying,
            hub: address(this),
            assetId: 0,
            decimals: 6,
            collateralRisk: 0,
            flags: 0,
            dynamicConfigKey: 0
        });
        s_listed[reserveId] = true;

        emit ReserveListed(reserveId, underlying);
    }

    /**
     * @notice Credits yield to a position, funded by the caller.
     * @param reserveId The reserve to credit.
     * @param onBehalfOf The position that earned it, which in riya is always the adapter.
     * @param amount The yield, in the underlying's units.
     * @dev Pulls real tokens so `harvest` can actually pay out; approve this contract first.
     *      This is the demo's clock: call it with at least `I_MIN_HARVEST` and the keeper's
     *      next cycle finds a harvestable position.
     */
    function accrueYield(uint256 reserveId, address onBehalfOf, uint256 amount) external {
        if (!s_listed[reserveId]) revert MockAaveSpoke__ReserveNotListed(reserveId);
        if (amount == 0) revert MockAaveSpoke__ZeroAmount();

        IERC20(s_reserves[reserveId].underlying).safeTransferFrom(msg.sender, address(this), amount);
        s_supplied[reserveId][onBehalfOf] += amount;

        emit YieldAccrued(reserveId, onBehalfOf, amount);
    }

    /**
     * @notice Shrinks a position below what was supplied, modelling a reserve deficit.
     * @param reserveId The reserve.
     * @param onBehalfOf The position to shrink.
     * @param amount How much to remove from the recorded balance.
     * @dev Aave can report less than principal when a reserve carries a deficit, and
     *      `AaveV4Adapter.yieldAccrued` clamps at zero rather than treating that as a
     *      negative harvest. Nothing else can produce that state, so tests need this.
     */
    function simulateDeficit(uint256 reserveId, address onBehalfOf, uint256 amount) external {
        if (!s_listed[reserveId]) revert MockAaveSpoke__ReserveNotListed(reserveId);

        uint256 balance = s_supplied[reserveId][onBehalfOf];
        s_supplied[reserveId][onBehalfOf] = amount > balance ? 0 : balance - amount;
    }

    /*//////////////////////////////////////////////////////////////
                            SPOKE INTERFACE
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IAaveV4Spoke
    /// @dev Pulls from `msg.sender`, so the adapter's `forceApprove` is load-bearing here
    ///      exactly as it is against the real Spoke.
    function supply(uint256 reserveId, uint256 amount, address onBehalfOf) external returns (uint256, uint256) {
        if (!s_listed[reserveId]) revert MockAaveSpoke__ReserveNotListed(reserveId);
        if (amount == 0) revert MockAaveSpoke__ZeroAmount();

        IERC20(s_reserves[reserveId].underlying).safeTransferFrom(msg.sender, address(this), amount);
        s_supplied[reserveId][onBehalfOf] += amount;

        emit Supplied(reserveId, onBehalfOf, amount);
        return (amount, amount);
    }

    /// @inheritdoc IAaveV4Spoke
    /// @dev Clamps to the balance rather than reverting, which is what makes
    ///      `type(uint256).max` a full exit. Reverting instead would hide a real bug.
    function withdraw(uint256 reserveId, uint256 amount, address onBehalfOf) external returns (uint256, uint256) {
        if (!s_listed[reserveId]) revert MockAaveSpoke__ReserveNotListed(reserveId);
        if (amount == 0) revert MockAaveSpoke__ZeroAmount();

        uint256 balance = s_supplied[reserveId][onBehalfOf];
        uint256 assets = amount > balance ? balance : amount;

        s_supplied[reserveId][onBehalfOf] = balance - assets;
        IERC20(s_reserves[reserveId].underlying).safeTransfer(msg.sender, assets);

        emit Withdrawn(reserveId, onBehalfOf, assets);
        return (assets, assets);
    }

    /// @inheritdoc IAaveV4Spoke
    function getReserve(uint256 reserveId) external view returns (Reserve memory) {
        if (!s_listed[reserveId]) revert MockAaveSpoke__ReserveNotListed(reserveId);
        return s_reserves[reserveId];
    }

    /// @inheritdoc IAaveV4Spoke
    function getUserSuppliedAssets(uint256 reserveId, address user) external view returns (uint256) {
        return s_supplied[reserveId][user];
    }
}
