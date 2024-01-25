//SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

import {ERC4626Test} from "a16z-erc4626-tests/ERC4626.test.sol";
import "openzeppelin/mocks/token/ERC20Mock.sol";
import "evc/EthereumVaultConnector.sol";
import "../../src/workshop_2/WorkshopVault.sol";
import {console} from "../../lib/forge-std/src/console.sol";

contract TestVault is WorkshopVault {
    bool internal shouldRunOriginalAccountStatusCheck;
    bool internal shouldRunOriginalVaultStatusCheck;

    constructor(
        IEVC _evc,
        IERC20 _asset,
        string memory _name,
        string memory _symbol
    ) WorkshopVault(_evc, _asset, _name, _symbol) {}

    function setShouldRunOriginalAccountStatusCheck(
        bool _shouldRunOriginalAccountStatusCheck
    ) external {
        shouldRunOriginalAccountStatusCheck = _shouldRunOriginalAccountStatusCheck;
    }

    function setShouldRunOriginalVaultStatusCheck(
        bool _shouldRunOriginalVaultStatusCheck
    ) external {
        shouldRunOriginalVaultStatusCheck = _shouldRunOriginalVaultStatusCheck;
    }

    function checkAccountStatus(address account, address[] calldata collaterals)
        public
        override
        returns (bytes4 magicValue)
    {
        return
            !shouldRunOriginalAccountStatusCheck
                ? super.checkAccountStatus(account, collaterals)
                : this.checkAccountStatus.selector;
    }

    function checkVaultStatus() public override returns (bytes4 magicValue) {
        return
            shouldRunOriginalVaultStatusCheck
                ? super.checkVaultStatus()
                : this.checkVaultStatus.selector;
    }
}

