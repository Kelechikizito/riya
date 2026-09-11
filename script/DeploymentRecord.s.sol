// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {console2} from "forge-std/console2.sol";

/**
 * @title DeploymentRecord
 * @author Kelechi Kizito Ugwu
 * @notice Writes every deployed address to `deployments/`, keyed by chain.
 * @dev riya deploys across two chains in three ordered steps, each needing addresses the
 *      previous one produced. Reading them off a terminal and pasting them into `.env` is
 *      where a demo dies, so the scripts record them instead.
 *
 *      Two files per deployment, both under `deployments/<chainId>-<label>`:
 *
 *      - `.json` is the record. Committed, diffable, and the thing you show someone.
 *      - `.env` is the same data as `KEY=value` lines. The Makefile includes it, so the
 *        interaction scripts and `make frontend-env` pick up new addresses with no paste.
 *
 *      Keys are the environment variable names rather than camelCase, so the two files map
 *      one to one and there is no lookup table to get wrong.
 *
 *      Only `forge script --broadcast` writes. A dry run leaves no trace, and neither does
 *      `forge test`, or every test that runs a deploy script would overwrite the real
 *      record with throwaway addresses.
 *
 *      A record is written while the script body runs, which is before the transactions are
 *      confirmed on chain. A broadcast that fails afterwards therefore leaves a record of a
 *      deployment that does not exist. `make verify-addresses` is what catches that.
 */
abstract contract DeploymentRecord is Script {
    string private constant OBJ = "riya-deployment";

    string private s_json;
    string private s_env;

    /**
     * @notice The address these transactions will actually be sent from.
     * @dev Under `forge script --account X --sender A`, forge signs with the keystore X,
     *      sends from A, and installs A as `msg.sender`. Any nonce prediction has to read
     *      that same address or it predicts a contract nobody deploys.
     *
     *      Overridden in tests, where `vm.startBroadcast()` broadcasts from forge's
     *      `DEFAULT_SENDER` rather than from whoever called `run()`.
     */
    function _broadcaster() internal view virtual returns (address) {
        return msg.sender;
    }

    /// @dev Records one address under an environment variable name.
    function _record(string memory envKey, address value) internal {
        s_json = vm.serializeAddress(OBJ, envKey, value);
        s_env = string.concat(s_env, envKey, "=", vm.toString(value), "\n");
    }

    /// @dev Same, for the numeric entries such as `MOCK_RESERVE_ID`.
    function _record(string memory envKey, uint256 value) internal {
        s_json = vm.serializeUint(OBJ, envKey, value);
        s_env = string.concat(s_env, envKey, "=", vm.toString(value), "\n");
    }

    /**
     * @notice Writes the record to disk and prints where it went.
     * @param label The deployment step: `mocks`, `source` or `destination`.
     * @dev Writes only under `--broadcast`. Tests run these scripts for real and would
     *      otherwise clobber a live record, and a dry run should be free of side effects.
     */
    function _save(string memory label) internal {
        if (!_shouldRecord()) return;
        _write(label);
    }

    /// @dev Whether this run should leave a record. Only a real broadcast should, and the
    ///      policy is named and overridable so a test can exercise the write path without
    ///      pretending to be one.
    function _shouldRecord() internal view virtual returns (bool) {
        return vm.isContext(VmSafe.ForgeContext.ScriptBroadcast);
    }

    /// @dev Where records go. Virtual so tests can write somewhere disposable.
    function _recordDir() internal view virtual returns (string memory) {
        return "deployments";
    }

    /// @dev The write itself, split out from the guard so it is reachable from a test.
    ///      `_save` is not, by design: it refuses to run outside a real broadcast.
    function _write(string memory label) internal {
        // Metadata goes to the JSON only. It would collide with real variables in `.env`.
        s_json = vm.serializeUint(OBJ, "chainId", block.chainid);
        s_json = vm.serializeUint(OBJ, "deployedAt", block.timestamp);
        s_json = vm.serializeUint(OBJ, "block", block.number);

        string memory dir = _recordDir();
        vm.createDir(dir, true);

        string memory stem = string.concat(dir, "/", vm.toString(block.chainid), "-", label);
        vm.writeJson(s_json, string.concat(stem, ".json"));
        vm.writeFile(string.concat(stem, ".env"), s_env);

        console2.log("recorded  :", string.concat(stem, ".json"));
    }
}
