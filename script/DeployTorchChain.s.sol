// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {TorchChain} from "../src/TorchChain.sol";

/// @title DeployTorchChain
/// @notice Reviewable deployment script. The launch itself is performed by the IMD deployer through
///         the factory from the attested bytecode, so this script exists to document and rehearse the
///         deployment: it takes no configuration, because the token takes no constructor arguments.
/// @dev `deploy()` is the unit the tests call directly. `run()` only wraps it in a broadcast.
contract DeployTorchChain is Script {
    /// @notice Deploys the token. Whoever calls this (the broadcaster in `run()`, the test contract in
    ///         tests, the factory at launch) receives the whole supply.
    function deploy() public returns (TorchChain token) {
        token = new TorchChain();
    }

    /// @notice Broadcast entry point for a manual rehearsal on a fork or a test network.
    function run() external returns (TorchChain token) {
        vm.startBroadcast();
        token = deploy();
        vm.stopBroadcast();
    }
}
