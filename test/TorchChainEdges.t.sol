// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, Vm} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {TorchChain} from "../src/TorchChain.sol";

/// @notice Edge cases and failure paths the main suite does not pin: allowance semantics at the
///         boundaries, error precedence in `transferFrom`, and stateless fuzzing with `bound`.
contract TorchChainEdgesTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;

    TorchChain internal token;
    address internal deployer = makeAddr("deployer");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public {
        vm.prank(deployer);
        token = new TorchChain();
    }

    // ───────────────────────────── allowance ─────────────────────────────

    function test_approveOverwritesRatherThanAdds() public {
        vm.startPrank(deployer);
        token.approve(alice, 10 ether);
        token.approve(alice, 3 ether);
        vm.stopPrank();
        assertEq(token.allowance(deployer, alice), 3 ether);
    }

    function test_approveZeroRevokes() public {
        vm.startPrank(deployer);
        token.approve(alice, 10 ether);
        token.approve(alice, 0);
        vm.stopPrank();
        assertEq(token.allowance(deployer, alice), 0);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 0, 1));
        token.transferFrom(deployer, bob, 1);
    }

    function test_allowanceSpentExactlyToZeroThenOneMoreReverts() public {
        vm.prank(deployer);
        token.approve(alice, 5 ether);
        vm.prank(alice);
        token.transferFrom(deployer, bob, 5 ether);
        assertEq(token.allowance(deployer, alice), 0);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 0, 1));
        token.transferFrom(deployer, bob, 1);
    }

    function test_allowanceIsPerSpender() public {
        vm.prank(deployer);
        token.approve(alice, 5 ether);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1 ether));
        token.transferFrom(deployer, bob, 1 ether);
        assertEq(token.allowance(deployer, bob), 0);
    }

    /// @dev Moving your own tokens through `transferFrom` still needs an allowance to yourself.
    function test_RevertWhen_ownerUsesTransferFromWithoutSelfAllowance() public {
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, deployer, 0, 1));
        token.transferFrom(deployer, alice, 1);
    }

    function test_selfApprovalAllowsTransferFrom() public {
        vm.startPrank(deployer);
        token.approve(deployer, 1 ether);
        token.transferFrom(deployer, alice, 1 ether);
        vm.stopPrank();
        assertEq(token.balanceOf(alice), 1 ether);
        assertEq(token.allowance(deployer, deployer), 0);
    }

    function test_unlimitedAllowanceMovesWholeSupplyAndStaysUnlimited() public {
        vm.prank(deployer);
        token.approve(alice, type(uint256).max);
        vm.prank(alice);
        token.transferFrom(deployer, bob, SUPPLY);
        assertEq(token.balanceOf(bob), SUPPLY);
        assertEq(token.balanceOf(deployer), 0);
        assertEq(token.allowance(deployer, alice), type(uint256).max);
    }

    /// @dev Just below the unlimited sentinel the allowance is finite and is decremented.
    function test_maxMinusOneAllowanceIsDecremented() public {
        vm.prank(deployer);
        token.approve(alice, type(uint256).max - 1);
        vm.prank(alice);
        token.transferFrom(deployer, bob, 1);
        assertEq(token.allowance(deployer, alice), type(uint256).max - 2);
    }

    function test_transferFromEmitsTransferButNoApproval() public {
        vm.prank(deployer);
        token.approve(alice, 5 ether);
        vm.recordLogs();
        vm.prank(alice);
        token.transferFrom(deployer, bob, 2 ether);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].topics[0], IERC20.Transfer.selector);
        assertEq(logs[0].topics[1], bytes32(uint256(uint160(deployer))));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(bob))));
        assertEq(abi.decode(logs[0].data, (uint256)), 2 ether);
    }

    function test_zeroAmountTransferFromNeedsNoAllowance() public {
        vm.prank(alice);
        assertTrue(token.transferFrom(deployer, bob, 0));
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(bob), 0);
    }

    // ───────────────────────────── failure precedence ─────────────────────────────

    function test_RevertWhen_transferFromToZeroAddress() public {
        vm.prank(deployer);
        token.approve(alice, 5 ether);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transferFrom(deployer, address(0), 1 ether);
        // The revert undid the allowance spend too.
        assertEq(token.allowance(deployer, alice), 5 ether);
    }

    /// @dev The allowance is checked before the receiver, so a spender with no allowance learns
    ///      nothing else about the call.
    function test_RevertWhen_transferFromToZeroWithoutAllowanceReportsAllowance() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 0, 1));
        token.transferFrom(deployer, address(0), 1);
    }

    function test_RevertWhen_transferFromZeroAddressOwner() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 0, 1));
        token.transferFrom(address(0), bob, 1);
    }

    function test_RevertWhen_zeroAmountTransferToZeroAddress() public {
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
    }

    function test_RevertWhen_transferOneWeiOverWholeSupply() public {
        vm.prank(deployer);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, deployer, SUPPLY, SUPPLY + 1)
        );
        token.transfer(alice, SUPPLY + 1);
    }

    function test_RevertWhen_transferMaxUint() public {
        vm.prank(deployer);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, deployer, SUPPLY, type(uint256).max)
        );
        token.transfer(alice, type(uint256).max);
    }

    function test_failedTransferLeavesStateUntouched() public {
        vm.prank(deployer);
        token.transfer(alice, 1 ether);
        vm.prank(alice);
        vm.expectRevert();
        token.transfer(bob, 1 ether + 1);
        assertEq(token.balanceOf(alice), 1 ether);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    // ───────────────────────────── recipients ─────────────────────────────

    /// @dev Tokens sent to the token contract are accepted and counted, but nothing can move them:
    ///      there is no rescue function. Documented, not a defect: the brief asks for no admin.
    function test_tokensSentToTokenContractAreStuck() public {
        vm.prank(deployer);
        token.transfer(address(token), 1 ether);
        assertEq(token.balanceOf(address(token)), 1 ether);
        assertEq(token.totalSupply(), SUPPLY);

        (bool ok,) = address(token).call(abi.encodeWithSignature("rescue(address,uint256)", alice, 1 ether));
        assertFalse(ok);
        assertEq(token.balanceOf(address(token)), 1 ether);
    }

    function test_constructorMintsOnlyToSender() public {
        vm.prank(alice);
        TorchChain t = new TorchChain();
        assertEq(t.balanceOf(alice), SUPPLY);
        assertEq(t.balanceOf(deployer), 0);
        assertEq(t.balanceOf(address(this)), 0);
        assertEq(t.totalSupply(), SUPPLY);
    }

    // ───────────────────────────── fuzz ─────────────────────────────

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_chainedTransfersConserve(uint256 a, uint256 b, uint256 c) public {
        a = bound(a, 0, SUPPLY);
        vm.prank(deployer);
        token.transfer(alice, a);
        b = bound(b, 0, a);
        vm.prank(alice);
        token.transfer(bob, b);
        c = bound(c, 0, b);
        vm.prank(bob);
        token.transfer(deployer, c);

        assertEq(token.balanceOf(deployer), SUPPLY - a + c);
        assertEq(token.balanceOf(alice), a - b);
        assertEq(token.balanceOf(bob), b - c);
        assertEq(token.balanceOf(deployer) + token.balanceOf(alice) + token.balanceOf(bob), SUPPLY);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_approveSetsExactAllowance(uint256 first, uint256 second) public {
        vm.startPrank(deployer);
        token.approve(alice, first);
        assertEq(token.allowance(deployer, alice), first);
        token.approve(alice, second);
        vm.stopPrank();
        assertEq(token.allowance(deployer, alice), second);
        // Approving moves nothing.
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_transferFromBalanceBoundOverAllowance(uint256 held, uint256 amount) public {
        held = bound(held, 0, SUPPLY - 1);
        amount = bound(amount, held + 1, SUPPLY);
        vm.prank(deployer);
        token.transfer(alice, held);
        vm.prank(alice);
        token.approve(bob, type(uint256).max);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, held, amount));
        token.transferFrom(alice, bob, amount);
        assertEq(token.balanceOf(alice), held);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_selfTransferNeverChangesBalance(uint256 held, uint256 amount) public {
        held = bound(held, 0, SUPPLY);
        vm.prank(deployer);
        token.transfer(alice, held);
        amount = bound(amount, 0, held);
        vm.prank(alice);
        token.transfer(alice, amount);
        assertEq(token.balanceOf(alice), held);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
