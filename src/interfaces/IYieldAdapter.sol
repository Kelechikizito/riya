// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

interface IYieldAdapter {
    function deposit(uint256 amount) external returns (uint256 assets);
    function withdraw(uint256 amount, address to) external returns (uint256 assets);
    function harvest() external returns (uint256 assets);
    function totalAssets() external view returns (uint256);
    function yieldAccrued() external view returns (uint256);
    function asset() external view returns (address);
}
