// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {SuthsayerToken} from "../../src/token/SuthsayerToken.sol";

contract SuthsayerTokenTest is Test {
    SuthsayerToken internal token;

    address internal admin = address(0xA11CE);
    address internal treasury = address(0xBEEF);
    address internal user = address(0xCAFE);

    uint256 internal constant MAX_SUPPLY = 1_000_000_000 ether;

    function setUp() external {
        vm.prank(admin);
        token = new SuthsayerToken(
            "Suthsayer Token",
            "SUTH",
            admin,
            treasury,
            MAX_SUPPLY,
            0
        );
    }

    function testMetadata() external view {
        assertEq(token.name(), "Suthsayer Token");
        assertEq(token.symbol(), "SUTH");
    }

    function testAdminCanMint() external {
        vm.prank(admin);
        token.mint(user, 100 ether);

        assertEq(token.balanceOf(user), 100 ether);
    }

    function testNonAdminCannotMint() external {
        vm.prank(user);
        vm.expectRevert();
        token.mint(user, 100 ether);
    }

    function testTransferWorks() external {
        vm.prank(admin);
        token.mint(user, 100 ether);

        vm.prank(user);
        token.transfer(address(0xB0B), 40 ether);

        assertEq(token.balanceOf(address(0xB0B)), 40 ether);
        assertEq(token.balanceOf(user), 60 ether);
    }
}