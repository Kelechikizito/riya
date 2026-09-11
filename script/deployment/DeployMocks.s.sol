// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {console2} from "forge-std/console2.sol";

import {DeploymentRecord} from "script/DeploymentRecord.s.sol";
import {MockAaveSpoke} from "test/mocks/MockAaveSpoke.sol";
import {MockUSD} from "test/mocks/MockUSD.sol";

/**
 * @title DeployMocks
 * @author Kelechi Kizito Ugwu
 * @notice Deploys the Sepolia stand-ins for USDC and the Aave V4 Spoke.
 * @dev Aave V4 is live on Ethereum Mainnet and nowhere else, so the demo supplies its own
 *      reserve. Run this once, then `DeployRiyaSourceChain`, which reads these addresses
 *      through `HelperConfig.getSepoliaConfig`. The Makefile includes the recorded `.env`,
 *      so there is nothing to paste between the two.
 *
 *      Imported from `test/` on purpose. These are demo scaffolding, not part of riya, and
 *      keeping them out of `src/` keeps the production tree honest about what it contains.
 */
contract DeployMocks is DeploymentRecord {
    function run() external returns (MockUSD usd, MockAaveSpoke spoke, uint256 reserveId) {
        // Signed by `--account`, so there is no key in the environment to leak.
        vm.startBroadcast();

        usd = new MockUSD();
        spoke = new MockAaveSpoke();
        reserveId = spoke.listReserve(address(usd));

        vm.stopBroadcast();

        _record("MOCK_USD", address(usd));
        _record("MOCK_SPOKE", address(spoke));
        _record("MOCK_RESERVE_ID", reserveId);
        _save("mocks");

        console2.log("MOCK_USD        =", address(usd));
        console2.log("MOCK_SPOKE      =", address(spoke));
        console2.log("MOCK_RESERVE_ID =", reserveId);
    }
}
