// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {EvmV1Decoder} from "@gluwa/usc-contracts/contracts/write-ability/common/EvmV1Decoder.sol";

/**
 * @title EvmTxFixture
 * @author Kelechi Kizito Ugwu
 * @notice Builds the `encodedTransaction` bytes `RiyaASC.submit` expects.
 * @dev The Proof Builder service produces these on Creditcoin, but the encoding is plain
 *      ABI: a leading type byte, then three chunks, of which only the receipt chunk matters
 *      to `decodeReceiptFields`. That makes a real fixture constructible in Solidity, so
 *      `submit` is unit-testable with no network and no Proof Builder.
 *
 *      Kept in sync with `EvmV1Decoder._decodeReceiptChunk`. If that layout moves these
 *      fixtures decode into nonsense rather than failing, so re-check it against the pin.
 */
library EvmTxFixture {
    /// @notice A type-2 transaction whose receipt carries `logs` and the given status.
    /// @param receiptStatus 1 for a successful transaction, 0 for a reverted one.
    /// @param logs The receipt's logs, in emission order.
    function encode(uint8 receiptStatus, EvmV1Decoder.LogEntryTuple[] memory logs)
        internal
        pure
        returns (bytes memory)
    {
        bytes[] memory chunks = new bytes[](3);

        // Common fields. Nothing in riya reads these, but the chunk count is checked.
        chunks[0] = abi.encode(uint64(0), uint64(21000), address(0), false, address(0), uint256(0), bytes(""));

        // Type-specific fields, unread by `decodeReceiptFields`.
        chunks[1] = bytes("");

        chunks[2] = abi.encode(receiptStatus, uint64(50000), logs, bytes(""));

        return abi.encode(uint8(2), chunks);
    }

    /// @notice One log with the given emitter and topics, and empty data.
    /// @dev Both riya events index every parameter, so `data` is always empty and every
    ///      value is read out of `topics`.
    function log(address emitter, bytes32[] memory topics) internal pure returns (EvmV1Decoder.LogEntryTuple memory) {
        return EvmV1Decoder.LogEntryTuple({address_: emitter, topics: topics, data: bytes("")});
    }

    function topics3(bytes32 signature, bytes32 a, bytes32 b) internal pure returns (bytes32[] memory out) {
        out = new bytes32[](3);
        out[0] = signature;
        out[1] = a;
        out[2] = b;
    }

    /// @dev A log carrying the right signature but the wrong shape. `RiyaASC` must skip it
    ///      rather than revert, or an attacker could block a real proof with one of these.
    function topics1(bytes32 signature) internal pure returns (bytes32[] memory out) {
        out = new bytes32[](1);
        out[0] = signature;
    }
}
