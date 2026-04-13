// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {SuthsayerAutomationResolver} from "../../src/oracle/SuthsayerAutomationResolver.sol";

contract MockPredictionMarket {
    enum Outcome {
        Unresolved,
        Yes,
        No,
        Invalid
    }

    bytes32 public lastMarketId;
    Outcome public lastOutcome;

    function resolveMarket(bytes32 marketId, Outcome outcome) external {
        lastMarketId = marketId;
        lastOutcome = outcome;
    }
}

contract SuthsayerAutomationResolverTest is Test {
    MockPredictionMarket internal predictionMarket;
    SuthsayerAutomationResolver internal resolver;

    address internal owner = address(0xA11CE);

    function setUp() external {
        vm.prank(owner);
        predictionMarket = new MockPredictionMarket();

        vm.prank(owner);
        resolver = new SuthsayerAutomationResolver(address(predictionMarket));
    }

    function testResolveManuallyYes() external {
        bytes32 marketId = keccak256("market-1");

        vm.prank(owner);
        resolver.resolveManually(marketId, 1);

        assertEq(predictionMarket.lastMarketId(), marketId);
        assertEq(uint8(predictionMarket.lastOutcome()), 1);
    }

    function testResolveManuallyNo() external {
        bytes32 marketId = keccak256("market-2");

        vm.prank(owner);
        resolver.resolveManually(marketId, 2);

        assertEq(predictionMarket.lastMarketId(), marketId);
        assertEq(uint8(predictionMarket.lastOutcome()), 2);
    }

    function testResolveManuallyInvalid() external {
        bytes32 marketId = keccak256("market-3");

        vm.prank(owner);
        resolver.resolveManually(marketId, 3);

        assertEq(predictionMarket.lastMarketId(), marketId);
        assertEq(uint8(predictionMarket.lastOutcome()), 3);
    }

    function testNonOwnerCannotResolve() external {
        bytes32 marketId = keccak256("market-4");

        vm.expectRevert("not owner");
        resolver.resolveManually(marketId, 1);
    }

    function testBadOutcomeReverts() external {
        bytes32 marketId = keccak256("market-5");

        vm.prank(owner);
        vm.expectRevert("bad outcome");
        resolver.resolveManually(marketId, 4);
    }
}