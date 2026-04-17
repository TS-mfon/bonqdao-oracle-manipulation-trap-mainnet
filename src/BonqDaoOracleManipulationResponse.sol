// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {TrapAlert} from "./TrapTypes.sol";

interface IBonqDaoOracleManipulationEnvironmentRegistryResponseView {
    function environmentId() external view returns (bytes32);
    function monitoredTarget() external view returns (address);
    function responseExecutor() external view returns (address);
    function active() external view returns (bool);
}

contract BonqDaoOracleManipulationResponse {
    address public immutable REGISTRY;
    address public constant DROSERA_PROTOCOL = address(0x000000000000000000000000000000000000d0A0);
    bytes32 public constant INVARIANT_ID = keccak256("BONQ_ORACLE_COLLATERAL_DIVERGENCE_V2");
    uint256 public constant COOLDOWN_BLOCKS = 20;

    bool public incidentHandled;
    uint256 public lastHandledBlock;
    TrapAlert public lastAlert;

    event IncidentHandled(bytes32 indexed invariantId, bytes32 indexed environmentId, address indexed target, uint256 observed, uint256 expected, uint256 blockNumber);
    event PauseAttempted(address indexed target, bool success, bytes returnData);

    error NotDrosera();
    error RegistryMissing();
    error RegistryInactive();
    error WrongInvariant();
    error WrongEnvironment();
    error WrongTarget();
    error WrongResponseExecutor();
    error CooldownActive();

    constructor(address registry_) {
        REGISTRY = registry_;
    }

    function handleIncident(TrapAlert calldata alert) external {
        if (msg.sender != DROSERA_PROTOCOL) revert NotDrosera();
        if (alert.invariantId != INVARIANT_ID) revert WrongInvariant();
        if (REGISTRY.code.length == 0) revert RegistryMissing();
        IBonqDaoOracleManipulationEnvironmentRegistryResponseView registry = IBonqDaoOracleManipulationEnvironmentRegistryResponseView(REGISTRY);
        if (!registry.active()) revert RegistryInactive();
        if (registry.environmentId() != alert.environmentId) revert WrongEnvironment();
        if (registry.monitoredTarget() != alert.target) revert WrongTarget();
        if (registry.responseExecutor() != address(this)) revert WrongResponseExecutor();
        if (lastHandledBlock != 0 && block.number < lastHandledBlock + COOLDOWN_BLOCKS) revert CooldownActive();
        incidentHandled = true;
        lastHandledBlock = block.number;
        lastAlert = alert;
        (bool success, bytes memory returnData) = alert.target.call(abi.encodeWithSignature("emergencyPause()"));
        emit PauseAttempted(alert.target, success, returnData);
        emit IncidentHandled(alert.invariantId, alert.environmentId, alert.target, alert.observed, alert.expected, alert.blockNumber);
    }
}
