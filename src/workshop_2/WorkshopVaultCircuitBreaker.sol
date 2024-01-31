// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

import {LimiterLib, LimitStatus, Limiter, LiqChangeNode} from "./utils/LimiterLib.sol";
import "./WorkshopVault.sol";
import "./ICircuitBreaker.sol";

/// @title WorkshopVaultCircuitBreaker
/// @notice This contract extends WorkshopVault with additional feature like Circuit Breaker
contract WorkshopVaultCircuitBreaker is WorkshopVault {
    using SafeERC20 for IERC20;

    address private _owner;
    mapping(address => bool) private _allowed;
    bool private _emergency;

    // Circuit Breaker
    ICircuitBreaker public circuitBreaker;

    constructor(
        address _circuitBreaker,
        IEVC _evc,
        ERC20 _asset,
        string memory _name,
        string memory _symbol
    ) WorkshopVault(_evc, _asset, _name, _symbol) {
        circuitBreaker = ICircuitBreaker(_circuitBreaker);
    }

    // Internal function to be used when tokens are deposited
    // Transfers the tokens from sender to recipient and then calls the circuitBreaker's onTokenInflow
    function cbInflowTransfer(address _token, address _to, uint256 _amount) internal {
        // Transfer the tokens safely from sender to recipient
        ERC20(_token).transfer(_to, _amount);
        // Call the circuitBreaker's onTokenInflow
        circuitBreaker.onTokenInflow(_token, _amount);
    }

    function cbInflowSafeTransferFrom(address _token, address _sender, address _recipient, uint256 _amount) internal {
        // Transfer the tokens safely from sender to recipient
        IERC20(_token).safeTransferFrom(_sender, _recipient, _amount);
        // Call the circuitBreaker's onTokenInflow
        circuitBreaker.onTokenInflow(_token, _amount);
    }

    // Internal function to be used when tokens are withdrawn
    // Transfers the tokens to the circuitBreaker and then calls the circuitBreaker's onTokenOutflow
    function cbOutflowSafeTransfer(
        address _token,
        address _recipient,
        uint256 _amount,
        bool _revertOnRateLimit
    ) internal {
        // Transfer the tokens safely to the circuitBreaker
        IERC20(_token).safeTransfer(address(circuitBreaker), _amount);
        // Call the circuitBreaker's onTokenOutflow
        circuitBreaker.onTokenOutflow(_token, _amount, _recipient, _revertOnRateLimit);
    }

    function cbInflowNative() internal {
        // Transfer the tokens safely from sender to recipient
        circuitBreaker.onNativeAssetInflow(msg.value);
    }

    function cbOutflowNative(address _recipient, uint256 _amount, bool _revertOnRateLimit) internal {
        // Transfer the native tokens safely through the circuitBreaker
        circuitBreaker.onNativeAssetOutflow{value: _amount}(_recipient, _revertOnRateLimit);
    }

    function doCheckVaultStatus(bytes memory oldSnapshot) public virtual override {
        // sanity check in case the snapshot hasn't been taken
        if (oldSnapshot.length == 0) revert SnapshotNotTaken();

        // use the vault status hook to update the interest rate (it should happen only once per transaction).
        // EVC.forgiveVaultStatus check should never be used for this vault, otherwise the interest rate will not be
        // updated.
        _updateInterest();

        // validate the vault state here:
        (uint256 initialSupply, uint256 initialBorrowed) = abi.decode(oldSnapshot, (uint256, uint256));
        uint256 finalSupply = _convertToAssets(totalSupply(), Math.Rounding.Floor);
        uint256 finalBorrowed = totalBorrowed;

        // the supply cap can be implemented like this:
        if (supplyCap != 0 && finalSupply > supplyCap && finalSupply > initialSupply) {
            revert SupplyCapExceeded();
        }

        // or the borrow cap can be implemented like this:
        if (borrowCap != 0 && finalBorrowed > borrowCap && finalBorrowed > initialBorrowed) {
            revert BorrowCapExceeded();
        }

        // cb if limit exceeded
    }

    function deposit(
        uint256 assets,
        address receiver
    ) public virtual override callThroughEVC withChecks(address(0)) nonReentrant returns (uint256 shares) {
        address msgSender = _msgSender();

        takeVaultSnapshot();

        // Check for rounding error since we round down in previewDeposit.
        require((shares = previewDeposit(assets)) != 0, "ZERO_SHARES");

        cbInflowSafeTransferFrom(address(IERC20(asset())), msgSender, address(this), assets);
        // Need to transfer before minting or ERC777s could reenter.
        // IERC20(asset()).safeTransferFrom(msgSender, address(this), assets);

        _mint(receiver, shares);

        emit Deposit(msgSender, receiver, assets, shares);
    }

    function mint(
        uint256 shares,
        address receiver
    ) public virtual override callThroughEVC withChecks(address(0)) nonReentrant returns (uint256 assets) {
        address msgSender = _msgSender();

        takeVaultSnapshot();

        assets = previewMint(shares);

        // IERC20(asset()).safeTransferFrom(msgSender, address(this), assets);
        cbInflowSafeTransferFrom(address(IERC20(asset())), msgSender, address(this), assets);

        _mint(receiver, shares);

        emit Deposit(msgSender, receiver, assets, shares);
    }
    // IWorkshopVault

    function borrow(
        uint256 assets,
        address receiver
    ) external override callThroughEVC withChecks(_msgSenderForBorrow()) nonReentrant {
        address msgSender = _msgSenderForBorrow();

        takeVaultSnapshot();

        require(assets != 0, "ZERO_ASSETS");

        receiver = getAccountOwner(receiver);

        _increaseOwed(msgSender, assets);

        emit Borrow(msgSender, receiver, assets);

        // SafeERC20.safeTransfer(ERC20(asset()), receiver, assets);
        // ERC20(asset()).transfer(receiver, assets);
        cbInflowTransfer(address(ERC20(asset())), receiver, assets);
    }
}

