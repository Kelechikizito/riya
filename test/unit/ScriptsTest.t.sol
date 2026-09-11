// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";

import {AaveV4Adapter} from "src/adapters/AaveV4Adapter.sol";
import {LoanLedger} from "src/destination-chain/LoanLedger.sol";
import {RiyaASC} from "src/destination-chain/RiyaASC.sol";
import {RiyaUSD} from "src/destination-chain/RiyaUSD.sol";
import {RiyaEscrow} from "src/source-chain/ethereum/RiyaEscrow.sol";
import {IAaveV4Spoke} from "src/interfaces/IAaveV4Spoke.sol";
import {DeploymentRecord} from "script/DeploymentRecord.s.sol";
import {DeployMocks} from "script/deployment/DeployMocks.s.sol";
import {AccrueYield, Deposit, Harvest, SourceStatus} from "script/interactions/SourceChainActions.s.sol";
import {Borrow, Position, Repay, Settle} from "script/interactions/DestinationChainActions.s.sol";
import {MockAaveSpoke} from "test/mocks/MockAaveSpoke.sol";
import {MockNativeQueryVerifier} from "test/mocks/MockNativeQueryVerifier.sol";
import {MockUSD} from "test/mocks/MockUSD.sol";
import {SharedEnv} from "test/helpers/SharedEnv.sol";

/*//////////////////////////////////////////////////////////////
                              HARNESSES
//////////////////////////////////////////////////////////////*/

// Every harness does two things: it pins `_broadcaster` to forge's `DEFAULT_SENDER`, which is
// who `vm.startBroadcast()` actually sends from inside a test, and it injects addresses
// instead of reading `vm.envAddress`. The second matters as much as the first: `vm.setEnv`
// writes the shared process environment and forge runs test contracts in parallel, so a suite
// that configured these through the environment would race with every other one.

contract DepositHarness is Deposit {
    address immutable H_USD;
    address immutable H_SPOKE;
    address immutable H_ESCROW;
    address immutable H_ADAPTER;
    uint256 immutable H_RESERVE;
    uint256 immutable H_AMOUNT;

    constructor(address usd_, address spoke_, address escrow_, address adapter_, uint256 reserve_, uint256 amount_) {
        H_USD = usd_;
        H_SPOKE = spoke_;
        H_ESCROW = escrow_;
        H_ADAPTER = adapter_;
        H_RESERVE = reserve_;
        H_AMOUNT = amount_;
    }

    function _broadcaster() internal pure override returns (address) {
        return DEFAULT_SENDER;
    }

    function _amount(uint256) internal view override returns (uint256) {
        return H_AMOUNT;
    }

    function _load() internal override {
        deployer = _broadcaster();
        usd = MockUSD(H_USD);
        spoke = MockAaveSpoke(H_SPOKE);
        reserveId = H_RESERVE;
        escrow = RiyaEscrow(H_ESCROW);
        adapter = AaveV4Adapter(H_ADAPTER);
    }
}

contract AccrueHarness is AccrueYield {
    address immutable H_USD;
    address immutable H_SPOKE;
    address immutable H_ESCROW;
    address immutable H_ADAPTER;
    uint256 immutable H_RESERVE;
    uint256 immutable H_AMOUNT;

    constructor(address usd_, address spoke_, address escrow_, address adapter_, uint256 reserve_, uint256 amount_) {
        H_USD = usd_;
        H_SPOKE = spoke_;
        H_ESCROW = escrow_;
        H_ADAPTER = adapter_;
        H_RESERVE = reserve_;
        H_AMOUNT = amount_;
    }

    function _broadcaster() internal pure override returns (address) {
        return DEFAULT_SENDER;
    }

    function _amount(uint256) internal view override returns (uint256) {
        return H_AMOUNT;
    }

    function _load() internal override {
        deployer = _broadcaster();
        usd = MockUSD(H_USD);
        spoke = MockAaveSpoke(H_SPOKE);
        reserveId = H_RESERVE;
        escrow = RiyaEscrow(H_ESCROW);
        adapter = AaveV4Adapter(H_ADAPTER);
    }
}

