// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockUSD
 * @author Kelechi Kizito Ugwu
 * @notice A 6-decimal stand-in for USDC, for local tests and the Sepolia demo.
 * @dev `mint` is unguarded, which is the point of a faucet token and the reason this lives
 *      under `test/`: nothing in the production tree may import it.
 */
contract MockUSD is ERC20 {
    constructor() ERC20("Mock USD", "mUSD") {}

    /// @notice Mints to any address. Anyone may call this.
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    /// @notice Six decimals. Changing this means changing `MIN_DEPOSIT`, `MIN_HARVEST`
    ///         and `RiyaUSD.decimals` alongside it.
    function decimals() public pure override returns (uint8) {
        return 6;
    }
}
