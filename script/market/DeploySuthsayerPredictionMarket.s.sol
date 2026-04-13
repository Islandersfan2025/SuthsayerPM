// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {MockUSDC} from "../../src/vault/MockUSDC.sol";
import {SuthsayerToken} from "../../src/token/SuthsayerToken.sol";
import {SuthsayerPredictionMarket} from "../../src/market/SuthsayerPredictionMarket.sol";

contract DeploySuthsayerPredictionMarket is Script {
    function run() external {
        uint256 deployerPk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPk);

        address admin = vm.envOr("ADMIN_ADDRESS", deployer);
        address treasury = vm.envOr("TREASURY_ADDRESS", deployer);

        address collateralToken = vm.envOr("USDC_ADDRESS", address(0));
        address suthToken = vm.envOr("SUTH_TOKEN_ADDRESS", address(0));

        uint16 defaultFeeBps = uint16(vm.envOr("DEFAULT_FEE_BPS", uint256(100)));

        vm.startBroadcast(deployerPk);

        if (collateralToken == address(0)) {
            MockUSDC mockUsdc = new MockUSDC(admin);
            collateralToken = address(mockUsdc);
            console2.log("MockUSDC deployed:", collateralToken);
        }

        if (suthToken == address(0)) {
            SuthsayerToken token = new SuthsayerToken(
                "Suthsayer Token",
                "SUTH",
                admin,
                treasury,
                1_000_000_000 ether,
                0
            );
            suthToken = address(token);
            console2.log("SUTH token deployed:", suthToken);
        }

        SuthsayerPredictionMarket predictionMarket = new SuthsayerPredictionMarket(
            MockUSDC(collateralToken),
            SuthsayerToken(suthToken),
            admin,
            treasury,
            defaultFeeBps
        );

        try SuthsayerToken(suthToken).grantRole(
            SuthsayerToken(suthToken).FEE_REBATE_ROLE(),
            address(predictionMarket)
        ) {
            console2.log("Granted FEE_REBATE_ROLE to market");
        } catch {
            console2.log("WARNING: Could not grant FEE_REBATE_ROLE automatically");
        }

        vm.stopBroadcast();

        console2.log("Prediction Market deployed:", address(predictionMarket));
        console2.log("Admin:", admin);
        console2.log("Treasury:", treasury);
        console2.log("Collateral token:", collateralToken);
        console2.log("SUTH token:", suthToken);
        console2.log("Default fee bps:", defaultFeeBps);
    }
}