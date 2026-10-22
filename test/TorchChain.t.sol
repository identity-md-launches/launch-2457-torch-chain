// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {TorchChain} from "../src/TorchChain.sol";

/// @notice A deployer that is a contract, standing in for the launch factory: it must receive the
///         whole supply and be able to pay it out with plain `transfer`.
contract FactoryStandIn {
    TorchChain public token;

    function launch() external returns (TorchChain) {
        token = new TorchChain();
        return token;
    }

    function pay(address to, uint256 amount) external returns (bool) {
        return token.transfer(to, amount);
    }
}

contract TorchChainTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;

    TorchChain internal token;
    address internal deployer = makeAddr("deployer");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public {
        vm.prank(deployer);
        token = new TorchChain();
    }

    // ───────────────────────────── metadata ─────────────────────────────

    function test_name() public view {
        assertEq(token.name(), "Torch Chain");
        assertEq(token.TOKEN_NAME(), "Torch Chain");
    }

    function test_symbol() public view {
        assertEq(token.symbol(), "TCH");
        assertEq(token.TOKEN_SYMBOL(), "TCH");
    }

    function test_decimals() public view {
        assertEq(token.decimals(), 18);
        assertEq(token.TOKEN_DECIMALS(), 18);
    }

    // ───────────────────────────── supply ─────────────────────────────

    function test_totalSupplyIsOneBillionWithEighteenDecimals() public view {
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.totalSupply(), 1_000_000_000 * 10 ** 18);
        assertEq(token.TOTAL_SUPPLY(), SUPPLY);
        assertEq(token.SUPPLY_WHOLE_TOKENS(), 1_000_000_000);
    }

    function test_wholeSupplyMintedToDeployer() public view {
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    function test_constructorEmitsSingleMintTransfer() public {
        vm.expectEmit(true, true, true, true);
        emit IERC20.Transfer(address(0), deployer, SUPPLY);
        vm.prank(deployer);
        new TorchChain();
    }

    function test_contractDeployerReceivesSupplyAndCanPayItOut() public {
        FactoryStandIn factory = new FactoryStandIn();
        TorchChain launched = factory.launch();
        assertEq(launched.totalSupply(), SUPPLY);
        assertEq(launched.balanceOf(address(factory)), SUPPLY);

        uint256 swarm = SUPPLY / 10;
        assertTrue(factory.pay(alice, swarm));
        assertEq(launched.balanceOf(alice), swarm);
        assertEq(launched.balanceOf(address(factory)), SUPPLY - swarm);
        assertEq(launched.totalSupply(), SUPPLY);
    }

    function test_noMintFunctionExists() public {
        bytes[5] memory calls = [
            abi.encodeWithSignature("mint(address,uint256)", alice, 1),
            abi.encodeWithSignature("mint(uint256)", 1),
            abi.encodeWithSignature("mint()"),
            abi.encodeWithSignature("issue(uint256)", 1),
            abi.encodeWithSignature("setMinter(address)", alice)
        ];
        for (uint256 i; i < calls.length; ++i) {
            vm.prank(deployer);
            (bool ok,) = address(token).call(calls[i]);
            assertFalse(ok, "an unexpected admin function answered");
        }
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_noOwnerOrPrivilegedFunctionExists() public {
        bytes[8] memory calls = [
            abi.encodeWithSignature("owner()"),
            abi.encodeWithSignature("transferOwnership(address)", alice),
            abi.encodeWithSignature("pause()"),
            abi.encodeWithSignature("blacklist(address)", alice),
            abi.encodeWithSignature("freeze(address)", alice),
            abi.encodeWithSignature("burnFrom(address,uint256)", alice, 1),
            abi.encodeWithSignature("burn(uint256)", 1),
            abi.encodeWithSignature("seize(address)", alice)
        ];
        for (uint256 i; i < calls.length; ++i) {
            vm.prank(deployer);
            (bool ok,) = address(token).call(calls[i]);
            assertFalse(ok, "an unexpected privileged function answered");
        }
    }

    function test_plainEtherTransferIsRejected() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (bool ok,) = address(token).call{value: 1 ether}("");
        assertFalse(ok);
        assertEq(address(token).balance, 0);
    }

    // ───────────────────────────── transfer ─────────────────────────────

    function test_transferMovesExactAmount() public {
        vm.prank(deployer);
        vm.expectEmit(true, true, true, true);
        emit IERC20.Transfer(deployer, alice, 1_000 ether);
        assertTrue(token.transfer(alice, 1_000 ether));
        assertEq(token.balanceOf(alice), 1_000 ether);
        assertEq(token.balanceOf(deployer), SUPPLY - 1_000 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferOfZeroSucceeds() public {
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(bob), 0);
    }

    function test_transferToSelfKeepsBalance() public {
        vm.prank(deployer);
        assertTrue(token.transfer(deployer, SUPPLY));
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    function test_transferWholeSupplyThenNothingLeft() public {
        vm.prank(deployer);
        token.transfer(alice, SUPPLY);
        assertEq(token.balanceOf(deployer), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
    }

    function test_RevertWhen_transferExceedsBalance() public {
        vm.prank(deployer);
        token.transfer(alice, 5 ether);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 5 ether, 6 ether));
        token.transfer(bob, 6 ether);
    }

    function test_RevertWhen_transferFromEmptyAccount() public {
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, bob, 0, 1));
        token.transfer(alice, 1);
    }

    function test_RevertWhen_transferToZeroAddress() public {
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
    }

    // ───────────────────────────── allowance ─────────────────────────────

    function test_approveSetsAllowanceAndEmits() public {
        vm.prank(deployer);
        vm.expectEmit(true, true, true, true);
        emit IERC20.Approval(deployer, alice, 10 ether);
        assertTrue(token.approve(alice, 10 ether));
        assertEq(token.allowance(deployer, alice), 10 ether);
    }

    function test_RevertWhen_approveZeroSpender() public {
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
    }

    function test_transferFromSpendsAllowance() public {
        vm.prank(deployer);
        token.approve(alice, 10 ether);
        vm.prank(alice);
        assertTrue(token.transferFrom(deployer, bob, 4 ether));
        assertEq(token.balanceOf(bob), 4 ether);
        assertEq(token.balanceOf(deployer), SUPPLY - 4 ether);
        assertEq(token.allowance(deployer, alice), 6 ether);
    }

    function test_transferFromWithMaxAllowanceDoesNotDecrease() public {
        vm.prank(deployer);
        token.approve(alice, type(uint256).max);
        vm.prank(alice);
        token.transferFrom(deployer, bob, 4 ether);
        assertEq(token.allowance(deployer, alice), type(uint256).max);
    }

    function test_RevertWhen_transferFromExceedsAllowance() public {
        vm.prank(deployer);
        token.approve(alice, 3 ether);
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 3 ether, 4 ether)
        );
        token.transferFrom(deployer, bob, 4 ether);
    }

    function test_RevertWhen_transferFromWithoutAllowance() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 0, 1));
        token.transferFrom(deployer, bob, 1);
    }

    function test_RevertWhen_transferFromExceedsOwnerBalanceDespiteAllowance() public {
        vm.prank(deployer);
        token.transfer(alice, 2 ether);
        vm.prank(alice);
        token.approve(bob, 10 ether);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 2 ether, 3 ether));
        token.transferFrom(alice, deployer, 3 ether);
    }

    /// @dev Nobody can pull a holder's tokens without that holder's approval, not even the deployer.
    function test_RevertWhen_deployerPullsFromHolderWithoutApproval() public {
        vm.prank(deployer);
        token.transfer(alice, 1 ether);
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, deployer, 0, 1));
        token.transferFrom(alice, deployer, 1);
        assertEq(token.balanceOf(alice), 1 ether);
    }

    // ───────────────────────────── fuzz ─────────────────────────────

    function testFuzz_transferConservesSupply(address to, uint256 amount) public {
        vm.assume(to != address(0));
        amount = bound(amount, 0, SUPPLY);
        vm.prank(deployer);
        assertTrue(token.transfer(to, amount));
        if (to == deployer) {
            assertEq(token.balanceOf(deployer), SUPPLY);
        } else {
            assertEq(token.balanceOf(to), amount);
            assertEq(token.balanceOf(deployer), SUPPLY - amount);
        }
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferAboveBalanceReverts(uint256 held, uint256 attempt) public {
        held = bound(held, 0, SUPPLY - 1);
        attempt = bound(attempt, held + 1, SUPPLY);
        vm.prank(deployer);
        token.transfer(alice, held);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, held, attempt));
        token.transfer(bob, attempt);
    }

    function testFuzz_transferFromRespectsAllowance(uint256 allowed, uint256 spend) public {
        allowed = bound(allowed, 0, SUPPLY);
        spend = bound(spend, 0, SUPPLY);
        vm.prank(deployer);
        token.approve(alice, allowed);
        vm.prank(alice);
        if (spend > allowed) {
            vm.expectRevert(
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, allowed, spend)
            );
            token.transferFrom(deployer, bob, spend);
        } else {
            assertTrue(token.transferFrom(deployer, bob, spend));
            assertEq(token.balanceOf(bob), spend);
            assertEq(token.allowance(deployer, alice), allowed - spend);
        }
        assertEq(token.totalSupply(), SUPPLY);
    }

    // ───────────────────────────── bytecode ─────────────────────────────

    /// @dev Mirrors the launch floor's reachable-opcode scan: no DELEGATECALL, CALLCODE or
    ///      SELFDESTRUCT in executable runtime code, and the runtime fits EIP-170.
    function test_runtimeHasNoDelegatecallCallcodeOrSelfdestruct() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576);
        bool reachable = true;
        for (uint256 i; i < runtime.length; ++i) {
            uint8 op = uint8(runtime[i]);
            if (op == 0x5B) reachable = true;
            if (op >= 0x60 && op <= 0x7F) {
                i += (op - 0x5F);
                continue;
            }
            if (reachable) {
                assertTrue(op != 0xF4, "DELEGATECALL");
                assertTrue(op != 0xF2, "CALLCODE");
                assertTrue(op != 0xFF, "SELFDESTRUCT");
            }
            if (op == 0x00 || op == 0x56 || op == 0xF3 || op == 0xFD || op == 0xFE || op == 0xFF) reachable = false;
        }
    }
}
