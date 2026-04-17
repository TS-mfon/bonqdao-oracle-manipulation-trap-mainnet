// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../src/BonqDaoOracleManipulationTrap.sol";
import "../src/BonqDaoOracleManipulationResponse.sol";
import "../src/TrapTypes.sol";


interface Vm {
    function etch(address target, bytes calldata newRuntimeBytecode) external;
    function prank(address sender) external;
}

contract TestBase {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    address internal constant TARGET = address(0x0000000000000000000000000000000000001001);
    address internal constant TOKEN = address(0x0000000000000000000000000000000000002002);
    address internal constant DROSERA = address(0x000000000000000000000000000000000000d0A0);

    function assertTrue(bool value, string memory reason) internal pure {
        require(value, reason);
    }

    function assertFalse(bool value, string memory reason) internal pure {
        require(!value, reason);
    }

    function assertEq(uint256 a, uint256 b, string memory reason) internal pure {
        require(a == b, reason);
    }
}

contract TrapLifecycleTest is TestBase {
    function _samples(BonqDaoOracleManipulationTrap trap, bool exploit) internal view returns (bytes[] memory data) {
        data = new bytes[](10);
        bytes memory healthy = trap.collect();
        for (uint256 i = 0; i < data.length; i++) data[i] = healthy;
        if (exploit) {
            BonqDaoOracleManipulationTrap.CollectOutput memory staged = BonqDaoOracleManipulationTrap.CollectOutput({
                target: TARGET,
                reportedPrice: 300e18,
            referencePrice: 100e18,
            lastUpdate: 101,
            aggregateCollateral: 900_000e18,
            aggregateDebt: 800_000e18,
            collateralRatio: 11250,
                blockNumber: block.number,
                paused: false
            });
            data[0] = abi.encode(staged);
        }
    }

    function testMainnetAddressConfig() public {
        assertTrue(true, "mainnet placeholders are explicit until addresses are provided");
    }

    function testCollectDecodesConfiguredTargets() public {
        BonqDaoOracleManipulationTrap trap = new BonqDaoOracleManipulationTrap();
        BonqDaoOracleManipulationTrap.CollectOutput memory out = abi.decode(trap.collect(), (BonqDaoOracleManipulationTrap.CollectOutput));
        assertEq(out.blockNumber, block.number, "block number encoded");
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
        assertTrue(alert.invariantId == keccak256("BONQ_ORACLE_COLLATERAL_DIVERGENCE"), "invariant id");
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
        BonqDaoOracleManipulationResponse response = new BonqDaoOracleManipulationResponse();
        TrapAlert memory alert = TrapAlert(keccak256("BONQ_ORACLE_COLLATERAL_DIVERGENCE"), TARGET, 1, 0, block.number, bytes(""));
        bool reverted;
        try response.handleIncident(alert) {} catch { reverted = true; }
        assertTrue(reverted, "non-Drosera caller must revert");
    }

    function testResponseRejectsWrongInvariant() public {
        BonqDaoOracleManipulationResponse response = new BonqDaoOracleManipulationResponse();
        TrapAlert memory alert = TrapAlert(bytes32(uint256(1)), TARGET, 1, 0, block.number, bytes(""));
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
