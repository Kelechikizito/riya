// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test, Vm} from "forge-std/Test.sol";
import {EvmV1Decoder} from "@gluwa/usc-contracts/contracts/write-ability/common/EvmV1Decoder.sol";
import {
    INativeQueryVerifier,
    NativeQueryVerifierLib
} from "@gluwa/usc-contracts/contracts/write-ability/common/INativeQueryVerifier.sol";

import {AaveV4Adapter} from "src/adapters/AaveV4Adapter.sol";
import {LoanLedger} from "src/destination-chain/LoanLedger.sol";
import {RiyaASC} from "src/destination-chain/RiyaASC.sol";
import {RiyaUSD} from "src/destination-chain/RiyaUSD.sol";
import {RiyaEscrow} from "src/source-chain/ethereum/RiyaEscrow.sol";
import {IAaveV4Spoke} from "src/interfaces/IAaveV4Spoke.sol";
import {EvmTxFixture} from "test/helpers/EvmTxFixture.sol";
import {MockAaveSpoke} from "test/mocks/MockAaveSpoke.sol";
import {MockNativeQueryVerifier} from "test/mocks/MockNativeQueryVerifier.sol";
import {MockUSD} from "test/mocks/MockUSD.sol";

/**
 * @title RiyaEndToEndTest
 * @author Kelechi Kizito Ugwu
 * @notice Runs all five contracts together: deposit on Ethereum, harvest, prove, borrow.
 * @dev Proof bytes are built from logs actually emitted by `RiyaEscrow` and `AaveV4Adapter`,
 *      captured with `vm.recordLogs`, rather than hand-written topics. That is the point of
 *      this file: if an event signature drifts on the source chain, the matching constant in
 *      `RiyaASC` stops selecting it and these tests fail. The unit tests cannot see that,
 *      because they build both sides from the same string.
 *
 *      What this does not cover is the off-chain leg. The keeper and the readability worker
 *      are Node programs, Foundry cannot run them, and mocking them here would mock exactly
 *      the parts carrying the risk. Their tests live in `offchain/test/` and the real join is
 *      the Sepolia rehearsal. This file proves every seam they connect to lines up.
 */
