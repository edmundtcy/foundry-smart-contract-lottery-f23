//SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {Raffle} from "../src/Raffle.sol";
import {VRFCoordinatorV2Mock} from "@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";
import {LinkToken} from "../test/mocks/LinkToken.sol";

contract HelperConfig is Script{
    struct NetworkConfig {
        uint64 subscriptionId;
        bytes32 gasLane;
        uint256 automationUpdateInterval;
        uint256 raffleEntranceFee;
        uint32 callbackGasLimit;
        address vrfCoordinatorV2;
        address link;
        uint256 deployerKey;
    }

    uint256 public constant DEFAULT_ANVIL_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    NetworkConfig public activeNetworkConfig;

    constructor(){
        if(block.chainid == 11155111){
            activeNetworkConfig = getSepoliaEthConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    function getSepoliaEthConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            subscriptionId: 8562, // If left as 0, our scripts will create one!
            gasLane: 0x474e34a077df58807dbe9c96d3c009b23b3c6d0cce433e59bbf5b34f823bc56c,
            automationUpdateInterval: 30, // 30 seconds
            raffleEntranceFee: 0.01 ether,
            callbackGasLimit: 500000, // 500,000 gas
            vrfCoordinatorV2: 0x8103B0A8A00be2DDC778e6e7eaa21791Cd364625,
            link: 0x779877A7B0D9E8603169DdbD7836e478b4624789,
            deployerKey: vm.envUint("SEPOLIA_PK")
        });
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        if(activeNetworkConfig.vrfCoordinatorV2 != address(0)){
            return activeNetworkConfig;
        } 
        else{
            uint96 baseFee = 0.25 ether; // 0.25 LINK
            uint96 gasPriceLink = 1e9; // 1 gwei LINK

            vm.startBroadcast();
            VRFCoordinatorV2Mock vrfCoordinatorV2Mock = new VRFCoordinatorV2Mock(
                baseFee,
                gasPriceLink
            );
            LinkToken link = new LinkToken();
            vm.stopBroadcast();

            return NetworkConfig({
                subscriptionId: 0, // If left as 0, our scripts will create one!
                gasLane: 0x474e34a077df58807dbe9c96d3c009b23b3c6d0cce433e59bbf5b34f823bc56c, // doesn't really matter
                automationUpdateInterval: 30, // 30 seconds
                raffleEntranceFee: 0.01 ether,
                callbackGasLimit: 500000, // 500,000 gas
                vrfCoordinatorV2: address(vrfCoordinatorV2Mock),
                link: address(link),
                deployerKey: DEFAULT_ANVIL_KEY
            });
        }
    }

}
