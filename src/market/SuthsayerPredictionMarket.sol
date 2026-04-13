// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

import {OutcomeShareToken} from "./OutcomeShareToken.sol";
import {SuthsayerToken} from "../token/SuthsayerToken.sol";

/// @title SuthsayerPredictionMarket
/// @notice Binary prediction market with fully collateralized YES / NO ERC-20 outcome tokens.
/// @dev This is the closest of the requested options to Polymarket's token semantics:
///      - each market has transferrable YES and NO tokens
///      - one collateral unit mints one YES + one NO token (a full set)
///      - full sets can be merged back before resolution
///      - after resolution, only the winning token redeems 1:1 for collateral
///      Trading venues (AMM or offchain orderbook) can be added on top of these ERC-20 positions later.
contract SuthsayerPredictionMarket is AccessControl, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20Metadata;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant RESOLVER_ROLE = keccak256("RESOLVER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    enum MarketState {
        None,
        Open,
        Resolved,
        Cancelled
    }

    enum Outcome {
        Unresolved,
        Yes,
        No,
        Invalid
    }

    struct Market {
        bytes32 marketId;
        string blueskyUri;
        string question;
        string rulesUri;
        address creator;
        uint64 createdAt;
        uint64 closeTime;
        MarketState state;
        Outcome outcome;
        address collateralToken;
        address yesToken;
        address noToken;
        uint256 totalCollateral;
        uint256 totalMintedSets;
        uint256 resolvedAt;
        uint256 feeBps;
    }

    IERC20Metadata public immutable defaultCollateralToken;
    OutcomeShareToken public immutable outcomeTokenImplementation;
    SuthsayerToken public immutable suthToken;

    uint256 public constant MAX_BPS = 10_000;
    uint16 public defaultFeeBps;
    address public treasury;
    uint256 public marketCount;

    mapping(bytes32 => Market) public markets;
    mapping(string => bytes32) public marketIdByBlueskyUri;

    event MarketCreated(
        bytes32 indexed marketId,
        string blueskyUri,
        address indexed creator,
        address collateralToken,
        address yesToken,
        address noToken,
        uint64 closeTime,
        uint256 feeBps
    );
    event Split(address indexed user, bytes32 indexed marketId, uint256 collateralIn, uint256 feePaid, uint256 sharesMinted);
    event Merged(address indexed user, bytes32 indexed marketId, uint256 sharesBurned, uint256 collateralOut);
    event Redeemed(address indexed user, bytes32 indexed marketId, uint256 winningSharesBurned, uint256 collateralOut);
    event MarketResolved(bytes32 indexed marketId, Outcome outcome);
    event MarketCancelled(bytes32 indexed marketId);
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);
    event DefaultFeeBpsUpdated(uint256 oldFeeBps, uint256 newFeeBps);
    event FeeRebateMinted(address indexed user, bytes32 indexed marketId, uint256 feePaid, uint256 rebateMinted);

    error ZeroAddress();
    error MarketExists();
    error MarketNotFound();
    error InvalidCloseTime();
    error InvalidState();
    error MarketClosed();
    error MarketStillOpen();
    error InvalidAmount();
    error InvalidOutcome();
    error FeeTooHigh();

    constructor(
        IERC20Metadata defaultCollateralToken_,
        SuthsayerToken suthToken_,
        address admin_,
        address treasury_,
        uint16 defaultFeeBps_
    ) {
        if (address(defaultCollateralToken_) == address(0) || address(suthToken_) == address(0) || admin_ == address(0) || treasury_ == address(0)) {
            revert ZeroAddress();
        }
        if (defaultFeeBps_ > 1_000) revert FeeTooHigh();

        defaultCollateralToken = defaultCollateralToken_;
        suthToken = suthToken_;
        treasury = treasury_;
        defaultFeeBps = defaultFeeBps_;
        outcomeTokenImplementation = new OutcomeShareToken();

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(OPERATOR_ROLE, admin_);
        _grantRole(RESOLVER_ROLE, admin_);
        _grantRole(PAUSER_ROLE, admin_);
    }

    function createMarket(
        string calldata blueskyUri,
        string calldata question,
        string calldata rulesUri,
        uint64 closeTime,
        address collateralToken,
        address creator
    ) external onlyRole(OPERATOR_ROLE) whenNotPaused returns (bytes32 marketId) {
        if (closeTime <= block.timestamp) revert InvalidCloseTime();
        if (creator == address(0)) revert ZeroAddress();

        marketId = keccak256(bytes(blueskyUri));
        if (markets[marketId].state != MarketState.None) revert MarketExists();

        IERC20Metadata collateral = collateralToken == address(0) ? defaultCollateralToken : IERC20Metadata(collateralToken);
        uint8 collateralDecimals = collateral.decimals();

        address yesToken = Clones.clone(address(outcomeTokenImplementation));
        address noToken = Clones.clone(address(outcomeTokenImplementation));

        string memory idSuffix = _shortId(marketId);
        OutcomeShareToken(yesToken).initialize(
            string.concat("Suthsayer YES ", idSuffix),
            string.concat("YES-", idSuffix),
            collateralDecimals,
            address(this)
        );
        OutcomeShareToken(noToken).initialize(
            string.concat("Suthsayer NO ", idSuffix),
            string.concat("NO-", idSuffix),
            collateralDecimals,
            address(this)
        );

        markets[marketId] = Market({
            marketId: marketId,
            blueskyUri: blueskyUri,
            question: question,
            rulesUri: rulesUri,
            creator: creator,
            createdAt: uint64(block.timestamp),
            closeTime: closeTime,
            state: MarketState.Open,
            outcome: Outcome.Unresolved,
            collateralToken: address(collateral),
            yesToken: yesToken,
            noToken: noToken,
            totalCollateral: 0,
            totalMintedSets: 0,
            resolvedAt: 0,
            feeBps: defaultFeeBps
        });
        marketIdByBlueskyUri[blueskyUri] = marketId;
        marketCount += 1;

        emit MarketCreated(marketId, blueskyUri, creator, address(collateral), yesToken, noToken, closeTime, defaultFeeBps);
    }

    function splitPosition(bytes32 marketId, uint256 collateralAmount, address receiver)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 sharesMinted)
    {
        if (collateralAmount == 0) revert InvalidAmount();
        Market storage market = _getOpenMarket(marketId);
        if (block.timestamp >= market.closeTime) revert MarketClosed();

        IERC20Metadata collateral = IERC20Metadata(market.collateralToken);
        uint256 fee = (collateralAmount * market.feeBps) / MAX_BPS;
        uint256 netCollateral = collateralAmount - fee;
        if (netCollateral == 0) revert InvalidAmount();

        collateral.safeTransferFrom(msg.sender, address(this), collateralAmount);
        if (fee != 0) {
            collateral.safeTransfer(treasury, fee);
            _mintFeeRebate(msg.sender, marketId, fee);
        }

        sharesMinted = netCollateral;
        OutcomeShareToken(market.yesToken).mint(receiver, sharesMinted);
        OutcomeShareToken(market.noToken).mint(receiver, sharesMinted);

        market.totalCollateral += netCollateral;
        market.totalMintedSets += sharesMinted;

        emit Split(msg.sender, marketId, collateralAmount, fee, sharesMinted);
    }

    function mergePositions(bytes32 marketId, uint256 amount, address receiver)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 collateralOut)
    {
        if (amount == 0) revert InvalidAmount();
        Market storage market = _getMarket(marketId);
        if (market.state != MarketState.Open) revert InvalidState();

        OutcomeShareToken(market.yesToken).burn(msg.sender, amount);
        OutcomeShareToken(market.noToken).burn(msg.sender, amount);

        market.totalCollateral -= amount;
        market.totalMintedSets -= amount;

        collateralOut = amount;
        IERC20Metadata(market.collateralToken).safeTransfer(receiver, collateralOut);

        emit Merged(msg.sender, marketId, amount, collateralOut);
    }

    function resolveMarket(bytes32 marketId, Outcome outcome) external onlyRole(RESOLVER_ROLE) whenNotPaused {
        Market storage market = _getMarket(marketId);
        if (market.state != MarketState.Open) revert InvalidState();
        if (block.timestamp < market.closeTime) revert MarketStillOpen();
        if (outcome == Outcome.Unresolved) revert InvalidOutcome();

        if (outcome == Outcome.Invalid) {
            market.state = MarketState.Cancelled;
            market.outcome = Outcome.Invalid;
            market.resolvedAt = block.timestamp;
            emit MarketCancelled(marketId);
            return;
        }

        market.state = MarketState.Resolved;
        market.outcome = outcome;
        market.resolvedAt = block.timestamp;

        emit MarketResolved(marketId, outcome);
    }

    function redeem(bytes32 marketId, uint256 amount, address receiver)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 collateralOut)
    {
        if (amount == 0) revert InvalidAmount();
        Market storage market = _getMarket(marketId);
        if (market.state == MarketState.Open) revert MarketStillOpen();

        if (market.state == MarketState.Cancelled) {
            OutcomeShareToken(market.yesToken).burn(msg.sender, amount);
            OutcomeShareToken(market.noToken).burn(msg.sender, amount);
            collateralOut = amount;
        } else if (market.outcome == Outcome.Yes) {
            OutcomeShareToken(market.yesToken).burn(msg.sender, amount);
            collateralOut = amount;
        } else if (market.outcome == Outcome.No) {
            OutcomeShareToken(market.noToken).burn(msg.sender, amount);
            collateralOut = amount;
        } else {
            revert InvalidOutcome();
        }

        market.totalCollateral -= collateralOut;
        IERC20Metadata(market.collateralToken).safeTransfer(receiver, collateralOut);

        emit Redeemed(msg.sender, marketId, amount, collateralOut);
    }

    function setTreasury(address newTreasury) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newTreasury == address(0)) revert ZeroAddress();
        emit TreasuryUpdated(treasury, newTreasury);
        treasury = newTreasury;
    }

    function setDefaultFeeBps(uint16 newFeeBps) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newFeeBps > 1_000) revert FeeTooHigh();
        emit DefaultFeeBpsUpdated(defaultFeeBps, newFeeBps);
        defaultFeeBps = newFeeBps;
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function getOutcomeTokens(bytes32 marketId) external view returns (address yesToken, address noToken) {
        Market storage market = _getMarket(marketId);
        return (market.yesToken, market.noToken);
    }

    function _mintFeeRebate(address user, bytes32 marketId, uint256 feePaid) internal {
        if (address(suthToken) == address(0) || feePaid == 0) return;

        // 1:1 nominal mint against fee units; governance can swap to a different formula later.
        // This call requires the market contract to hold FEE_REBATE_ROLE on the SUTH token.
        try suthToken.mintFeeRebate(user, feePaid, marketId) {
            emit FeeRebateMinted(user, marketId, feePaid, feePaid);
        } catch {
            // swallow to avoid blocking the core market flow if rebate role/config is missing
        }
    }

    function _getMarket(bytes32 marketId) internal view returns (Market storage market) {
        market = markets[marketId];
        if (market.state == MarketState.None) revert MarketNotFound();
    }

    function _getOpenMarket(bytes32 marketId) internal view returns (Market storage market) {
        market = _getMarket(marketId);
        if (market.state != MarketState.Open) revert InvalidState();
    }

    function _shortId(bytes32 marketId) internal pure returns (string memory) {
        bytes memory alphabet = "0123456789abcdef";
        bytes memory out = new bytes(8);
        for (uint256 i = 0; i < 4; ++i) {
            uint8 b = uint8(marketId[i]);
            out[i * 2] = alphabet[b >> 4];
            out[i * 2 + 1] = alphabet[b & 0x0f];
        }
        return string(out);
    }
}