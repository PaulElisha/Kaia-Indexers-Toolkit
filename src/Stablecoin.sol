// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Stablecoin is ERC20Burnable, Ownable {
    error Stablecoin__ZeroBalance();
    error Stablecoin__BurnAmountExceedsBalance();
    error Stablecoin__ZeroAddress();
    error Stablecoin__AmountLessThanZero();

    constructor() ERC20("stablecoin", "stb") {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert Stablecoin__ZeroBalance();
        }

        if (balance < _amount) {
            revert Stablecoin__BurnAmountExceedsBalance();
        }
        super.burn(_amount);
    }

    function mint(
        address _to,
        uint256 _amount
    ) public onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert Stablecoin__ZeroAddress();
        }

        if (_amount <= 0) {
            revert Stablecoin__AmountLessThanZero();
        }
        _mint(_to, _amount);
    }
}