contract HarvestHarness is Harvest {
    address immutable H_USD;
    address immutable H_SPOKE;
    address immutable H_ESCROW;
    address immutable H_ADAPTER;
    uint256 immutable H_RESERVE;

    constructor(address usd_, address spoke_, address escrow_, address adapter_, uint256 reserve_) {
        H_USD = usd_;
        H_SPOKE = spoke_;
        H_ESCROW = escrow_;
        H_ADAPTER = adapter_;
        H_RESERVE = reserve_;
    }

    function _broadcaster() internal pure override returns (address) {
        return DEFAULT_SENDER;
    }

    function _load() internal override {
        deployer = _broadcaster();
        usd = MockUSD(H_USD);
        spoke = MockAaveSpoke(H_SPOKE);
        reserveId = H_RESERVE;
        escrow = RiyaEscrow(H_ESCROW);
        adapter = AaveV4Adapter(H_ADAPTER);
    }
}

contract StatusHarness is SourceStatus {
    address immutable H_USD;
    address immutable H_SPOKE;
    address immutable H_ESCROW;
    address immutable H_ADAPTER;
    uint256 immutable H_RESERVE;

    constructor(address usd_, address spoke_, address escrow_, address adapter_, uint256 reserve_) {
        H_USD = usd_;
        H_SPOKE = spoke_;
        H_ESCROW = escrow_;
        H_ADAPTER = adapter_;
        H_RESERVE = reserve_;
    }

    function _load() internal override {
        deployer = DEFAULT_SENDER;
        usd = MockUSD(H_USD);
        spoke = MockAaveSpoke(H_SPOKE);
        reserveId = H_RESERVE;
        escrow = RiyaEscrow(H_ESCROW);
        adapter = AaveV4Adapter(H_ADAPTER);
    }
}

contract BorrowHarness is Borrow {
    address immutable H_LEDGER;
    address immutable H_USD;
    address immutable H_ASC;
    uint256 immutable H_AMOUNT;

    constructor(address ledger_, address usd_, address asc_, uint256 amount_) {
        H_LEDGER = ledger_;
        H_USD = usd_;
        H_ASC = asc_;
        H_AMOUNT = amount_;
    }

    function _broadcaster() internal pure override returns (address) {
        return DEFAULT_SENDER;
    }

    function _amount(uint256) internal view override returns (uint256) {
        return H_AMOUNT;
    }

    function _load() internal override {
        user = _broadcaster();
        ledger = LoanLedger(H_LEDGER);
        riyaUSD = RiyaUSD(H_USD);
        asc = RiyaASC(H_ASC);
    }
}

contract RepayHarness is Repay {
    address immutable H_LEDGER;
    address immutable H_USD;
    address immutable H_ASC;
    uint256 immutable H_AMOUNT;

    constructor(address ledger_, address usd_, address asc_, uint256 amount_) {
        H_LEDGER = ledger_;
        H_USD = usd_;
        H_ASC = asc_;
        H_AMOUNT = amount_;
    }

    function _broadcaster() internal pure override returns (address) {
        return DEFAULT_SENDER;
    }

    function _amount(uint256) internal view override returns (uint256) {
        return H_AMOUNT;
    }

    function _load() internal override {
        user = _broadcaster();
        ledger = LoanLedger(H_LEDGER);
        riyaUSD = RiyaUSD(H_USD);
        asc = RiyaASC(H_ASC);
    }
}

contract SettleHarness is Settle {
    address immutable H_LEDGER;
    address immutable H_USD;
    address immutable H_ASC;

    constructor(address ledger_, address usd_, address asc_) {
        H_LEDGER = ledger_;
        H_USD = usd_;
        H_ASC = asc_;
    }

    function _broadcaster() internal pure override returns (address) {
        return DEFAULT_SENDER;
    }

    function _load() internal override {
        user = _broadcaster();
        ledger = LoanLedger(H_LEDGER);
        riyaUSD = RiyaUSD(H_USD);
        asc = RiyaASC(H_ASC);
    }
}

contract PositionHarness is Position {
    address immutable H_LEDGER;
    address immutable H_USD;
    address immutable H_ASC;
    address immutable H_TARGET;

    constructor(address ledger_, address usd_, address asc_, address target_) {
        H_LEDGER = ledger_;
        H_USD = usd_;
        H_ASC = asc_;
        H_TARGET = target_;
    }

    function _target() internal view override returns (address) {
        return H_TARGET;
    }

    function _load() internal override {
        user = DEFAULT_SENDER;
        ledger = LoanLedger(H_LEDGER);
        riyaUSD = RiyaUSD(H_USD);
        asc = RiyaASC(H_ASC);
    }
}

