// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {DeployTorchChain} from "../script/DeployTorchChain.s.sol";
import {TorchChain} from "../src/TorchChain.sol";

/// @notice Exercises the deploy script's `deploy()` directly, with no environment and no broadcast.
contract DeployTorchChainTest is Test {
    function test_deployMintsWholeSupplyToTheCaller() public {
        DeployTorchChain deployer = new DeployTorchChain();
        TorchChain token = deployer.deploy();
        assertEq(token.name(), "Torch Chain");
        assertEq(token.symbol(), "TCH");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), 1_000_000_000 ether);
        // The script contract is `msg.sender` of the constructor, so it holds the supply.
        assertEq(token.balanceOf(address(deployer)), 1_000_000_000 ether);
    }

    function test_twoDeploymentsAreIndependent() public {
        DeployTorchChain a = new DeployTorchChain();
        DeployTorchChain b = new DeployTorchChain();
        TorchChain ta = a.deploy();
        TorchChain tb = b.deploy();
        assertTrue(address(ta) != address(tb));
        assertEq(ta.balanceOf(address(a)), 1_000_000_000 ether);
        assertEq(tb.balanceOf(address(b)), 1_000_000_000 ether);
        assertEq(ta.balanceOf(address(b)), 0);
    }
}
