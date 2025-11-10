// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Wrapper} from "../src/Wrapper.sol";
import {KipuBankV3} from "../src/KipuBankV3.sol";

contract DeployKipuBankV3Script is Script {
    function run() external {
        // Load env variables
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address admin = vm.envAddress("ADMIN");
        address router = vm.envAddress("SEPOLIA_UNI_V2_ROUTER");
        address usdc = vm.envAddress("SEPOLIA_USDC");
        uint256 bankCap = vm.envUint("INITIAL_BANK_CAP_USDC");

        vm.startBroadcast(deployerPrivateKey);

        // 1) Deploy Wrapper
        Wrapper wrapper = new Wrapper(router, usdc);

        // 2) Deploy KipuBankV3
        KipuBankV3 bank = new KipuBankV3(
            router,
            usdc,
            bankCap,
            admin
        );

        // 3) Link wrapper
        bank.setWrapper(address(wrapper));

        vm.stopBroadcast();

        console.log("Wrapper deployed at:", address(wrapper));
        console.log("KipuBankV3 deployed at:", address(bank));
    }
}

