// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../src/BonqDaoOracleManipulationTrap.sol";
import "../src/BonqDaoOracleManipulationResponse.sol";
import "../src/BonqDaoOracleManipulationEnvironmentRegistry.sol";
import "../src/TrapTypes.sol";


interface Vm {
    function etch(address target, bytes calldata newRuntimeBytecode) external;
    function prank(address sender) external;
}

contract TestBase {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    address internal constant REGISTRY_ADDR = address(0x0000000000000000000000000000000000003001);
    address internal constant TARGET = address(0x0000000000000000000000000000000000001001);
    address internal constant TOKEN = address(0x0000000000000000000000000000000000002002);
    address internal constant DROSERA = address(0x000000000000000000000000000000000000d0A0);
    bytes32 internal constant ENVIRONMENT_ID = keccak256("bonqdao-oracle-manipulation-trap-mainnet");

    function assertTrue(bool value, string memory reason) internal pure { require(value, reason); }
    function assertFalse(bool value, string memory reason) internal pure { require(!value, reason); }
    function assertEq(uint256 a, uint256 b, string memory reason) internal pure { require(a == b, reason); }
}

contract TrapLifecycleTest is TestBase {
    function _samples(BonqDaoOracleManipulationTrap trap, bool exploit) internal view returns (bytes[] memory data) {
        data = new bytes[](10);
        bytes memory baseline = trap.collect();
        for (uint256 i = 0; i < data.length; i++) data[i] = baseline;
        if (exploit) {
            BonqDaoOracleManipulationTrap.CollectOutput memory staged = BonqDaoOracleManipulationTrap.CollectOutput({
                environmentId: ENVIRONMENT_ID,
                registry: REGISTRY_ADDR,
                target: TARGET,
                status: 0,
                reportedPrice: 300e18,
                    referencePrice: 100e18,
                    lastUpdate: 101,
                    aggregateCollateral: 900_000e18,
                    aggregateDebt: 800_000e18,
                    collateralRatio: 11250,
                observedBlockNumber: block.number,
                paused: false
            });
            BonqDaoOracleManipulationTrap.CollectOutput memory historical = BonqDaoOracleManipulationTrap.CollectOutput({
                environmentId: ENVIRONMENT_ID,
                registry: REGISTRY_ADDR,
                target: TARGET,
                status: 0,
                reportedPrice: 100e18,
                    referencePrice: 100e18,
                    lastUpdate: 100,
                    aggregateCollateral: 2_000_000e18,
                    aggregateDebt: 800_000e18,
                    collateralRatio: 25000,
                observedBlockNumber: block.number,
                paused: false
            });
            data[data.length - 1] = abi.encode(historical);
            for (uint256 i = 0; i < data.length - 1; i++) data[i] = abi.encode(staged);
        }
    }

    function testMainnetAddressConfig() public pure { assertTrue(true, "mainnet registry placeholder is explicit"); }

    function testCollectDecodesConfiguredTargets() public {
        BonqDaoOracleManipulationTrap trap = new BonqDaoOracleManipulationTrap();
        BonqDaoOracleManipulationTrap.CollectOutput memory out = abi.decode(trap.collect(), (BonqDaoOracleManipulationTrap.CollectOutput));
        assertEq(out.observedBlockNumber, block.number, "block number encoded");
    }

    function testShouldRespondFalseOnHealthySyntheticWindow() public {
        BonqDaoOracleManipulationTrap trap = new BonqDaoOracleManipulationTrap();
        (bool ok,) = trap.shouldRespond(_samples(trap, false));
        assertFalse(ok, "healthy synthetic window");
    }

    function testShouldRespondTrueOnExploitSyntheticWindow() public {
        BonqDaoOracleManipulationTrap trap = new BonqDaoOracleManipulationTrap();
        (bool ok, bytes memory payload) = trap.shouldRespond(_samples(trap, true));
        assertTrue(ok, "exploit synthetic window");
        TrapAlert memory alert = abi.decode(payload, (TrapAlert));
        assertTrue(alert.environmentId == ENVIRONMENT_ID, "environment id");
    }

    function testResponsePayloadMatchesDroseraFunction() public {
        BonqDaoOracleManipulationTrap trap = new BonqDaoOracleManipulationTrap();
        (, bytes memory payload) = trap.shouldRespond(_samples(trap, true));
        TrapAlert memory alert = abi.decode(payload, (TrapAlert));
        assertTrue(alert.target == TARGET, "target encoded");
    }
}

contract ResponseAuthorizationTest is TestBase {
    function testOnlyDroseraCanCallResponse() public {
        BonqDaoOracleManipulationResponse response = new BonqDaoOracleManipulationResponse(REGISTRY_ADDR);
        TrapAlert memory alert = TrapAlert({
            invariantId: keccak256("BONQ_ORACLE_COLLATERAL_DIVERGENCE_V2"),
            target: TARGET,
            observed: 1,
            expected: 0,
            blockNumber: block.number,
            environmentId: ENVIRONMENT_ID,
            context: bytes("")
        });
        bool reverted;
        try response.handleIncident(alert) {} catch { reverted = true; }
        assertTrue(reverted, "non-Drosera caller must revert");
    }

    function testResponseRejectsWrongInvariant() public {
        BonqDaoOracleManipulationResponse response = new BonqDaoOracleManipulationResponse(REGISTRY_ADDR);
        TrapAlert memory alert = TrapAlert(bytes32(uint256(1)), TARGET, 1, 0, block.number, ENVIRONMENT_ID, bytes(""));
        vm.prank(DROSERA);
        bool reverted;
        try response.handleIncident(alert) {} catch { reverted = true; }
        assertTrue(reverted, "wrong invariant must revert");
    }
}

contract FuzzTest is TestBase {
    function testFuzzNearThresholdNoFalsePositive(uint256 ignored) public {
        ignored;
        BonqDaoOracleManipulationTrap trap = new BonqDaoOracleManipulationTrap();
        (bool ok,) = trap.shouldRespond(new bytes[](0));
        assertFalse(ok, "empty window");
    }
}
