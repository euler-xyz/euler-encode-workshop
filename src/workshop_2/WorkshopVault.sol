// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

import "openzeppelin/token/ERC20/extensions/ERC4626.sol";
import "evc/interfaces/IEthereumVaultConnector.sol";
import "evc/interfaces/IVault.sol";
import "./IWorkshopVault.sol";
import "./IPOracle.sol";


contract WorkshopVault is ERC4626, IVault, IWorkshopVault {
    IEVC internal immutable evc;
    IPOracle private oracle;
        using SafeMath for uint256;
    uint256 private _totalAssets;
    uint256 private totalSupply;

 mapping(address account => uint256 assets) own;
    constructor(
        IEVC _evc,
        IERC20 _asset,
        string memory _name,
        string memory _symbol,
         IPOracle _oracle

    ) ERC4626(_asset) ERC20(_name, _symbol) {
        evc = _evc;
         oracle = _oracle;
    }
 function _convertToAssets(uint256 shares, bool roundUp) internal view virtual returns (uint256) {
        uint256 numerator = roundUp ? shares.mul(_totalAssets.add(1)) : shares.mul(_totalAssets.add(1));
        uint256 denominator = roundUp ? totalSupply.add(1) : totalSupply.add(1);
        
        return numerator.div(denominator);
    }
    // [ASSIGNMENT]: what is the purpose of this modifier?
//he main purpose of the callThroughEVC modifier is to enforce having a proper authorization and authentication within the Euler Version Controller (EVC) system. This modifier ensures that when a function is called, it checks whether the caller (msg.sender) is authorized to perform operations on a specified account (onBehalfOfAccount). The modifier allows for flexible interaction with the EVC, granting authorization to sub-accounts, previously authorized operators, or the EVC itself in the case of a permit. 
    modifier callThroughEVC() {
        if (msg.sender == address(evc)) {
            _;
        } else {
            bytes memory result = evc.call(address(this), msg.sender, 0, msg.data);

            assembly {
                return(add(32, result), mload(result))
            }
        }
    }

    // [ASSIGNMENT]: why the account status check might not be necessary in certain situations?
//The absence of an account status check in certain situations may be justified when the operation being performed does not affect the account's balance or debt. BUT
//everytime it doesnt deal with the financial position of the account, such as reading data or executing operations unrelated to the account's financial state.

 // [ASSIGNMENT]: is the vault status check always necessary? why?
// the vault status check is crucial in most cases, as it verifies the overall health and integrity of the vault. The vault status check is required to ensure that the global state of the vault, including total balances and debts, remains valid after an operation.
//prevent potential vulnerabilities and maintain the reliability of the EVC system.
    modifier withChecks(address account) {
        _;

        if (account == address(0)) {
            evc.requireVaultStatusCheck();
        } else {
            evc.requireAccountAndVaultStatusCheck(account);
        }
    }

    // [ASSIGNMENT]: can this function be used to authenticate the account for the sake of the borrow-related operations? why?
//'_msgSender' function is not suitable for authenticating the account for borrow-related operations. The reason we consider the account on behalf of which the current operation is being performed in the context of the EVC.

    // [ASSIGNMENT]: if the answer to the above is "no", how this function could be modified to allow safe borrowing?
//To modify the function for safe borrowing, you would need to consider the actual borrower's address, not just the account on behalf of which the operation is being performed. A modified version could involve obtaining the borrower's address directly from msg.sender without relying on the EVC context.
    function _msgSender() internal view virtual override returns (address) {
        if (msg.sender == address(evc)) {
            (address onBehalfOfAccount,) = evc.getCurrentOnBehalfOfAccount(address(0));
            return onBehalfOfAccount;
        } else {
            return msg.sender;
        }
    }

    // IVault
    // [ASSIGNMENT]: why this function is necessary? is it safe to unconditionally disable the controller?
    //Only controller can call disableController on the EVC, if this value werer borrowablw we need to do  check if the user fully repaid their loan, if the controller disabled itself it means no longer can control the account, also other thing is if the user doens't repaid then user can walk away with their looan bevcause it has no control o over the what they provided as collateral.
    function disableController() external {
        evc.disableController(_msgSender());
    }



    // [ASSIGNMENT]: provide a couple use cases for this function
//This function evaluates account health, considering factors like borrow versus collateral values, and reverts if an imbalance is detected.This adaptability empowers vaults to consider diverse factors, including market conditions or user-specific parameters, when determining the overall health of an account.
    function checkAccountStatus(
        address account,
        address[] calldata collaterals
    ) public virtual returns (bytes4 magicValue) {
        require(msg.sender == address(evc), "only evc can call this");
        require(evc.areChecksInProgress(), "can only be called when checks in progress");
      (, uint256 borrowValue, uint256 collateralValue) = calcBorrowCollateral(account, collaterals);
            if (borrowValue > collateralValue) {
                revert ("Not healthy");
            }

        return IVault.checkAccountStatus.selector;
    }

     function calcBorrowCollateral(
        address account,
        address[] memory collaterals
    ) internal view returns (uint256 borrowAssets, uint256 borrowValue, uint256 collateralValue) {
        borrowValue = IPOracle(oracle).getQuote(borrowAssets, address(asset), address(referenceAsset));
        for (uint256 i = 0; i < collaterals.length; ++i) {
            ERC4626 collateral = ERC4626(collaterals[i]);
            uint256 collateralratio = collateralFactor[collateral];
            if (collateralratio= 0) {
                uint256 collateralShares = collateral.balanceOf(account);
                if (collateralShares > 0) {
                    uint256 collateralAssets = collateral.convertToAssets(collateralShares);
                    collateralValue += (
                        IPOracle(oracle).getQuote(
                            collateralAssets, address(collateral.asset()), address(referenceAsset)
                        ) * collateralratio
                    ) / 100;
                }
            }
        }
    }
    function doCreateVaultSnapshot() internal virtual override returns (bytes memory) {
        return abi.encode(_convertToAssets(totalSupply, false));
    }
       function checkVaultStatus() external onlyEVCWithChecksInProgress returns (bytes4 magicValue) {
        doCheckVaultStatus(snapshot);
        delete snapshot;

        return IVault.checkVaultStatus.selector;
    }


    // [ASSIGNMENT]: provide a couple use cases for this function
//It can validate various aspects, including supply cap enforcement, by comparing current and initial supply values derived from a snapshot. This ensures compliance with predefined limits and strengthens the protocol's risk management capabilities, contributing to the overall safety
    function checkVaultStatus() public virtual returns (bytes4 magicValue) {
        require(msg.sender == address(evc), "only evc can call this");
        require(evc.areChecksInProgress(), "can only be called when checks in progress");
   if (oldSnapshot.length == 0) revert SnapshotNotTaken();

        // validate the vault state here:
        uint256 initialSupply = abi.decode(oldSnapshot, (uint256));
        uint256 finalSupply = _convertToAssets(totalSupply, false);

        // the supply cap can be implemented like this:
        if (supplyCap != 0 && finalSupply > supplyCap && finalSupply > initialSupply) {
            revert ("exceedsupply");
        }
   delete snapshot;

        return IVault.checkVaultStatus.selector;

    }

    function deposit(
        uint256 assets,
        address receiver
    ) public virtual override callThroughEVC withChecks(address(0)) returns (uint256 shares) {
        return super.deposit(assets, receiver);
    }

    function mint(
        uint256 shares,
        address receiver
    ) public virtual override callThroughEVC withChecks(address(0)) returns (uint256 assets) {
        return super.mint(shares, receiver);
    }

    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public virtual override callThroughEVC withChecks(owner) returns (uint256 shares) {
        return super.withdraw(assets, receiver, owner);
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public virtual override callThroughEVC withChecks(owner) returns (uint256 assets) {
        return super.redeem(shares, receiver, owner);
    }

    function transfer(
        address to,
        uint256 value
    ) public virtual override (ERC20, IERC20) callThroughEVC withChecks(_msgSender()) returns (bool) {
        return super.transfer(to, value);
    }

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) public virtual override (ERC20, IERC20) callThroughEVC withChecks(from) returns (bool) {
        return super.transferFrom(from, to, value);
    }

    // IWorkshopVault
    function borrow(uint256 assets, address receiver) external {}
    function repay(uint256 assets, address receiver) external {}
    function pullDebt(address from, uint256 assets) external returns (bool) {}
    function liquidate(address violator, address collateral) external {}
}
