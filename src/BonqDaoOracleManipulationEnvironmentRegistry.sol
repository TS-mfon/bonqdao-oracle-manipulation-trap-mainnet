// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract BonqDaoOracleManipulationEnvironmentRegistry {
    address public owner;
    bytes32 public environmentId;
    address public monitoredTarget;
    address public responseExecutor;
    address public protocolGuardian;
    bool public active;

    event RegistryConfigured(bytes32 indexed environmentId, address indexed monitoredTarget, address indexed responseExecutor, address protocolGuardian, bool active);
    error NotOwner();
    error ZeroAddress();

    constructor(bytes32 environmentId_, address monitoredTarget_, address responseExecutor_, address protocolGuardian_, bool active_) {
        owner = msg.sender;
        _setConfig(environmentId_, monitoredTarget_, responseExecutor_, protocolGuardian_, active_);
    }

    function setConfig(bytes32 environmentId_, address monitoredTarget_, address responseExecutor_, address protocolGuardian_, bool active_) external {
        if (owner == address(0)) {
            owner = msg.sender;
        } else if (msg.sender != owner) {
            revert NotOwner();
        }
        _setConfig(environmentId_, monitoredTarget_, responseExecutor_, protocolGuardian_, active_);
    }

    function _setConfig(bytes32 environmentId_, address monitoredTarget_, address responseExecutor_, address protocolGuardian_, bool active_) internal {
        if (monitoredTarget_ == address(0) || responseExecutor_ == address(0) || protocolGuardian_ == address(0)) revert ZeroAddress();
        environmentId = environmentId_;
        monitoredTarget = monitoredTarget_;
        responseExecutor = responseExecutor_;
        protocolGuardian = protocolGuardian_;
        active = active_;
        emit RegistryConfigured(environmentId_, monitoredTarget_, responseExecutor_, protocolGuardian_, active_);
    }
}
