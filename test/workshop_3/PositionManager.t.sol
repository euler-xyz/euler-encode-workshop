// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "evc/EthereumVaultConnector.sol";
import "evc-playground/vaults/VaultRegularBorrowable.sol";
import "evc-playground/vaults/VaultSimple.sol";
import "solmate/test/utils/mocks/MockERC20.sol";
import "../mocks/IRMMock.sol";
import "../mocks/PriceOracleMock.sol";
import "../../src/workshop_3/PositionManager.sol";

contract PositionManagerTest is Test {
    IEVC evc;
    MockERC20 referenceAsset;
    MockERC20 liabilityAsset;
    MockERC20 collateralAsset;
    IRMMock irm1;
    IRMMock irm2;
    IRMMock irm3;
    PriceOracleMock oracle;
    VaultRegularBorrowable vault1;
    VaultRegularBorrowable vault2;
    VaultRegularBorrowable vault3;
    VaultSimple collateralVault;

    PositionManager positionManager;

    function setUp() public {
        evc = new EthereumVaultConnector();
        referenceAsset = new MockERC20("Reference Asset", "RA", 18);
        liabilityAsset = new MockERC20("Liability Asset", "LA", 18);
        collateralAsset = new MockERC20("Collateral Asset", "CA", 18);
        irm1 = new IRMMock();
        irm2 = new IRMMock();
        irm3 = new IRMMock();
        oracle = new PriceOracleMock();

        vault1 =
            new VaultRegularBorrowable(evc, liabilityAsset, irm1, oracle, referenceAsset, "Liability Vault 1", "LV1");

        vault2 =
            new VaultRegularBorrowable(evc, liabilityAsset, irm2, oracle, referenceAsset, "Liability Vault 2", "LV2");

        vault3 =
            new VaultRegularBorrowable(evc, liabilityAsset, irm3, oracle, referenceAsset, "Liability Vault 3", "LV3");

        collateralVault = new VaultSimple(evc, collateralAsset, "Collateral Vault", "CV");

        irm1.setInterestRate(10); // 10% APY
        irm2.setInterestRate(15); // 15% APY
        irm3.setInterestRate(20); // 20% APY
        oracle.setQuote(address(liabilityAsset), address(referenceAsset), 1e17); // 1 LA = 0.1 RA
        oracle.setQuote(address(collateralAsset), address(referenceAsset), 1e16); // 1 CA = 0.01 RA

        address[] memory allowedVaults = new address[](3);
        allowedVaults[0] = address(vault1);
        allowedVaults[1] = address(vault2);
        allowedVaults[2] = address(vault3);

        positionManager = new PositionManager(evc, allowedVaults);

        // all vaults accept collateralVault as collateral
        vault1.setCollateralFactor(collateralVault, 100);
        vault2.setCollateralFactor(collateralVault, 100);
        vault3.setCollateralFactor(collateralVault, 100);
    }

    function test_PositionManagementCreated() public {
        assert(address(positionManager) != address(0));
        assert(positionManager.evc() == evc);
        assertTrue(positionManager.vaults(address(vault1)));
        assertTrue(positionManager.vaults(address(vault2)));
        assertTrue(positionManager.vaults(address(vault3)));
        assertFalse(positionManager.vaults(address(collateralVault)));
    }

    function test_PositionRebalance(address alice, address bob, address carol, address dave) public {
        vm.assume(alice != address(0) && bob != address(0) && !evc.haveCommonOwner(alice, bob));
        vm.assume(
            carol != address(0) && dave != address(0) && !evc.haveCommonOwner(bob, carol)
                && !evc.haveCommonOwner(carol, dave)
        );
        vm.assume(
            !evc.haveCommonOwner(alice, bob) && !evc.haveCommonOwner(alice, carol) && !evc.haveCommonOwner(bob, carol)
                && !evc.haveCommonOwner(alice, dave) && !evc.haveCommonOwner(bob, dave) && !evc.haveCommonOwner(carol, dave)
        );
        vm.assume(alice != address(evc) && bob != address(evc) && carol != address(evc) && dave != address(evc));
        vm.assume(
            address(vault1) != address(evc) && address(vault2) != address(evc) && address(vault3) != address(evc)
                && address(collateralVault) != address(evc)
        );
        vm.assume(
            alice != address(positionManager) && bob != address(positionManager) && carol != address(positionManager)
                && dave != address(positionManager)
        );
        vm.assume(
            alice != address(vault1) && bob != address(vault1) && carol != address(vault1) && dave != address(vault1)
        );
        vm.assume(
            alice != address(vault2) && bob != address(vault2) && carol != address(vault2) && dave != address(vault2)
        );
        vm.assume(
            alice != address(vault3) && bob != address(vault3) && carol != address(vault3) && dave != address(vault3)
        );
        vm.assume(
            alice != address(collateralVault) && bob != address(collateralVault) && carol != address(collateralVault)
                && dave != address(collateralVault)
        );

        /*
        *   Initial Asset Minting
        */
        // alice and bob will act as the lenders of reference asset
        liabilityAsset.mint(alice, 100e18);
        liabilityAsset.mint(bob, 100e18);
        // carol will act as the borrower while also holds enough to repay the loadn
        collateralAsset.mint(carol, 1000e18);

        // alice deposits liability asset in vault1 and authorizes position manager
        vm.startPrank(alice);
        liabilityAsset.approve(address(vault1), 100e18);
        vault1.deposit(100e18, alice);
        // alice authorizes the Position Manager to act on behalf of her account
        evc.setAccountOperator(alice, address(positionManager), true);
        vm.stopPrank();
        // assert that all ok
        assertEq(liabilityAsset.balanceOf(address(alice)), 0);
        assertEq(vault1.maxWithdraw(alice), 100e18);

        // bob deposits half liability asset in vault2 and half in vault3
        vm.startPrank(bob);
        liabilityAsset.approve(address(vault2), 50e18);
        liabilityAsset.approve(address(vault3), 50e18);
        vault2.deposit(50e18, bob);
        vault3.deposit(50e18, bob);
        vm.stopPrank();

        // dave rebalances alice's sub account from vault1 to vault2 that has higher interest rate
        vm.prank(dave);
        positionManager.rebalance(alice, address(vault1), address(vault2));

        // alice's account balance on vault 2 is the initial minus the operator's tip
        assertEq(vault2.maxWithdraw(alice), 100e18 - 100e18 / 100);

        // bot cannot rebalance more often than every after day
        vm.prank(dave);
        vm.expectRevert("Rebalance can only be performed once a day");
        positionManager.rebalance(alice, address(vault2), address(vault3));

        // make it pass a day
        vm.warp(block.timestamp + 1 days );

        // bot cannot rebalance to a non allowed vault
        vm.prank(dave);
        vm.expectRevert("Not allowed vault");
        positionManager.rebalance(alice, address(vault2), address(collateralVault));

        // bot cannot rebalance to a lowest rate vault
        vm.prank(dave);
        vm.expectRevert("Cannot rebalance to a lowest rate vault");
        positionManager.rebalance(alice, address(vault2), address(vault1));

        // bot can rebalance to a highest rate vault
        vm.prank(dave);
        positionManager.rebalance(alice, address(vault2), address(vault3));

        // alice's account balance on vault 2 is the initial minus twice operator's tips
        uint256 alicesBalance = 100e18 - 100e18 / 100; // after first rebalance
        assertEq(vault3.maxWithdraw(alice), alicesBalance - alicesBalance / 100 );
        // and dave has earned twice tips from alice
        assertEq(liabilityAsset.balanceOf(dave), 100e18 / 100 + alicesBalance / 100);
    }
}