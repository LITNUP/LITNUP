// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

/// @title LITNUPTimelock
/// @notice Governance execution timelock. All sensitive on-chain actions
///         (signer set rotation, parameter changes, treasury movements) flow through here
///         after a delay, giving stakers time to exit if a malicious proposal lands.
///
///         At v1 launch:
///         - Proposers: governance contract (after veLITNUP is live)
///         - Executors: open (anyone can execute after delay) — saves gas, no security cost since timelock has already passed
///         - Min delay: 48 hours initially; raisable by governance to 14 days for Critical params
///
///         This is a thin wrapper around OpenZeppelin's audited TimelockController
///         to give it a project-specific name in our deployments.
contract LITNUPTimelock is TimelockController {
    constructor(
        uint256 minDelay,
        address[] memory proposers,
        address[] memory executors,
        address admin
    ) TimelockController(minDelay, proposers, executors, admin) {}
}
