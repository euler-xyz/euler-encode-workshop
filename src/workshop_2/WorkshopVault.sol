// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

import "openzeppelin/token/ERC20/extensions/ERC4626.sol";
import "evc/interfaces/IEthereumVaultConnector.sol";
import "evc/interfaces/IVault.sol";
import "./IWorkshopVault.sol";
import {Math} from "../../openzeppelin/utils/math/Math.sol";
import {console} from "../../lib/forge-std/src/console.sol";
import {ReentrancyGuard} from "../../openzeppelin/utils/ReentrancyGuard.sol";

///////////////////FOR SIMPLICITY, THIS VAULT ONLY SUPPORT LENDING AND BORROWING////////////////////////////////
///////////////////>>>>>>>>>>>>>>>>///////////////////////////////
//1. LENDING THE BASE ASSET 
//2. LIQUIDATING UNDER-COLLATERIZED LOAN
//3. DEPOSIT USDT AND BE AWARDED THE VAULT TOKEN AS SHARES WITH INTEREST ACCRUAL ON YOUR SHARES OVER TIME.

//reserve factor” — a percentage of capital supplied by lenders that they do not receive interest on.
// The interest from this capital instead goes to the protocol

//UTILIZATION = BORROWED/TOTAL DEPOSIT
//SUPPLY INTEREST RATE = BORROW INTEREST RATE * UTILIZATION * (1 - RESERVE FACTOR)
//OPTIMAL UTILIZATION = 80% - 95%
//COLLATERAL_FACTOR = LOAN VALUE/ COLLATERAL_VALUE
//@Note The loan to value is the current value of the loan as a percentage of the collateral value
//liquidation factor — a threshold percentage at which the collateral can be forcibly taken from the borrower.

