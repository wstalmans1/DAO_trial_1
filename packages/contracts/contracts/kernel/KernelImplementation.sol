// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

interface IUUPSUpgradeableMinimal {
    function upgradeTo(address newImplementation) external;
}

/// @notice Central registry that tracks DAO module proxies and coordinates upgrades.
contract KernelImplementation is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    bytes32 public constant MODULE_TIMELOCK = keccak256("MODULE_TIMELOCK");
    bytes32 public constant MODULE_GOVERNOR = keccak256("MODULE_GOVERNOR");
    bytes32 public constant MODULE_TOKEN = keccak256("MODULE_TOKEN");
    bytes32 public constant MODULE_TREASURY = keccak256("MODULE_TREASURY");

    event ModuleSet(bytes32 indexed key, address indexed proxy);
    event ModuleUpgraded(bytes32 indexed key, address indexed newImplementation, bytes32 codehash);

    mapping(bytes32 => address) private _modules;
    mapping(bytes32 => address) public currentImplementation;

    /// @notice Initialize the kernel with module proxy addresses and timelock ownership.
    function initialize(
        address timelock,
        address governor,
        address token,
        address treasury
    ) public initializer {
        __Ownable_init(timelock);
        __UUPSUpgradeable_init();

        _set(MODULE_TIMELOCK, timelock);
        _set(MODULE_GOVERNOR, governor);
        _set(MODULE_TOKEN, token);
        _set(MODULE_TREASURY, treasury);
    }

    function module(bytes32 key) external view returns (address) {
        return _modules[key];
    }

    function setModule(bytes32 key, address proxy) external onlyOwner {
        _set(key, proxy);
    }

    /// @notice Upgrade the implementation behind a module proxy (must be UUPS compliant).
    function upgradeModule(bytes32 key, address newImplementation) external onlyOwner {
        address proxy = _modules[key];
        require(proxy != address(0), "Kernel: unknown module");
        require(newImplementation != address(0), "Kernel: impl zero");
        require(newImplementation.code.length > 0, "Kernel: impl code");

        // sanity check on the implementation exposing proxiableUUID (EIP-1822)
        (bool ok, bytes memory ret) = newImplementation.staticcall(abi.encodeWithSignature("proxiableUUID()"));
        require(ok && ret.length == 32, "Kernel: not UUPS");

        IUUPSUpgradeableMinimal(proxy).upgradeTo(newImplementation);

        bytes32 codehash;
        assembly {
            codehash := extcodehash(newImplementation)
        }
        currentImplementation[key] = newImplementation;
        emit ModuleUpgraded(key, newImplementation, codehash);
    }

    function _set(bytes32 key, address proxy) internal {
        require(proxy != address(0), "Kernel: proxy zero");
        _modules[key] = proxy;
        emit ModuleSet(key, proxy);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
