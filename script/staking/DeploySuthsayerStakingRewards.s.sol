// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {SuthsayerToken} from "../../src/token/SuthsayerToken.sol";
import {SuthsayerStakingRewards} from "../../src/staking/SuthsayerStakingRewards.sol";

contract DeploySuthsayerStakingRewards is Script {
    function run() external {
        uint256 deployerPk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPk);

        address rewardToken = vm.envAddress("SUTH_TOKEN");
        address owner = vm.envOr("OWNER", deployer);

        uint256 rewardPerSecond = vm.envOr("REWARD_PER_SECOND", uint256(1 ether));
        uint256 startTime = vm.envOr("START_TIME", block.timestamp + 60);

        vm.startBroadcast(deployerPk);

        SuthsayerStakingRewards staking = new SuthsayerStakingRewards(
            rewardToken,
            owner,
            rewardPerSecond,
            startTime
        );

        vm.stopBroadcast();

        console2.log("Staking contract deployed:", address(staking));
        console2.log("Reward token:", rewardToken);
        console2.log("Owner:", owner);
        console2.log("Reward/sec:", rewardPerSecond);
        console2.log("Start time:", startTime);

        console2.log("IMPORTANT: Grant REWARDS_DISTRIBUTOR_ROLE to this contract!");
    }
}