contract WorkshopVault is ERC4626, IVault, IWorkshopVault, ReentrancyGuard {
    //error
    error unAbleToBorrow();
    error stillOwing();

    using Math for uint;
    IEVC internal immutable evc;
    IERC20 assetToBorrow;

    //Storage variable
    uint256 public s_totalAmountBorrowedFromVault;
    bytes private takeSnapshot;
    uint public totalBorrowedAssets;
    uint internal _totalAssets;
    uint internal interestTimeStamp;
    uint internal interestRate;

    mapping(address => uint256) public accountAccruedDebt;
    mapping(address => uint256) public balanceOfShares;

    constructor(
        IEVC _evc,
        IERC20 _asset,
        string memory _name,
        string memory _symbol
    ) ERC4626(_asset) ERC20(_name, _symbol) {
        evc = _evc;
        assetToBorrow = _asset;
        interestTimeStamp = block.timestamp;
    }

    // [ASSIGNMENT]: what is the purpose of this modifier?
    modifier callThroughEVC() {
        if (msg.sender == address(evc)) {
            _;
        } else {
            bytes memory result = evc.call(
                address(this),
                msg.sender,
                0,
                msg.data
            );

            assembly {
                return(add(32, result), mload(result))
            }
        }
    }

    modifier withChecks(address account) {
        //take the snapshot of the vault/account

        //ALWAYS take the most recent snapshot of the vault by including "withChecks" modifier
        //on any vault changing function
        takeSnapshot = abi.encode(
            _convertToAssets(totalAssets(), Math.Rounding.Floor),
            totalBorrowedAssets
        );

        _;

        if (account == address(0)) {
            evc.requireVaultStatusCheck();
        } else {
            evc.requireAccountAndVaultStatusCheck(account);
        }
    }

    function _calculateBorrowInterest() internal returns (bool) {
        ///UTILIZATION DETERMINES BORROW INTEREST RATES
        ///UTILIZATION = BORROWED/TOTAL Deposits
        ///let's get the current utilization
        //@audit not a production maths
        if (block.timestamp - interestTimeStamp > 0) {
            //hardcode interest rate
            return true;
        }
        interestTimeStamp = block.timestamp;
        return false;
    }

    function convertToAssets(uint256 shares)
        public
        view
        virtual
        override
        returns (uint256)
    {
        return shares;
    }

    function maxWithdraw(address owner)
        public
        view
        virtual
        override
        returns (uint256)
    {
        uint256 currentTotalAssets = totalAssets();
        uint256 ownerAssets = convertToAssets(
            balanceOfShares[owner] - accountAccruedDebt[owner]
        );

        if (ownerAssets > currentTotalAssets) {
            return currentTotalAssets;
        } else {
            return ownerAssets;
        }
    }

    function disableController() external nonReentrant {
        if (accountAccruedDebt[_msgSender()] > 0) {
            revert stillOwing();
        } else {
            evc.disableController(_msgSender());
        }
    }

    function checkAccountStatus(address account, address[] calldata collaterals)
        public
        virtual
        returns (bytes4 magicValue)
    {
        require(msg.sender == address(evc), "only evc can call this");
        require(
            evc.areChecksInProgress(),
            "can only be called when checks in progress"
        );
        //do you have an outstanding debt?
        uint accountDebt = accountAccruedDebt[account];

        //logic to check if the account is healthy
        //We can keep it minimal. However,for fully functional lending dapp, we will use oracle
        //pricefeed to determine the value of the collaterals relative to the asset value we lend out

        //loan value= collateral_factor * collateral_value
        //Therefore, loan_value > debt ? accountHealthy: accountUnHealthyStatus;
       

        /////////////////////////////////////HARDCODED/////////////////////////////
        require(accountDebt < type(uint104).max, "unhealthy Account");

        return IVault.checkAccountStatus.selector;
    }


    function checkVaultStatus() public virtual returns (bytes4 magicValue) {
        require(msg.sender == address(evc), "only evc can call this");
        require(
            evc.areChecksInProgress(),
            "can only be called when checks in progress"
        );

      
        //withChecks modifier must have taken the snapshot of the vault
        require(takeSnapshot.length != 0, "snapShot must have been taken");

        (uint256 sharesSupply, uint256 borrowLevel) = abi.decode(
            takeSnapshot,
            (uint256, uint256)
        );
        uint256 currentSupply = _convertToAssets(
            totalSupply(),
            Math.Rounding.Floor
        );

       

        delete takeSnapshot;

        return IVault.checkVaultStatus.selector;
    }

    function deposit(uint256 assets, address receiver)
        public
        virtual
        override
        callThroughEVC
        withChecks(address(0))
        nonReentrant
        returns (uint256 shares)
    {
        assetToBorrow.transferFrom(_msgSender(), address(this), assets);
        _totalAssets += assets;
        shares = _convertToShares(assets, Math.Rounding.Floor);
        balanceOfShares[receiver] += shares;

         mint(shares, receiver);
       
    }

    function totalAssets() public view virtual override returns (uint256) {
        return _totalAssets;
    }

    function mint(uint256 shares, address receiver)
        public
        virtual
        override
        withChecks(address(0))
        returns (uint256 assets)
    {
        _mint(receiver, shares);
    }

    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    )
        public
        virtual
        override
        callThroughEVC
        withChecks(owner)
        returns (uint256 shares)
    {
        return super.withdraw(assets, receiver, owner);
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    )
        public
        virtual
        override
        callThroughEVC
        withChecks(owner)
        returns (uint256 assets)
    {
        return super.redeem(shares, receiver, owner);
    }

    function transfer(address to, uint256 value)
        public
        virtual
        override(ERC20, IERC20)
        callThroughEVC
        withChecks(_msgSender())
        returns (bool)
    {
        return super.transfer(to, value);
    }

    function _convertToAssets(uint256 shares, Math.Rounding rounding)
        internal
        view
        virtual
        override
        returns (uint256)
    {
        return shares;
    }

    function _convertToShares(uint256 assets, Math.Rounding rounding)
        internal
        view
        virtual
        override
        returns (uint256)
    {
        return assets;
    }

    // IWorkshopVault
    function borrow(uint256 assets, address receiver)
        external
        callThroughEVC
        withChecks(_msgSenderBorrower())
        nonReentrant
    {
        //////////////////////CHECKS
        if (!evc.isControllerEnabled(_msgSender(), address(this))) {
            revert unAbleToBorrow();
        }
        require(assets != 0, "asset cannot be zero");

        ///UPDATE STATES
        accountAccruedDebt[_msgSender()] += assets;
        totalBorrowedAssets += assets;

        //EXTERNAL CALLS
        assetToBorrow.transfer(receiver, assets);
    }

    function maxRedeem(address owner)
        public
        view
        virtual
        override
        returns (uint256)
    {
        uint256 totalCurrentAssets = totalAssets();
        uint256 ownerShares = this.balanceOf(owner) - accountAccruedDebt[owner];

        return
            _convertToAssets(ownerShares, Math.Rounding.Floor) >
                totalCurrentAssets
                ? _convertToShares(totalCurrentAssets, Math.Rounding.Floor)
                : ownerShares;
    }

    function repay(uint256 assets, address receiver)
        external
        withChecks(address(0))
        nonReentrant
    {
        if (!evc.isControllerEnabled(receiver, address(this))) {
            revert("is Disabled");
        }
        //BORROW INTEREST ACCRUED
        require(assets != 0, "NO ASSET VALUE");
        if (_calculateBorrowInterest()) {
            accountAccruedDebt[receiver] += 1;
        }
        accountAccruedDebt[receiver] -= assets;

        totalBorrowedAssets -= assets;

        assetToBorrow.transferFrom(_msgSender(), address(this), assets);
    }

    function pullDebt(address from, uint256 assets)
        external
        callThroughEVC
        withChecks(_msgSender())
        nonReentrant
        returns (bool)
    {
        //ensure the address calling is under the control of EVC
        if (!evc.isControllerEnabled(_msgSender(), address(this))) {
            revert("is Disabled");
        }
        require(assets != 0, "invalid");
        require(_msgSender() != from, "selfcall error");
        accountAccruedDebt[from] -= assets;
        accountAccruedDebt[_msgSender()] += assets;
        return true;
    }

    function liquidate(address violator, address collateral)
        external
        callThroughEVC
        withChecks(_msgSender())
        nonReentrant
    {
        //@audit for now,  the vault needs to pay the debt, huh? bad business lol
        uint assetDebt = accountAccruedDebt[violator];

        //get the value of the asset using pricefeed during full implementation

        //get the collateral
        uint collateralValue = ERC4626(collateral).balanceOf(violator);
        if (assetDebt > collateralValue) {
            bytes memory result = evc.controlCollateral(
                address(this),
                violator,
                0,
                abi.encodeCall(this.transfer, (address(this), collateralValue))
            );

            //decode the bytes result
            bool success = abi.decode(result, (bool));
            if (success) {
                accountAccruedDebt[address(this)] += (assetDebt -
                    collateralValue);
                ///bad debt <sad>
                evc.forgiveAccountStatusCheck(violator);
            }
        }
    }

    function _msgSender() internal view virtual override returns (address) {
        if (msg.sender == address(evc)) {
            (address onBehalfOfAccount, ) = evc.getCurrentOnBehalfOfAccount(
                address(this)
            );
            return onBehalfOfAccount;
        } else {
            return msg.sender;
        }
    }

    function transferFrom(
        address from,
        address to,
        uint256 value
    )
        public
        virtual
        override(ERC20, IERC20)
        callThroughEVC
        withChecks(from)
        returns (bool)
    {
        return super.transferFrom(from, to, value);
    }

    function _msgSenderBorrower() internal view virtual returns (address) {
        bool enabled;
        if (msg.sender == address(evc)) {
            (address onBehalfOfAccount, ) = evc.getCurrentOnBehalfOfAccount(
                address(0)
            );
            return onBehalfOfAccount;
        } else {
            enabled = evc.isControllerEnabled(msg.sender, address(this));
            require(enabled, "controller disabled");
        }
        return msg.sender;
    }
}
