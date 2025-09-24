// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";

/// @notice Soulbound ERC-721 membership badge that provides one vote per member without delegation.
contract MembershipNFTImplementation is Initializable, UUPSUpgradeable, OwnableUpgradeable, ERC721Upgradeable, IVotes {
    using Checkpoints for Checkpoints.Trace208;

    uint256 private _nextId;
    uint256 private _memberCount;
    mapping(address => bool) private _isMember;
    mapping(address => uint256) private _tokenIdOf;
    mapping(address => Checkpoints.Trace208) private _memberVotes;
    Checkpoints.Trace208 private _totalVotes;

    address public kernel;

    event KernelSet(address indexed kernel);

    function initialize(address admin, address[] memory initialMembers) public initializer {
        __Ownable_init(admin);
        __UUPSUpgradeable_init();
        __ERC721_init("GovMemberNFT", "GMN");

        _nextId = 1;
        uint256 len = initialMembers.length;
        for (uint256 i = 0; i < len; i++) {
            _addMember(initialMembers[i]);
        }
    }

    function setKernel(address newKernel) external onlyOwner {
        require(newKernel != address(0), "MembershipNFT: kernel zero");
        kernel = newKernel;
        emit KernelSet(newKernel);
    }

    function addMember(address account) external onlyOwner {
        _addMember(account);
    }

    function removeMember(address account) external onlyOwner {
        require(_isMember[account], "MembershipNFT: not member");

        uint256 tokenId = _tokenIdOf[account];
        delete _tokenIdOf[account];
        _isMember[account] = false;
        _memberCount -= 1;

        _burn(tokenId);
        _writeCheckpoint(_memberVotes[account], -1);
        _writeCheckpoint(_totalVotes, -1);
    }

    function isMember(address account) external view returns (bool) {
        return _isMember[account];
    }

    function memberCount() external view returns (uint256) {
        return _memberCount;
    }

    function tokenIdOf(address account) external view returns (uint256) {
        require(_isMember[account], "MembershipNFT: missing");
        return _tokenIdOf[account];
    }

    /// @dev Prevent transfers except mint (from 0) and burn (to 0).
    function _update(address to, uint256 tokenId, address auth)
        internal
        override(ERC721Upgradeable)
        returns (address)
    {
        address from = _ownerOf(tokenId);
        if (from != address(0) && to != address(0)) {
            revert("MembershipNFT: soulbound");
        }
        return super._update(to, tokenId, auth);
    }

    // --- IVotes implementation (no delegation) ---

    function getVotes(address account) public view override returns (uint256) {
        return _memberVotes[account].latest();
    }

    function getPastVotes(address account, uint256 blockNumber) public view override returns (uint256) {
        return _memberVotes[account].upperLookupRecent(uint48(blockNumber));
    }

    function getPastTotalSupply(uint256 blockNumber) public view override returns (uint256) {
        return _totalVotes.upperLookupRecent(uint48(blockNumber));
    }

    function delegates(address) external pure override returns (address) {
        return address(0);
    }

    function delegate(address) external pure override {
        revert("MembershipNFT: delegation disabled");
    }

    function delegateBySig(
        address,
        uint256,
        uint256,
        uint8,
        bytes32,
        bytes32
    ) external pure override {
        revert("MembershipNFT: delegation disabled");
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721Upgradeable)
        returns (bool)
    {
        return interfaceId == type(IVotes).interfaceId || super.supportsInterface(interfaceId);
    }

    function version() external pure returns (string memory) {
        return "membership-nft-1.1.0";
    }

    function _authorizeUpgrade(address) internal view override {
        if (msg.sender != owner() && msg.sender != kernel) {
            revert("MembershipNFT: not authorized");
        }
    }

    function _addMember(address account) internal {
        require(account != address(0), "MembershipNFT: zero");
        require(!_isMember[account], "MembershipNFT: exists");

        uint256 tokenId = _nextId++;
        _isMember[account] = true;
        _tokenIdOf[account] = tokenId;
        _memberCount += 1;
        _safeMint(account, tokenId);

        _writeCheckpoint(_memberVotes[account], 1);
        _writeCheckpoint(_totalVotes, 1);
    }

    function _writeCheckpoint(Checkpoints.Trace208 storage trace, int256 delta) private {
        uint208 oldValue = trace.latest();
        int256 newValue = int256(uint256(oldValue)) + delta;
        require(newValue >= 0 && newValue <= int256(uint256(type(uint208).max)), "MembershipNFT: votes overflow");
        trace.push(uint48(block.number), uint208(uint256(newValue)));
    }
}