contract CircuitBreaker is ICircuitBreaker {
    using SafeERC20 for IERC20;
    using LimiterLib for Limiter;
    ////////////////////////////////////////////////////////////////
    //                      STATE VARIABLES                       //
    ////////////////////////////////////////////////////////////////

    mapping(address => Limiter limiter) public tokenLimiters;

    /**
     * @notice Funds locked if rate limited reached
     */
    mapping(address recipient => mapping(address asset => uint256 amount)) public lockedFunds;

    mapping(address account => bool protectionActive) public isProtectedContract;

    address public admin;

    bool public isRateLimited;

    uint256 public rateLimitCooldownPeriod;

    uint256 public lastRateLimitTimestamp;

    uint256 public gracePeriodEndTimestamp;

    // Using address(1) as a proxy for native token (ETH, BNB, etc), address(0) could be problematic
    address public immutable NATIVE_ADDRESS_PROXY = address(1);

    uint256 public immutable WITHDRAWAL_PERIOD;

    uint256 public immutable TICK_LENGTH;

    bool public isOperational = true;

    ////////////////////////////////////////////////////////////////
    //                           EVENTS                           //
    ////////////////////////////////////////////////////////////////

    /**
     * @notice Non-EIP standard events
     */
    event TokenBacklogCleaned(address indexed token, uint256 timestamp);

    ////////////////////////////////////////////////////////////////
    //                           ERRORS                           //
    ////////////////////////////////////////////////////////////////

    error NotAProtectedContract();
    error NotAdmin();
    error InvalidAdminAddress();
    error NoLockedFunds();
    error RateLimited();
    error NotRateLimited();
    error TokenNotRateLimited();
    error CooldownPeriodNotReached();
    error NativeTransferFailed();
    error InvalidRecipientAddress();
    error InvalidGracePeriodEnd();
    error ProtocolWasExploited();
    error NotExploited();

    ////////////////////////////////////////////////////////////////
    //                         MODIFIERS                          //
    ////////////////////////////////////////////////////////////////

    modifier onlyProtected() {
        if (!isProtectedContract[msg.sender]) revert NotAProtectedContract();
        _;
    }

    modifier onlyAdmin() {
        if (msg.sender != admin) revert NotAdmin();
        _;
    }

    /**
     * @notice When the isOperational flag is set to false, the protocol is considered locked and will
     * revert all future deposits, withdrawals, and claims to locked funds.
     * The admin should migrate the funds from the underlying protocol and what is remaining
     * in the CircuitBreaker contract to a multisig. This multisig should then be used to refund users pro-rata.
     * (Social Consensus)
     */
    modifier onlyOperational() {
        if (!isOperational) revert ProtocolWasExploited();
        _;
    }

    /**
     * @notice gracePeriod refers to the time after a rate limit trigger and then overriden where withdrawals are
     * still allowed.
     * @dev For example a false positive rate limit trigger, then it is overriden, so withdrawals are still
     * allowed for a period of time.
     * Before the rate limit is enforced again, it should be set to be at least your largest
     * withdrawalPeriod length
     */
    constructor(
        address _admin,
        uint256 _rateLimitCooldownPeriod,
        uint256 _withdrawlPeriod,
        uint256 _liquidityTickLength
    ) {
        admin = _admin;
        rateLimitCooldownPeriod = _rateLimitCooldownPeriod;
        WITHDRAWAL_PERIOD = _withdrawlPeriod;
        TICK_LENGTH = _liquidityTickLength;
    }

    ////////////////////////////////////////////////////////////////
    //                         FUNCTIONS                          //
    ////////////////////////////////////////////////////////////////

    /**
     * @dev Give protected contracts one function to call for convenience
     */
    function onTokenInflow(address _token, uint256 _amount) external onlyProtected onlyOperational {
        _onTokenInflow(_token, _amount);
    }

    function onTokenOutflow(
        address _token,
        uint256 _amount,
        address _recipient,
        bool _revertOnRateLimit
    ) external onlyProtected onlyOperational {
        _onTokenOutflow(_token, _amount, _recipient, _revertOnRateLimit);
    }

    function onNativeAssetInflow(uint256 _amount) external onlyProtected onlyOperational {
        _onTokenInflow(NATIVE_ADDRESS_PROXY, _amount);
    }

    function onNativeAssetOutflow(
        address _recipient,
        bool _revertOnRateLimit
    ) external payable onlyProtected onlyOperational {
        _onTokenOutflow(NATIVE_ADDRESS_PROXY, msg.value, _recipient, _revertOnRateLimit);
    }

    /**
     * @notice Allow users to claim locked funds when rate limit is resolved
     * use address(1) for native token claims
     */
    function claimLockedFunds(address _asset, address _recipient) external onlyOperational {
        if (lockedFunds[_recipient][_asset] == 0) revert NoLockedFunds();
        if (isRateLimited) revert RateLimited();

        uint256 amount = lockedFunds[_recipient][_asset];
        lockedFunds[_recipient][_asset] = 0;

        emit LockedFundsClaimed(_asset, _recipient);

        _safeTransferIncludingNative(_asset, _recipient, amount);
    }

    /**
     * @dev Due to potential inactivity, the linked list may grow to where
     * it is better to clear the backlog in advance to save gas for the users
     * this is a public function so that anyone can call it as it is not user sensitive
     */
    function clearBackLog(address _token, uint256 _maxIterations) external {
        tokenLimiters[_token].sync(WITHDRAWAL_PERIOD, _maxIterations);
        emit TokenBacklogCleaned(_token, block.timestamp);
    }

    function overrideExpiredRateLimit() external {
        if (!isRateLimited) revert NotRateLimited();
        if (block.timestamp - lastRateLimitTimestamp < rateLimitCooldownPeriod) {
            revert CooldownPeriodNotReached();
        }

        isRateLimited = false;
    }

    function registerAsset(
        address _asset,
        uint256 _minLiqRetainedBps,
        uint256 _limitBeginThreshold
    ) external onlyAdmin {
        tokenLimiters[_asset].init(_minLiqRetainedBps, _limitBeginThreshold);
        emit AssetRegistered(_asset, _minLiqRetainedBps, _limitBeginThreshold);
    }

    function updateAssetParams(
        address _asset,
        uint256 _minLiqRetainedBps,
        uint256 _limitBeginThreshold
    ) external onlyAdmin {
        Limiter storage limiter = tokenLimiters[_asset];
        limiter.updateParams(_minLiqRetainedBps, _limitBeginThreshold);
        limiter.sync(WITHDRAWAL_PERIOD);
    }

    function overrideRateLimit() external onlyAdmin {
        if (!isRateLimited) revert NotRateLimited();
        isRateLimited = false;
        // Allow the grace period to extend for the full withdrawal period to not trigger rate limit again
        // if the rate limit is removed just before the withdrawal period ends
        gracePeriodEndTimestamp = lastRateLimitTimestamp + WITHDRAWAL_PERIOD;
    }

    function addProtectedContracts(address[] calldata _ProtectedContracts) external onlyAdmin {
        for (uint256 i = 0; i < _ProtectedContracts.length; i++) {
            isProtectedContract[_ProtectedContracts[i]] = true;
        }
    }

    function removeProtectedContracts(address[] calldata _ProtectedContracts) external onlyAdmin {
        for (uint256 i = 0; i < _ProtectedContracts.length; i++) {
            isProtectedContract[_ProtectedContracts[i]] = false;
        }
    }

    function startGracePeriod(uint256 _gracePeriodEndTimestamp) external onlyAdmin {
        if (_gracePeriodEndTimestamp <= block.timestamp) revert InvalidGracePeriodEnd();
        gracePeriodEndTimestamp = _gracePeriodEndTimestamp;
        emit GracePeriodStarted(_gracePeriodEndTimestamp);
    }

    function setAdmin(address _newAdmin) external onlyAdmin {
        if (_newAdmin == address(0)) revert InvalidAdminAddress();
        admin = _newAdmin;
        emit AdminSet(_newAdmin);
    }

    function tokenLiquidityChanges(
        address _token,
        uint256 _tickTimestamp
    ) external view returns (uint256 nextTimestamp, int256 amount) {
        LiqChangeNode storage node = tokenLimiters[_token].listNodes[_tickTimestamp];
        nextTimestamp = node.nextTimestamp;
        amount = node.amount;
    }

    function isRateLimitTriggered(address _asset) public view returns (bool) {
        return tokenLimiters[_asset].status() == LimitStatus.Triggered;
    }

    function isInGracePeriod() public view returns (bool) {
        return block.timestamp <= gracePeriodEndTimestamp;
    }

    function markAsNotOperational() external onlyAdmin {
        isOperational = false;
    }

    function migrateFundsAfterExploit(address[] calldata _assets, address _recoveryRecipient) external onlyAdmin {
        if (isOperational) revert NotExploited();
        for (uint256 i = 0; i < _assets.length; i++) {
            if (_assets[i] == NATIVE_ADDRESS_PROXY) {
                uint256 amount = address(this).balance;
                _safeTransferIncludingNative(_assets[i], _recoveryRecipient, amount);
            } else {
                uint256 amount = IERC20(_assets[i]).balanceOf(address(this));
                _safeTransferIncludingNative(_assets[i], _recoveryRecipient, amount);
            }
        }
    }

    ////////////////////////////////////////////////////////////////
    //                       INTERNAL  FUNCTIONS                  //
    ////////////////////////////////////////////////////////////////

    function _onTokenInflow(address _token, uint256 _amount) internal {
        /// @dev uint256 could overflow into negative
        Limiter storage limiter = tokenLimiters[_token];

        limiter.recordChange(int256(_amount), WITHDRAWAL_PERIOD, TICK_LENGTH);
        emit AssetInflow(_token, _amount);
    }

    function _onTokenOutflow(address _token, uint256 _amount, address _recipient, bool _revertOnRateLimit) internal {
        Limiter storage limiter = tokenLimiters[_token];
        // Check if the token has enforced rate limited
        if (!limiter.initialized()) {
            // if it is not rate limited, just transfer the tokens
            _safeTransferIncludingNative(_token, _recipient, _amount);
            return;
        }
        limiter.recordChange(-int256(_amount), WITHDRAWAL_PERIOD, TICK_LENGTH);
        // Check if currently rate limited, if so, add to locked funds claimable when resolved
        if (isRateLimited) {
            if (_revertOnRateLimit) {
                revert RateLimited();
            }
            lockedFunds[_recipient][_token] += _amount;
            return;
        }

        // Check if rate limit is triggered after withdrawal and not in grace period
        // (grace period allows for withdrawals to be made if rate limit is triggered but overriden)
        if (limiter.status() == LimitStatus.Triggered && !isInGracePeriod()) {
            if (_revertOnRateLimit) {
                revert RateLimited();
            }
            // if it is, set rate limited to true
            isRateLimited = true;
            lastRateLimitTimestamp = block.timestamp;
            // add to locked funds claimable when resolved
            lockedFunds[_recipient][_token] += _amount;

            emit AssetRateLimitBreached(_token, block.timestamp);

            return;
        }

        // if everything is good, transfer the tokens
        _safeTransferIncludingNative(_token, _recipient, _amount);

        emit AssetWithdraw(_token, _recipient, _amount);
    }

    function _safeTransferIncludingNative(address _token, address _recipient, uint256 _amount) internal {
        if (_amount == 0) return;

        if (_token == NATIVE_ADDRESS_PROXY) {
            (bool success,) = _recipient.call{value: _amount}("");
            if (!success) revert NativeTransferFailed();
        } else {
            IERC20(_token).safeTransfer(_recipient, _amount);
        }
    }
}
