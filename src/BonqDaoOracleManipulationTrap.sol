// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ITrap} from "./ITrap.sol";
import {TrapAlert} from "./TrapTypes.sol";

interface IBonqDaoOracleManipulationEnvironmentRegistryView {
    function environmentId() external view returns (bytes32);
    function monitoredTarget() external view returns (address);
    function active() external view returns (bool);
}

interface IBonqDaoOracleManipulationTarget {
    function getMetrics() external view returns (uint256 reportedPrice, uint256 referencePrice, uint256 lastUpdate, uint256 aggregateCollateral, uint256 aggregateDebt, uint256 collateralRatio, uint256 observedBlockNumber, bool paused);
}

contract BonqDaoOracleManipulationTrap is ITrap {
    address public constant REGISTRY = address(0x0000000000000000000000000000000000003001);
    bytes32 public constant INVARIANT_ID = keccak256("BONQ_ORACLE_COLLATERAL_DIVERGENCE_V2");
    uint256 public constant REQUIRED_SAMPLES = 10;
    uint8 internal constant STATUS_OK = 0;
    uint8 internal constant STATUS_REGISTRY_INACTIVE = 1;
    uint8 internal constant STATUS_TARGET_MISSING = 2;
    uint8 internal constant STATUS_METRICS_CALL_FAILED = 3;
    uint8 internal constant STATUS_INVALID_METRICS = 4;
    uint256 internal constant BREACH_WINDOW = 5;
    uint256 internal constant MIN_BREACH_COUNT = 2;
    uint256 internal constant PRICE_DIVERGENCE_BPS = 5_000;
    uint256 internal constant MIN_COLLATERAL_RATIO = 15_000;

    struct CollectOutput {
        bytes32 environmentId;
        address registry;
        address target;
        uint8 status;
        uint256 reportedPrice;
        uint256 referencePrice;
        uint256 lastUpdate;
        uint256 aggregateCollateral;
        uint256 aggregateDebt;
        uint256 collateralRatio;
        uint256 observedBlockNumber;
        bool paused;
    }

    function collect() external view returns (bytes memory) {
        if (REGISTRY.code.length == 0) {
            return _status(bytes32(0), address(0), STATUS_REGISTRY_INACTIVE);
        }

        IBonqDaoOracleManipulationEnvironmentRegistryView registry = IBonqDaoOracleManipulationEnvironmentRegistryView(REGISTRY);
        bytes32 environmentId = registry.environmentId();
        address target = registry.monitoredTarget();
        if (!registry.active()) return _status(environmentId, target, STATUS_REGISTRY_INACTIVE);
        if (target.code.length == 0) return _status(environmentId, target, STATUS_TARGET_MISSING);

        try IBonqDaoOracleManipulationTarget(target).getMetrics() returns (uint256 reportedPrice, uint256 referencePrice, uint256 lastUpdate, uint256 aggregateCollateral, uint256 aggregateDebt, uint256 collateralRatio, uint256 observedBlockNumber, bool paused) {
            if (observedBlockNumber == 0 || paused) {
                return abi.encode(CollectOutput({
                    environmentId: environmentId,
                    registry: REGISTRY,
                    target: target,
                    status: paused ? STATUS_OK : STATUS_INVALID_METRICS,
                    reportedPrice: reportedPrice,
                    referencePrice: referencePrice,
                    lastUpdate: lastUpdate,
                    aggregateCollateral: aggregateCollateral,
                    aggregateDebt: aggregateDebt,
                    collateralRatio: collateralRatio,
                    observedBlockNumber: observedBlockNumber == 0 ? block.number : observedBlockNumber,
                    paused: paused
                }));
            }
            return abi.encode(CollectOutput({
                environmentId: environmentId,
                registry: REGISTRY,
                target: target,
                status: STATUS_OK,
                reportedPrice: reportedPrice,
                    referencePrice: referencePrice,
                    lastUpdate: lastUpdate,
                    aggregateCollateral: aggregateCollateral,
                    aggregateDebt: aggregateDebt,
                    collateralRatio: collateralRatio,
                observedBlockNumber: observedBlockNumber,
                paused: paused
            }));
        } catch {
            return _status(environmentId, target, STATUS_METRICS_CALL_FAILED);
        }
    }

    function shouldRespond(bytes[] calldata data) external pure returns (bool, bytes memory) {
        if (data.length < REQUIRED_SAMPLES) return (false, bytes(""));
        CollectOutput memory latest = abi.decode(data[0], (CollectOutput));
        CollectOutput memory historical = abi.decode(data[data.length - 1], (CollectOutput));
        if (latest.status != STATUS_OK || latest.paused) return (false, bytes(""));
        if (historical.status != STATUS_OK || historical.environmentId != latest.environmentId || historical.target != latest.target) {
            return (false, bytes(""));
        }

        bool latestBreached = (_divergence(latest.reportedPrice, latest.referencePrice) > PRICE_DIVERGENCE_BPS && latest.collateralRatio < MIN_COLLATERAL_RATIO);
        if (!latestBreached) return (false, bytes(""));

        uint256 checked = data.length < BREACH_WINDOW ? data.length : BREACH_WINDOW;
        uint256 breachCount;
        for (uint256 i = 0; i < checked; i++) {
            CollectOutput memory sample = abi.decode(data[i], (CollectOutput));
            if (sample.status != STATUS_OK || sample.paused || sample.target != latest.target) continue;
            if (sample.observedBlockNumber >= historical.observedBlockNumber) {
                if (_divergence(sample.reportedPrice, sample.referencePrice) > PRICE_DIVERGENCE_BPS && sample.collateralRatio < MIN_COLLATERAL_RATIO) breachCount++;
            }
        }

        uint256 deteriorationSignals;
        if (latest.observedBlockNumber >= historical.observedBlockNumber) deteriorationSignals++;
        if (latest.target == historical.target) deteriorationSignals++;

        if (breachCount < MIN_BREACH_COUNT || deteriorationSignals < 2) return (false, bytes(""));

        TrapAlert memory alert = TrapAlert({
            invariantId: INVARIANT_ID,
            target: latest.target,
            observed: latest.collateralRatio,
            expected: MIN_COLLATERAL_RATIO,
            blockNumber: latest.observedBlockNumber,
            environmentId: latest.environmentId,
            context: abi.encode(latest.registry, latest.status, latest.reportedPrice, latest.referencePrice, latest.lastUpdate, latest.aggregateCollateral, latest.aggregateDebt, latest.collateralRatio, breachCount, deteriorationSignals)
        });
        return (true, abi.encode(alert));
    }

    function _status(bytes32 environmentId, address target, uint8 status) internal view returns (bytes memory) {
        return abi.encode(CollectOutput({
            environmentId: environmentId,
            registry: REGISTRY,
            target: target,
            status: status,
            reportedPrice: 100e18,
                    referencePrice: 100e18,
                    lastUpdate: 100,
                    aggregateCollateral: 2_000_000e18,
                    aggregateDebt: 800_000e18,
                    collateralRatio: 25000,
            observedBlockNumber: block.number,
            paused: false
        }));
    }

    function _divergence(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == b) return 0;
        if (a == 0 || b == 0) return type(uint256).max;
        uint256 high = a > b ? a : b;
        uint256 low = a > b ? b : a;
        return ((high - low) * 10_000) / low;
    }

}
