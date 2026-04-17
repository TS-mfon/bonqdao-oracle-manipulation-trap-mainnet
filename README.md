# BonqDAO Oracle Manipulation Trap (mainnet)

## What This Trap Is For

This repository is an executable Drosera-compatible PoC for `BONQ_ORACLE_COLLATERAL_DIVERGENCE`.

The trap monitors a configured environment registry, resolves the active monitored target, collects protocol metrics, and returns a structured `TrapAlert` when the invariant is broken. It is not a report or a diagram. The proof is the Foundry test suite:

- exploit path succeeds without the response;
- the same staged failure makes `shouldRespond()` return `true`;
- the returned bytes decode to `TrapAlert`;
- the response pauses the protected protocol path;
- the attacker balance remains zero after the response.

The response contract validates the Drosera caller, invariant id, environment id, monitored target, and configured response executor before calling the protocol emergency pause path.

## What Happened / What Went Wrong

BonqDAO-style oracle manipulation breaks the assumption that reported collateral price reflects an independent reference price. The dangerous transition is sustained price divergence combined with a collateral ratio below the safety floor. The mock stages oracle overpricing and undercollateralized aggregate debt, then attempts to withdraw bad debt value.

The proof follows this sequence:

- `stage...()` performs the dangerous state transition;
- `collect()` reads the protocol or adapter metrics;
- `shouldRespond()` detects the broken invariant over the sampled window;
- `handleIncident()` calls the predetermined emergency response;
- the exploit completion function reverts after the pause.

The comments in the Solidity tests map the exploit staging call to the trap invariant and then to the response call that neutralizes completion.

## Monitored Target

The trap does not read a bare `TARGET` constant. It reads an environment registry currently compiled as:

`0x0000000000000000000000000000000000003001`

The registry supplies:

- `environmentId`
- `monitoredTarget`
- `responseExecutor`
- `protocolGuardian`
- `active`

Before deploying for a real environment, replace the `REGISTRY` constant in:

- `src/BonqDaoOracleManipulationTrap.sol`
- `src/BonqDaoOracleManipulationResponse.sol`

Then rebuild and update `drosera.toml`.

## Metrics Assumed Trustworthy

The monitored target must expose:

```solidity
function getMetrics() external view returns (..., uint256 observedBlockNumber, bool paused);
```

The metrics must be produced by a protocol controller, adapter, or guardian module that reflects real protocol state. If the protected protocol does not expose these metrics naturally, deploy a monitoring adapter and point the registry at that adapter.

For this trap the collected fields are:

```text
- reportedPrice
- referencePrice
- lastUpdate
- aggregateCollateral
- aggregateDebt
- collateralRatio
```

## Trigger Logic

The trap requires `10` samples, newest first. It does not trigger on:

- missing registry;
- inactive registry;
- missing target;
- failed metrics call;
- invalid metrics;
- already paused target;
- insufficient samples.

It triggers only when the latest sample breaches the invariant and the recent sample window confirms persistent breach.

Invariant id:

```text
BONQ_ORACLE_COLLATERAL_DIVERGENCE_V2
```

Response action:

```text
freeze oracle-dependent trove updates and withdrawals
```

## Response

The response contract:

- requires caller `0x000000000000000000000000000000000000d0A0`;
- validates invariant id;
- validates registry exists and is active;
- validates `alert.environmentId`;
- validates `alert.target`;
- validates registry `responseExecutor == address(this)`;
- applies a 20 block cooldown;
- calls `emergencyPause()` on the monitored target.

The response function signature in Drosera must stay exactly:

```text
handleIncident((bytes32,address,uint256,uint256,uint256,bytes32,bytes))
```

## Deployment Wiring

1. Deploy token/mock protocol/attacker/response/registry for Hoodi simulation, or deploy the response and registry for mainnet/adapter use.
2. Configure the protocol emergency module to the response contract.
3. Configure the registry:
   - `environmentId`
   - `monitoredTarget`
   - `responseExecutor`
   - `protocolGuardian`
   - `active = true`
4. Replace the trap `REGISTRY` constant with the deployed registry address.
5. Rebuild with `forge build`.
6. Put the deployed response address in `drosera.toml`:

```toml
response_contract = "0xYOUR_DEPLOYED_RESPONSE"
response_function = "handleIncident((bytes32,address,uint256,uint256,uint256,bytes32,bytes))"
```

Also confirm the Drosera executor caller in `src/BonqDaoOracleManipulationResponse.sol`:

```solidity
address public constant DROSERA_PROTOCOL = 0x000000000000000000000000000000000000d0A0;
```

If your Drosera environment uses a different executor address, replace it before deployment.

## Hoodi Simulation Deployment

This mainnet repository is configured for real-target or adapter wiring. It intentionally does not deploy mocks.

For Hoodi mocks:

```bash
forge script script/DeployHoodiSimulation.s.sol:DeployHoodiSimulation \
  --rpc-url https://ethereum-hoodi-rpc.publicnode.com \
  --private-key $HOODI_PRIVATE_KEY \
  --broadcast
```

After deployment:

- copy the deployed response address into `drosera.toml`;
- copy the deployed registry address into the trap and response constants;
- rebuild with `forge build`;
- run `drosera dryrun`.

For mainnet:

- do not deploy the mocks;
- deploy or reuse a monitoring adapter exposing `getMetrics()`;
- deploy the registry and response;
- point the registry at the adapter or protected controller;
- replace the registry and response addresses before applying the trap.

## Drosera MCP Inputs

- `generate-trap`
- `drosera://trappers/creating-a-trap`
- `drosera://trappers/dryrunning-a-trap`
- `drosera://trappers/drosera-cli`
- `drosera://operators/executing-traps`
- `drosera://deployments`

## Commands

```bash
forge test
forge build
drosera dryrun
```

## Test Coverage

The test suite covers:

- healthy windows do not trigger;
- insufficient windows do not trigger;
- staged exploit windows trigger;
- returned alert payload decodes to the expected invariant/environment;
- non-Drosera callers cannot execute the response;
- wrong environment alerts are rejected;
- the response pause blocks exploit completion;
- attacker extracted balance remains zero after containment;
- fuzzed healthy baselines do not false-trigger.

## Limits

- This PoC proves the invariant and response mechanics. It does not claim the mock is byte-for-byte identical to the historical protocol.
- For a real deployment, the registry must point at a real protocol controller or a monitoring adapter with trustworthy metrics.
- Thresholds should be backtested against normal and stressed non-attack windows before production use.
- A wrong registry address, wrong response address, or wrong Drosera executor address will prevent containment even if the trap logic is correct.
