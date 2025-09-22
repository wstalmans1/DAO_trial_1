// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {Governor} from "@openzeppelin/contracts/governance/Governor.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {GovernorSettings} from "@openzeppelin/contracts/governance/extensions/GovernorSettings.sol";
import {GovernorCountingSimple} from "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import {GovernorVotes} from "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";
import {GovernorVotesQuorumFraction} from "@openzeppelin/contracts/governance/extensions/GovernorVotesQuorumFraction.sol";
import {GovernorTimelockControl} from "@openzeppelin/contracts/governance/extensions/GovernorTimelockControl.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721Votes} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Votes.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

// This source groups every contract required to spin up a DAO instance via the factory below.

/// @notice Soulbound membership badge implemented as an ERC721Votes token.
contract MembershipNFT is ERC721, ERC721Votes, Ownable {
    mapping(address => bool) private _isMember;
    mapping(address => uint256) private _memberTokenId;
    uint256 private _memberCount;
    uint256 private _nextTokenId = 1;

    /// @param admin Address that receives token ownership (the factory transfers this to the timelock).
    /// @param initialMembers Addresses that should be seeded with a governance vote.
    constructor(address admin, address[] memory initialMembers)
        ERC721("GovMember", "GM")
        EIP712("GovMember", "1")
        Ownable(admin)
    {
        require(admin != address(0), "MembershipNFT: admin is zero");

        uint256 length = initialMembers.length;
        for (uint256 i = 0; i < length; i++) {
            _addMember(initialMembers[i]);
        }
    }

    /// @notice Mints a non-transferable governance badge to a new member.
    function addMember(address account) external onlyOwner {
        _addMember(account);
    }

    /// @notice Burns the badge so the address can no longer participate.
    function removeMember(address account) external onlyOwner {
        require(account != address(0), "MembershipNFT: zero address");
        require(_isMember[account], "MembershipNFT: not member");

        uint256 tokenId = _memberTokenId[account];
        delete _memberTokenId[account];
        _isMember[account] = false;
        _memberCount -= 1;
        _burn(tokenId);
    }

    function isMember(address account) external view returns (bool) {
        return _isMember[account];
    }

    function memberCount() external view returns (uint256) {
        return _memberCount;
    }

    function tokenIdOf(address account) external view returns (uint256) {
        require(_isMember[account], "MembershipNFT: not member");
        return _memberTokenId[account];
    }

    /// @dev Internal guard that enforces unique, non-zero members and mints the badge.
    function _addMember(address account) internal {
        require(account != address(0), "MembershipNFT: zero address");
        require(!_isMember[account], "MembershipNFT: already member");

        uint256 tokenId = _nextTokenId++;
        _memberTokenId[account] = tokenId;
        _isMember[account] = true;
        _memberCount += 1;
        _safeMint(account, tokenId);
    }

    /// @dev Block transfers by reverting when moving from a non-zero address to another non-zero address.
    function _update(address to, uint256 tokenId, address auth)
        internal
        override(ERC721, ERC721Votes)
        returns (address)
    {
        address from = _ownerOf(tokenId);
        if (from != address(0) && to != address(0)) {
            revert("MembershipNFT: non-transferable");
        }
        return super._update(to, tokenId, auth);
    }

    function _increaseBalance(address account, uint128 value)
        internal
        override(ERC721, ERC721Votes)
    {
        super._increaseBalance(account, value);
    }
}

/// @notice Minimal ETH treasury handed to the timelock.
contract SimpleTreasury is Ownable {
    constructor(address initialOwner) Ownable(initialOwner) {}

    receive() external payable {}

    function transferETH(address payable to, uint256 amount) external onlyOwner {
        require(to != address(0), "SimpleTreasury: zero address");

        (bool ok, ) = to.call{value: amount}("");
        require(ok, "SimpleTreasury: ETH transfer failed");
    }
}

/// @notice Registry contract that keeps track of deployed DAO module addresses.
contract Kernel is Ownable {
    bytes32 public constant MODULE_TIMELOCK = keccak256("MODULE_TIMELOCK");
    bytes32 public constant MODULE_GOVERNOR = keccak256("MODULE_GOVERNOR");
    bytes32 public constant MODULE_TOKEN = keccak256("MODULE_TOKEN");
    bytes32 public constant MODULE_TREASURY = keccak256("MODULE_TREASURY");

    event ModuleSet(bytes32 indexed key, address indexed implementation);

    mapping(bytes32 => address) private _modules;

    constructor(address timelock_, address governor_, address token_, address treasury_)
        Ownable(timelock_)
    {
        _setModule(MODULE_TIMELOCK, timelock_);
        _setModule(MODULE_GOVERNOR, governor_);
        _setModule(MODULE_TOKEN, token_);
        _setModule(MODULE_TREASURY, treasury_);
    }

    function module(bytes32 key) external view returns (address) {
        return _modules[key];
    }

    function timelock() external view returns (address) {
        return _modules[MODULE_TIMELOCK];
    }

    function governor() external view returns (address) {
        return _modules[MODULE_GOVERNOR];
    }

    function token() external view returns (address) {
        return _modules[MODULE_TOKEN];
    }

    function treasury() external view returns (address) {
        return _modules[MODULE_TREASURY];
    }

    function setModule(bytes32 key, address implementation) external onlyOwner {
        _setModule(key, implementation);
    }

    function _setModule(bytes32 key, address implementation) internal {
        require(implementation != address(0), "Kernel: zero address");
        _modules[key] = implementation;
        emit ModuleSet(key, implementation);
    }
}

