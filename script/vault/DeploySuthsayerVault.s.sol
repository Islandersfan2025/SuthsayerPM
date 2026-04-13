// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {MockUSDC} from "../../src/vault/MockUSDC.sol";
import {SuthsayerVault} from "../../src/vault/SuthsayerVault.sol";

contract DeploySuthsayerVault is Script {
    function run() external {
        uint256 deployerPk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPk);

        address asset = vm.envOr("USDC_ADDRESS", address(0));
        address feeRecipient = vm.envOr("FEE_RECIPIENT", deployer);
        address initialOwner = vm.envOr("INITIAL_OWNER", deployer);
        uint16 performanceFeeBps = uint16(vm.envOr("PERFORMANCE_FEE_BPS", uint256(1000))); // 10%
        uint256 depositCap = vm.envOr("DEPOSIT_CAP", uint256(10_000_000e6));

        vm.startBroadcast(deployerPk);

        if (asset == address(0)) {
            MockUSDC mock = new MockUSDC(initialOwner);
            asset = address(mock);
            console2.log("MockUSDC deployed:", asset);
        }

        SuthsayerVault vault = new SuthsayerVault(
            MockUSDC(asset),
            "Suthsayer Vault Share",
            "svUSDC",
            initialOwner,
            feeRecipient,
            performanceFeeBps,
            depositCap
        );

        vm.stopBroadcast();

        console2.log("Vault deployed:", address(vault));
        console2.log("Asset:", asset);
        console2.log("Owner:", initialOwner);
        console2.log("Fee recipient:", feeRecipient);
        console2.log("Performance fee bps:", performanceFeeBps);
        console2.log("Deposit cap:", depositCap);
    }
}