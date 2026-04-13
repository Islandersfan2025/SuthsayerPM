// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Capped} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Capped.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";

contract SuthsayerToken is
    ERC20,
    ERC20Burnable,
    ERC20Capped,
    ERC20Permit,
    ERC20Votes,
    AccessControl,
    Pausable
{
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant REWARDS_DISTRIBUTOR_ROLE = keccak256("REWARDS_DISTRIBUTOR_ROLE");
    bytes32 public constant FEE_REBATE_ROLE = keccak256("FEE_REBATE_ROLE");

    event RewardsMinted(address indexed to, uint256 amount, bytes32 indexed campaignId);
    event FeeRebateMinted(address indexed to, uint256 amount, bytes32 indexed rebateId);

    error ArrayLengthMismatch();
    error ZeroAddress();

    constructor(
        string memory name_,
        string memory symbol_,
        address admin_,
        address treasury_,
        uint256 maxSupply_,
        uint256 treasuryAllocation_
    )
        ERC20(name_, symbol_)
        ERC20Permit(name_)
        ERC20Capped(maxSupply_)
    {
        if (admin_ == address(0) || treasury_ == address(0)) revert ZeroAddress();

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(PAUSER_ROLE, admin_);
        _grantRole(MINTER_ROLE, admin_);
        _grantRole(REWARDS_DISTRIBUTOR_ROLE, admin_);
        _grantRole(FEE_REBATE_ROLE, admin_);

        if (treasuryAllocation_ > 0) {
            _mint(treasury_, treasuryAllocation_);
        }
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    function batchMint(address[] calldata recipients, uint256[] calldata amounts) external onlyRole(MINTER_ROLE) {
        uint256 length = recipients.length;
        if (length != amounts.length) revert ArrayLengthMismatch();

        for (uint256 i = 0; i < length; ++i) {
            _mint(recipients[i], amounts[i]);
        }
    }

    function mintRewards(address to, uint256 amount, bytes32 campaignId)
        external
        onlyRole(REWARDS_DISTRIBUTOR_ROLE)
    {
        _mint(to, amount);
        emit RewardsMinted(to, amount, campaignId);
    }

    function mintFeeRebate(address to, uint256 amount, bytes32 rebateId)
        external
        onlyRole(FEE_REBATE_ROLE)
    {
        _mint(to, amount);
        emit FeeRebateMinted(to, amount, rebateId);
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function _update(address from, address to, uint256 value)
        internal
        override(ERC20, ERC20Capped, ERC20Votes)
        whenNotPaused
    {
        super._update(from, to, value);
    }

    function nonces(address owner) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }
}