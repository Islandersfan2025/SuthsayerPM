// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {MockUSDC} from "../../src/vault/MockUSDC.sol";
import {SuthsayerToken} from "../../src/token/SuthsayerToken.sol";
import {SuthsayerStakingRewards} from "../../src/staking/SuthsayerStakingRewards.sol";

contract SuthsayerStakingRewardsTest is Test {
    MockUSDC internal stakingToken;
    SuthsayerToken internal rewardToken;
    SuthsayerStakingRewards internal staking;

    address internal admin = address(0xA11CE);
    address internal treasury = address(0xBEEF);

    function setUp() external {
        vm.startPrank(admin);

        stakingToken = new MockUSDC(admin);

        rewardToken = new SuthsayerToken(
            "Suthsayer Token",
            "SUTH",
            admin,
            treasury,
            1_000_000_000 ether,
            0
        );

        staking = new SuthsayerStakingRewards(
            address(rewardToken),
            admin,
            1 ether,
            block.timestamp + 1
        );

        vm.stopPrank();
    }

    function testDeploys() external view {
        assertEq(address(staking.rewardToken()), address(rewardToken));
        assertEq(staking.rewardPerSecond(), 1 ether);
    }
}