/*//////////////////////////////////////////////////////////////
                     THE PRODUCTION DEFAULTS
//////////////////////////////////////////////////////////////*/

// The harnesses above replace `_load`, `_amount` and `_target` so tests need no environment.
// These two expose the real implementations instead, so the code that actually runs under
// `forge script` is covered too. They only read and cast addresses, never call them, so no
// contract has to exist at any of them.
//
// The values come from `SharedEnv` for the usual reason: `vm.setEnv` writes the shared
// process environment, forge runs test contracts in parallel, and identical values make the
// race harmless.

contract SourceEnvHarness is SourceStatus {
    function loadFromEnv() external returns (address, uint256, address) {
        _load();
        return (address(usd), reserveId, address(escrow));
    }

    function amount(uint256 fallbackAmount) external view returns (uint256) {
        return _amount(fallbackAmount);
    }

    function broadcaster() external view returns (address) {
        return _broadcaster();
    }
}

contract DestinationEnvHarness is Position {
    function loadFromEnv() external returns (address, address, address) {
        _load();
        return (address(ledger), address(riyaUSD), address(asc));
    }

    function amount(uint256 fallbackAmount) external view returns (uint256) {
        return _amount(fallbackAmount);
    }

    function target() external view returns (address) {
        return _target();
    }

    function broadcaster() external view returns (address) {
        return _broadcaster();
    }
}

/// @dev `_save` refuses to run outside a real broadcast, so the write itself is reached
///      through `_write`, pointed at a directory the test owns.
contract RecordHarness is DeploymentRecord {
    function _recordDir() internal pure override returns (string memory) {
        return "deployments-test";
    }

    function put(string memory key, address value) external {
        _record(key, value);
    }

    function putUint(string memory key, uint256 value) external {
        _record(key, value);
    }

    function write(string memory label) external {
        _write(label);
    }

    /// @dev Proves the guard: under `forge test` this must write nothing at all.
    function save(string memory label) external {
        _save(label);
    }
}

/// @dev Reads the production defaults without writing anything.
contract RecordDirHarness is DeploymentRecord {
    function dir() external view returns (string memory) {
        return _recordDir();
    }

    function broadcaster() external view returns (address) {
        return _broadcaster();
    }
}

/// @dev Pretends to be a broadcast, so `_save`'s write path runs. Writes to the test's own
///      directory, never to `deployments/`.
contract RecordingHarness is DeploymentRecord {
    function _shouldRecord() internal pure override returns (bool) {
        return true;
    }

    function _recordDir() internal pure override returns (string memory) {
        return "deployments-test";
    }

    function put(string memory key, address value) external {
        _record(key, value);
    }

    function save(string memory label) external {
        _save(label);
    }
}

/*//////////////////////////////////////////////////////////////
                               TESTS
//////////////////////////////////////////////////////////////*/

/**
 * @title ScriptsTest
 * @author Kelechi Kizito Ugwu
 * @notice Runs every deployment and interaction script against a local stack.
 * @dev These are the commands a demo is driven by, so a broken one is found on stage rather
 *      than in CI. They are also the only code in the repo that nothing else exercises.
 */
