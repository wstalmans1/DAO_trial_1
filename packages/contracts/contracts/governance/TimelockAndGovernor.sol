// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {TimelockControllerUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/TimelockControllerUpgradeable.sol";
import {GovernorUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/GovernorUpgradeable.sol";
import {GovernorSettingsUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorSettingsUpgradeable.sol";
import {GovernorCountingSimpleUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorCountingSimpleUpgradeable.sol";
import {GovernorVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorVotesUpgradeable.sol";
import {GovernorVotesQuorumFractionUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorVotesQuorumFractionUpgradeable.sol";
import {GovernorTimelockControlUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorTimelockControlUpgradeable.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";

contract TimelockControllerImpl is Initializable, UUPSUpgradeable, OwnableUpgradeable, TimelockControllerUpgradeable {
    address public kernel;

    event KernelSet(address indexed kernel);

    function initialize(
        uint256 minDelay,
        address[] memory proposers,
        address[] memory executors,
        address admin
    ) public override(TimelockControllerUpgradeable) initializer {
        __Ownable_init(admin);
        __UUPSUpgradeable_init();
        __TimelockController_init(minDelay, proposers, executors, admin);
    }

    function setKernel(address newKernel) external onlyOwner {
        require(newKernel != address(0), "Timelock: kernel zero");
        kernel = newKernel;
        emit KernelSet(newKernel);
    }

    function moduleVersion() external pure returns (string memory) {
        return "timelock-1.0.0";
    }

    function _authorizeUpgrade(address) internal view override {
        if (msg.sender != owner() && msg.sender != kernel) {
            revert("Timelock: not authorized");
        }
    }
}

contract DAOGovernorImpl is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    GovernorUpgradeable,
    GovernorSettingsUpgradeable,
    GovernorCountingSimpleUpgradeable,
    GovernorVotesUpgradeable,
    GovernorVotesQuorumFractionUpgradeable,
    GovernorTimelockControlUpgradeable
{
    address public kernel;

    event KernelSet(address indexed kernel);

    function initialize(
        address admin,
        IVotes votesAdapter,
        TimelockControllerUpgradeable timelock
    ) public initializer {
        __Ownable_init(admin);
        __UUPSUpgradeable_init();
        __Governor_init("DAOGovernor");
        // 15-block voting window (~3 minutes on Sepolia/Hardhat)
        __GovernorSettings_init(1, 15, 0);
        __GovernorCountingSimple_init();
        __GovernorVotes_init(votesAdapter);
        __GovernorVotesQuorumFraction_init(4);
        __GovernorTimelockControl_init(timelock);
    }

    function setKernel(address newKernel) external onlyOwner {
        require(newKernel != address(0), "Governor: kernel zero");
        kernel = newKernel;
        emit KernelSet(newKernel);
    }

    // --- Overrides required by Solidity ---

    function quorum(uint256 timepoint)
        public
        view
        override(GovernorUpgradeable, GovernorVotesQuorumFractionUpgradeable)
        returns (uint256)
    {
        return super.quorum(timepoint);
    }

    function proposalThreshold()
        public
        view
        override(GovernorUpgradeable, GovernorSettingsUpgradeable)
        returns (uint256)
    {
        return super.proposalThreshold();
    }

    function proposalNeedsQueuing(uint256 proposalId)
        public
        view
        override(GovernorUpgradeable, GovernorTimelockControlUpgradeable)
        returns (bool)
    {
        return super.proposalNeedsQueuing(proposalId);
    }

    function state(uint256 proposalId)
        public
        view
        override(GovernorUpgradeable, GovernorTimelockControlUpgradeable)
        returns (ProposalState)
    {
        return super.state(proposalId);
    }

    function _queueOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(GovernorUpgradeable, GovernorTimelockControlUpgradeable) returns (uint48) {
        return super._queueOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _executeOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(GovernorUpgradeable, GovernorTimelockControlUpgradeable) {
        super._executeOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(GovernorUpgradeable, GovernorTimelockControlUpgradeable) returns (uint256) {
        return super._cancel(targets, values, calldatas, descriptionHash);
    }

    function _executor()
        internal
        view
        override(GovernorUpgradeable, GovernorTimelockControlUpgradeable)
        returns (address)
    {
        return super._executor();
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(GovernorUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function version() public pure override returns (string memory) {
        return "governor-1.0.0";
    }

    function _authorizeUpgrade(address) internal view override {
        if (msg.sender != owner() && msg.sender != kernel) {
            revert("Governor: not authorized");
        }
    }
}
