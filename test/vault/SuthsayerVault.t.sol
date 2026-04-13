// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {MockUSDC} from "../../src/vault/MockUSDC.sol";
import {SuthsayerVault} from "../../src/vault/SuthsayerVault.sol";

contract SuthsayerVaultTest is Test {
    MockUSDC internal usdc;
    SuthsayerVault internal vault;

    address internal owner = address(0xA11CE);
    address internal feeRecipient = address(0xBEEF);
    address internal alice = address(0xCAFE);

    uint16 internal constant PERFORMANCE_FEE_BPS = 500;
    uint256 internal constant DEPOSIT_CAP = 1_000_000e6;

    function setUp() external {
        vm.startPrank(owner);

        usdc = new MockUSDC(owner);

        vault = new SuthsayerVault(
            usdc,
            "Suthsayer Vault Share",
            "svUSDC",
            owner,
            feeRecipient,
            PERFORMANCE_FEE_BPS,
            DEPOSIT_CAP
        );

        usdc.mint(alice, 100_000e6);

        vm.stopPrank();

        vm.prank(alice);
        usdc.approve(address(vault), type(uint256).max);
    }

    function testDeposit() external {
        vm.prank(alice);
        uint256 shares = vault.deposit(1_000e6, alice);

        assertGt(shares, 0);
        assertEq(vault.totalAssets(), 1_000e6);
        assertEq(usdc.balanceOf(address(vault)), 1_000e6);
    }

    function testWithdraw() external {
        vm.startPrank(alice);

        vault.deposit(1_000e6, alice);
        vault.withdraw(500e6, alice, alice);

        vm.stopPrank();

        assertEq(vault.totalAssets(), 500e6);
    }
}