// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title RiyaUSD
 * @author Kelechi Kizito Ugwu
 * @notice riya's borrowable dollar: a credit instrument issued against escrowed collateral,
 *         fully reserved and not yet redeemable. The only thing a user actually holds.
 * @dev Supply and debt do not track each other:
 *
 *          totalSupply = Σ outstanding debt + Σ debt retired by proven yield
 *
 *      Settlement from yield burns nothing, so a borrower's debt falls while the tokens
 *      they spent stay in circulation. Backing shifts from over-collateralised loans to
 *      USDC already sitting in the escrow, and outruns retired debt because the whole
 *      gross harvest lands there while only 85% is distributed.
 *
 *      Not redeemable in v1: paying a holder out in USDC needs the outbound leg. Call it
 *      a dollar-denominated credit token, not a stablecoin. There is no peg.
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
     * @dev No owner, no pause, no cap, no roles, so this is the entire trust configuration
     *      and it can never change. Circular with the ledger's own pin, so the deploy
     *      script predicts this address and asserts the prediction afterwards.
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
     * @dev No supply cap. The real cap is the LTV ladder in `LoanLedger`, and one here
     *      would be a second, weaker copy of it.
     */
    function mint(address to, uint256 amount) external onlyLedger {
        _mint(to, amount);
    }

    /**
     * @notice Destroys RiyaUSD as a borrower repays in cash.
     * @param from The holder whose tokens are destroyed.
     * @param amount The amount to destroy, in 6-decimal units.
     * @dev This function confiscates. Unlike `burnFrom` it spends no allowance, which
     *      removes an `approve` from the repayment flow and costs nothing, since a
     *      contract with unbounded mint authority is not constrained by lacking burn.
     *
     *      The security boundary is `LoanLedger.repay`, which must only ever burn from
     *      `msg.sender` against their own debt. There is nothing further to check here.
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
     * @dev Every other number in riya is in USDC's units. Left at OpenZeppelin's default
     *      of 18, `borrow(100e6)` would mint a hundred dollars that wallets render as
     *      0.0000000001 rUSD, with nothing reverting and nothing looking wrong on-chain.
     */
    function decimals() public pure override returns (uint8) {
        return 6;
    }
}
