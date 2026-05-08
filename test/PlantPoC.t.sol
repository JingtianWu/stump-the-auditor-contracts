// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseTest} from "./helpers/BaseTest.sol";
import {ILendingPool} from "src/interfaces/ILendingPool.sol";
import {IPriceOracle} from "src/interfaces/IPriceOracle.sol";
import {Lending} from "src/Lending/Lending.sol";
import {PriceOracle} from "src/PriceOracle.sol";
import {MockERC20} from "src/mocks/MockERC20.sol";

contract PlantPoC is BaseTest {
    uint256 internal constant USDC_PRICE = 1e8;
    uint256 internal constant WETH_PRICE = 2_000e8;

    MockERC20 internal usdc;
    MockERC20 internal weth;
    Lending internal lending;
    PriceOracle internal oracle;

    function setUp() public override {
        super.setUp();

        usdc = deployMockToken("USDC", 6);
        weth = deployMockToken("WETH", 18);

        vm.startPrank(owner);
        oracle = new PriceOracle();
        lending = new Lending(IPriceOracle(address(oracle)), 10_000);
        lending.listReserve(address(usdc), _defaultIrParams(), 8_000, 8_500, 500, 1_000, true, true);
        lending.listReserve(address(weth), _defaultIrParams(), 8_000, 8_000, 2_500, 1_000, true, true);
        oracle.setPrice(address(usdc), USDC_PRICE);
        oracle.setPrice(address(weth), WETH_PRICE);
        vm.stopPrank();

        mintAndApprove(usdc, bob, address(lending), 1_600e6);
        mintAndApprove(weth, alice, address(lending), 1 ether);
        mintAndApprove(usdc, charlie, address(lending), 1_600e6);
    }

    function testPoC_boundaryBonusLeavesUncollateralizedDebtAndFrozenSupplierClaim() public {
        vm.prank(bob);
        lending.supply(address(usdc), 1_600e6, bob);

        vm.prank(alice);
        lending.supply(address(weth), 1 ether, alice);

        vm.prank(alice);
        lending.borrow(address(usdc), 1_600e6, alice);

        advanceSeconds(365 days);

        vm.startPrank(owner);
        oracle.setPrice(address(usdc), USDC_PRICE);
        oracle.setPrice(address(weth), WETH_PRICE);
        vm.stopPrank();

        (, uint256 debtBefore,, uint256 healthBefore) = lending.getUserAccountData(alice);
        assertGt(debtBefore, 1_600e18);
        assertLt(healthBefore, lending.MIN_HEALTH_FACTOR());

        vm.prank(charlie);
        (uint256 debtRepaid, uint256 collateralSeized) =
            lending.liquidate(alice, address(weth), address(usdc), 1_600e6);

        assertEq(debtRepaid, 1_600e6);
        assertEq(collateralSeized, 1 ether);

        vm.prank(charlie);
        lending.withdraw(address(weth), type(uint256).max, charlie);

        (uint256 collateralAfter, uint256 debtAfter,, uint256 healthAfter) = lending.getUserAccountData(alice);
        assertEq(collateralAfter, 0);
        assertGt(debtAfter, 0);
        assertEq(healthAfter, 0);

        (uint256 lenderClaim,) = lending.getUserReserveData(bob, address(usdc));
        uint256 poolLiquidity = usdc.balanceOf(address(lending));
        assertGt(lenderClaim, poolLiquidity);

        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(
                ILendingPool.InsufficientLiquidity.selector, address(usdc), lenderClaim, poolLiquidity
            )
        );
        lending.withdraw(address(usdc), type(uint256).max, bob);
    }

    function _defaultIrParams() internal pure returns (ILendingPool.InterestRateParams memory params) {
        params = ILendingPool.InterestRateParams({
            baseRateRayPerYear: 0, slope1RayPerYear: 2e26, slope2RayPerYear: 8e26, optimalUtilizationBps: 8_000
        });
    }
}