contract RiyaEndToEndTest is Test {
    // Source chain.
    MockAaveSpoke spoke;
    MockUSD usd;
    AaveV4Adapter adapter;
    RiyaEscrow escrow;

    // Destination chain.
    MockNativeQueryVerifier verifier;
    RiyaASC asc;
    LoanLedger ledger;
    RiyaUSD riyaUSD;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address keeper = makeAddr("keeper");
    address funder = makeAddr("funder");

    uint256 reserveId;
    uint64 nextHeight = 1_000;
    uint64 nextTxIndex = 1;

    uint64 constant CHAIN_KEY = 1;
    uint256 constant MIN_HARVEST = 10e6;
    uint256 constant MIN_DEPOSIT = 100e6;

    function setUp() public {
        // --- Ethereum ---
        usd = new MockUSD();
        spoke = new MockAaveSpoke();
        reserveId = spoke.listReserve(address(usd));

        uint256 nonce = vm.getNonce(address(this));
        address predictedEscrow = vm.computeCreateAddress(address(this), nonce + 1);

        adapter = new AaveV4Adapter(predictedEscrow, IAaveV4Spoke(address(spoke)), reserveId, MIN_HARVEST);
        escrow = new RiyaEscrow(address(adapter), MIN_DEPOSIT);

        // --- Creditcoin ---
        verifier = new MockNativeQueryVerifier();
        vm.etch(NativeQueryVerifierLib.PRECOMPILE, address(verifier).code);
        verifier = MockNativeQueryVerifier(NativeQueryVerifierLib.PRECOMPILE);
        verifier.setValid(true);

        nonce = vm.getNonce(address(this));
        address predictedLedger = vm.computeCreateAddress(address(this), nonce + 2);

        riyaUSD = new RiyaUSD(predictedLedger);
        asc = new RiyaASC(CHAIN_KEY, address(escrow), address(adapter), predictedLedger);
        ledger = new LoanLedger(address(asc), riyaUSD);

        assertEq(address(ledger), predictedLedger);
    }

    /// @notice The demo, start to finish, for one user.
    function testDepositProveHarvestBorrow() external {
        // ARRANGE
        // ACT
        // 1. Alice deposits on Ethereum. Nothing exists on Creditcoin yet.
        bytes memory depositTx = _depositOnEthereum(alice, 1_000e6);
        assertEq(ledger.s_collateral(alice), 0, "no proof, no collateral");

        // 2. The worker proves that transaction. Collateral appears.
        _prove(depositTx);
        assertEq(ledger.s_collateral(alice), 1_000e6);

        // 3. Alice borrows against it, at the bottom rung of the ladder.
        vm.prank(alice);
        ledger.borrow(100e6);
        assertEq(riyaUSD.balanceOf(alice), 100e6);

        // 4. Yield accrues and the keeper harvests. The money moves on Ethereum.
        _accrueYield(100e6);
        bytes memory harvestTx = _harvestOnEthereum();
        assertEq(usd.balanceOf(address(escrow)), 100e6, "yield arrived before the proof");

        // 5. The worker proves the harvest. Alice's debt falls without her touching it.
        _prove(harvestTx);

        // ASSERT
        assertEq(ledger.pendingYield(alice), 85e6);

        // Settlement is lazy, so touch the position to apply it. One unit of cash repayment
        // rides along, which is why the figures below are off by one.
        vm.prank(alice);
        ledger.repay(1);

        assertEq(ledger.s_debt(alice), 15e6 - 1, "85 of 100 retired by proven yield");
        assertEq(ledger.s_repaidByYield(alice), 85e6);
        assertEq(ledger.s_protocolFees(), 15e6);
        assertEq(riyaUSD.balanceOf(alice), 100e6 - 1, "settlement itself burns nothing");
    }

    /// @notice The demo shot: one harvest, one proof, every borrower's debt falls at once.
    function testOneHarvestRetiresEveryBorrowersDebt() external {
        // ARRANGE
        _prove(_depositOnEthereum(alice, 1_000e6));
        _prove(_depositOnEthereum(bob, 3_000e6));

        vm.prank(alice);
        ledger.borrow(100e6);
        vm.prank(bob);
        ledger.borrow(300e6);

        // ACT
        _accrueYield(400e6);
        _prove(_harvestOnEthereum());

        // ASSERT
        // 340 distributed after the 15% fee, split one quarter to three quarters.
        assertEq(ledger.pendingYield(alice), 85e6);
        assertEq(ledger.pendingYield(bob), 255e6);
        assertEq(ledger.s_protocolFees(), 60e6);
    }

    /// @dev The score is only reachable through the whole loop, so this is the only place it
    ///      can be checked against real source-chain events.
    function testRepeatedProvenYieldGraduatesTheBorrower() external {
        // ARRANGE
        _prove(_depositOnEthereum(alice, 1_000e6));
        assertEq(ledger.maxLtvBps(alice), 1_000);

        // ACT
        _borrowAndSelfRepay(alice, 50e6);
        _borrowAndSelfRepay(alice, 50e6);
        _borrowAndSelfRepay(alice, 30e6);
        _borrowAndSelfRepay(alice, 70e6);

        // ASSERT
        assertEq(ledger.score(alice), 100);
        assertEq(ledger.maxLtvBps(alice), 5_000);

        vm.prank(alice);
        ledger.borrow(500e6);
        assertEq(ledger.s_debt(alice), 500e6, "half of collateral, earned");
    }

    /// @dev Proof bytes are public and `submit` is permissionless, so replaying a real
    ///      harvest is the cheapest attack on the whole system.
    function testReplayingARealHarvestIsRejected() external {
        // ARRANGE
        _prove(_depositOnEthereum(alice, 1_000e6));
        _accrueYield(100e6);

        bytes memory harvestTx = _harvestOnEthereum();
        uint64 height = nextHeight;
        uint64 txIndex = nextTxIndex;
        _prove(harvestTx);

        uint256 yieldPerShare = ledger.s_yieldPerShare();

        // ACT
        // ASSERT
        verifier.setTxIndex(txIndex);
        vm.expectRevert(
            abi.encodeWithSelector(
                RiyaASC.RiyaASC__AlreadyConsumed.selector,
                keccak256(abi.encode(CHAIN_KEY, height, _merkleProof().root, txIndex))
            )
        );
        asc.submit(height, harvestTx, _merkleProof(), _continuityProof());

        assertEq(ledger.s_yieldPerShare(), yieldPerShare, "nothing moved");
    }

    /*//////////////////////////////////////////////////////////////
                            SOURCE CHAIN LEG
    //////////////////////////////////////////////////////////////*/

    /// @dev Runs a real deposit and returns the encoded transaction the worker would build
    ///      from it, with the logs captured as the contracts actually emitted them.
    function _depositOnEthereum(address user, uint256 amount) internal returns (bytes memory) {
        usd.mint(user, amount);

        vm.prank(user);
        usd.approve(address(escrow), amount);

        vm.recordLogs();
        vm.prank(user);
        escrow.deposit(amount);

        return _encodeRecordedLogs();
    }

    function _harvestOnEthereum() internal returns (bytes memory) {
        vm.recordLogs();
        vm.prank(keeper);
        adapter.harvest();

        return _encodeRecordedLogs();
    }

    function _accrueYield(uint256 amount) internal {
        usd.mint(funder, amount);

        vm.startPrank(funder);
        usd.approve(address(spoke), amount);
        spoke.accrueYield(reserveId, address(adapter), amount);
        vm.stopPrank();
    }

    /// @dev The whole receipt, every log in it, exactly as emitted. Passing the unfiltered
    ///      set is deliberate: ERC-20 `Transfer` logs and the adapter's own deposit event
    ///      ride along, so `RiyaASC` has to select correctly out of real noise.
    function _encodeRecordedLogs() private returns (bytes memory) {
        Vm.Log[] memory recorded = vm.getRecordedLogs();

        EvmV1Decoder.LogEntryTuple[] memory logs = new EvmV1Decoder.LogEntryTuple[](recorded.length);
        for (uint256 i; i < recorded.length; ++i) {
            logs[i] = EvmV1Decoder.LogEntryTuple({
                address_: recorded[i].emitter, topics: recorded[i].topics, data: recorded[i].data
            });
        }

        return EvmTxFixture.encode(1, logs);
    }

    /*//////////////////////////////////////////////////////////////
                         DESTINATION CHAIN LEG
    //////////////////////////////////////////////////////////////*/

    /// @dev Stands in for the worker: pick the next height and index, then submit. The
    ///      worker's real job is to do this in the order Ethereum produced the events, which
    ///      the increasing height enforces here.
    function _prove(bytes memory encodedTransaction) internal {
        verifier.setTxIndex(nextTxIndex);
        asc.submit(nextHeight, encodedTransaction, _merkleProof(), _continuityProof());

        nextHeight += 1;
        nextTxIndex += 1;
    }

    function _borrowAndSelfRepay(address user, uint256 amount) internal {
        vm.prank(user);
        ledger.borrow(amount);

        // 85% of gross is distributed, so gross up by the fee to retire exactly `amount`.
        uint256 gross = (amount * 10_000) / 8_500;
        _accrueYield(gross);
        _prove(_harvestOnEthereum());

        vm.prank(user);
        ledger.repay(1);
    }

    function _merkleProof() internal pure returns (INativeQueryVerifier.MerkleProof memory) {
        return INativeQueryVerifier.MerkleProof({
            root: bytes32(uint256(0x1111)), siblings: new INativeQueryVerifier.MerkleProofEntry[](0)
        });
    }

    function _continuityProof() internal pure returns (INativeQueryVerifier.ContinuityProof memory) {
        return INativeQueryVerifier.ContinuityProof({lowerEndpointDigest: bytes32(0), roots: new bytes32[](0)});
    }
}
