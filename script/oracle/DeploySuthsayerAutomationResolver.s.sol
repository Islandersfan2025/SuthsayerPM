// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {SuthsayerAutomationResolver} from "../../src/oracle/SuthsayerAutomationResolver.sol";

contract DeploySuthsayerAutomationResolver is Script {
    function run() external {
        uint256 deployerPk = vm.envUint("PRIVATE_KEY");
        address predictionMarket = vm.envAddress("PREDICTION_MARKET");

        vm.startBroadcast(deployerPk);

        SuthsayerAutomationResolver resolver =
            new SuthsayerAutomationResolver(predictionMarket);

        vm.stopBroadcast();

        console2.log("Automation Resolver deployed:", address(resolver));
        console2.log("Prediction Market:", predictionMarket);
    }
}