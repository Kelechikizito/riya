// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IAaveV4Spoke} from "../interfaces/IAaveV4Spoke.sol";

/**
 * @title AaveV4Adapter
 * @author Kelechi Kizito Ugwu
 * @notice Parks the source-chain vault's deposits in a single Aave V4 reserve and harvests the yield they earn back out to the vault.
 * @dev Lives on Ethereum (Sepolia for the demo). Aave V4 replaces the V3 `Pool` with a `Spoke` that routes to a liquidity `Hub`; a reserve is addressed by a numeric `reserveId` rather than by the underlying's address, so the id is fixed at construction and the underlying is read back from the Spoke.
 This contract deliberately holds no idle balance. Every asset it receives is supplied immediately, and every asset it withdraws leaves in the same call. That is what lets `harvest` satisfy the protocol's "real money has to arrive" rule: the yield is moved to the vault before anything is proven on Creditcoin, so the proof and the value travel together.
 */
contract AaveV4Adapter {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error AaveV4Adapter__NotVault();
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

    /// @notice The source-chain vault. The only address allowed to move principal.
    address public immutable i_vault;

    /// @notice The Aave V4 Spoke this adapter supplies to.
    IAaveV4Spoke public immutable i_spoke;

    /// @notice The reserve within `i_spoke` that this adapter uses.
    uint256 public immutable i_reserveId;

    /// @notice The underlying asset of `i_reserveId`, read from the Spoke at construction.
    IERC20 public immutable i_asset;

    /// @notice Smallest harvest worth paying Ethereum gas for, in `i_asset` units.
    /// @dev Batches dust into occasional meaningful harvests. Mainnet gas is the real
    ///      constraint here and the only lever is harvesting less often in bigger
    ///      batches, so this is sized per deployment rather than hardcoded.
    uint256 public immutable i_minHarvest;

    /// @notice Assets supplied on the vault's behalf that are principal, not yield.
    /// @dev Everything Aave holds for this adapter above this figure is harvestable.
    uint256 public s_principal;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when the vault's assets are supplied to Aave.
    event Deposited(uint256 assets, uint256 shares);

    /// @notice Emitted when principal is pulled back out of Aave for the vault.
    event Withdrawn(address indexed to, uint256 assets, uint256 shares);

    /// @notice Emitted once harvested yield has actually landed in the vault.
    /// @dev This is the source-chain event the watcher bot proves to the ASC. It is
    ///      emitted after the transfer, so its presence in a successful transaction
    ///      means the money moved.
    event Harvested(address indexed caller, uint256 assets);

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyVault() {
        _onlyVault();
        _;
    }

    function _onlyVault() internal view {
        if (msg.sender != i_vault) revert AaveV4Adapter__NotVault();
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address vault, IAaveV4Spoke spoke, uint256 reserveId, uint256 minHarvest) {
        if (vault == address(0) || address(spoke) == address(0)) revert AaveV4Adapter__ZeroAddress();

        i_vault = vault;
        i_spoke = spoke;
        i_reserveId = reserveId;
        i_minHarvest = minHarvest;

        // Reverts if the reserve is not listed, so a bad id cannot be deployed.
        i_asset = IERC20(spoke.getReserve(reserveId).underlying);
    }

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Pulls `amount` of the underlying from the vault and supplies it to Aave.
    /// @dev The vault must have approved this adapter for `amount` first.
    /// @param amount The amount of underlying to supply.
    /// @return assets The amount Aave recorded as supplied.
    function deposit(uint256 amount) external onlyVault returns (uint256 assets) {
        if (amount == 0) revert AaveV4Adapter__ZeroAmount();

        i_asset.safeTransferFrom(i_vault, address(this), amount);
        i_asset.forceApprove(address(i_spoke), amount);

        uint256 shares;
        (shares, assets) = i_spoke.supply(i_reserveId, amount, address(this));
        s_principal += assets;

        emit Deposited(assets, shares);
    }

    /// @notice Withdraws principal from Aave and sends it to `to`.
    /// @dev Aave treats an amount above the maximum withdrawable as a full withdrawal,
    ///      so passing `type(uint256).max` exits the whole position, yield included.
    /// @param amount The amount of underlying to withdraw.
    /// @param to The recipient of the withdrawn assets.
    /// @return assets The amount actually withdrawn.
    function withdraw(uint256 amount, address to) external onlyVault returns (uint256 assets) {
        if (amount == 0) revert AaveV4Adapter__ZeroAmount();
        if (to == address(0)) revert AaveV4Adapter__ZeroAddress();

        uint256 shares;
        (shares, assets) = i_spoke.withdraw(i_reserveId, amount, address(this));

        // A full exit takes the yield with it; principal must not underflow.
        uint256 principal = s_principal;
        s_principal = assets < principal ? principal - assets : 0;

        i_asset.safeTransfer(to, assets);

        emit Withdrawn(to, assets, shares);
    }

    /// @notice Moves everything Aave holds above principal into the vault.
    /// @dev Permissionless — anyone may pay the gas to retire someone else's debt, and
    ///      the yield can only ever go to the vault. The `i_minHarvest` floor stops the
    ///      position being churned for dust.
    /// @return assets The amount of yield delivered to the vault.
    function harvest() external returns (uint256 assets) {
        uint256 available = yieldAccrued();
        if (available < i_minHarvest) revert AaveV4Adapter__HarvestBelowMinimum(available, i_minHarvest);

        (, assets) = i_spoke.withdraw(i_reserveId, available, address(this));
        i_asset.safeTransfer(i_vault, assets);

        emit Harvested(msg.sender, assets);
    }

    /*//////////////////////////////////////////////////////////////
                         PUBLIC VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice The adapter's current supplied balance in the reserve, principal plus yield.
    function totalAssets() public view returns (uint256) {
        return i_spoke.getUserSuppliedAssets(i_reserveId, address(this));
    }

    /// @notice Yield earned but not yet harvested.
    /// @dev Clamped at zero: a reserve carrying a deficit can in principle report less
    ///      than principal, and that is not a negative harvest.
    function yieldAccrued() public view returns (uint256) {
        uint256 total = totalAssets();
        uint256 principal = s_principal;
        return total > principal ? total - principal : 0;
    }
}
