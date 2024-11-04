// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../../script/DeployStablecoin.s.sol";
import "../../src/StablecoinEngine.sol";
import "../../src/Stablecoin.sol";
import "../../script/NetworkConfig.s.sol";
import "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract StablecoinEngine is Test {
    DeployStablecoin deployStablecoin;
    StablecoinEngine stablecoinEngine;
    Stablecoin stablecoin;
    NetworkConfig config;

    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address wbtc;
    address weth;

    address USER = makeAddr("USER");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;

    function setUp() public {
        deployStablecoin = new DeployStablecoinEngine();
        (stablecoinEngine, stablecoin, config) = deployStablecoin.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc, ) = config
            .activeConfig();
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }

    address[] tokenAddresses;
    address[] priceFeedAddresses;

    function testRevertsIfTokenLengthDoesntMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(
            StablecoinEngine
                .StablecoinEngine__TokenAddressAndPriceFeedAddressMisMatch
                .selector
        );
        new StablecoinEngine(tokenAddresses, priceFeedAddresses);
    }

    function testGetUsdValue() public {
        uint256 ethAmount = 15e18;
        uint256 expectedUsd = 30000e18;

        uint256 actualUsd = stablecoinEngine.getUsdValue(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function testGetTokenAmountFromUsd() public {
        uint256 usdAmount = 100 ether;

        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = stablecoinEngine.getTokenAmountFromUsd(
            weth,
            usdAmount
        );
        assertEq(expectedWeth, actualWeth);
    }

    function testRevertsIfCollateralIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(stablecoinEngine), AMOUNT_COLLATERAL);

        vm.expectRevert(
            stablecoinEngine.StablecoinEngine__MustBeGreaterThanZero.selector
        );
        stablecoinEngine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsWithUnapprovedCollateral() public {
        ERC20Mock mockToken = new ERC20Mock(
            "MOCKTOKEN",
            "MCK",
            USER,
            AMOUNT_COLLATERAL
        );
        vm.startPrank(USER);
        VM.expectRevert(
            StablecoinEngine.StablecoinEngine__NotAllowedToken.selector
        );

        stablecoinEngine.depositCollateral(
            address(mockToken),
            AMOUNT_COLLATERAL
        );

        vm.stopPrank();
    }

    modifier depositCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(stablecoinEngine), AMOUNT_COLLATERAL);
        stablecoinEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndGetAccountInfo()
        public
        depositCollateral
    {
        (
            uint256 totalStablecoinMinted,
            uint256 collateralValueInUsd
        ) = stablecoinEngine.getAccountInformation(USER);

        uint256 expectedTotalStablecoinMinted = 0;
        uint256 expectedDepositAmount = stablecoinEngine.getTokenAmountFromUsd(
            weth,
            collateralValueInUsd
        );
        assertEq(totalStablecoinMinted, expectedTotalStablecoinMinted);
        assertEq(AMOUNT_COLLATERAL, expectedDepositAmount);
    }
}
