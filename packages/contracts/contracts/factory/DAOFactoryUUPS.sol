// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {KernelUpgradeable} from "../kernel/KernelUpgradeable.sol";
import {TimelockControllerImpl, DAOGovernorImpl} from "../governance/TimelockAndGovernor.sol";
import {MembershipNFTUpgradeable} from "../token/MembershipNFTUpgradeable.sol";
import {SimpleTreasuryUpgradeable} from "../treasury/SimpleTreasuryUpgradeable.sol";

interface IOwnableTransfer {
    function transferOwnership(address newOwner) external;
}

/// @notice Factory deploying upgradeable DAO stack using ERC1967 proxies and the kernel registry.
contract DAOFactoryUUPS {
    address public immutable timelockImplementation;
    address public immutable governorImplementation;
    address public immutable membershipImplementation;
    address public immutable treasuryImplementation;
    address public immutable kernelImplementation;

    event DaoGenesis(
        address indexed timelock,
        address indexed membershipNFT,
        address governor,
        address treasury,
        address kernel
    );

    constructor(
        address timelockImpl,
        address governorImpl,
        address membershipImpl,
        address treasuryImpl,
        address kernelImpl
    ) {
        timelockImplementation = timelockImpl;
        governorImplementation = governorImpl;
        membershipImplementation = membershipImpl;
        treasuryImplementation = treasuryImpl;
        kernelImplementation = kernelImpl;
    }

    function deployDao(uint256 minDelaySeconds, address[] calldata initialMembers)
        external
        returns (address tl, address nft, address governor, address treasury, address kernel)
    {
        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](0);
        bytes memory tlInit = abi.encodeCall(
            TimelockControllerImpl.initialize,
            (minDelaySeconds, proposers, executors, address(this))
        );
        tl = address(new ERC1967Proxy(timelockImplementation, tlInit));

        address[] memory members = _initialMembersWithCaller(initialMembers);
        bytes memory nftInit = abi.encodeCall(MembershipNFTUpgradeable.initialize, (address(this), members));
        nft = address(new ERC1967Proxy(membershipImplementation, nftInit));

        bytes memory treasuryInit = abi.encodeCall(SimpleTreasuryUpgradeable.initialize, (address(this)));
        treasury = address(new ERC1967Proxy(treasuryImplementation, treasuryInit));

        bytes memory governorInit = abi.encodeCall(
            DAOGovernorImpl.initialize,
            (address(this), MembershipNFTUpgradeable(nft), TimelockControllerImpl(payable(tl)))
        );
        governor = address(new ERC1967Proxy(governorImplementation, governorInit));

        bytes memory kernelInit = abi.encodeCall(
            KernelUpgradeable.initialize,
            (tl, governor, nft, treasury)
        );
        kernel = address(new ERC1967Proxy(kernelImplementation, kernelInit));

        // Wire kernel access for upgrade routing before ownership handoff
        TimelockControllerImpl(payable(tl)).setKernel(kernel);
        MembershipNFTUpgradeable(nft).setKernel(kernel);
        SimpleTreasuryUpgradeable(payable(treasury)).setKernel(kernel);
        DAOGovernorImpl(payable(governor)).setKernel(kernel);

        // Grant timelock roles to governor and the world, then hand ownership over to timelock
        TimelockControllerImpl timelockProxy = TimelockControllerImpl(payable(tl));
        bytes32 proposerRole = timelockProxy.PROPOSER_ROLE();
        bytes32 executorRole = timelockProxy.EXECUTOR_ROLE();
        bytes32 adminRole = timelockProxy.DEFAULT_ADMIN_ROLE();

        timelockProxy.grantRole(proposerRole, governor);
        timelockProxy.grantRole(executorRole, address(0));
        timelockProxy.grantRole(adminRole, tl);

        IOwnableTransfer(nft).transferOwnership(tl);
        IOwnableTransfer(treasury).transferOwnership(tl);
        IOwnableTransfer(governor).transferOwnership(tl);
        IOwnableTransfer(tl).transferOwnership(tl);

        timelockProxy.revokeRole(adminRole, msg.sender);

        emit DaoGenesis(tl, nft, governor, treasury, kernel);
    }

    function _initialMembersWithCaller(address[] calldata initialMembers)
        private
        view
        returns (address[] memory members)
    {
        uint256 length = initialMembers.length;
        bool includeSender = true;
        for (uint256 i = 0; i < length; i++) {
            address member = initialMembers[i];
            require(member != address(0), "DAOFactory: zero member");
            if (member == msg.sender) {
                includeSender = false;
            }
        }

        uint256 size = length + (includeSender ? 1 : 0);
        members = new address[](size);
        uint256 index = 0;
        if (includeSender) {
            members[index++] = msg.sender;
        }
        for (uint256 i = 0; i < length; i++) {
            members[index++] = initialMembers[i];
        }
    }
}
