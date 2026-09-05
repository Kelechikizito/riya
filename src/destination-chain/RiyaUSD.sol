// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

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
}
