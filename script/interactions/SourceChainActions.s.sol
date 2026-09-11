// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {AaveV4Adapter} from "src/adapters/AaveV4Adapter.sol";
import {RiyaEscrow} from "src/source-chain/ethereum/RiyaEscrow.sol";
import {MockAaveSpoke} from "test/mocks/MockAaveSpoke.sol";
import {MockUSD} from "test/mocks/MockUSD.sol";

/**
 * @title SourceChainActions
 * @author Kelechi Kizito Ugwu
 * @notice The three transactions the demo runs on Ethereum, one script each.
 * @dev Every one of these emits a source-chain event the readability worker then proves on
 *      Creditcoin. Run them in order and watch the worker's log: deposit, accrue, harvest.
 *
 *      Addresses come from `.env`, which is where `DeployMocks` and `DeployRiyaSourceChain`
 *      print them.
 */
abstract contract SourceChainScript is Script {
    /// @dev Signed by `--account`; `--sender` is what arrives here.
    address internal deployer;

    /// @dev See `DeploymentRecord._broadcaster`. Tests override this, because
    ///      `vm.startBroadcast()` sends from forge's default sender rather than the caller.
    function _broadcaster() internal view virtual returns (address) {
        return msg.sender;
    }

    MockUSD internal usd;
    MockAaveSpoke internal spoke;
    RiyaEscrow internal escrow;
    AaveV4Adapter internal adapter;
    uint256 internal reserveId;

    /// @dev Virtual so tests can inject addresses directly. `vm.setEnv` writes the process
    ///      environment, which test contracts share and forge runs in parallel, so reading
    ///      these from the environment inside a test races with every other suite.
    function _load() internal virtual {
        deployer = _broadcaster();

        usd = MockUSD(vm.envAddress("MOCK_USD"));
        spoke = MockAaveSpoke(vm.envAddress("MOCK_SPOKE"));
        reserveId = vm.envUint("MOCK_RESERVE_ID");
        escrow = RiyaEscrow(vm.envAddress("RIYA_ESCROW_ADDRESS"));
        adapter = AaveV4Adapter(vm.envAddress("AAVE_V4_ADAPTER_ADDRESS"));
    }

    /// @dev The amount to act on, in USDC's 6 decimals. Overridden in tests for the same
    ///      reason `_load` is.
    function _amount(uint256 fallbackAmount) internal view virtual returns (uint256) {
        return vm.envOr("AMOUNT", fallbackAmount);
    }
}

/**
 * @notice Mints demo dollars and deposits them into `RiyaEscrow`.
 * @dev Emits `TokensDepositedConfirmedByEscrow`, which becomes the caller's collateral on
 *      Creditcoin once proven. The deposit must clear `I_MIN_DEPOSIT`, which is $100.
 *
 *      `AMOUNT` is in USDC's 6 decimals, so 1000000000 is one thousand dollars.
 */
contract Deposit is SourceChainScript {
    function run() external {
        _load();

        uint256 amount = _amount(1_000e6);

        vm.startBroadcast();

        usd.mint(deployer, amount);
        IERC20(address(usd)).approve(address(escrow), amount);
        escrow.deposit(amount);

        vm.stopBroadcast();

        console2.log("depositor :", deployer);
        console2.log("amount    :", amount);
        console2.log("principal :", adapter.s_principal());
    }
}

/**
 * @notice Credits yield to the adapter's position, funded by the caller.
 * @dev **This is the demo's clock.** Yield does not accrue with time on a mock reserve, and
 *      a realistic APY would put a $1,000 deposit years from the $10 harvest floor. Call this
 *      with at least `I_MIN_HARVEST` and the position becomes harvestable immediately.
 *
 *      Funded in real tokens rather than minted into the accounting, so the Spoke stays
 *      solvent and `harvest` can actually pay out.
 */
contract AccrueYield is SourceChainScript {
    function run() external {
        _load();

        uint256 amount = _amount(100e6);

        vm.startBroadcast();

        usd.mint(deployer, amount);
        IERC20(address(usd)).approve(address(spoke), amount);
        spoke.accrueYield(reserveId, address(adapter), amount);

        vm.stopBroadcast();

        console2.log("accrued   :", amount);
        console2.log("harvestable:", adapter.yieldAccrued());
    }
}

/**
 * @notice Moves accrued yield out of the reserve and into the escrow.
 * @dev Emits `TokensHarvested`, the event that retires every borrower's debt once proven.
 *      Permissionless, so any funded key can run it. The keeper does this on a schedule; this
 *      script is for driving it by hand during a demo.
 */
contract Harvest is SourceChainScript {
    function run() external {
        _load();

        uint256 available = adapter.yieldAccrued();
        console2.log("available :", available);
        console2.log("floor     :", adapter.I_MIN_HARVEST());

        vm.startBroadcast();
        uint256 harvested = adapter.harvest();
        vm.stopBroadcast();

        console2.log("harvested :", harvested);
        console2.log("in escrow :", IERC20(address(usd)).balanceOf(address(escrow)));
    }
}

/// @notice Prints the source-chain position without sending a transaction.
contract SourceStatus is SourceChainScript {
    function run() external {
        _load();

        console2.log("asset        :", adapter.asset());
        console2.log("principal    :", adapter.s_principal());
        console2.log("totalAssets  :", adapter.totalAssets());
        console2.log("yieldAccrued :", adapter.yieldAccrued());
        console2.log("minHarvest   :", adapter.I_MIN_HARVEST());
        console2.log("minDeposit   :", escrow.I_MIN_DEPOSIT());
        console2.log("escrowBalance:", IERC20(address(usd)).balanceOf(address(escrow)));
    }
}
