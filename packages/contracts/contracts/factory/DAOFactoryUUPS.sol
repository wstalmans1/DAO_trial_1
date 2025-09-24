// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24; // use Solidity 0.8.24 with built-in overflow checks

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol"; // proxy helper for UUPS pattern

import {KernelImplementation} from "../kernel/KernelImplementation.sol"; // kernel contract that records module addresses
import {TimelockControllerImplementation, DAOGovernorImplementation} from "../governance/TimelockAndGovernorImplementation.sol"; // timelock & governor implementations
import {MembershipNFTImplementation} from "../token/MembershipNFTImplementation.sol"; // soulbound membership NFT implementation
import {SimpleTreasuryImplementation} from "../treasury/SimpleTreasuryImplementation.sol"; // treasury implementation

interface IOwnableTransfer { // minimal ownable interface for ownership handoff
    /// @notice Transfer ownership to a new account. // describe function purpose
    function transferOwnership(address newOwner) external; // function signature used on module proxies
}

/// @notice Factory deploying upgradeable DAO stack using ERC1967 proxies and the kernel registry. // high-level summary
contract DAOFactoryUUPS { // solidity contract definition
    address public immutable timelockImplementation; // address of timelock logic contract
    address public immutable governorImplementation; // address of governor logic contract
    address public immutable membershipImplementation; // address of membership NFT logic contract
    address public immutable treasuryImplementation; // address of treasury logic contract
    address public immutable kernelImplementation; // address of kernel logic contract

    /// @notice Emitted after deploying a DAO so indexers/frontends can capture module addresses. // event description
    event DaoGenesis( // event declaration start
        address indexed timelock, // emitted timelock proxy address
        address indexed membershipNFT, // emitted membership NFT proxy address
        address governor, // emitted governor proxy address
        address treasury, // emitted treasury proxy address
        address kernel // emitted kernel proxy address
    );

    /// @param timelockImpl Logic contract new timelock proxies will point to. // constructor param doc
    /// @param governorImpl Logic contract new governor proxies will point to. // doc comment
    /// @param membershipImpl Logic contract new membership NFT proxies will point to. // doc comment
    /// @param treasuryImpl Logic contract new treasury proxies will point to. // doc comment
    /// @param kernelImpl Logic contract new kernel proxies will point to. // doc comment
    constructor( // constructor definition
        address timelockImpl, // param receives timelock implementation address
        address governorImpl, // param receives governor implementation address
        address membershipImpl, // param receives membership implementation address
        address treasuryImpl, // param receives treasury implementation address
        address kernelImpl // param receives kernel implementation address
    ) { // start constructor body
        // Implementation contracts are deployed up front and communicated to the factory via constructor args. // summary comment
        // These addresses remain immutable; each DAO deployment spins up proxies pointing to them, and upgrades // detail comment line 1
        // happen later via the proxy upgrade path (kernel/timelock governance). // detail comment line 2
        timelockImplementation = timelockImpl; // set immutable timelock implementation
        governorImplementation = governorImpl; // set immutable governor implementation
        membershipImplementation = membershipImpl; // set immutable membership implementation
        treasuryImplementation = treasuryImpl; // set immutable treasury implementation
        kernelImplementation = kernelImpl; // set immutable kernel implementation
    } // end constructor

    /// @notice Deploys a new DAO instance and wires ownership/permissions. // function summary
    /// @param minDelaySeconds Delay (in seconds) enforced by the timelock before execution. // param doc
    /// @param initialMembers Addresses that should each receive a membership NFT (deployer auto-added). // param doc
    function deployDao(uint256 minDelaySeconds, address[] calldata initialMembers) // function signature returning module addresses
        external // callable from outside
        returns (address tl, address nft, address governor, address treasury, address kernel) // named return vars for clarity
    { // function body start
        // 1) Timelock: deployed under factory control so we can wire roles before handing it to the DAO. // step comment
        address[] memory proposers = new address[](0); // start with empty proposers list
        address[] memory executors = new address[](0); // start with empty executors list
        bytes memory tlInit = abi.encodeCall( // encode initializer call for timelock proxy
            TimelockControllerImplementation.initialize, // selector for initialize function
            (minDelaySeconds, proposers, executors, address(this)) // pass delay, role arrays, and temporary admin (factory)
        ); // end encodeCall
        tl = address(new ERC1967Proxy(timelockImplementation, tlInit)); // deploy timelock proxy and record address

        address[] memory members = _initialMembersWithCaller(initialMembers); // Build the exact mint list (caller + user-supplied members)
        bytes memory nftInit = abi.encodeCall( // Encode initializer call for MembershipNFT proxy
            MembershipNFTImplementation.initialize, // initializer selector for membership NFT
            (address(this), members) // Factory is temporary admin; contract mints one soulbound token per address in `members`
        ); // end encodeCall for NFT
        nft = address(new ERC1967Proxy(membershipImplementation, nftInit)); // Deploy NFT proxy; initializer does the minting loop internally

        // 3) Treasury: minimal ETH vault owned by the timelock. // comment describing step
        bytes memory treasuryInit = abi.encodeCall(SimpleTreasuryImplementation.initialize, (address(this))); // encode treasury initializer with temporary owner
        treasury = address(new ERC1967Proxy(treasuryImplementation, treasuryInit)); // deploy treasury proxy

        // 4) Governor: references the membership votes and timelock for scheduling execution. // step comment
        bytes memory governorInit = abi.encodeCall( // encode governor initializer
            DAOGovernorImplementation.initialize, // initializer selector for governor
            (address(this), MembershipNFTImplementation(nft), TimelockControllerImplementation(payable(tl))) // admin (factory), votes source, timelock reference
        ); // end encodeCall governor
        governor = address(new ERC1967Proxy(governorImplementation, governorInit)); // deploy governor proxy

        // 5) Kernel: immutable registry of module proxies, responsible for upgrades. // step comment
        bytes memory kernelInit = abi.encodeCall( // encode kernel initializer call
            KernelImplementation.initialize, // initializer selector for kernel
            (tl, governor, nft, treasury) // pass module proxy addresses for registry storage
        ); // end encodeCall kernel
        kernel = address(new ERC1967Proxy(kernelImplementation, kernelInit)); // deploy kernel proxy

        // Each module keeps a reference to the kernel so future upgrades go through a single governance hub. // comment about wiring kernel
        TimelockControllerImplementation(payable(tl)).setKernel(kernel); // allow timelock to reference kernel for upgrades
        MembershipNFTImplementation(nft).setKernel(kernel); // allow membership NFT to reference kernel
        SimpleTreasuryImplementation(payable(treasury)).setKernel(kernel); // allow treasury to reference kernel
        DAOGovernorImplementation(payable(governor)).setKernel(kernel); // allow governor to reference kernel

        // Grant timelock roles to governor and the world, then hand ownership over to timelock. // comment about roles
        TimelockControllerImplementation timelockProxy = TimelockControllerImplementation(payable(tl)); // cast timelock proxy for role ops
        bytes32 proposerRole = timelockProxy.PROPOSER_ROLE(); // fetch proposer role constant
        bytes32 executorRole = timelockProxy.EXECUTOR_ROLE(); // fetch executor role constant
        bytes32 adminRole = timelockProxy.DEFAULT_ADMIN_ROLE(); // fetch admin role constant

        // Governor can queue timelock operations; anyone can execute; timelock administers itself after setup. // explain grant logic
        timelockProxy.grantRole(proposerRole, governor); // give governor proposer rights
        timelockProxy.grantRole(executorRole, address(0)); // allow anyone to execute (open executor)
        timelockProxy.grantRole(adminRole, tl); // timelock becomes its own admin

        // Transfer ownership of every module to the timelock to enforce DAO governance control. // ownership comment
        IOwnableTransfer(nft).transferOwnership(tl); // membership NFT owned by timelock
        IOwnableTransfer(treasury).transferOwnership(tl); // treasury owned by timelock
        IOwnableTransfer(governor).transferOwnership(tl); // governor owned by timelock
        IOwnableTransfer(tl).transferOwnership(tl); // timelock self-owned (admin handled above)

        // Revoke deployer's admin power on the timelock; only the DAO governs upgrades from now on. // final cleanup comment
        timelockProxy.revokeRole(adminRole, msg.sender); // remove deployer admin

        emit DaoGenesis(tl, nft, governor, treasury, kernel); // emit event summarizing module addresses
    } // end deployDao

    /// @dev Returns the array fed to the membership NFT initializer (one soulbound token per entry). // function comment
    ///      All comments sit inline below for maximum readability. // explanation note
    function _initialMembersWithCaller(address[] calldata initialMembers) // helper to build member list
        private // only used inside contract
        view // pure read of calldata and msg.sender
        returns (address[] memory members) // returns array for initializer
    { // function body
        uint256 length = initialMembers.length; // Original number of members supplied by caller
        bool includeSender = true; // Assume we need to add msg.sender unless we find it in the loop below
        for (uint256 i = 0; i < length; i++) { // iterate over provided members
            address member = initialMembers[i]; // Current member candidate from calldata
            require(member != address(0), "DAOFactory: zero member"); // Reject zero address up front (prevents bad mints)
            if (member == msg.sender) { // check if caller already included
                includeSender = false; // Caller already present -> skip auto-inclusion later
            }
        }

        uint256 size = length + (includeSender ? 1 : 0); // Final array length (adds caller if needed)
        members = new address[](size); // Allocate the exact array sent to NFT initializer

        uint256 index = 0; // Iterator reused for filling the array
        if (includeSender) { // if caller not already included
            members[index++] = msg.sender; // Place caller first when auto-including (predictable tokenId assignment)
        }

        for (uint256 i = 0; i < length; i++) { // iterate again to copy provided members
            members[index++] = initialMembers[i]; // copy user-supplied member preserving order
        }
    } // end helper
} // end contract
