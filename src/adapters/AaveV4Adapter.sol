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
 * @notice Parks the source-chain escrow's deposits in a single Aave V4 reserve and harvests the yield they earn back out to the escrow.
 * @dev Lives on Ethereum (Sepolia for the demo). Aave V4 replaces the V3 `Pool` with a `Spoke` that routes to a liquidity `Hub`; a reserve is addressed by a numeric `reserveId` rather than by the underlying's address, so the id is fixed at construction and the underlying is read back from the Spoke.
 *  This contract deliberately holds no idle balance. Every asset it receives is supplied immediately, and every asset it withdraws leaves in the same call. That is what lets `harvest` satisfy the protocol's "real money has to arrive" rule: the yield is moved to the escrow before anything is proven on Creditcoin, so the proof and the value travel together.
 * This adapter takes the escrow's money and parks it in Aave V4 to earn interest. Over time, the amount Aave reports it's holding grows past what was originally deposited (s_principal) — that growth is yield. harvest() is the function that skims off just that yield and sends it back to the escrow, leaving the original principal still earning interest in Aave.
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
    ///      constraint here and the only lever is harvesting less often in bigger
    ///      batches, so this is sized per deployment rather than hardcoded.
    uint256 public immutable I_MIN_HARVEST;

    /// @notice Assets supplied on the escrow's behalf that are principal, not yield.
    /// @dev Everything Aave holds for this adapter above this figure is harvestable.
    uint256 public s_principal;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when the escrow's assets are supplied to Aave.
    event TokensDeposited(uint256 indexed assets, uint256 indexed shares);

    /// @notice Emitted when principal is pulled back out of Aave for the escrow.
    event TokensWithdrawn(address indexed to, uint256 indexed assets, uint256 indexed shares);

    /// @notice Emitted once harvested yield has actually landed in the escrow.
    /// @dev This is the source-chain event the watcher bot proves to the ASC. It is
    ///      emitted after the transfer, so its presence in a successful transaction
    ///      means the money moved.
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
     *  @dev Aave treats an amount above the maximum withdrawable as a full withdrawal, so passing `type(uint256).max` exits the whole position, yield included.
     * @param amount The amount of underlying to withdraw.
     * @param to The recipient of the TokensWithdrawn assets.
     * @return assets The amount actually TokensWithdrawn.
     */
    function withdraw(uint256 amount, address to) external nonReentrant onlyEscrow returns (uint256 assets) {
        return assets = _withdraw(amount, to);
    }

    /**
     * @notice Moves everything Aave holds above principal into the escrow.
     * @dev Permissionless — anyone may pay the gas to retire someone else's debt, and the yield can only ever go to the escrow. The `I_MIN_HARVEST` floor stops the
     * @return assets The amount of yield delivered to the escrow.
     */
    function harvest() external nonReentrant returns (uint256 assets) {
        return assets = _harvest();
    }
    // @question: who calls the harvest function to trigger the event, i would assume the readabiluty worker, righttt? Thta means we have to write code so the readability worker checks the event at how many intervals, who pays for the gas? The job of the readability worker in CTC is to pick up events, c'est fini.
    // @question: how does this adapter contract track for multiple users? // @answer: Notice the contract never holds an idle balance — every token it receives goes straight into Aave in the same transaction. That's mentioned explicitly in the contract's top comment as a deliberate design choice.

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
        uint256 shares;
        (shares, assets) = I_SPOKE.supply(I_RESERVE_ID, amount, address(this));
        s_principal += assets;
        // @question: why did we define shares and not assets?

        emit TokensDeposited(assets, shares);
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
        // 1. Check how much yield exists.
        uint256 availableYield = yieldAccrued();
        // 2. Enforce a minimum.
        if (availableYield < I_MIN_HARVEST) revert AaveV4Adapter__HarvestBelowMinimum(availableYield, I_MIN_HARVEST);

        // EFFECTS
        // INTERACTIONS
        // 3. Withdraw just the yield from Aave.
        (, assets) = I_SPOKE.withdraw(I_RESERVE_ID, availableYield, address(this));
        // 4. Send it to the escrow.
        I_ASSET.safeTransfer(I_ESCROW, assets);

        emit TokensHarvested(msg.sender, assets);
    }

    /*//////////////////////////////////////////////////////////////
                         PUBLIC VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice The adapter's current supplied balance in the reserve, principal plus yield.
     * @return The total supplied assets for this contract
     */
    function totalAssets() public view returns (uint256) {
        return I_SPOKE.getUserSuppliedAssets(I_RESERVE_ID, address(this));
    }

    /**
     * @notice Yield earned but not yet harvested.
     * @dev Clamped at zero: a reserve carrying a deficit can in        principle report less than principal, and that is not a negative harvest.
     */
    function yieldAccrued() public view returns (uint256) {
        uint256 total = totalAssets();
        uint256 principal = s_principal;
        return total > principal ? total - principal : 0;
    }
}
