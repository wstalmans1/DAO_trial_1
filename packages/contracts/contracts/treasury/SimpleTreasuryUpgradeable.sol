// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/// @notice Timelock-controlled ETH treasury with upgrade hooks gated by kernel.
contract SimpleTreasuryUpgradeable is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    address public kernel;

    event KernelSet(address indexed kernel);

    function initialize(address admin) public initializer {
        __Ownable_init(admin);
        __UUPSUpgradeable_init();
    }

    receive() external payable {}

    function setKernel(address newKernel) external onlyOwner {
        require(newKernel != address(0), "Treasury: kernel zero");
        kernel = newKernel;
        emit KernelSet(newKernel);
    }

    function transferETH(address payable to, uint256 amount) external onlyOwner {
        require(to != address(0), "Treasury: zero" );
        (bool ok, ) = to.call{value: amount}("");
        require(ok, "Treasury: transfer failed");
    }

    function version() external pure returns (string memory) {
        return "treasury-1.0.0";
    }

    function _authorizeUpgrade(address) internal view override {
        if (msg.sender != owner() && msg.sender != kernel) {
            revert("Treasury: not authorized");
        }
    }
}
