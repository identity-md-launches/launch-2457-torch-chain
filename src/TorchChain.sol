// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Torch Chain (TCH)
/// @notice A fixed-supply ERC-20. The whole supply is minted once, in the constructor, to the
///         deployer (`msg.sender`). There is no owner, no minter, no pause, no blocklist and no
///         transfer fee: after deployment the contract has no privileged function at all.
/// @dev Deployed through the launch factory, so `msg.sender` at construction is the factory, which
///      then distributes the supply (swarm share, pool seed, remainder). Nothing here can change
///      `totalSupply` afterwards: ERC-20 `_mint` is never reachable and no burn is exposed.
contract TorchChain is ERC20 {
    /// @notice Token name returned by `name()`.
    string public constant TOKEN_NAME = "Torch Chain";

    /// @notice Token symbol returned by `symbol()`.
    string public constant TOKEN_SYMBOL = "TCH";

    /// @notice Decimals returned by `decimals()` (the ERC-20 default).
    uint8 public constant TOKEN_DECIMALS = 18;

    /// @notice Whole-token supply before scaling by decimals: one billion.
    uint256 public constant SUPPLY_WHOLE_TOKENS = 1_000_000_000;

    /// @notice The fixed total supply in minor units: 1,000,000,000 * 10^18.
    uint256 public constant TOTAL_SUPPLY = SUPPLY_WHOLE_TOKENS * 10 ** TOKEN_DECIMALS;

    /// @notice Mints `TOTAL_SUPPLY` to the deployer. Takes no arguments and calls no other contract.
    constructor() ERC20(TOKEN_NAME, TOKEN_SYMBOL) {
        _mint(msg.sender, TOTAL_SUPPLY);
    }

    /// @inheritdoc ERC20
    function decimals() public pure override returns (uint8) {
        return TOKEN_DECIMALS;
    }
}
