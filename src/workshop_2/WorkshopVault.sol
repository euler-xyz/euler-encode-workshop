//SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

import "openzeppelin/token/ERC20/extensions/ERC4626.sol";
import "evc/interfaces/IEthereumVaultConnector.sol";
import "evc/interfaces/IVault.sol";
import "./IWorkshopVault.sol";

contract WorkshopVault is ERC4626, IVault, IWorkshopVault {
    IEVC internal immutable evc;
    uint internal totalBorrowedasset;
    IERC20 assetss;

    //assumption
    uint internal borrowCap = type(uint104).max;

    error NO_asset();

    mapping(address => uint) internal balanceOfs;
    mapping(address => uint) internal debtor;

    event Borrow(address operator, address onBehalfOf, uint amount);
    event Repay(address operator, address onBehalfOf, uint amount);
    event deposits(uint amount, address from, address onBehalfOf);

    constructor(
        IEVC _evc,
        IERC20 _asset,
        string memory _name,
        string memory _symbol
    ) ERC4626(_asset) ERC20(_name, _symbol) {
        evc = _evc;
        assetss = _asset;
    }

  
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
        //do take the snapshot of the vault and compare with the borrow cap
        //totalBorrowedasset > borrowCap ? revert

        _;

        if (account == address(0)) {
            evc.requireVaultStatusCheck();
        } else {
            evc.requireAccountAndVaultStatusCheck(account);
        }
    }

    function _msgSender() internal view virtual override returns (address) {
        if (msg.sender == address(evc)) {
            (address onBehalfOfAccount, ) = evc.getCurrentOnBehalfOfAccount(
                address(0)
            );
            return onBehalfOfAccount;
        } else {
            return msg.sender;
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

        // some custom logic evaluating the account health

        return IVault.checkAccountStatus.selector;
    }

  
    function checkVaultStatus() public virtual returns (bytes4 magicValue) {
        require(msg.sender == address(evc), "only evc can call this");
        require(
            evc.areChecksInProgress(),
            "can only be called when checks in progress"
        );

        // some custom logic evaluating the vault health
        if (totalBorrowedasset > borrowCap) {
            revert("borrow cap exceeded");
        }
        //EIP-7265 should implemented here to control large outflow of funds

        // [ASSIGNMENT]: what can be done if the vault status check needs access to the initial state of the vault in
        // order to evaluate the vault health?

        return IVault.checkVaultStatus.selector;
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


    function _updateState(uint assets) internal returns (bool) {
        uint shares = previewDeposit(assets);
        if (shares > 0) {
            return true;
        }
        return false;
    }

    function deposit(uint256 assets, address receiver)
        public
        virtual
        override
        callThroughEVC
        withChecks(address(0))
        returns (uint256 shares)
    {
        require(assets > 0, "INVALID asset");
        assetss.transferFrom(_msgSender(), address(this), assets);
        balanceOfs[receiver] += assets;
        _mint(receiver, assets);

        emit deposits(assets, receiver, _msgSender());
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

    function mint(uint256 shares, address receiver)
        public
        virtual
        override
        callThroughEVC
        withChecks(address(0))
        returns (uint256 assets)
    {
        return super.mint(shares, receiver);
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
     function disableController() external {
        if (debtor[_msgSender()] > 0) {
            revert();
        } else {
            evc.disableController(_msgSender());
        }
    }


    function borrow(uint256 assets, address receiver)
        external
        callThroughEVC
        withChecks(_msgSenderBorrower())
    {
        require(
            evc.isControllerEnabled(_msgSender(), address(this)),
            "oops you can't borrow"
        );

        if (assets <= 0) {
            revert NO_asset();
        }

        debtor[_msgSenderBorrower()] += assets;
        totalBorrowedasset += assets;

        assetss.transfer(receiver, assets);
    }

    function repay(uint256 assets, address receiver)
        external
        callThroughEVC
        withChecks(address(0))
    {
        require(assets != 0, "ZERO_assetS");
        require(
            evc.isControllerEnabled(receiver, address(this)),
            "controller not enabled for this operator"
        );
        debtor[receiver] -= assets;
        totalBorrowedasset -= assets;
        emit Repay(_msgSender(), receiver, assets);
        assetss.transferFrom(_msgSender(), address(this), assets);
    }

    function pullDebt(address from, uint256 assets)
        external
        callThroughEVC
        withChecks(_msgSender())
        returns (bool)
    {
        require(
            evc.isControllerEnabled(_msgSender(), address(this)),
            "controller not enabled for this operator"
        );

        require(assets != 0, "no amount");

        debtor[_msgSender()] += assets;
        debtor[from] -= assets;

        return true;
    }

    function liquidate(address violator, address collateral)
        external
        callThroughEVC
        withChecks(_msgSender())
    {
        uint debt = debtor[violator];
        //if debt value > collateral value
        //UNDER_COLLATERIZED LOAN?
    }

    function maxWithdraw(address owner)
        public
        view
        virtual
        override
        returns (uint256)
    {
        uint256 borrowedassets = totalAssets();
        uint256 ownerassets = convertToAssets(
            balanceOfs[owner] - debtor[owner]
        );

        return ownerassets > borrowedassets ? borrowedassets : ownerassets;
    }

    function maxRedeem(address owner)
        public
        view
        virtual
        override
        returns (uint256)
    {
        uint256 borrowedassets = totalAssets();
        uint256 ownerShares = balanceOfs[owner];

        return
            convertToAssets(ownerShares) > borrowedassets
                ? _convertToShares(borrowedassets, Math.Rounding.Floor)
                : ownerShares;
    }

   
}

