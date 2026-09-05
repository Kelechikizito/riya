// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title RiyaUSD
 * @author Kelechi Kizito Ugwu
 * @notice riya's borrowable dollar: a credit instrument issued against escrowed
 *         collateral, fully reserved and not yet redeemable. It is the only thing a
 *         user actually holds — collateral and debt are numbers in `LoanLedger`, while
 *         this is an ordinary ERC-20 that any Creditcoin wallet or contract can accept.
 * @dev Supply and debt deliberately do not track each other:
 *
 *          totalSupply = Σ outstanding debt + Σ debt retired by proven yield
 *
 *      Borrowing mints and manual repayment burns, but settlement from proven yield
 *      burns nothing — the borrower's `s_debt` falls while the tokens they already
 *      spent stay in circulation. Every token is still backed by one of two things:
 *      an outstanding loan over-collateralised at >=2x (the LTV ladder tops out at
 *      50%), or USDC that has already arrived in the escrow as harvested yield. As
 *      debt is retired, backing shifts from the first to the second.
 *
 *      Reserve actually outruns retired debt, because 100% of each gross harvest lands
 *      in the escrow while the ledger's 15% fee means only 85% is distributed into
 *      `s_yieldPerShare`. The difference is margin.
 *
 *      **Not redeemable in v1.** Paying a holder out in USDC on Ethereum needs the
 *      outbound leg, and writability is unavailable. The backing is real and locked,
 *      but it is a claim nobody can exercise yet. Redemption is the first thing
 *      writability unlocks. Describe this as a dollar-denominated credit token rather
 *      than a stablecoin: there is no peg and no arbitrage path to close one.
 *
 *      This contract is the second of two locks in series:
 *
 *          proof -> RiyaASC --(only the ASC)--> LoanLedger --(only the ledger)--> mint
 *
 *      What it guarantees is narrow: RiyaUSD cannot come into existence except through
 *      a borrow that passed the LTV check. Whether that check is correct is entirely
 *      `LoanLedger`'s problem.
 */
contract RiyaUSD is ERC20 {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error RiyaUSD__NotLedger();
    error RiyaUSD__ZeroAddress();

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice The only address allowed to mint or burn. Fixed at construction.
    address public immutable I_LEDGER;

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/
    modifier onlyLedger() {
        if (msg.sender != I_LEDGER) revert RiyaUSD__NotLedger();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @param ledger The `LoanLedger` that will hold mint and burn authority.
     * @dev There is no owner, no pause, no cap and no grantable role, so this argument
     *      is the contract's entire trust configuration and it can never be changed.
     *      `LoanLedger` needs this token's address and this token needs the ledger's,
     *      so deployment predicts the ledger's address with `vm.computeCreateAddress`
     *      and asserts the prediction afterwards. A shifted nonce does not fail loudly;
     *      it deploys a token that rejects every mint the real ledger ever attempts.
     */
    constructor(address ledger) ERC20("Riya USD", "rUSD") {
        if (ledger == address(0)) revert RiyaUSD__ZeroAddress();
        I_LEDGER = ledger;
    }

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Issues new RiyaUSD against a loan the ledger has already approved.
     * @param to The borrower.
     * @param amount The amount to issue, in 6-decimal units.
     * @dev No supply cap on purpose. The real cap is the LTV ladder in `LoanLedger`,
     *      and a cap here would be a second, weaker copy of a rule that already exists.
     */
    function mint(address to, uint256 amount) external onlyLedger {
        _mint(to, amount);
    }

    /**
     * @notice Destroys RiyaUSD as a borrower repays in cash.
     * @param from The holder whose tokens are destroyed.
     * @param amount The amount to destroy, in 6-decimal units.
     * @dev **This function confiscates.** Unlike `ERC20Burnable.burnFrom` it spends no
     *      allowance, so the ledger can burn anyone's balance without their approval.
     *      That is deliberate — a contract with unbounded mint authority is not
     *      meaningfully constrained by lacking burn authority, and it removes an
     *      `approve` transaction from the repayment flow.
     *
     *      **The security boundary is `LoanLedger.repay`, not this function.** Safety
     *      rests entirely on that function only ever burning from `msg.sender` against
     *      their own debt. If you are auditing who can destroy whose tokens, read
     *      `LoanLedger.repay`; there is nothing further to check here.
     *
     *      Burning more than the holder's balance reverts with OpenZeppelin's
     *      `ERC20InsufficientBalance` rather than clamping.
     */
    function burn(address from, uint256 amount) external onlyLedger {
        _burn(from, amount);
    }

    /*//////////////////////////////////////////////////////////////
                       PUBLIC VIEW/PURE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice The token uses 6 decimals, matching USDC.
     * @return The number of decimals, always 6.
     * @dev Overriding OpenZeppelin's default of 18 is the highest-value line in this
     *      file. Every other number in riya is in USDC's units: `MIN_DEPOSIT` is
     *      `100e6`, the escrow forwards raw USDC amounts, `TokensHarvested` carries raw
     *      USDC amounts, and `LoanLedger` stores collateral and debt in the same units.
     *      Left at 18, `borrow(100e6)` would mint a hundred dollars that every wallet
     *      renders as 0.0000000001 rUSD. Nothing reverts and nothing looks wrong
     *      on-chain, which is what makes it dangerous.
     *
     *      One unit of account through the whole system, and it is USDC's.
     */
    function decimals() public pure override returns (uint8) {
        return 6;
    }
}