contract ScriptsTest is Test {
    MockUSD usd;
    MockAaveSpoke spoke;
    AaveV4Adapter adapter;
    RiyaEscrow escrow;

    MockNativeQueryVerifier verifier;
    RiyaASC asc;
    RiyaUSD riyaUSD;
    LoanLedger ledger;

    uint256 reserveId;

    uint256 constant MIN_HARVEST = 10e6;
    uint256 constant MIN_DEPOSIT = 100e6;

    function setUp() public {
        usd = new MockUSD();
        spoke = new MockAaveSpoke();
        reserveId = spoke.listReserve(address(usd));

        uint256 nonce = vm.getNonce(address(this));
        address predictedEscrow = vm.computeCreateAddress(address(this), nonce + 1);

        adapter = new AaveV4Adapter(predictedEscrow, IAaveV4Spoke(address(spoke)), reserveId, MIN_HARVEST);
        escrow = new RiyaEscrow(address(adapter), MIN_DEPOSIT);

        verifier = new MockNativeQueryVerifier();

        nonce = vm.getNonce(address(this));
        address predictedLedger = vm.computeCreateAddress(address(this), nonce + 2);

        riyaUSD = new RiyaUSD(predictedLedger);
        asc = new RiyaASC(1, address(escrow), address(adapter), predictedLedger);
        ledger = new LoanLedger(address(asc), riyaUSD);
    }

    /*//////////////////////////////////////////////////////////////
                              DEPLOY MOCKS
    //////////////////////////////////////////////////////////////*/

    /// @dev Aave V4 is mainnet-only, so this is what makes a Sepolia demo possible at all.
    function testDeployMocksListsAUsableReserve() external {
        // ARRANGE
        DeployMocks script = new DeployMocks();

        // ACT
        (MockUSD deployedUsd, MockAaveSpoke deployedSpoke, uint256 id) = script.run();

        // ASSERT
        assertEq(deployedUsd.decimals(), 6, "matches USDC");
        assertEq(deployedSpoke.getReserve(id).underlying, address(deployedUsd));
        assertEq(id, 1, "reserve ids start at 1");
    }

    /*//////////////////////////////////////////////////////////////
                             SOURCE CHAIN
    //////////////////////////////////////////////////////////////*/

    function testDepositScriptMintsApprovesAndDeposits() external {
        // ARRANGE
        DepositHarness script = _depositScript(1_000e6);

        // ACT
        script.run();

        // ASSERT
        assertEq(adapter.s_principal(), 1_000e6);
        assertEq(usd.balanceOf(address(escrow)), 0, "forwarded in the same call");
    }

    function testAccrueScriptMakesYieldHarvestable() external {
        // ARRANGE
        _depositScript(1_000e6).run();

        // ACT
        new AccrueHarness(address(usd), address(spoke), address(escrow), address(adapter), reserveId, 100e6).run();

        // ASSERT
        assertEq(adapter.yieldAccrued(), 100e6);
        assertEq(adapter.s_principal(), 1_000e6, "principal untouched");
    }

    function testHarvestScriptMovesYieldToTheEscrow() external {
        // ARRANGE
        _depositScript(1_000e6).run();
        new AccrueHarness(address(usd), address(spoke), address(escrow), address(adapter), reserveId, 100e6).run();

        // ACT
        new HarvestHarness(address(usd), address(spoke), address(escrow), address(adapter), reserveId).run();

        // ASSERT
        assertEq(usd.balanceOf(address(escrow)), 100e6, "money arrives before the proof");
        assertEq(adapter.yieldAccrued(), 0);
    }

    function testSourceStatusReadsWithoutSpending() external {
        // ARRANGE
        _depositScript(1_000e6).run();
        uint256 principal = adapter.s_principal();

        // ACT
        new StatusHarness(address(usd), address(spoke), address(escrow), address(adapter), reserveId).run();

        // ASSERT
        assertEq(adapter.s_principal(), principal, "read-only");
    }

    /*//////////////////////////////////////////////////////////////
                          DESTINATION CHAIN
    //////////////////////////////////////////////////////////////*/

    function testBorrowScriptDrawsAgainstProvenCollateral() external {
        // ARRANGE
        _credit(DEFAULT_SENDER, 1_000e6);

        // ACT
        new BorrowHarness(address(ledger), address(riyaUSD), address(asc), 100e6).run();

        // ASSERT
        assertEq(ledger.s_debt(DEFAULT_SENDER), 100e6);
        assertEq(riyaUSD.balanceOf(DEFAULT_SENDER), 100e6);
    }

    /// @dev No proof, no collateral, no loan. The script is not a way around that.
    function testBorrowScriptFailsWithoutAProvenDeposit() external {
        // ARRANGE
        BorrowHarness script = new BorrowHarness(address(ledger), address(riyaUSD), address(asc), 100e6);

        // ACT
        // ASSERT
        vm.expectRevert(LoanLedger.LoanLedger__ExceedsLimit.selector);
        script.run();
    }

    function testRepayScriptBurnsDebt() external {
        // ARRANGE
        _credit(DEFAULT_SENDER, 1_000e6);
        new BorrowHarness(address(ledger), address(riyaUSD), address(asc), 100e6).run();

        // ACT
        new RepayHarness(address(ledger), address(riyaUSD), address(asc), 40e6).run();

        // ASSERT
        assertEq(ledger.s_debt(DEFAULT_SENDER), 60e6);
        assertEq(riyaUSD.balanceOf(DEFAULT_SENDER), 60e6);
    }

    /// @dev Settlement is lazy, so proven yield sits in `pendingYield` until something
    ///      touches the position. This script is what touches it.
    function testSettleScriptAppliesProvenYield() external {
        // ARRANGE
        _credit(DEFAULT_SENDER, 1_000e6);
        new BorrowHarness(address(ledger), address(riyaUSD), address(asc), 100e6).run();

        vm.prank(address(asc));
        ledger.onHarvest(100e6);
        assertEq(ledger.pendingYield(DEFAULT_SENDER), 85e6, "proven but unapplied");

        // ACT
        new SettleHarness(address(ledger), address(riyaUSD), address(asc)).run();

        // ASSERT
        assertEq(ledger.pendingYield(DEFAULT_SENDER), 0);
        assertEq(ledger.s_repaidByYield(DEFAULT_SENDER), 85e6);
    }

    function testPositionScriptReadsWithoutSpending() external {
        // ARRANGE
        _credit(DEFAULT_SENDER, 1_000e6);
        new BorrowHarness(address(ledger), address(riyaUSD), address(asc), 100e6).run();

        // ACT
        new PositionHarness(address(ledger), address(riyaUSD), address(asc), DEFAULT_SENDER).run();

        // ASSERT
        assertEq(ledger.s_debt(DEFAULT_SENDER), 100e6, "read-only");
    }

    /*//////////////////////////////////////////////////////////////
                           DEPLOYMENT RECORD
    //////////////////////////////////////////////////////////////*/

    function testRecordWritesBothFiles() external {
        // ARRANGE
        RecordHarness record = new RecordHarness();
        record.put("RIYA_ESCROW_ADDRESS", address(escrow));
        record.putUint("MOCK_RESERVE_ID", 7);

        // ACT
        record.write("probe");

        // ASSERT
        string memory stem = string.concat("deployments-test/", vm.toString(block.chainid), "-probe");

        string memory json = vm.readFile(string.concat(stem, ".json"));
        assertEq(vm.parseJsonAddress(json, ".RIYA_ESCROW_ADDRESS"), address(escrow));
        assertEq(vm.parseJsonUint(json, ".MOCK_RESERVE_ID"), 7);
        assertEq(vm.parseJsonUint(json, ".chainId"), block.chainid, "metadata rides along");

        // The env fragment is what the Makefile includes, so its shape is load-bearing.
        string memory env = vm.readFile(string.concat(stem, ".env"));
        assertTrue(
            vm.contains(env, string.concat("RIYA_ESCROW_ADDRESS=", vm.toString(address(escrow)))),
            "KEY=value, one per line"
        );
        assertTrue(vm.contains(env, "MOCK_RESERVE_ID=7"));
        assertFalse(vm.contains(env, "chainId"), "metadata stays out of the environment");

        vm.removeFile(string.concat(stem, ".json"));
        vm.removeFile(string.concat(stem, ".env"));
    }

    /// @dev The guard that keeps a test run from clobbering a real deployment record.
    function testSaveWritesNothingUnderForgeTest() external {
        // ARRANGE
        RecordHarness record = new RecordHarness();
        record.put("RIYA_ESCROW_ADDRESS", address(escrow));

        // ACT
        record.save("guarded");

        // ASSERT
        assertFalse(
            vm.exists(string.concat("deployments-test/", vm.toString(block.chainid), "-guarded.json")),
            "forge test must never write a record"
        );
    }

    /*//////////////////////////////////////////////////////////////
                        THE PRODUCTION DEFAULTS
    //////////////////////////////////////////////////////////////*/

    /// @dev The path that runs under `forge script`, where addresses come from `.env`.
    function testSourceScriptsReadTheirAddressesFromTheEnvironment() external {
        // ARRANGE
        vm.setEnv("MOCK_USD", vm.toString(SharedEnv.MOCK_USD));
        vm.setEnv("MOCK_SPOKE", vm.toString(SharedEnv.MOCK_SPOKE));
        vm.setEnv("MOCK_RESERVE_ID", vm.toString(SharedEnv.MOCK_RESERVE_ID));
        vm.setEnv("RIYA_ESCROW_ADDRESS", vm.toString(SharedEnv.ESCROW));
        vm.setEnv("AAVE_V4_ADAPTER_ADDRESS", vm.toString(SharedEnv.ADAPTER));

        SourceEnvHarness harness = new SourceEnvHarness();

        // ACT
        (address loadedUsd, uint256 loadedReserve, address loadedEscrow) = harness.loadFromEnv();

        // ASSERT
        assertEq(loadedUsd, SharedEnv.MOCK_USD);
        assertEq(loadedReserve, SharedEnv.MOCK_RESERVE_ID);
        assertEq(loadedEscrow, SharedEnv.ESCROW);
        assertEq(harness.broadcaster(), address(this), "msg.sender under forge script");
    }

    function testDestinationScriptsReadTheirAddressesFromTheEnvironment() external {
        // ARRANGE
        vm.setEnv("LOAN_LEDGER_ADDRESS", vm.toString(SharedEnv.LOAN_LEDGER));
        vm.setEnv("RIYA_USD_ADDRESS", vm.toString(SharedEnv.RIYA_USD));
        vm.setEnv("RIYA_ASC_ADDRESS", vm.toString(SharedEnv.RIYA_ASC));

        DestinationEnvHarness harness = new DestinationEnvHarness();

        // ACT
        (address loadedLedger, address loadedUsd, address loadedAsc) = harness.loadFromEnv();

        // ASSERT
        assertEq(loadedLedger, SharedEnv.LOAN_LEDGER);
        assertEq(loadedUsd, SharedEnv.RIYA_USD);
        assertEq(loadedAsc, SharedEnv.RIYA_ASC);
    }

    /// @dev AMOUNT and USER are written by no other suite, so these cannot race.
    function testAmountAndTargetFallBackWhenUnset() external {
        // ARRANGE
        vm.setEnv("LOAN_LEDGER_ADDRESS", vm.toString(SharedEnv.LOAN_LEDGER));
        vm.setEnv("RIYA_USD_ADDRESS", vm.toString(SharedEnv.RIYA_USD));
        vm.setEnv("RIYA_ASC_ADDRESS", vm.toString(SharedEnv.RIYA_ASC));

        SourceEnvHarness source = new SourceEnvHarness();
        DestinationEnvHarness destination = new DestinationEnvHarness();
        destination.loadFromEnv();

        // ACT
        // ASSERT
        assertEq(source.amount(1_000e6), 1_000e6, "the script's own default");
        assertEq(destination.amount(100e6), 100e6);
        assertEq(destination.target(), address(this), "defaults to the caller");

        vm.setEnv("AMOUNT", "555000000");
        vm.setEnv("USER", vm.toString(SharedEnv.ESCROW));
        assertEq(source.amount(1_000e6), 555e6, "AMOUNT wins when set");
        assertEq(destination.target(), SharedEnv.ESCROW, "USER wins when set");
    }

    /// @dev The other half of `testSaveWritesNothingUnderForgeTest`: when the policy says
    ///      yes, `_save` writes.
    function testSaveWritesWhenTheRunIsARealBroadcast() external {
        // ARRANGE
        RecordingHarness record = new RecordingHarness();
        record.put("LOAN_LEDGER_ADDRESS", address(ledger));

        // ACT
        record.save("broadcasting");

        // ASSERT
        string memory stem = string.concat("deployments-test/", vm.toString(block.chainid), "-broadcasting");
        assertTrue(vm.exists(string.concat(stem, ".json")));

        string memory json = vm.readFile(string.concat(stem, ".json"));
        assertEq(vm.parseJsonAddress(json, ".LOAN_LEDGER_ADDRESS"), address(ledger));

        vm.removeFile(string.concat(stem, ".json"));
        vm.removeFile(string.concat(stem, ".env"));
    }

    function testRecordsGoToTheDeploymentsDirectory() external {
        // ARRANGE
        RecordDirHarness harness = new RecordDirHarness();

        // ACT
        // ASSERT
        assertEq(harness.dir(), "deployments");
    }

    /// @dev Under `forge script --sender A`, forge makes A both the signer and `msg.sender`,
    ///      which is why the nonce prediction reads it.
    function testTheBroadcasterDefaultsToMsgSender() external {
        // ARRANGE
        RecordDirHarness harness = new RecordDirHarness();

        // ACT
        // ASSERT
        assertEq(harness.broadcaster(), address(this));
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    function _depositScript(uint256 amount) internal returns (DepositHarness) {
        return new DepositHarness(address(usd), address(spoke), address(escrow), address(adapter), reserveId, amount);
    }

    /// @dev Stands in for a proven deposit. The proof path itself is `RiyaASCTest`'s subject.
    function _credit(address user, uint256 amount) internal {
        vm.prank(address(asc));
        ledger.onDeposit(user, amount);
    }
}
