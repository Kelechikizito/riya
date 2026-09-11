// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {LoanLedger} from "src/destination-chain/LoanLedger.sol";
import {RiyaASC} from "src/destination-chain/RiyaASC.sol";
import {RiyaUSD} from "src/destination-chain/RiyaUSD.sol";

/**
 * @title DestinationChainActions
 * @author Kelechi Kizito Ugwu
 * @notice The transactions a user sends on Creditcoin, one script each.
 * @dev Nothing here proves anything. Collateral arrives only through `RiyaASC`, driven by the
 *      readability worker, so these scripts fail until a deposit proof has landed. That is
 *      the point: `borrow` reverts with `LoanLedger__ExceedsLimit` when no proof exists.
 */
abstract contract DestinationChainScript is Script {
    /// @dev Signed by `--account`; `--sender` is what arrives here.
    address internal user;

    /// @dev See `DeploymentRecord._broadcaster`. Tests override this, because
    ///      `vm.startBroadcast()` sends from forge's default sender rather than the caller.
    function _broadcaster() internal view virtual returns (address) {
        return msg.sender;
    }

    LoanLedger internal ledger;
    RiyaUSD internal riyaUSD;
    RiyaASC internal asc;

    /// @dev Virtual so tests can inject addresses directly, rather than through the shared
    ///      process environment that every parallel test suite writes to.
    function _load() internal virtual {
        user = _broadcaster();

        ledger = LoanLedger(vm.envAddress("LOAN_LEDGER_ADDRESS"));
        riyaUSD = RiyaUSD(vm.envAddress("RIYA_USD_ADDRESS"));
        asc = RiyaASC(vm.envAddress("RIYA_ASC_ADDRESS"));
    }

    /// @dev The amount to act on, in USDC's 6 decimals.
    function _amount(uint256 fallbackAmount) internal view virtual returns (uint256) {
        return vm.envOr("AMOUNT", fallbackAmount);
    }

    /// @dev Whose position to read. Only `Position` uses it.
    function _target() internal view virtual returns (address) {
        return vm.envOr("USER", user);
    }
}

/**
 * @notice Draws RiyaUSD against proven collateral.
 * @dev Bounded by the LTV ladder, which starts at 10% and only rises as proven yield retires
 *      debt. `AMOUNT` is in 6 decimals.
 */
contract Borrow is DestinationChainScript {
    function run() external {
        _load();

        uint256 amount = _amount(100e6);
        uint256 limit = (ledger.s_collateral(user) * ledger.maxLtvBps(user)) / 10_000;

        console2.log("collateral:", ledger.s_collateral(user));
        console2.log("limit     :", limit);
        console2.log("borrowing :", amount);

        vm.startBroadcast();
        ledger.borrow(amount);
        vm.stopBroadcast();

        console2.log("debt      :", ledger.s_debt(user));
        console2.log("rUSD      :", riyaUSD.balanceOf(user));
    }
}

/**
 * @notice Repays debt in cash, burning the caller's own RiyaUSD.
 * @dev Clamped to outstanding debt, so passing more than you owe clears the position rather
 *      than reverting. Deliberately does not move the credit score.
 */
contract Repay is DestinationChainScript {
    function run() external {
        _load();

        uint256 amount = _amount(10e6);

        console2.log("debt before:", ledger.s_debt(user));

        vm.startBroadcast();
        ledger.repay(amount);
        vm.stopBroadcast();

        console2.log("debt after :", ledger.s_debt(user));
        console2.log("rUSD       :", riyaUSD.balanceOf(user));
    }
}

/**
 * @notice Settles a position without moving it, applying any yield already proven.
 * @dev Settlement is lazy: proven yield sits in `pendingYield` until the position is touched.
 *      A one-unit repayment is the cheapest way for a user to force it, and it is what the
 *      dashboard's refresh button would call.
 */
contract Settle is DestinationChainScript {
    function run() external {
        _load();

        console2.log("pending before:", ledger.pendingYield(user));

        vm.startBroadcast();
        ledger.repay(1);
        vm.stopBroadcast();

        console2.log("pending after :", ledger.pendingYield(user));
        console2.log("retired total :", ledger.s_repaidByYield(user));
    }
}

/// @notice Prints a full position without sending a transaction.
contract Position is DestinationChainScript {
    function run() external {
        _load();

        address target = _target();

        console2.log("user          :", target);
        console2.log("collateral    :", ledger.s_collateral(target));
        console2.log("debt          :", ledger.s_debt(target));
        console2.log("pendingYield  :", ledger.pendingYield(target));
        console2.log("repaidByYield :", ledger.s_repaidByYield(target));
        console2.log("credit        :", ledger.s_credit(target));
        console2.log("score         :", ledger.score(target));
        console2.log("maxLtvBps     :", ledger.maxLtvBps(target));
        console2.log("rUSD balance  :", riyaUSD.balanceOf(target));
        console2.log("--- protocol ---");
        console2.log("totalCollateral:", ledger.s_totalCollateral());
        console2.log("yieldPerShare  :", ledger.s_yieldPerShare());
        console2.log("protocolFees   :", ledger.s_protocolFees());
        console2.log("rUSD supply    :", riyaUSD.totalSupply());
        console2.log("ASC chainKey   :", asc.I_CHAIN_KEY());
    }
}
