// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import {
//     SafeERC20
// } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {RiyaUSD} from "src/destination-chain/RiyaUSD.sol";
import {RiyaASC} from "src/destination-chain/RiyaASC.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IRiyaASC} from "src/interfaces/IRiyaASC.sol";

contract LoanLedger is ReentrancyGuard {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error LoanLedger__NotASCContract();
    error LoanLedger__ZeroAddress();
    error LoanLedger__ExceedsLimit();
    error LoanLedger__NoCollateral();

    /*//////////////////////////////////////////////////////////////
                           TYPE DECLARATIONS
    //////////////////////////////////////////////////////////////*/
    // using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    IRiyaASC public immutable I_RIYA_ASC;
    RiyaUSD public immutable I_RIYA_USD;

    uint256 private constant PRECISION = 1e18;
    uint256 private constant GRADUATION_TARGET_BPS = 2_000; // 20% of collateral
    uint256 private constant FEE_BPS = 1_500; // 15%
    uint256 private constant BPS_DENOMINATOR = 10_000;

    // Collateral is 1:1 with the dollars escrowed.
    mapping(address user => uint256 collateralAmount) public s_collateral;
    uint256 public s_totalCollateral;

    mapping(address user => uint256 debtAmount) public s_debt;
    mapping(address user => uint256 repaidByYieldAmount) public s_repaidByYield; // the score's basis
    mapping(address user => uint256 creditAmount) public s_credit; // yield with no debt to retire

    /// @dev s_protocolFees is a number. It is a claim on USDC in the Ethereum escrow, and it becomes spendable only with writability.
    uint256 public s_protocolFees; // a claim on the Ethereum reserve

    /// @dev s_yieldPerShare holds yield per unit of collateral, s_yieldPerShare is the running total of yield distributed per unit of collateral, ever.
    uint256 public s_yieldPerShare;
    /// @dev s_marker[user] is that number's value at the user's last settlement. The gap between them, times their collateral, is what they are owed.
    mapping(address user => uint256 yieldPerShareMarker) public s_marker;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event DebtRetired(address indexed user, uint256 applied, uint256 surplus);
    event Borrowed(address indexed user, uint256 amount);
    event Repaid(address indexed user, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/
    // In a contract inheriting ERC2771Context, a bare msg.sender looks like a bug, and "use _msgSender() for consistency"
    modifier onlyASC() {
        if (msg.sender != address(I_RIYA_ASC)) revert LoanLedger__NotASCContract();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor(address ascContract, RiyaUSD riyaUSD) {
        if (ascContract == address(0)) revert LoanLedger__ZeroAddress();
        if (address(riyaUSD) == address(0)) revert LoanLedger__ZeroAddress();

        I_RIYA_ASC = IRiyaASC(ascContract);
        I_RIYA_USD = riyaUSD;
    }

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function onDeposit(address user, uint256 assets) external nonReentrant onlyASC {
        _settle(user);
        s_collateral[user] += assets;
        s_totalCollateral += assets;
    }

    function onHarvest(uint256 gross) external nonReentrant onlyASC {
        if (s_totalCollateral == 0) revert LoanLedger__NoCollateral();

        uint256 fee = (gross * FEE_BPS) / BPS_DENOMINATOR;
        s_protocolFees += fee;
        s_yieldPerShare += ((gross - fee) * PRECISION) / s_totalCollateral;
    }

    function borrow(uint256 amount) external nonReentrant {
        // @question: why is the _msgSender here?
        // @question isn't there supposed to be a check to see that i have deposited othe partcular amount on the source chain?
        address user = msg.sender;
        _settle(user);

        uint256 limit = (s_collateral[user] * maxLtvBps(user)) / BPS_DENOMINATOR;
        if (s_debt[user] + amount > limit) revert LoanLedger__ExceedsLimit();

        s_debt[user] += amount;
        I_RIYA_USD.mint(user, amount);

        emit Borrowed(user, amount);
    }

    function repay(uint256 amount) external nonReentrant {
        address user = msg.sender;
        _settle(user);

        uint256 debt = s_debt[user];
        uint256 paid = amount < debt ? amount : debt;

        I_RIYA_USD.burn(user, paid);
        s_debt[user] = debt - paid;

        // Deliberately does NOT touch s_repaidByYield.
        // Otherwise borrow-$100 / repay-$100 twice buys the top tier for free.
        emit Repaid(user, paid);
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function _settle(address user) internal {
        uint256 collateral = s_collateral[user];
        uint256 acc = s_yieldPerShare;

        if (collateral != 0) {
            uint256 pending = (collateral * (acc - s_marker[user])) / PRECISION;
            if (pending != 0) {
                uint256 debt = s_debt[user];
                uint256 applied = pending < debt ? pending : debt;

                s_debt[user] = debt - applied;
                s_repaidByYield[user] += applied; // score counts proven dollars only
                s_credit[user] += pending - applied; // surplus when debt is already clear

                emit DebtRetired(user, applied, pending - applied);
            }
        }

        s_marker[user] = acc;
    }

    /*//////////////////////////////////////////////////////////////
                      EXTERNAL VIEW/PURE FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function selfRepayRateBps(address user, uint256 yieldRateBps) external view returns (uint256 bps) {
        uint256 debt = s_debt[user];
        if (debt == 0) return 0;
        return (s_collateral[user] * yieldRateBps) / debt;
    }

    function score(address user) public view returns (uint256) {
        uint256 target = (s_collateral[user] * GRADUATION_TARGET_BPS) / BPS_DENOMINATOR;
        if (target == 0) return 0;

        uint256 s = (s_repaidByYield[user] * 100) / target;
        return s > 100 ? 100 : s;
    }

    function maxLtvBps(address user) public view returns (uint256) {
        uint256 s = score(user);
        if (s < 20) return 1_000;
        if (s < 40) return 2_000;
        if (s < 60) return 3_000;
        if (s < 85) return 4_000;
        return 5_000;
    }
}
