// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Stablecoin.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract StablecoinEngine is ReentrancyGuard {
    error StablecoinEngine__MustBeGreaterThanZero();
    error StablecoinEngine__TokenAddressAndPriceFeedAddressMisMatch();
    error StablecoinEngine__NeedsMoreThanZero();
    error StablecoinEngine__BreaksHealthFactor(uint256);
    error StablecoinEngine__MintFailed();
    error StablecoinEngine__HealthFactorNotImproved();

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10; // 10%

    mapping(address => address) private priceFeeds; // tokenToPriceFeed
    mapping(address => mapping(address => uint)) private collateralBalance;
    mapping(address => uint) private stablecoinMinted;
    address[] private collateralTokens;

    Stablecoin private immutable stablecoin;

    event CollateralDeposited(
        address indexed user,
        address indexed token,
        uint256 indexed amount
    );

    event CollateralRedeemed(
        address indexed from,
        address indexed to,
        address indexed token,
        uint256 amount
    );

    modifier moreThanZero(uint2256 _amount) {
        if (_amount == 0) {
            revert StablecoinEngine__MustBeGreaterThanZero();
        }
        _;
    }

    modifier isAllowedToken(address _token) {
        if (priceFeedAddresses[_token] == address(0)) {
            revert StablecoinEngine__NotAllowedToken();
        }
    }

    constructor(
        address[] memory tokenAddresses,
        address[] memory priceFeedAddresses,
        address stablecoin
    ) {
        if (tokenAddresses.length != priceFeedAddresses) {
            revert StablecoinEngine__TokenAddressAndPriceFeedAddressMisMatch();
        }

        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
        }
        stablecoin = Stablecoin(stablecoin);
    }

    function depositCollateralAndMintStablecoin(
        address _collateralToken,
        uint256 _amountCollateral,
        uint256 _amountStableToMint
    ) external {
        depositCollateral(_collateralToken, _amountCollateral);
        mintStablecoin(_amountStableToMint);
    }

    function depositCollateral(
        address _collateralToken,
        uint256 _amountCollateral
    )
        external
        moreThanZero(_amountCollateral)
        isAllowedToken(_collateralToken)
        nonReentrant
    {
        collateralBalance[msg.sender][_collateralToken] += _amountCollateral;
        emit CollateralDeposited(
            msg.sender,
            _collateralToken,
            _amountCollateral
        );
        bool success = IERC20(_collateralToken).transferFrom(
            msg.sender,
            address(this),
            _amountCollateral
        );

        if (!success) {
            revert StablecoinEngine__TransferFailed();
        }
    }

    function redeemCollateralForStablecoin(
        address _tokenCollateral,
        uint256 _amountCollateral,
        uint256 _amountStablecoinToBurn
    ) external {
        burnStablecoin(_amountStablecoinToBurn);

        redeemCollateral(_tokenCollateral, _amountCollateral);
    }

    function redeemCollateral(
        address _tokenCollateral,
        uint256 _amountCollateral
    ) external moreThanZero(_amountCollateral) nonReentrant {
        _redeemCollateral(
            msg.sender,
            msg.sender,
            _tokenCollateral,
            _amountCollateral
        );

        _revertIfHealthFactorIsBroken(msg.msg.sender);
    }

    function mintStablecoin(
        uint256 _amountToMint
    ) external moreThanZero(_amountToMint) nonReentrant {
        stablecoinMinted[msg.sender] += _amountToMint;

        _revertIfHealthFactorIsBroken(msg.sender);

        bool minted = stablecoin.mint(msg.sender, _amountToMint);
        if (!minted) {
            revert StablecoinEngine__MintFailed();
        }
    }

    function _burnStablecoin(
        uint256 _amount,
        address _onBehalf,
        address _from
    ) private {
        stablecoinMinted[_onBehalf] -= _amount;
        bool success = stablecoin.transferFrom(_from, address(this), _amount);

        if (!success) {
            revert StablecoinEngine__TransferFailed();
        }

        stablecoin.burn(_amount);
    }

    function burnStablecoin(uint256 _amount) external moreThanZero(_amount) {
        _burnStablecoin(_amount, msg.sender, msg.sender);

        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function liquidate(
        address _collateral,
        address _user,
        uint256 _debtToCover
    ) external moreThanZero(_debtToCover) nonReentrant {
        uint256 startingUserHealthFactor = _healthFactor(_user);

        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert StablecoinEngine__HealthFactorOK();
        }

        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(
            _collateral,
            _debtToCover
        );

        uint256 bonusCollateral = (tokenAmountFromDebtCovered *
            LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;

        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered +
            bonusCollateral;

        _redeemCollateral(
            _user,
            msg.sender,
            _collateral,
            totalCollateralToRedeem
        );

        _burnStablecoin(_debtToCover, _user, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(_user);

        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert StablecoinEngine__HealthFactorNotImproved();
        }

        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function getHealthFactor(address _user) external view returns (uint256) {
        return _healthFactor(_user);
    }

    function _redeemCollateral(
        address _tokenCollateral,
        uint256 _amountCollateral,
        address _from,
        address _to
    ) private {
        collateralBalance[_from][_tokenCollateral] -= _amountCollateral;

        emit CollateralRedeemed(
            _from,
            _to,
            _tokenCollateral,
            _amountCollateral
        );

        bool success = IERC20(_tokenCollateral).transfer(
            _to,
            _amountCollateral
        );

        if (!success) {
            revert StablecoinEngine__TransferFailed();
        }
    }

    function _getAccountInformation(
        address _user
    )
        private
        view
        returns (uint256 totalStablecoinMinted, uint256 collateralUsdValue)
    {
        totalStablecoinMinted = stablecoinMinted[_user];
        collateralUsdValue = getAccountCollateralUsdValue(_user);
    }

    function _healthFactor(address _user) private view returns (uint256) {
        (
            uint256 totalStablecoinMinted,
            uint256 collateralUsdValue
        ) = _getAccountInformation(_user);

        uint256 collateralAdjustedForThreshold = (collateralUsdValue *
            LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return
            (collateralAdjustedForThreshold * PRECISION) /
            totalStablecoinMinted;
    }

    function _revertIfHealthFactorIsBroken(address _user) internal view {
        uint256 userHealthFactor = _healthFactor(_user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert StablecoinEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    function getTokenAmountFromUsd(
        address _token,
        uint256 _usdAmountInWei
    ) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            priceFeeds[_token]
        );

        (, int256 price, , , ) = priceFeed.latestRoundData();

        (_usdAmountInWei * PRECISION) /
            (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    function getAccountCollateralUsdValue(
        address _user
    ) public view returns (uint256 totalCollateralUsdValue) {
        for (uint256 i = 0; i <= collateralTokens.length; i++) {
            address token = collateralTokens[i];
            uint256 amount = depositCollateral[_user][token];
            totalCollateralUsdValue += getUsdValue(token, amount);
        }
        return totalCollateralUsdValue;
    }

    function getUsdValue(
        add _token,
        uint256 _amount
    ) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            priceFeeds[_token]
        );
        (, int256 price, , , ) = priceFeed.latestRoundData();

        return ((uint256(price) * ADDITIONAL_FEED_PRECISION * _amount) /
            PRECISION);
    }

    function getAccountInformation(address _user) public view returns (uint256 totalStablecoinMinted, uint256 collateralUsdValue {
        (totalStablecoinMinted, collateralUsdValue) = _getAccountInformation(_user);
    }
}