contract VaultTest is ERC4626Test {
    IEVC _evc_;

    function setUp() public override {
        _evc_ = new EthereumVaultConnector();
        _underlying_ = address(new ERC20Mock());
        _delta_ = 0;
        _vaultMayBeEmpty = false;
        _unlimitedAmount = false;
        _vault_ = address(
            new WorkshopVault(_evc_, IERC20(_underlying_), "Vault", "VLT")
        );
    }

    function test_DepositWithEVC(address alice, uint64 amount) public {
        vm.assume(
            alice != address(0) &&
                alice != address(_evc_) &&
                alice != address(_vault_)
        );
        vm.assume(amount > 0);

        ERC20 underlying = ERC20(_underlying_);
        WorkshopVault vault = WorkshopVault(_vault_);

        // mint some assets to alice
        ERC20Mock(_underlying_).mint(alice, amount);

        // alice approves the vault to spend her assets
        vm.prank(alice);
        underlying.approve(address(vault), type(uint256).max);

        // alice deposits assets through the EVC
        vm.prank(alice);
        _evc_.call(
            address(vault),
            alice,
            0,
            abi.encodeWithSelector(IERC4626.deposit.selector, amount, alice)
        );
        console.log(address(_evc_));

        // verify alice's balance
        assertEq(underlying.balanceOf(alice), 0);
        assertEq(vault.convertToAssets(vault.balanceOf(alice)), amount);
    }

    function test_assignment_BasicFlow(
        address alice,
        address bob,
        address charlie,
        uint64 amount
    ) public {
        vm.assume(
            alice != address(0) &&
                alice != address(_evc_) &&
                alice != address(_vault_)
        );
        vm.assume(
            bob != address(0) &&
                bob != address(_evc_) &&
                bob != address(_vault_)
        );
        vm.assume(
            charlie != address(0) &&
                charlie != address(_evc_) &&
                charlie != address(_vault_)
        );
        vm.assume(
            !_evc_.haveCommonOwner(alice, bob) &&
                !_evc_.haveCommonOwner(alice, charlie) &&
                !_evc_.haveCommonOwner(bob, charlie)
        );
        vm.assume(amount > 100);

        uint256 amountToBorrow = amount / 2;
        ERC20 underlying = ERC20(_underlying_);
        WorkshopVault vault = WorkshopVault(_vault_);

        // mint some assets to alice
        ERC20Mock(_underlying_).mint(alice, amount);

        // make charlie an operator of alice's account
        vm.prank(alice);
        _evc_.setAccountOperator(alice, charlie, true);

        // alice approves the vault to spend her assets
        vm.prank(alice);
        underlying.approve(address(vault), type(uint256).max);
        //address simulatedCollateral = makeAddr("collateralVault");
        //   _evc_.enableCollateral(alice,simulatedCollateral);

        // charlie deposits assets on alice's behalf
        vm.prank(charlie);
        _evc_.call(
            address(vault),
            alice,
            0,
            abi.encodeWithSelector(IERC4626.deposit.selector, amount, alice)
        );
        //   vm.deal(address(vault),1 ether);
        // console.log(underlying.balanceOf(address(vault)));
        // verify alice's balance
        assertEq(underlying.balanceOf(alice), 0);
        assertEq(vault.convertToAssets(vault.balanceOf(alice)), amount);

        // // alice tries to borrow assets from the vault, should fail due to controller disabled
        vm.prank(alice);
        vm.expectRevert();
        vault.borrow(amount, alice);

        // // alice enables controller
        vm.prank(alice);
        _evc_.enableController(alice, address(vault));

        // // alice tries to borrow again, now it should succeed
        vm.prank(alice);
        vault.borrow(amountToBorrow, alice);
        
    
        // // varify alice's balance. despite amount borrowed, she should still hold shares worth the full amount
         assertEq(underlying.balanceOf(alice), amountToBorrow);
         assertEq(vault.convertToAssets(vault.balanceOf(alice)), amount);

        // // verify maxWithdraw and maxRedeem functions
        assertEq(vault.maxWithdraw(alice), amount - amountToBorrow);
        assertEq(vault.convertToAssets(vault.maxRedeem(alice)), amount - amountToBorrow);

        // // verify conversion functions
         assertEq(vault.convertToShares(amount), vault.balanceOf(alice));
         assertEq(vault.convertToAssets(vault.balanceOf(alice)), amount);

        // // alice tries to disable controller, it should fail due to outstanding debt
        vm.prank(alice);
        vm.expectRevert();
        vault.disableController();

        // // bob tries to pull some debt from alice's account, it should fail due to disabled controller
        vm.prank(bob);
        vm.expectRevert();
        vault.pullDebt(alice, amountToBorrow / 2);

        // // bob enables controller
        vm.prank(bob);
        _evc_.enableController(bob, address(vault));

        // // bob tries again to pull some debt from alice's account, it should succeed now
        vm.prank(bob);
        vault.pullDebt(alice, amountToBorrow / 2);

        // // charlie repays part of alice's debt using her assets
        vm.prank(charlie);
        _evc_.call(
            address(vault),
            alice,
            0,
            abi.encodeWithSelector(WorkshopVault.repay.selector, amountToBorrow - amountToBorrow / 2, alice)
        );

        // // verify alice's balance
        assertEq(underlying.balanceOf(alice), amountToBorrow / 2);
        assertEq(vault.convertToAssets(vault.balanceOf(alice)), amount);

        // // alice can disable the controller now
        vm.prank(alice);
        vault.disableController();

        // // bob tries to disable the controller, it should fail due to outstanding debt
        vm.prank(bob);
        vm.expectRevert();
        vault.disableController();

        // // alice repays bob's debt
        vm.prank(alice);
        vault.repay(amountToBorrow / 2, bob);

        // // verify bob's balance
        assertEq(underlying.balanceOf(bob), 0);

        // // bob can disable the controller now
         vm.prank(bob);
         vault.disableController();
    }

    function test_assigment_InterestAccrual(address alice, uint64 amount)
        public
    {
        vm.assume(
            alice != address(0) &&
                alice != address(_evc_) &&
                alice != address(_vault_)
        );
        vm.assume(amount > 1e18);

        ERC20 underlying = ERC20(_underlying_);
        WorkshopVault vault = WorkshopVault(_vault_);

        // mint some assets to alice
        ERC20Mock(_underlying_).mint(alice, amount);

        // alice approves the vault to spend her assets
        vm.prank(alice);
        underlying.approve(address(vault), type(uint256).max);

        // alice deposits the assets
        vm.prank(alice);
        vault.deposit(amount, alice);

        // verify alice's balance
        assertEq(underlying.balanceOf(alice), 0);
        assertEq(vault.convertToAssets(vault.balanceOf(alice)), amount);

        // alice enables controller
        vm.prank(alice);
        _evc_.enableController(alice, address(vault));

        // alice borrows assets from the vault
        vm.prank(alice);
        vault.borrow(amount, alice);

        // allow some time to pass to check if interest accrues
        vm.roll(365 days);
        vm.warp(365 days / 12);

        // repay the amount borrowed. if interest accrues, alice should still have outstanding debt
        vm.prank(alice);
        vault.repay(amount, alice);

        // try to disable controller, it should fail due to outstanding debt if interest accrues
        vm.prank(alice);
        vm.expectRevert();
        vault.disableController();
    }
}
