# Torch Chain (TCH)

A fixed-supply ERC-20 token for a custom token launch on Robinhood Chain (chain id 4663).

| Property | Value |
| --- | --- |
| Solidity contract | `TorchChain` (`src/TorchChain.sol`) |
| `name()` | `Torch Chain` |
| `symbol()` | `TCH` |
| `decimals()` | `18` |
| `totalSupply()` | `1,000,000,000 × 10^18` = `1000000000000000000000000000` minor units |
| Constructor arguments | none |
| Owner / admin | none |
| Compiler | solc `0.8.26`, optimizer on (200 runs), `bytecode_hash = "none"` |

## Behaviour

- The constructor mints the whole supply once to `msg.sender` and emits a single `Transfer(0x0, deployer, supply)`.
  At launch `msg.sender` is the launch factory, which then distributes the supply.
- The contract is OpenZeppelin `ERC20` v5.1.0 with nothing added: no mint, burn, pause, blocklist, fee,
  reflection, owner or upgrade path. `totalSupply` can never change after construction.
- Transfers move exactly the requested amount. `transfer`, `transferFrom` and `approve` return `true`
  on success and revert with the ERC-6093 custom errors (`ERC20InsufficientBalance`,
  `ERC20InsufficientAllowance`, `ERC20InvalidReceiver`, `ERC20InvalidSpender`) on failure.
- The runtime contains no `DELEGATECALL`, `CALLCODE` or `SELFDESTRUCT` and has no `receive`/`fallback`,
  so plain ETH sent to it is rejected.

## Assumptions

- "All minted once to the deployer" means `msg.sender` of the constructor. The factory deploys the
  token, so the factory receives the supply and pays it out (swarm share, pool seed, remainder). No
  address is hard-coded and no constructor argument is needed.
- No tax, burn-on-transfer or exemption logic was requested, so none exists. The three launch addresses
  (factory, pool manager, distributor) need no exemption because every transfer is already exact.
- Nothing in the brief called for an owner, so the contract has no `Ownable` and no privileged function.
  This is deliberate: it is the simplest way to satisfy the launch floor (no supply growth, no freeze,
  no seizure) and leaves no key to protect after launch.

## Deployment parameters

The launch is performed by IMD's deployer through the factory from the bytecode as built. These are
the values that launch uses; they are recorded by the separate manifest step, not by this repository.

| Parameter | Value |
| --- | --- |
| Chain | Robinhood Chain, chain id 4663 |
| Token contract | `TorchChain` |
| Constructor args | `[]` |
| Total supply (minor units) | `1000000000000000000000000000` |
| Decimals | `18` |
| Paired currency | IMD, `0x5f7bb59365ce557c26dbcaa4ee9d39a4b95b7127` |
| Pool fee | `12500` (1.25%) |
| Tick spacing | `60` |
| Pool share | `6000` bps (60% of supply seeds the pool) |
| Initial market cap | `1600000000000000000000` wei of IMD (1,600 IMD) |
| Remainder to | `0xf0cb4a38f195ed01c6442a69b6b7692941b67347` (30% of supply) |
| Swarm share | 10% of supply, forwarded by the factory to the MerkleDistributor |

Application contracts: none. This launch is the token alone.

`script/DeployTorchChain.s.sol` is a reviewable rehearsal script. Its `deploy()` function is what the
tests call; `run()` wraps it in a broadcast for a fork or test network. It is not how the production
launch happens and this repository holds no keys and broadcasts nothing.

## After launch

There is nothing to configure. The token has no owner-settable value, no setter and no admin role.

Operational responsibilities that remain with the requester:

- Verify the source on the chain explorer once the deployer publishes the address (`forge verify-contract`
  with the same compiler settings as `foundry.toml`).
- Keep custody of whatever receives the 30% remainder (`0xf0cb…7347`). The contract cannot recover
  tokens sent to a wrong address, and there is no admin to call.
- Treat any future change (vesting, taxes, governance) as a new contract: this one cannot be upgraded.

## Repository layout

```
foundry.toml                 compiler and project pins (solc 0.8.26, bytecode_hash none)
remappings.txt               forge-std/ and @openzeppelin/contracts/ → lib/
src/TorchChain.sol           the token
script/DeployTorchChain.s.sol rehearsal deploy script
test/TorchChain.t.sol        unit, failure and fuzz tests for the token
test/DeployTorchChain.t.sol  tests calling the script's deploy() directly
lib/forge-std/               forge-std v1.9.6, vendored as plain files
lib/openzeppelin-contracts/  the ERC20 subset of OpenZeppelin v5.1.0, vendored as plain files
```

Dependencies are committed as ordinary files (no git submodules) so the project builds offline.

## Checks

```
forge build
forge test
forge fmt --check
```

The fuzz tests were run with `FOUNDRY_FUZZ_SEED=0x150c2e8ed36c356256d6ad7adb69d41e15a110ee5957dfb28a68e3b642753791`.
Tests read no environment variables and do not depend on the calling address.

Tests passing are not a security audit. The token is unmodified OpenZeppelin ERC20, but an independent
review before launch is still the right practice for anything that will hold value.
