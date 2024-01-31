// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

import {ERC4626Test} from "a16z-erc4626-tests/ERC4626.test.sol";
import "openzeppelin/mocks/token/ERC20Mock.sol";
import "evc/EthereumVaultConnector.sol";
import "../../src/workshop_2/WorkshopVault.sol";
import {CircuitBreaker, WorkshopVaultCircuitBreaker} from "../../src/workshop_2/WorkshopVaultCircuitBreaker.sol";
import {LimiterLib} from "../../src/workshop_2/utils/LimiterLib.sol";

contract TestVault is WorkshopVaultCircuitBreaker {
    bool internal shouldRunOriginalAccountStatusCheck;
    bool internal shouldRunOriginalVaultStatusCheck;

    constructor(
        address _circuitBreaker,
        IEVC _evc,
        ERC20 _asset,
        string memory _name,
        string memory _symbol
    ) WorkshopVaultCircuitBreaker(_circuitBreaker, _evc, _asset, _name, _symbol) {}

    function setShouldRunOriginalAccountStatusCheck(bool _shouldRunOriginalAccountStatusCheck) external {
        shouldRunOriginalAccountStatusCheck = _shouldRunOriginalAccountStatusCheck;
    }

    function setShouldRunOriginalVaultStatusCheck(bool _shouldRunOriginalVaultStatusCheck) external {
        shouldRunOriginalVaultStatusCheck = _shouldRunOriginalVaultStatusCheck;
    }

    function checkAccountStatus(
        address account,
        address[] calldata collaterals
    ) public override returns (bytes4 magicValue) {
        return shouldRunOriginalAccountStatusCheck
            ? super.checkAccountStatus(account, collaterals)
            : this.checkAccountStatus.selector;
    }

    function checkVaultStatus() public override returns (bytes4 magicValue) {
        return shouldRunOriginalVaultStatusCheck ? super.checkVaultStatus() : this.checkVaultStatus.selector;
    }
}

