// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {TorchChain} from "../src/TorchChain.sol";

/// @notice Drives the token with random, bounded calls from several actors and keeps an independent
///         model (ghost balances and allowances) of what the token should hold. Calls that must fail
///         are made too, and a call that succeeds where it should revert, or reverts where it should
///         succeed, is counted in `violations`, which the invariants require to stay zero.
contract TorchChainHandler is Test {
    TorchChain public immutable token;
    address[] internal actors;

    // ── ghost model ──
    mapping(address => uint256) public ghostBalance;
    mapping(address => mapping(address => uint256)) public ghostAllowance;
    uint256 public violations;

    // ── call counters, so a run that did nothing is visible ──
    uint256 public transfers;
    uint256 public transferFroms;
    uint256 public approvals;
    uint256 public expectedReverts;

    constructor(TorchChain token_, address[] memory actors_) {
        token = token_;
        actors = actors_;
        for (uint256 i; i < actors_.length; ++i) {
            ghostBalance[actors_[i]] = token_.balanceOf(actors_[i]);
        }
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    function actorAt(uint256 i) external view returns (address) {
        return actors[i];
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    // ───────────────────────── calls that must succeed ─────────────────────────

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        amount = bound(amount, 0, ghostBalance[from]);

        vm.prank(from);
        try token.transfer(to, amount) returns (bool ok) {
            if (!ok) violations++;
            ghostBalance[from] -= amount;
            ghostBalance[to] += amount;
            transfers++;
        } catch {
            violations++;
        }
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount, bool unlimited) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        if (unlimited) amount = type(uint256).max;

        vm.prank(owner);
        try token.approve(spender, amount) returns (bool ok) {
            if (!ok) violations++;
            ghostAllowance[owner][spender] = amount;
            approvals++;
        } catch {
            violations++;
        }
    }

    function transferFrom(uint256 spenderSeed, uint256 ownerSeed, uint256 toSeed, uint256 amount) external {
        address spender = _actor(spenderSeed);
        address owner = _actor(ownerSeed);
        address to = _actor(toSeed);
        uint256 allowed = ghostAllowance[owner][spender];
        uint256 cap = ghostBalance[owner] < allowed ? ghostBalance[owner] : allowed;
        amount = bound(amount, 0, cap);

        vm.prank(spender);
        try token.transferFrom(owner, to, amount) returns (bool ok) {
            if (!ok) violations++;
            if (allowed != type(uint256).max) ghostAllowance[owner][spender] = allowed - amount;
            ghostBalance[owner] -= amount;
            ghostBalance[to] += amount;
            transferFroms++;
        } catch {
            violations++;
        }
    }

    // ───────────────────────── calls that must fail ─────────────────────────

    function transferMoreThanBalance(uint256 fromSeed, uint256 toSeed, uint256 excess) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 held = ghostBalance[from];
        uint256 amount = held + bound(excess, 1, type(uint256).max - held);

        vm.prank(from);
        try token.transfer(to, amount) {
            violations++;
        } catch (bytes memory reason) {
            _expect(reason, abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, held, amount));
        }
    }

    function transferToZero(uint256 fromSeed, uint256 amount) external {
        address from = _actor(fromSeed);
        amount = bound(amount, 0, ghostBalance[from]);

        vm.prank(from);
        try token.transfer(address(0), amount) {
            violations++;
        } catch (bytes memory reason) {
            _expect(reason, abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        }
    }

    function transferFromMoreThanAllowance(uint256 spenderSeed, uint256 ownerSeed, uint256 toSeed, uint256 excess)
        external
    {
        address spender = _actor(spenderSeed);
        address owner = _actor(ownerSeed);
        address to = _actor(toSeed);
        uint256 allowed = ghostAllowance[owner][spender];
        if (allowed == type(uint256).max) return; // unlimited: no amount exceeds it
        uint256 amount = allowed + bound(excess, 1, type(uint256).max - allowed);

        vm.prank(spender);
        try token.transferFrom(owner, to, amount) {
            violations++;
        } catch (bytes memory reason) {
            _expect(
                reason,
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, amount)
            );
        }
    }

    function transferFromMoreThanBalance(uint256 spenderSeed, uint256 ownerSeed, uint256 toSeed, uint256 excess)
        external
    {
        address spender = _actor(spenderSeed);
        address owner = _actor(ownerSeed);
        address to = _actor(toSeed);
        uint256 allowed = ghostAllowance[owner][spender];
        uint256 held = ghostBalance[owner];
        if (allowed <= held) return; // the allowance check would fire first
        uint256 amount = held + bound(excess, 1, allowed - held);

        vm.prank(spender);
        try token.transferFrom(owner, to, amount) {
            violations++;
        } catch (bytes memory reason) {
            _expect(reason, abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, held, amount));
        }
    }

    function approveZeroSpender(uint256 ownerSeed, uint256 amount) external {
        address owner = _actor(ownerSeed);
        vm.prank(owner);
        try token.approve(address(0), amount) {
            violations++;
        } catch (bytes memory reason) {
            _expect(reason, abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        }
    }

    function _expect(bytes memory reason, bytes memory expected) internal {
        if (keccak256(reason) != keccak256(expected)) violations++;
        expectedReverts++;
    }
}

contract TorchChainInvariantTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;

    TorchChain internal token;
    TorchChainHandler internal handler;
    address internal deployer = makeAddr("deployer");

    function setUp() public {
        vm.prank(deployer);
        token = new TorchChain();

        address[] memory actors = new address[](6);
        actors[0] = deployer;
        actors[1] = makeAddr("alice");
        actors[2] = makeAddr("bob");
        actors[3] = makeAddr("carol");
        actors[4] = makeAddr("dave");
        // Tokens sent to the token contract itself are stuck, but must still be counted.
        actors[5] = address(token);

        handler = new TorchChainHandler(token, actors);
        targetContract(address(handler));
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_totalSupplyNeverChanges() public view {
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.totalSupply(), token.TOTAL_SUPPLY());
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_balancesSumToSupply() public view {
        uint256 sum;
        for (uint256 i; i < handler.actorCount(); ++i) {
            sum += token.balanceOf(handler.actorAt(i));
        }
        assertEq(sum, token.totalSupply());
        assertEq(token.balanceOf(address(0)), 0);
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_balancesMatchModel() public view {
        for (uint256 i; i < handler.actorCount(); ++i) {
            address a = handler.actorAt(i);
            assertEq(token.balanceOf(a), handler.ghostBalance(a));
        }
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_allowancesMatchModel() public view {
        uint256 n = handler.actorCount();
        for (uint256 i; i < n; ++i) {
            for (uint256 j; j < n; ++j) {
                address o = handler.actorAt(i);
                address s = handler.actorAt(j);
                assertEq(token.allowance(o, s), handler.ghostAllowance(o, s));
            }
        }
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_everyCallBehavedAsSpecified() public view {
        assertEq(handler.violations(), 0);
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_tokenHoldsNoEther() public view {
        assertEq(address(token).balance, 0);
    }
}
