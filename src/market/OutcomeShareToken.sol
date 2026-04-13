// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

/// @title OutcomeShareToken
/// @notice Minimal-clone ERC-20 used for per-market YES / NO shares.
/// @dev The prediction market is the sole minter / burner.
contract OutcomeShareToken is ERC20, Initializable {
    address public market;
    uint8 private _customDecimals;
    string private _customName;
    string private _customSymbol;

    error NotMarket();
    error AlreadyInitialized();

    constructor() ERC20("", "") {
        _disableInitializers();
    }

    function initialize(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        address market_
    ) external initializer {
        if (market_ == address(0)) revert NotMarket();
        _customName = name_;
        _customSymbol = symbol_;
        _customDecimals = decimals_;
        market = market_;
    }

    function mint(address to, uint256 amount) external {
        if (msg.sender != market) revert NotMarket();
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        if (msg.sender != market) revert NotMarket();
        _burn(from, amount);
    }

    function name() public view override returns (string memory) {
        return _customName;
    }

    function symbol() public view override returns (string memory) {
        return _customSymbol;
    }

    function decimals() public view override returns (uint8) {
        return _customDecimals;
    }
}