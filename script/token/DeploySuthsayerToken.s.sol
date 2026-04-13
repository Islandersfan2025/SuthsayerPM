// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {SuthsayerToken} from "../../src/token/SuthsayerToken.sol";

contract DeploySuthsayerToken is Script {
    function run() external {
        uint256 deployerPk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPk);

        address admin = vm.envOr("ADMIN_ADDRESS", deployer);
        address treasury = vm.envOr("TREASURY_ADDRESS", deployer);

        uint256 maxSupply = vm.envOr("MAX_SUPPLY", uint256(1_000_000_000 ether));
        uint256 treasuryAllocation = vm.envOr("TREASURY_ALLOCATION", uint256(100_000_000 ether));

        vm.startBroadcast(deployerPk);

        SuthsayerToken token = new SuthsayerToken(
            "Suthsayer Token",
            "SUTH",
            admin,
            treasury,
            maxSupply,
            treasuryAllocation
        );

        vm.stopBroadcast();

        console2.log("SUTH Token deployed:", address(token));
        console2.log("Admin:", admin);
        console2.log("Treasury:", treasury);
        console2.log("Max Supply:", maxSupply);
        console2.log("Treasury Allocation:", treasuryAllocation);
    }
}