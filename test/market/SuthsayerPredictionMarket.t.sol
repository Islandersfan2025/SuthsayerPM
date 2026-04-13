// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {MockUSDC} from "../../src/vault/MockUSDC.sol";
import {SuthsayerToken} from "../../src/token/SuthsayerToken.sol";
import {SuthsayerPredictionMarket} from "../../src/market/SuthsayerPredictionMarket.sol";

contract SuthsayerPredictionMarketTest is Test {
    MockUSDC internal usdc;
    SuthsayerToken internal suth;
    SuthsayerPredictionMarket internal market;

    address internal admin = address(0xA11CE);
    address internal treasury = address(0xBEEF);
    address internal creator = address(0xCAFE);
    address internal alice = address(0x1);

    uint16 internal constant DEFAULT_FEE_BPS = 100;

    bytes32 internal marketId;

    function setUp() external {
        vm.startPrank(admin);

        usdc = new MockUSDC(admin);

        suth = new SuthsayerToken(
            "Suthsayer Token",
            "SUTH",
            admin,
            treasury,
            1_000_000_000 ether,
            0
        );

        market = new SuthsayerPredictionMarket(
            usdc,
            suth,
            admin,
            treasury,
            DEFAULT_FEE_BPS
        );

        suth.grantRole(suth.FEE_REBATE_ROLE(), address(market));
        usdc.mint(alice, 100_000e6);

        vm.stopPrank();

        vm.prank(alice);
        usdc.approve(address(market), type(uint256).max);

        vm.prank(admin);
        marketId = market.createMarket(
            "test-uri",
            "Will this work?",
            "rules",
            uint64(block.timestamp + 1 days),
            address(usdc),
            creator
        );
    }

    function testCreateMarketBasic() external view {
        (address yesToken, address noToken) = market.getOutcomeTokens(marketId);

        assertTrue(yesToken != address(0));
        assertTrue(noToken != address(0));
        assertEq(market.defaultFeeBps(), DEFAULT_FEE_BPS);
        assertEq(market.treasury(), treasury);
    }

    function testSplitPosition() external {
        vm.prank(alice);
        market.splitPosition(marketId, 1_000e6, alice);
    }

    function testResolveMarket() external {
        vm.warp(block.timestamp + 2 days);

        vm.prank(admin);
        market.resolveMarket(marketId, SuthsayerPredictionMarket.Outcome.Yes);
    }
}