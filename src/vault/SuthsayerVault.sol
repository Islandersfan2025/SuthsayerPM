// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title SuthsayerVault
/// @notice ERC-4626 vault over USDC for the Suthsayer protocol.
/// @dev Optimized for Foundry deployment on Sonic-compatible EVM networks.
///      - ERC-4626-compliant share accounting
///      - ERC-20 shares with EIP-2612 permit
///      - Optional protocol fee on yield only
///      - Deposit cap and allowlist-ready admin controls
///      - Pausable entrypoints for operational safety
contract SuthsayerVault is ERC4626, ERC20Permit, Ownable2Step, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20Metadata;

    uint256 public constant MAX_BPS = 10_000;
    uint8 public constant SHARE_DECIMALS_OFFSET = 12;

    /// @notice Fee charged only on positive yield, denominated in basis points.
    uint16 public performanceFeeBps;

    /// @notice Fee recipient for minted fee shares.
    address public feeRecipient;

    /// @notice Optional cap on total underlying assets managed by the vault.
    uint256 public depositCap;

    /// @dev Tracks the total assets after the most recent fee crystallization.
    uint256 public highWaterMark;

    event FeeRecipientUpdated(address indexed oldRecipient, address indexed newRecipient);
    event PerformanceFeeUpdated(uint16 oldFeeBps, uint16 newFeeBps);
    event DepositCapUpdated(uint256 oldCap, uint256 newCap);
    event FeesAccrued(uint256 yieldAssets, uint256 feeAssets, uint256 mintedShares);

    error ZeroAddress();
    error FeeTooHigh();
    error DepositCapExceeded();

    constructor(
        IERC20Metadata asset_,
        string memory name_,
        string memory symbol_,
        address initialOwner_,
        address feeRecipient_,
        uint16 performanceFeeBps_,
        uint256 depositCap_
    )
        ERC20(name_, symbol_)
        ERC20Permit(name_)
        ERC4626(asset_)
        Ownable(initialOwner_)
    {
        if (initialOwner_ == address(0) || feeRecipient_ == address(0)) revert ZeroAddress();
        if (performanceFeeBps_ > 2_000) revert FeeTooHigh();

        feeRecipient = feeRecipient_;
        performanceFeeBps = performanceFeeBps_;
        depositCap = depositCap_;
        highWaterMark = IERC20Metadata(asset()).balanceOf(address(this));
    }

    // ------------------------------------------------------------
    // Admin
    // ------------------------------------------------------------

    function setFeeRecipient(address newFeeRecipient) external onlyOwner {
        if (newFeeRecipient == address(0)) revert ZeroAddress();
        emit FeeRecipientUpdated(feeRecipient, newFeeRecipient);
        feeRecipient = newFeeRecipient;
    }

    function setPerformanceFeeBps(uint16 newFeeBps) external onlyOwner {
        if (newFeeBps > 2_000) revert FeeTooHigh();
        _accrueFees();
        emit PerformanceFeeUpdated(performanceFeeBps, newFeeBps);
        performanceFeeBps = newFeeBps;
    }

    function setDepositCap(uint256 newDepositCap) external onlyOwner {
        emit DepositCapUpdated(depositCap, newDepositCap);
        depositCap = newDepositCap;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Crystallize accrued performance fees into vault shares for the fee recipient.
    function accrueFees() external returns (uint256 mintedShares) {
        mintedShares = _accrueFees();
    }

    // ------------------------------------------------------------
    // User helpers
    // ------------------------------------------------------------

    /// @notice Deposit with EIP-2612 permit on the underlying USDC-like token.
    /// @dev Requires the asset token to implement permit. Native Circle USDC does.
    function depositWithPermit(
        uint256 assets,
        address receiver,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external nonReentrant returns (uint256 shares) {
        IERC20Permit(asset()).permit(msg.sender, address(this), assets, deadline, v, r, s);
        shares = deposit(assets, receiver);
    }

    /// @notice Mint exact vault shares with EIP-2612 permit on the underlying token.
    function mintWithPermit(
        uint256 shares,
        address receiver,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external nonReentrant returns (uint256 assets) {
        assets = previewMint(shares);
        IERC20Permit(asset()).permit(msg.sender, address(this), assets, deadline, v, r, s);
        mint(shares, receiver);
    }

    // ------------------------------------------------------------
    // ERC-4626 overrides
    // ------------------------------------------------------------

    function decimals() public view override(ERC20, ERC4626) returns (uint8) {
        return super.decimals();
    }

    function maxDeposit(address) public view override returns (uint256) {
        if (paused()) return 0;
        uint256 cap = depositCap;
        if (cap == 0) return type(uint256).max;

        uint256 assetsNow = totalAssets();
        if (assetsNow >= cap) return 0;
        unchecked {
            return cap - assetsNow;
        }
    }

    function maxMint(address) public view override returns (uint256) {
        uint256 maxAssets_ = maxDeposit(address(0));
        if (maxAssets_ == 0) return 0;
        return previewDeposit(maxAssets_);
    }

    function maxWithdraw(address owner) public view override returns (uint256) {
        if (paused()) return 0;
        return super.maxWithdraw(owner);
    }

    function maxRedeem(address owner) public view override returns (uint256) {
        if (paused()) return 0;
        return super.maxRedeem(owner);
    }

    function deposit(uint256 assets, address receiver)
        public
        override
        whenNotPaused
        nonReentrant
        returns (uint256 shares)
    {
        _accrueFees();
        _enforceDepositCap(assets);
        shares = super.deposit(assets, receiver);
        highWaterMark += assets;
    }

    function mint(uint256 shares, address receiver)
        public
        override
        whenNotPaused
        nonReentrant
        returns (uint256 assets)
    {
        _accrueFees();
        assets = previewMint(shares);
        _enforceDepositCap(assets);
        assets = super.mint(shares, receiver);
        highWaterMark += assets;
    }

    function withdraw(uint256 assets, address receiver, address owner)
        public
        override
        whenNotPaused
        nonReentrant
        returns (uint256 shares)
    {
        _accrueFees();
        shares = super.withdraw(assets, receiver, owner);
        uint256 hwm = highWaterMark;
        highWaterMark = assets >= hwm ? 0 : hwm - assets;
    }

    function redeem(uint256 shares, address receiver, address owner)
        public
        override
        whenNotPaused
        nonReentrant
        returns (uint256 assets)
    {
        _accrueFees();
        assets = super.redeem(shares, receiver, owner);
        uint256 hwm = highWaterMark;
        highWaterMark = assets >= hwm ? 0 : hwm - assets;
    }

    /// @dev Higher share precision improves early-vault safety and UX.
    function _decimalsOffset() internal pure override returns (uint8) {
        return SHARE_DECIMALS_OFFSET;
    }

    // ------------------------------------------------------------
    // Internals
    // ------------------------------------------------------------

    function _enforceDepositCap(uint256 incomingAssets) internal view {
        uint256 cap = depositCap;
        if (cap == 0) return;
        if (totalAssets() + incomingAssets > cap) revert DepositCapExceeded();
    }

    function _accrueFees() internal returns (uint256 mintedShares) {
        uint16 feeBps = performanceFeeBps;
        if (feeBps == 0) {
            highWaterMark = totalAssets();
            return 0;
        }

        uint256 assetsNow = totalAssets();
        uint256 hwm = highWaterMark;
        if (assetsNow <= hwm) {
            highWaterMark = assetsNow;
            return 0;
        }

        uint256 yieldAssets = assetsNow - hwm;
        uint256 feeAssets = (yieldAssets * feeBps) / MAX_BPS;
        if (feeAssets == 0) {
            highWaterMark = assetsNow;
            return 0;
        }

        mintedShares = previewDeposit(feeAssets);
        if (mintedShares == 0) {
            highWaterMark = assetsNow;
            return 0;
        }

        _mint(feeRecipient, mintedShares);
        highWaterMark = assetsNow;

        emit FeesAccrued(yieldAssets, feeAssets, mintedShares);
    }
}