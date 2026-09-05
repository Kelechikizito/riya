// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
//At every row, every RiyaUSD in circulation is backed by one of two things:

// an outstanding loan, over-collateralised by USDC locked in the escrow at ≥2× (the LTV ladder tops out at 50%), or
// USDC that has already arrived in the escrow as harvested yield.
/**
 * @title
 * @author
 * @notice RiyaUSD is a credit instrument issued against escrowed collateral, fully reserved and not yet redeemable. Redemption is the first thing writability unlocks.
 * a dollar-denominated credit token in the README and the problem evaporates; call it a stablecoin and every question after that one is hostile.
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
    address public immutable I_LEDGER;

    // totalSupply(RiyaUSD)  =  Σ outstanding debt  +  Σ debt retired by proven yield

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
    constructor(address ledger) ERC20("Riya USD", "rUSD") {
        if (ledger == address(0)) revert RiyaUSD__ZeroAddress();
        I_LEDGER = ledger;
    }

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function mint(address to, uint256 amount) external onlyLedger {
        _mint(to, amount);
    }
    function burn(address from, uint256 amount) external onlyLedger {
        _burn(from, amount);
    }
    /*//////////////////////////////////////////////////////////////
                       PUBLIC VIEW/PURE FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function decimals() public pure override returns (uint8) {
        return 6;
    }

    // There is even a margin. The ledger takes a 15% fee, so only 85% of each gross harvest is distributed into s_yieldPerShare — while 100% of it landed in the escrow. Reserve outruns retired debt by the fee. // @question: I don't undertsnad this line
}
