// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

struct TrapAlert {
    bytes32 invariantId;
    address target;
    uint256 observed;
    uint256 expected;
    uint256 blockNumber;
    bytes32 environmentId;
    bytes context;
}
