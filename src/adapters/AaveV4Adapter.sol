// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IAaveV4Spoke} from "src/interfaces/IAaveV4Spoke.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IYieldAdapter} from "src/interfaces/IYieldAdapter.sol";

/**
 * @title AaveV4Adapter
 * @author Kelechi Kizito Ugwu
 * @notice Parks the escrow's deposits in a single Aave V4 reserve and harvests the yield
 *         back out to the escrow.
 * @dev Aave V4 replaces the V3 `Pool` with a `Spoke` that routes to a liquidity `Hub`, and
 *      addresses a reserve by numeric id rather than by the underlying's address. The id is
 *      fixed at construction and the underlying is read back from the Spoke.
 *
 *      Holds no idle balance: everything received is supplied in the same call, everything
 *      withdrawn leaves in the same call. That is what lets `harvest` satisfy riya's rule
 *      that the yield reaches the escrow before anything is proven on Creditcoin.
 *
 *      Whatever Aave reports above `s_principal` is yield, and `harvest` skims exactly that.
 */
contract AaveV4Adapter is IYieldAdapter, ReentrancyGuard {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error AaveV4Adapter__NotEscrow();
    error AaveV4Adapter__ZeroAmount();
    error AaveV4Adapter__ZeroAddress();
    error AaveV4Adapter__HarvestBelowMinimum(uint256 available, uint256 minimum);

    /*//////////////////////////////////////////////////////////////
                            TYPE DECLARATIONS
    //////////////////////////////////////////////////////////////*/
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice The source-chain escrow. The only address allowed to move principal.
    address public immutable I_ESCROW;

    /// @notice The Aave V4 Spoke this adapter supplies to.
    IAaveV4Spoke public immutable I_SPOKE;

    /// @notice The reserve within `I_SPOKE` that this adapter uses.
    uint256 public immutable I_RESERVE_ID;

    /// @notice The underlying asset of `I_RESERVE_ID`, read from the Spoke at construction.
    IERC20 public immutable I_ASSET;

    /// @notice Smallest harvest worth paying Ethereum gas for, in `I_ASSET` units.
    /// @dev Batches dust into occasional meaningful harvests. Mainnet gas is the real
    ///      constraint and batching is the only lever, so this is sized per deployment.
    uint256 public immutable I_MIN_HARVEST;

    /// @notice Assets supplied on the escrow's behalf that are principal, not yield.
    /// @dev Everything Aave holds for this adapter above this figure is harvestable.
    uint256 public s_principal;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when the escrow's assets are supplied to Aave.
    event TokensDepositedConfirmedByAdapter(uint256 indexed assets, uint256 indexed shares);

    /// @notice Emitted when principal is pulled back out of Aave for the escrow.
    event TokensWithdrawn(address indexed to, uint256 indexed assets, uint256 indexed shares);

    /// @notice Emitted once harvested yield has landed in the escrow.
    /// @dev The source-chain event the worker proves. Emitted after the transfer, so its
    ///      presence in a successful transaction means the money moved.
    event TokensHarvested(address indexed caller, uint256 indexed assets);

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyEscrow() {
        if (msg.sender != I_ESCROW) revert AaveV4Adapter__NotEscrow();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address escrow, IAaveV4Spoke spoke, uint256 reserveId, uint256 minHarvest) {
        if (escrow == address(0) || address(spoke) == address(0)) revert AaveV4Adapter__ZeroAddress();

        I_ESCROW = escrow;
        I_SPOKE = IAaveV4Spoke(spoke);
        I_RESERVE_ID = reserveId;
        I_MIN_HARVEST = minHarvest;

        // Reverts if the reserve is not listed, so a bad id cannot be deployed.
        I_ASSET = IERC20(spoke.getReserve(reserveId).underlying);
    }

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Pulls `amount` of the underlying from the escrow and supplies it to Aave.
     * @dev The escrow must have approved this adapter for `amount` first.
     * @param amount The amount of underlying TOKEN to supply.
     * @return assets The amount Aave recorded as supplied.
     */
    function deposit(uint256 amount) external nonReentrant onlyEscrow returns (uint256 assets) {
        return assets = _deposit(amount);
    }

    /**
     * @notice Withdraws principal from Aave and sends it to `to`.
     * @param amount The amount of underlying to withdraw.
     * @param to The recipient.
     * @return assets The amount actually withdrawn.
     * @dev Aave treats an amount above the maximum withdrawable as a full exit, so
     *      `type(uint256).max` closes the whole position, yield included.
     */
    function withdraw(uint256 amount, address to) external nonReentrant onlyEscrow returns (uint256 assets) {
        return assets = _withdraw(amount, to);
    }

    /**
     * @notice Moves everything Aave holds above principal into the escrow.
     * @return assets The amount of yield delivered to the escrow.
     * @dev Permissionless: anyone may pay the gas to retire someone else's debt, and the
     *      yield can only ever go to the escrow. The keeper calls this on a schedule; the
     *      `I_MIN_HARVEST` floor is what stops it burning gas on dust.
     */
    function harvest() external nonReentrant returns (uint256 assets) {
        return assets = _harvest();
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _deposit(uint256 amount) internal returns (uint256 assets) {
        // CHECKS
        if (amount == 0) revert AaveV4Adapter__ZeroAmount();

        // EFFECTS
        I_ASSET.safeTransferFrom(I_ESCROW, address(this), amount);
        I_ASSET.forceApprove(address(I_SPOKE), amount);

        // INTERACTIONS
        // `assets` is what Aave confirmed, which can differ from `amount`. Principal
        // tracks the confirmed figure, because that is what `yieldAccrued` measures against.
        uint256 shares;
        (shares, assets) = I_SPOKE.supply(I_RESERVE_ID, amount, address(this));
        s_principal += assets;

        emit TokensDepositedConfirmedByAdapter(assets, shares);
    }

    function _withdraw(uint256 amount, address to) internal returns (uint256 assets) {
        // CHECKS
        if (amount == 0) revert AaveV4Adapter__ZeroAmount();
        if (to == address(0)) revert AaveV4Adapter__ZeroAddress();

        // EFFECTS
        uint256 shares;
        (shares, assets) = I_SPOKE.withdraw(I_RESERVE_ID, amount, address(this));

        // A full exit takes the yield with it; principal must not underflow.
        uint256 principal = s_principal;
        s_principal = assets < principal ? principal - assets : 0;

        // INTERACTIONS

        I_ASSET.safeTransfer(to, assets);

        emit TokensWithdrawn(to, assets, shares);
    }

    function _harvest() internal returns (uint256 assets) {
        // CHECKS
        uint256 availableYield = yieldAccrued();
        if (availableYield < I_MIN_HARVEST) revert AaveV4Adapter__HarvestBelowMinimum(availableYield, I_MIN_HARVEST);

        // INTERACTIONS
        // Withdraws the yield only, leaving principal earning.
        (, assets) = I_SPOKE.withdraw(I_RESERVE_ID, availableYield, address(this));
        I_ASSET.safeTransfer(I_ESCROW, assets);

        // After the transfer, so the event means the money moved.
        emit TokensHarvested(msg.sender, assets);
    }

    /*//////////////////////////////////////////////////////////////
                         PUBLIC VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice The underlying asset of `I_RESERVE_ID`. Lets the escrow derive its own
    ///         asset instead of being handed a second copy that could disagree.
    function asset() external view returns (address) {
        return address(I_ASSET);
    }

    /// @notice The adapter's supplied balance in the reserve, principal plus yield.
    function totalAssets() public view returns (uint256) {
        return I_SPOKE.getUserSuppliedAssets(I_RESERVE_ID, address(this));
    }

    /**
     * @notice Yield earned but not yet harvested.
     * @dev Clamped at zero, because a reserve carrying a deficit can report less than
     *      principal and that is not a negative harvest.
     */
    function yieldAccrued() public view returns (uint256) {
        uint256 total = totalAssets();
        uint256 principal = s_principal;
        return total > principal ? total - principal : 0;
    }
}