contract VaultTest is ERC4626Test {
    IEVC _evc_;
    address internal NATIVE_ADDRESS_PROXY = address(1);
    CircuitBreaker internal _circuitBreaker_;
    address internal alice = vm.addr(0x1);
    address internal bob = vm.addr(0x2);
    address internal admin = vm.addr(0x3);

    function setUp() public override {
        _circuitBreaker_ = new CircuitBreaker(admin, 3 days, 4 hours, 5 minutes);
        _evc_ = new EthereumVaultConnector();
        _underlying_ = address(new ERC20Mock());
        _delta_ = 0;
        _vaultMayBeEmpty = false;
        _unlimitedAmount = false;
        _vault_ = address(new TestVault(address(_circuitBreaker_), _evc_, ERC20(_underlying_), "Vault", "VLT"));

        address[] memory addresses = new address[](1);
        addresses[0] = address(_vault_);

        vm.prank(admin);
        _circuitBreaker_.addProtectedContracts(addresses);
        vm.prank(admin);
        // Protect ERC20Token with 70% max drawdown per 4 hours
        _circuitBreaker_.registerAsset(address(_underlying_), 7000, 1000e18);
        vm.prank(admin);
        _circuitBreaker_.registerAsset(NATIVE_ADDRESS_PROXY, 7000, 1000e18);
        vm.warp(1 hours);
    }

    function test_CB_DepositWithEVC() public {
        // vm.assume(charlie != address(0) && charlie != address(_evc_) && charlie != address(_vault_));
        // vm.assume(amount > 10000e18);
        uint256 amount = 10000e18;
        uint256 amountDeposited = 10e18;

        // uint256 amountToBorrow = amount / 2;

        ERC20 underlying = ERC20(_underlying_);
        WorkshopVaultCircuitBreaker vault = WorkshopVaultCircuitBreaker(_vault_);

        // mint some assets to alice
        ERC20Mock(_underlying_).mint(alice, amount);

        // alice approves the vault to spend her assets
        vm.prank(alice);
        underlying.approve(address(vault), type(uint256).max);

        // make bob an operator of alice's account
        vm.prank(alice);
        _evc_.setAccountOperator(alice, bob, true);

        // // alice deposits assets through the EVC
        // vm.prank(alice);
        // _evc_.call(address(vault), alice, 0, abi.encodeWithSelector(IERC4626.deposit.selector, amount, alice));

        // bob deposits assets on alice's behalf
        vm.prank(bob);
        _evc_.call(address(vault), alice, 0, abi.encodeWithSelector(IERC4626.deposit.selector, amountDeposited, alice));

        // verify alice's balance
        assertEq(underlying.balanceOf(alice), amount - amountDeposited);
        assertEq(vault.convertToAssets(vault.balanceOf(alice)), amountDeposited);

        // alice tries to borrow assets from the vault, should fail due to controller disabled
        vm.prank(alice);
        vm.expectRevert();
        vault.borrow(amountDeposited, alice);

        // alice enables controller
        vm.prank(alice);
        _evc_.enableController(alice, address(vault));

        // // alice tries to borrow again, now it should succeed
        // vm.prank(alice);
        // vault.borrow(amountToBorrow, alice);

        // verify alice's balance. despite amount borrowed, she should still hold shares worth the full amount
        // assertEq(underlying.balanceOf(alice), amountToBorrow);
        // assertEq(vault.convertToAssets(vault.balanceOf(alice)), amount);

        // repay the amount borrowed. if interest accrues, alice should still have outstanding debt
        // vm.prank(alice);
        // vault.repay(amount, alice);

        // // verify maxWithdraw and maxRedeem functions
        // assertEq(vault.convertToAssets(vault.maxRedeem(alice)), amount - amountToBorrow);
        assertEq(vault.maxWithdraw(alice), amountDeposited);
        // vm.prank(alice);
        // //
        // _evc_.call(
        //     address(vault),
        //     alice,
        //     0,
        //     abi.encodeWithSelector(IERC4626.withdraw.selector, amountDeposited - 9e18 , alice, address(vault))
        // );
        // assertEq(underlying.balanceOf(alice), amount - 9e18);
        // // vault.withdraw(amountDeposited,alice,address(vault));
        // vm.prank(alice);
        // _evc_.call(address(vault), alice, 0, abi.encodeWithSelector(IERC4626.deposit.selector, amountDeposited ,
        // alice));
        // assertEq(underlying.balanceOf(alice), amount - amountDeposited);

        assertEq(_circuitBreaker_.isRateLimitTriggered(address(underlying)), false);
        vm.warp(1 hours);
        vm.prank(bob);
        // vault.withdraw(amountToBorrow - amountToBorrow / 2,alice,address(vault));
        // _evc_.call(
        //     address(vault),
        //     alice,
        //     0,
        //     abi.encodeWithSelector(WorkshopVault.repay.selector, amountToBorrow - amountToBorrow / 2 , alice)
        // );
        assertEq(_circuitBreaker_.isRateLimitTriggered(address(underlying)), false);

        (,, int256 liqTotal, int256 liqInPeriod, uint256 head, uint256 tail) =
            _circuitBreaker_.tokenLimiters(address(underlying));
        assertEq(head, tail);
        assertEq(liqTotal, 0);
        assertEq(liqInPeriod, 10e18);

        (uint256 nextTimestamp, int256 amountx) = _circuitBreaker_.tokenLiquidityChanges(address(underlying), head);
        assertEq(nextTimestamp, 0);
        assertEq(amountx, 10e18);

        vm.warp(1 hours);
        vm.prank(alice);
        _evc_.call(address(vault), alice, 0, abi.encodeWithSelector(IERC4626.deposit.selector, 110e18, alice));
        assertEq(_circuitBreaker_.isRateLimitTriggered(address(underlying)), false);
        (,, liqTotal, liqInPeriod,,) = _circuitBreaker_.tokenLimiters(address(underlying));
        assertEq(liqTotal, 0);
        assertEq(liqInPeriod, 120e18);

        // All the previous deposits are now out of the window and accounted for in the historacle
        vm.warp(10 hours);
        vm.prank(alice);
        _evc_.call(address(vault), alice, 0, abi.encodeWithSelector(IERC4626.deposit.selector, 10e18, alice));
        assertEq(_circuitBreaker_.isRateLimitTriggered(address(underlying)), false);
        (,, liqTotal, liqInPeriod, head, tail) = _circuitBreaker_.tokenLimiters(address(underlying));
        assertEq(liqTotal, 120e18);
        assertEq(liqInPeriod, 10e18);

        assertEq(head, block.timestamp);
        assertEq(tail, block.timestamp);
        assertEq(head % 5 minutes, 0);
        assertEq(tail % 5 minutes, 0);
    }
}
