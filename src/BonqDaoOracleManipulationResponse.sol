// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {TrapAlert} from "./TrapTypes.sol";

interface IPausableProtocol {
    function pauseAll() external;
}

contract BonqDaoOracleManipulationResponse {
    address public constant DROSERA_PROTOCOL = address(0x000000000000000000000000000000000000d0A0);
    address public constant TARGET = address(0x0000000000000000000000000000000000001001);
    bytes32 public constant INVARIANT_ID = keccak256("BONQ_ORACLE_COLLATERAL_DIVERGENCE");
    bool public incidentHandled;
    TrapAlert public lastAlert;

    event IncidentHandled(bytes32 indexed invariantId, address indexed target, uint256 observed, uint256 expected);

    error NotDrosera();
    error WrongInvariant();

    function handleIncident(TrapAlert calldata alert) external {
        if (msg.sender != DROSERA_PROTOCOL) revert NotDrosera();
        if (alert.invariantId != INVARIANT_ID) revert WrongInvariant();
        incidentHandled = true;
        lastAlert = alert;
        if (TARGET.code.length > 0) {
            IPausableProtocol(TARGET).pauseAll();
        }
        emit IncidentHandled(alert.invariantId, alert.target, alert.observed, alert.expected);
    }
}
