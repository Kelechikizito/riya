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

    uint256 public s_protocolFees; // a claim on the Ethereum reserve

    // s_yieldPerShare holds yield per unit of collateral,
    uint256 public s_yieldPerShare;
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
    function onDeposit(address user, uint256 assets) external nonReentrant onlyASC {}

    function onHarvest(uint256 gross) external nonReentrant onlyASC {}

    function borrow(uint256 amount) external nonReentrant {}

    function repay(uint256 amount) external nonReentrant {}

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
}
