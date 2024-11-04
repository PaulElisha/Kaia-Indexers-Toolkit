// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../src/Stablecoin.sol";
import "../src/StablecoinEngine.sol";
import "./NetworkConfig.s.sol";

contract DeployStablecoinEngine is Script {
    NetworkConfig networkConfig;
    address[] tokenAddresses;
    address[] priceFeedAddresses;

    function run() public returns (Stablecoin, StablecoinEngine) {
        return deployStablecoinEngine();
    }

    function deployStablecoinEngine()
        public
        returns (Stablecoin, StablecoinEngine, NetworkConfig)
    {
        networkConfig = new NetworkConfig();
        (
            address wethPriceFeed,
            address wbtcPriceFeed,
            address weth,
            address wbtc,
            uint256 deployerKey
        ) = networkConfig.activeConfig();

        tokenAddresses = [weth, wbtc];
        priceFeedAddresses = [wethPriceFeed, wbtcPriceFeed];

        vm.startBroadcast();
        Stablecoin stablecoin = new Stablecoin();
        StablecoinEngine stbEngine = new StablecoinEngine(
            tokenAddresses,
            priceFeedAddresses,
            address(stablecoin)
        );
        stablecoin.transferOwnership(address(stbEngine));
        vm.stopBroadcast();

        return (stablecoin, stbEngine, networkConfig);
    }
}