/// @notice OZ Governor setup that counts simple votes of the membership NFT via timelock.
contract DAOGovernor is
    Governor,
    GovernorSettings,
    GovernorCountingSimple,
    GovernorVotes,
    GovernorVotesQuorumFraction,
    GovernorTimelockControl
{
    constructor(ERC721Votes token, TimelockController timelock)
        Governor("DAOGovernor")
        GovernorSettings(1, 45818, 0)
        GovernorVotes(token)
        GovernorVotesQuorumFraction(4)
        GovernorTimelockControl(timelock)
    {}

    function quorum(uint256 blockNumber)
        public
        view
        override(Governor, GovernorVotesQuorumFraction)
        returns (uint256)
    {
        return super.quorum(blockNumber);
    }

    function proposalThreshold()
        public
        view
        override(Governor, GovernorSettings)
        returns (uint256)
    {
        return super.proposalThreshold();
    }

    function proposalNeedsQueuing(uint256 proposalId)
        public
        view
        override(Governor, GovernorTimelockControl)
        returns (bool)
    {
        return super.proposalNeedsQueuing(proposalId);
    }

    function state(uint256 proposalId)
        public
        view
        override(Governor, GovernorTimelockControl)
        returns (ProposalState)
    {
        return super.state(proposalId);
    }

    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) public override(Governor) returns (uint256) {
        return super.propose(targets, values, calldatas, description);
    }

    function _queueOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) returns (uint48) {
        return super._queueOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _executeOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) {
        super._executeOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) returns (uint256) {
        return super._cancel(targets, values, calldatas, descriptionHash);
    }

    function _executor()
        internal
        view
        override(Governor, GovernorTimelockControl)
        returns (address)
    {
        return super._executor();
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(Governor)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}

/// @notice Factory that instantiates the full DAO stack and emits the deployed module addresses.
contract DAOFactory {
    /// @notice Emitted after a DAO deployment so frontends can index module addresses.
    event DaoGenesis(
        address indexed timelock,
        address indexed token,
        address indexed governor,
        address treasury,
        address kernel
    );

    /// @param minDelaySeconds Required delay for timelock operations.
    /// @param initialMembers Seed list of member addresses (the caller is auto-included).
    function deployDao(uint256 minDelaySeconds, address[] calldata initialMembers)
        external
        returns (address tl, address tok, address gov, address tre, address ker)
    {
        TimelockController timelock = new TimelockController(
            minDelaySeconds,
            new address[](0),
            new address[](0),
            msg.sender
        );
        tl = address(timelock);

        // The deployer is the temporary admin until the role is revoked at the end of setup.
        // The factory instantiates the membership token with a curated member list.
        address[] memory members = _prepareMembers(initialMembers);
        MembershipNFT token = new MembershipNFT(address(this), members);
        tok = address(token);

        SimpleTreasury treasury = new SimpleTreasury(address(this));
        tre = address(treasury);

        // Governor connects votes and timelock, enforcing the governance process.
        DAOGovernor governor = new DAOGovernor(token, timelock);
        gov = address(governor);

        Kernel kernel = new Kernel(tl, gov, tok, tre);
        ker = address(kernel);

        // Wire up timelock permissions: governor proposes, anyone executes, timelock self-administers upgrades.
        timelock.grantRole(timelock.PROPOSER_ROLE(), gov);
        timelock.grantRole(timelock.EXECUTOR_ROLE(), address(0));
        timelock.grantRole(timelock.DEFAULT_ADMIN_ROLE(), tl);

        treasury.transferOwnership(tl);
        // Timelock owns the membership NFT so mint/burn flows through governance.
        token.transferOwnership(tl);

        // Drop the deployer's admin powers to avoid privileged access after deployment.
        timelock.revokeRole(timelock.DEFAULT_ADMIN_ROLE(), msg.sender);

        emit DaoGenesis(tl, tok, gov, tre, ker);
    }

    /// @dev Helper used only at deployment-time to build the initial member array.
    function _prepareMembers(address[] calldata initialMembers)
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
            // Guarantee the caller gets voting power even when not listed explicitly.
            members[index++] = msg.sender;
        }

        for (uint256 i = 0; i < length; i++) {
            // Preserve the user-supplied order after optionally injecting the caller.
            members[index++] = initialMembers[i];
        }
    }
}
