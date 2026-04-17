// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ITrap} from "./ITrap.sol";
import {TrapAlert} from "./TrapTypes.sol";

interface IBonqDaoOracleManipulationTarget {
    function getMetrics() external view returns (uint256 reportedPrice, uint256 referencePrice, uint256 lastUpdate, uint256 aggregateCollateral, uint256 aggregateDebt, uint256 collateralRatio, uint256 blockNumber, bool paused);
}

contract BonqDaoOracleManipulationTrap is ITrap {
    address public constant TARGET = address(0x0000000000000000000000000000000000001001);
    bytes32 public constant INVARIANT_ID = keccak256("BONQ_ORACLE_COLLATERAL_DIVERGENCE");
    uint256 public constant REQUIRED_SAMPLES = 10;

    uint256 internal constant PRICE_DIVERGENCE_BPS = 5_000;
    uint256 internal constant MIN_COLLATERAL_RATIO = 15_000;

    struct CollectOutput {
    address target;
    uint256 reportedPrice;
    uint256 referencePrice;
    uint256 lastUpdate;
    uint256 aggregateCollateral;
    uint256 aggregateDebt;
    uint256 collateralRatio;
    uint256 blockNumber;
    bool paused;
    }

    function collect() external view returns (bytes memory) {
        if (TARGET.code.length == 0) {
            return abi.encode(CollectOutput({
                target: TARGET,
                reportedPrice: 100e18,
            referencePrice: 100e18,
            lastUpdate: 100,
            aggregateCollateral: 2_000_000e18,
            aggregateDebt: 800_000e18,
            collateralRatio: 25000,
                blockNumber: block.number,
                paused: false
            }));
        }
        try IBonqDaoOracleManipulationTarget(TARGET).getMetrics() returns (uint256 reportedPrice, uint256 referencePrice, uint256 lastUpdate, uint256 aggregateCollateral, uint256 aggregateDebt, uint256 collateralRatio, uint256 blockNumber, bool paused) {
            return abi.encode(CollectOutput({
                target: TARGET,
                reportedPrice: reportedPrice,
                referencePrice: referencePrice,
                lastUpdate: lastUpdate,
                aggregateCollateral: aggregateCollateral,
                aggregateDebt: aggregateDebt,
                collateralRatio: collateralRatio,
                blockNumber: blockNumber,
                paused: paused
            }));
        } catch {
            return abi.encode(CollectOutput({
                target: TARGET,
                reportedPrice: 100e18,
            referencePrice: 100e18,
            lastUpdate: 100,
            aggregateCollateral: 2_000_000e18,
            aggregateDebt: 800_000e18,
            collateralRatio: 25000,
                blockNumber: block.number,
                paused: false
            }));
        }
    }

    function shouldRespond(bytes[] calldata data) external pure returns (bool, bytes memory) {
        if (data.length < REQUIRED_SAMPLES) return (false, bytes(""));
        CollectOutput memory latest = abi.decode(data[0], (CollectOutput));
        CollectOutput memory oldest = abi.decode(data[data.length - 1], (CollectOutput));
        if (_divergence(latest.reportedPrice, latest.referencePrice) > PRICE_DIVERGENCE_BPS && latest.collateralRatio < MIN_COLLATERAL_RATIO) {
            TrapAlert memory alert = TrapAlert({
                invariantId: INVARIANT_ID,
                target: latest.target,
                observed: latest.collateralRatio,
                expected: MIN_COLLATERAL_RATIO,
                blockNumber: latest.blockNumber,
                context: abi.encode(latest.reportedPrice, latest.referencePrice, latest.lastUpdate, latest.aggregateCollateral, latest.aggregateDebt, latest.collateralRatio)
            });
            return (true, abi.encode(alert));
        }
        return (false, bytes(""));
    }

    function _divergence(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == b) return 0;
        uint256 high = a > b ? a : b;
        uint256 low = a > b ? b : a;
        return ((high - low) * 10_000) / low;
    }

}
