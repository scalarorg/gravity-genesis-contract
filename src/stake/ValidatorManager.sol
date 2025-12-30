// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "../System.sol";
import "@src/interfaces/IStakeConfig.sol";
import "@src/interfaces/IEpochManager.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@src/access/Protectable.sol";
import "@src/interfaces/IStakeCredit.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@src/stake/StakeCredit.sol";
import "@src/interfaces/IValidatorManager.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@src/interfaces/ITimestamp.sol";
import "@src/interfaces/IValidatorPerformanceTracker.sol";

import "@src/interfaces/IReconfigurableModule.sol";
import "@src/interfaces/IValidatorManagerUtils.sol";
/**
 * @title ValidatorManager
 * @dev Contract for unified validator set management
 */

contract ValidatorManager is System, ReentrancyGuard, Protectable, IValidatorManager, Initializable {
    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 private constant BREATHE_BLOCK_INTERVAL = 1 days;
    uint64 public constant MAX_VALIDATOR_SET_SIZE = 65536;

    ValidatorSetData public validatorSetData;

    // validator info mapping
    mapping(address validator => ValidatorInfo validatorInfo) public validatorInfos;

    // consensus address mapping
    mapping(bytes consensusAddress => address operator) public consensusToValidator; // consensus address => validator address

    // validator name mapping
    mapping(bytes32 monikerHash => bool exists) private _monikerSet; // validator name hash => exists

    // validator set management
    EnumerableSet.AddressSet private activeValidators; // active validators
    EnumerableSet.AddressSet private pendingActive; // pending active validators
    EnumerableSet.AddressSet private pendingInactive; // pending inactive validators

    // index mapping
    mapping(address validator => uint256 index) private activeValidatorIndex;
    mapping(address validator => uint256 index) private pendingActiveIndex;
    mapping(address validator => uint256 index) private pendingInactiveIndex;

    mapping(address operator => address validator) public operatorToValidator; // operator => validator

    // initialized flag
    bool private initialized;

    // mapping for tracking validator accumulated rewards
    uint256 public totalIncoming;

    /*----------------- Modifiers -----------------*/

    modifier validatorExists(
        address validator
    ) {
        if (!validatorInfos[validator].registered) {
            revert ValidatorNotExists(validator);
        }
        _;
    }

    modifier onlyValidatorSelf(
        address validator
    ) {
        if (msg.sender != validator) {
            revert NotValidator(msg.sender, validator);
        }
        _;
    }

    modifier validAddress(
        address addr
    ) {
        if (addr == address(0)) {
            revert InvalidAddress(address(0));
        }
        _;
    }

    modifier onlyValidatorOperator(
        address validator
    ) {
        if (!hasOperatorPermission(validator, msg.sender)) {
            revert UnauthorizedCaller(msg.sender, validator);
        }
        _;
    }

    modifier whenValidatorSetChangeAllowed() {
        if (!IStakeConfig(STAKE_CONFIG_ADDR).allowValidatorSetChange()) {
            revert ValidatorSetChangeDisabled();
        }
        _;
    }

    /// @inheritdoc IValidatorManager
    function initialize(
        InitializationParams calldata params
    ) external initializer onlyGenesis {
        if (initialized) revert AlreadyInitialized();
        if (
            params.validatorAddresses.length != params.consensusPublicKeys.length
                || params.validatorAddresses.length != params.votingPowers.length
                || params.validatorAddresses.length != params.validatorNetworkAddresses.length
                || params.validatorAddresses.length != params.fullnodeNetworkAddresses.length
        ) revert ArrayLengthMismatch();

        initialized = true;

        // initialize ValidatorSetData
        validatorSetData = ValidatorSetData({ totalVotingPower: 0, totalJoiningPower: 0 });

        // add initial validators
        for (uint256 i = 0; i < params.validatorAddresses.length; i++) {
            bytes memory validator_aptos_address = params.aptosAddresses[i];
            // TODO: remove this
            // require(validator_aptos_address.length == 32, "Validator aptos address must be 32 bytes");
            address validator = params.validatorAddresses[i];
            bytes memory consensusPublicKey = params.consensusPublicKeys[i];
            uint256 votingPower = params.votingPowers[i];

            if (votingPower == 0) revert InvalidVotingPower(votingPower);

            // deploy StakeCredit contract for initial validator
            address stakeCreditAddress = _deployStakeCreditWithValue(
                validator, string(abi.encodePacked("VAL", uint256(i))), validator, votingPower
            );

            // create basic validator info
            validatorInfos[validator] = ValidatorInfo({
                consensusPublicKey: consensusPublicKey,
                commission: Commission({
                    rate: 0,
                    maxRate: 5000, // default max commission rate 50%
                    maxChangeRate: 500 // default max daily change rate 5%
                }),
                moniker: string(abi.encodePacked("VAL", uint256(i))), // generate default name
                registered: true,
                stakeCreditAddress: stakeCreditAddress,
                status: ValidatorStatus.ACTIVE,
                votingPower: votingPower,
                validatorIndex: i,
                updateTime: ITimestamp(TIMESTAMP_ADDR).nowSeconds(),
                operator: validator, // default self as operator
                validatorNetworkAddresses: params.validatorNetworkAddresses[i],
                fullnodeNetworkAddresses: params.fullnodeNetworkAddresses[i],
                aptosAddress: validator_aptos_address
            });

            // Add to active validators set
            activeValidators.add(validator);
            activeValidatorIndex[validator] = i;

            // Update total voting power
            validatorSetData.totalVotingPower += votingPower;

            // Set reverse mapping
            operatorToValidator[validator] = validator;

            // Set consensus address mapping
            if (consensusPublicKey.length > 0) {
                consensusToValidator[consensusPublicKey] = validator;
            }
        }
    }

    /// @inheritdoc IValidatorManager
    function registerValidator(
        ValidatorRegistrationParams calldata params
    ) external payable nonReentrant whenNotPaused {
        address validator = msg.sender;
        uint256 amount = msg.value;

        // validate params
        bytes32 monikerHash = keccak256(abi.encodePacked(params.moniker));
        // TODO: remove this
        // require(params.aptosAddress.length == 32, "Validator aptos address must be 32 bytes");
        IValidatorManagerUtils(VALIDATOR_MANAGER_UTILS_ADDR)
            .validateRegistrationParams(
                validator,
                params.consensusPublicKey,
                params.blsProof,
                params.moniker,
                params.commission,
                params.initialOperator,
                params.consensusPublicKey.length > 0 && consensusToValidator[params.consensusPublicKey] != address(0),
                _monikerSet[monikerHash],
                operatorToValidator[params.initialOperator] != address(0),
                validatorInfos[validator].registered
            );

        // check下溢检查
        if (amount < IStakeConfig(STAKE_CONFIG_ADDR).lockAmount()) {
            revert InvalidStakeAmount(amount, IStakeConfig(STAKE_CONFIG_ADDR).lockAmount());
        }
        // check stake requirements
        uint256 stakeMinusLock = amount - IStakeConfig(STAKE_CONFIG_ADDR).lockAmount();
        uint256 minStake = IStakeConfig(STAKE_CONFIG_ADDR).minValidatorStake();
        if (stakeMinusLock < minStake) {
            revert InvalidStakeAmount(stakeMinusLock, minStake);
        }

        // set beneficiary
        address beneficiary = params.initialBeneficiary == address(0) ? validator : params.initialBeneficiary;

        // deploy StakeCredit contract
        address stakeCreditAddress = _deployStakeCreditWithValue(validator, params.moniker, beneficiary, msg.value);

        // create and store validator info
        _createValidatorInfo(validator, params, stakeCreditAddress);

        // setup validator mappings
        _setupValidatorMappings(validator, params);

        // record validator name
        _monikerSet[monikerHash] = true;

        // initial stake
        // TODO: fix
        StakeCredit(payable(stakeCreditAddress)).delegate{ value: amount }(validator);

        emit ValidatorRegistered(validator, params.initialOperator, params.consensusPublicKey, params.moniker);
        emit StakeCreditDeployed(validator, stakeCreditAddress);
    }

    /**
     * @dev create validator info
     */
    function _createValidatorInfo(
        address validator,
        ValidatorRegistrationParams calldata params,
        address stakeCreditAddress
    ) internal {
        _setValidatorBasicInfo(validator, params);
        _setValidatorAddresses(validator, params);
        _setValidatorStatus(validator, stakeCreditAddress);
    }

    function _setValidatorBasicInfo(
        address validator,
        ValidatorRegistrationParams calldata params
    ) internal {
        ValidatorInfo storage info = validatorInfos[validator];

        info.moniker = params.moniker;
        info.commission = params.commission;
        info.updateTime = ITimestamp(TIMESTAMP_ADDR).nowSeconds();
        info.operator = params.initialOperator;
    }

    function _setValidatorAddresses(
        address validator,
        ValidatorRegistrationParams calldata params
    ) internal {
        ValidatorInfo storage info = validatorInfos[validator];

        info.consensusPublicKey = params.consensusPublicKey;
        info.validatorNetworkAddresses = params.validatorNetworkAddresses;
        info.fullnodeNetworkAddresses = params.fullnodeNetworkAddresses;
        info.aptosAddress = params.aptosAddress;
    }

    function _setValidatorStatus(
        address validator,
        address stakeCreditAddress
    ) internal {
        ValidatorInfo storage info = validatorInfos[validator];

        info.registered = true;
        info.stakeCreditAddress = stakeCreditAddress;
        info.status = ValidatorStatus.INACTIVE;
        info.votingPower = 0;
        info.validatorIndex = 0;
    }

    /**
     * @dev setup validator mappings
     */
    function _setupValidatorMappings(
        address validator,
        ValidatorRegistrationParams calldata params
    ) internal {
        operatorToValidator[params.initialOperator] = validator;

        if (params.consensusPublicKey.length > 0) {
            consensusToValidator[params.consensusPublicKey] = validator;
        }
    }

    /// @inheritdoc IValidatorManager
    function joinValidatorSet(
        address validator
    ) external whenNotPaused whenValidatorSetChangeAllowed validatorExists(validator) onlyValidatorOperator(validator) {
        ValidatorInfo storage info = validatorInfos[validator];

        // check current status
        if (info.status != ValidatorStatus.INACTIVE) {
            revert ValidatorNotInactive(validator);
        }

        // get current stake and check requirements
        uint256 votingPower = _getValidatorStake(validator);
        uint256 minStake = IStakeConfig(STAKE_CONFIG_ADDR).minValidatorStake();
        uint256 maxStake = IStakeConfig(STAKE_CONFIG_ADDR).maximumStake();

        if (votingPower < minStake) {
            revert InvalidStakeAmount(votingPower, minStake);
        }

        if (votingPower > maxStake) {
            revert StakeExceedsMaximum(votingPower, maxStake);
        }

        // check validator set size limit
        uint256 totalSize = activeValidators.length() + pendingActive.length();
        if (totalSize >= MAX_VALIDATOR_SET_SIZE) {
            revert ValidatorSetReachedMax(totalSize, MAX_VALIDATOR_SET_SIZE);
        }

        // check voting power increase limit
        // calculate current pending power
        uint256 currentPendingPower = 0;
        address[] memory pendingVals = pendingActive.values();
        for (uint256 i = 0; i < pendingVals.length; i++) {
            address stakeCreditAddress = validatorInfos[pendingVals[i]].stakeCreditAddress;
            if (stakeCreditAddress != address(0)) {
                currentPendingPower += StakeCredit(payable(stakeCreditAddress)).getNextEpochVotingPower();
            }
        }

        IValidatorManagerUtils(VALIDATOR_MANAGER_UTILS_ADDR)
            .checkVotingPowerIncrease(votingPower, validatorSetData.totalVotingPower, currentPendingPower);

        // update status to PENDING_ACTIVE
        info.status = ValidatorStatus.PENDING_ACTIVE;
        info.votingPower = votingPower;

        // add to pending_active set
        pendingActive.add(validator);
        pendingActiveIndex[validator] = pendingActive.length() - 1;

        // update total joining power
        validatorSetData.totalJoiningPower += votingPower;

        uint64 currentEpoch = uint64(IEpochManager(EPOCH_MANAGER_ADDR).currentEpoch());
        emit ValidatorJoinRequested(validator, votingPower, currentEpoch);
        emit ValidatorStatusChanged(
            validator, uint8(ValidatorStatus.INACTIVE), uint8(ValidatorStatus.PENDING_ACTIVE), currentEpoch
        );
    }

    /// @inheritdoc IValidatorManager
    function leaveValidatorSet(
        address validator
    ) external whenNotPaused whenValidatorSetChangeAllowed validatorExists(validator) onlyValidatorOperator(validator) {
        ValidatorInfo storage info = validatorInfos[validator];
        uint8 currentStatus = uint8(info.status);
        uint64 currentEpoch = uint64(IEpochManager(EPOCH_MANAGER_ADDR).currentEpoch());

        if (currentStatus == uint8(ValidatorStatus.PENDING_ACTIVE)) {
            // use current actual stake to update totalJoiningPower
            uint256 currentVotingPower = _getValidatorStake(validator);
            validatorSetData.totalJoiningPower -= currentVotingPower;

            // other processing logic remains unchanged
            pendingActive.remove(validator);
            delete pendingActiveIndex[validator];
            info.votingPower = 0;
            info.status = ValidatorStatus.INACTIVE;

            emit ValidatorStatusChanged(
                validator, uint8(ValidatorStatus.PENDING_ACTIVE), uint8(ValidatorStatus.INACTIVE), currentEpoch
            );
        } else if (currentStatus == uint8(ValidatorStatus.ACTIVE)) {
            // check if it's the last validator
            if (activeValidators.length() <= 1) {
                revert LastValidatorCannotLeave();
            }

            // add to pending_inactive
            pendingInactive.add(validator);
            pendingInactiveIndex[validator] = pendingInactive.length() - 1;

            info.status = ValidatorStatus.PENDING_INACTIVE;

            emit ValidatorStatusChanged(
                validator, uint8(ValidatorStatus.ACTIVE), uint8(ValidatorStatus.PENDING_INACTIVE), currentEpoch
            );
        } else {
            revert ValidatorNotActive(validator);
        }

        emit ValidatorLeaveRequested(validator, currentEpoch);
    }

    /// @inheritdoc IValidatorManager
    function onNewEpoch() external onlyEpochManager {
        uint64 currentEpoch = uint64(IEpochManager(EPOCH_MANAGER_ADDR).currentEpoch());
        uint256 minStakeRequired = IStakeConfig(STAKE_CONFIG_ADDR).minValidatorStake();

        // 1. process all StakeCredit status transitions (make pending_active become active)
        _processAllStakeCreditsNewEpoch();

        // 2. activate pending_active validators (based on updated stake data)
        _activatePendingValidators(currentEpoch);

        // 3. remove pending_inactive validators
        _removePendingInactiveValidators(currentEpoch);

        // 4. distribute rewards (based on updated status)
        _distributeRewards();

        // 5. recalculate validator set (based on latest stake data)
        _recalculateValidatorSet(minStakeRequired, currentEpoch);

        // 6. notify ValidatorPerformanceTracker contract
        IValidatorPerformanceTracker(VALIDATOR_PERFORMANCE_TRACKER_ADDR).onNewEpoch();

        // 7. reset joining power
        validatorSetData.totalJoiningPower = 0;

        emit ValidatorSetUpdated(
            currentEpoch + 1,
            activeValidators.length(),
            pendingActive.length(),
            pendingInactive.length(),
            validatorSetData.totalVotingPower
        );
    }

    /// @inheritdoc IValidatorManager
    function getValidatorInfo(
        address validator
    ) external view returns (ValidatorInfo memory) {
        return validatorInfos[validator];
    }

    /// @inheritdoc IValidatorManager
    function getActiveValidators() external view returns (address[] memory) {
        return activeValidators.values();
    }

    /// @inheritdoc IValidatorManager
    function getValidatorSetData() external view returns (ValidatorSetData memory) {
        return validatorSetData;
    }

    /// @inheritdoc IValidatorManager
    function updateConsensusKey(
        address validator,
        bytes calldata newConsensusKey
    ) external validatorExists(validator) onlyValidatorOperator(validator) {
        // check if new consensus address is duplicate and not from the same validator
        if (
            newConsensusKey.length > 0 && consensusToValidator[newConsensusKey] != address(0)
                && consensusToValidator[newConsensusKey] != validator
        ) {
            revert DuplicateConsensusAddress(newConsensusKey);
        }

        // clear old consensus address mapping
        bytes memory oldConsensusKey = validatorInfos[validator].consensusPublicKey;
        if (oldConsensusKey.length > 0) {
            delete consensusToValidator[oldConsensusKey];
        }

        // update validator info
        validatorInfos[validator].consensusPublicKey = newConsensusKey;

        // update consensus address mapping
        if (newConsensusKey.length > 0) {
            consensusToValidator[newConsensusKey] = validator;
        }

        emit ValidatorInfoUpdated(validator, "consensusKey");
    }

    /// @inheritdoc IValidatorManager
    function updateCommissionRate(
        address validator,
        uint64 newCommissionRate
    ) external validatorExists(validator) onlyValidatorOperator(validator) {
        ValidatorInfo storage info = validatorInfos[validator];

        // check update frequency
        if (info.updateTime + BREATHE_BLOCK_INTERVAL > ITimestamp(TIMESTAMP_ADDR).nowSeconds()) {
            revert UpdateTooFrequently();
        }

        uint256 maxCommissionRate = IStakeConfig(STAKE_CONFIG_ADDR).maxCommissionRate();
        if (newCommissionRate > maxCommissionRate) {
            revert InvalidCommissionRate(newCommissionRate, uint64(maxCommissionRate));
        }

        // calculate change amount
        uint256 changeRate = newCommissionRate >= info.commission.rate
            ? newCommissionRate - info.commission.rate
            : info.commission.rate - newCommissionRate;

        // check if change exceeds daily max change rate
        if (changeRate > info.commission.maxChangeRate) {
            revert InvalidCommission();
        }

        // update commission rate
        info.commission.rate = newCommissionRate;
        info.updateTime = ITimestamp(TIMESTAMP_ADDR).nowSeconds();

        emit CommissionRateEdited(validator, newCommissionRate);
        emit ValidatorInfoUpdated(validator, "commissionRate");
    }

    /// @inheritdoc IValidatorManager
    function updateValidatorNetworkAddresses(
        address validator,
        bytes calldata newAddresses
    ) external validatorExists(validator) onlyValidatorOperator(validator) {
        validatorInfos[validator].validatorNetworkAddresses = newAddresses;
        emit ValidatorInfoUpdated(validator, "validatorNetworkAddresses");
    }

    /// @inheritdoc IValidatorManager
    function updateFullnodeNetworkAddresses(
        address validator,
        bytes calldata newAddresses
    ) external validatorExists(validator) onlyValidatorOperator(validator) {
        validatorInfos[validator].fullnodeNetworkAddresses = newAddresses;
        emit ValidatorInfoUpdated(validator, "fullnodeNetworkAddresses");
    }

    /**
     * @dev Activate pending validators
     */
    function _activatePendingValidators(
        uint64 currentEpoch
    ) internal {
        address[] memory pendingValidators = pendingActive.values();

        for (uint256 i = 0; i < pendingValidators.length; i++) {
            address validator = pendingValidators[i];
            ValidatorInfo storage info = validatorInfos[validator];

            // remove from pending_active
            pendingActive.remove(validator);
            delete pendingActiveIndex[validator];

            // add to active
            activeValidators.add(validator);
            info.validatorIndex = activeValidators.length() - 1;
            activeValidatorIndex[validator] = info.validatorIndex;

            // update status
            info.status = ValidatorStatus.ACTIVE;

            emit ValidatorStatusChanged(
                validator, uint8(ValidatorStatus.PENDING_ACTIVE), uint8(ValidatorStatus.ACTIVE), currentEpoch
            );
        }
    }

    /**
     * @dev Remove pending inactive validators
     */
    function _removePendingInactiveValidators(
        uint64 currentEpoch
    ) internal {
        address[] memory pendingInactiveValidators = pendingInactive.values();

        for (uint256 i = 0; i < pendingInactiveValidators.length; i++) {
            address validator = pendingInactiveValidators[i];
            ValidatorInfo storage info = validatorInfos[validator];

            activeValidators.remove(validator);
            delete activeValidatorIndex[validator];

            validatorSetData.totalVotingPower -= info.votingPower;

            pendingInactive.remove(validator);
            delete pendingInactiveIndex[validator];

            // update status
            info.status = ValidatorStatus.INACTIVE;
            info.votingPower = 0;

            // fund status is already handled in StakeCredit.onNewEpoch()

            emit ValidatorStatusChanged(
                validator, uint8(ValidatorStatus.PENDING_INACTIVE), uint8(ValidatorStatus.INACTIVE), currentEpoch
            );
        }
    }

    /**
     * @dev 重新计算验证者集合
     */
    function _recalculateValidatorSet(
        uint256 minStakeRequired,
        uint64 currentEpoch
    ) internal {
        uint256 newTotalVotingPower = 0;
        address[] memory currentActive = activeValidators.values();

        for (uint256 i = 0; i < currentActive.length; i++) {
            address validator = currentActive[i];
            ValidatorInfo storage info = validatorInfos[validator];

            // update voting power
            uint256 currentStake = _getValidatorStake(validator);
            // TODO(jason): need further discussion
            // 或许要先都设置成20000之类的？
            // currentStake = 1; // 移除硬编码，使用实际的质押金额

            if (currentStake >= minStakeRequired) {
                info.votingPower = currentStake;
                newTotalVotingPower += currentStake;
            } else {
                // insufficient voting power, remove validator
                activeValidators.remove(validator);
                delete activeValidatorIndex[validator];

                info.status = ValidatorStatus.INACTIVE;
                info.votingPower = 0;

                emit ValidatorStatusChanged(
                    validator, uint8(ValidatorStatus.ACTIVE), uint8(ValidatorStatus.INACTIVE), currentEpoch
                );
            }
        }

        // update total voting power
        validatorSetData.totalVotingPower = newTotalVotingPower;
    }

    function _deployStakeCreditWithValue(
        address validator,
        string memory moniker,
        address beneficiary,
        uint256 value
    ) internal returns (address) {
        address creditProxy = address(new TransparentUpgradeableProxy(STAKE_CREDIT_ADDR, DEAD_ADDRESS, ""));
        IStakeCredit(creditProxy).initialize{ value: value }(validator, moniker, beneficiary);
        emit StakeCreditDeployed(validator, creditProxy);

        return creditProxy;
    }

    /**
     * @dev get validator stake
     */
    function _getValidatorStake(
        address validator
    ) internal view returns (uint256) {
        address stakeCreditAddress = validatorInfos[validator].stakeCreditAddress;
        if (stakeCreditAddress == address(0)) {
            return 0;
        }

        // get next epoch voting power directly from StakeCredit
        return StakeCredit(payable(stakeCreditAddress)).getNextEpochVotingPower();
    }

    /**
     * @dev Process all StakeCredits for epoch transition
     */
    function _processAllStakeCreditsNewEpoch() internal {
        // 1. process active validators' StakeCredit
        address[] memory activeVals = activeValidators.values();
        for (uint256 i = 0; i < activeVals.length; i++) {
            address validator = activeVals[i];
            address stakeCreditAddress = validatorInfos[validator].stakeCreditAddress;
            if (stakeCreditAddress != address(0)) {
                StakeCredit(payable(stakeCreditAddress)).onNewEpoch();
            }
        }

        // 2. process pending active validators' StakeCredit
        address[] memory pendingActiveVals = pendingActive.values();
        for (uint256 i = 0; i < pendingActiveVals.length; i++) {
            address validator = pendingActiveVals[i];
            address stakeCreditAddress = validatorInfos[validator].stakeCreditAddress;
            if (stakeCreditAddress != address(0)) {
                StakeCredit(payable(stakeCreditAddress)).onNewEpoch();
            }
        }

        // 3. process pending inactive validators' StakeCredit
        address[] memory pendingInactiveVals = pendingInactive.values();
        for (uint256 i = 0; i < pendingInactiveVals.length; i++) {
            address validator = pendingInactiveVals[i];
            address stakeCreditAddress = validatorInfos[validator].stakeCreditAddress;
            if (stakeCreditAddress != address(0)) {
                StakeCredit(payable(stakeCreditAddress)).onNewEpoch();
            }
        }
    }

    /// @inheritdoc IValidatorManager
    function checkValidatorMinStake(
        address validator
    ) external {
        _checkValidatorMinStake(validator);
    }

    function _checkValidatorMinStake(
        address validator
    ) internal {
        ValidatorInfo storage info = validatorInfos[validator];
        if (info.status == ValidatorStatus.ACTIVE) {
            uint256 validatorStake = _getValidatorStake(validator);
            uint256 minStake = IStakeConfig(STAKE_CONFIG_ADDR).minValidatorStake();

            if (validatorStake < minStake) {
                uint8 oldStatus = uint8(info.status);
                info.status = ValidatorStatus.PENDING_INACTIVE;

                // add to pending_inactive set
                pendingInactive.add(validator);
                pendingInactiveIndex[validator] = pendingInactive.length() - 1;

                uint64 currentEpoch = uint64(IEpochManager(EPOCH_MANAGER_ADDR).currentEpoch());
                emit ValidatorStatusChanged(validator, oldStatus, uint8(ValidatorStatus.PENDING_INACTIVE), currentEpoch);
            }
        }
    }

    /// @inheritdoc IValidatorManager
    function getValidatorStakeCredit(
        address validator
    ) external view returns (address) {
        return validatorInfos[validator].stakeCreditAddress;
    }

    /// @inheritdoc IValidatorManager
    function checkVotingPowerIncrease(
        uint256 increaseAmount
    ) external view {
        // calculate current pending power
        uint256 currentPendingPower = 0;
        address[] memory pendingVals = pendingActive.values();
        for (uint256 i = 0; i < pendingVals.length; i++) {
            address stakeCreditAddress = validatorInfos[pendingVals[i]].stakeCreditAddress;
            if (stakeCreditAddress != address(0)) {
                currentPendingPower += StakeCredit(payable(stakeCreditAddress)).getNextEpochVotingPower();
            }
        }

        IValidatorManagerUtils(VALIDATOR_MANAGER_UTILS_ADDR)
            .checkVotingPowerIncrease(increaseAmount, validatorSetData.totalVotingPower, currentPendingPower);
    }

    /// @inheritdoc IValidatorManager
    function isValidatorRegistered(
        address validator
    ) external view override returns (bool) {
        return validatorInfos[validator].registered;
    }

    /// @inheritdoc IValidatorManager
    function isValidatorExists(
        address validator
    ) external view returns (bool) {
        return validatorInfos[validator].registered;
    }

    /// @inheritdoc IValidatorManager
    function getTotalVotingPower() external view override returns (uint256) {
        return validatorSetData.totalVotingPower;
    }

    /**
     * @dev 获取待处理验证者列表
     */
    function getPendingValidators() external view override returns (address[] memory) {
        return pendingActive.values();
    }

    /// @inheritdoc IValidatorManager
    function isCurrentEpochValidator(
        address validator
    ) public view override returns (bool) {
        ValidatorStatus status = validatorInfos[validator].status;
        return status == ValidatorStatus.ACTIVE || status == ValidatorStatus.PENDING_INACTIVE;
    }

    /// @inheritdoc IValidatorManager
    function isCurrentEpochValidator(
        bytes calldata validator
    ) public view override returns (bool) {
        for (uint256 i = 0; i < activeValidators.length(); i++) {
            address validatorAddress = activeValidators.at(i);
            if (keccak256(validatorInfos[validatorAddress].aptosAddress) == keccak256(validator)) {
                return validatorInfos[validatorAddress].status == ValidatorStatus.ACTIVE;
            }
        }
        return false;
    }

    /// @inheritdoc IValidatorManager
    function getValidatorStatus(
        address validator
    ) external view override returns (ValidatorStatus) {
        if (!validatorInfos[validator].registered) {
            return ValidatorStatus.INACTIVE;
        }
        return validatorInfos[validator].status;
    }

    /**
     * @dev Get validator index in current active validator set
     * @param validator Validator address
     * @return Validator index, may return 0 or revert if not active
     */
    function getValidatorIndex(
        address validator
    ) external view returns (uint64) {
        if (!isCurrentEpochValidator(validator)) {
            revert ValidatorNotActive(validator);
        }
        return uint64(activeValidatorIndex[validator]);
    }

    /// @inheritdoc IValidatorManager
    function getValidatorByProposer(
        bytes calldata proposer
    ) external view override returns (address validatorAddress, uint64 validatorIndex) {
        for (uint256 i = 0; i < activeValidators.length(); i++) {
            address validator = activeValidators.at(i);
            if (keccak256(validatorInfos[validator].aptosAddress) == keccak256(proposer)) {
                return (validator, uint64(activeValidatorIndex[validator]));
            }
        }
        revert ValidatorNotActive(address(0));
    }

    /**
     * @dev System caller calls, deposit transaction fees of current block as rewards
     */
    function deposit() external payable onlySystemCaller {
        // accumulate to total reward pool
        totalIncoming += msg.value;

        emit RewardsCollected(msg.value, totalIncoming);
    }

    /**
     * @dev Distribute validator rewards
     */
    function _distributeRewards() internal {
        if (totalIncoming == 0) return;

        address[] memory validators = activeValidators.values();
        uint256 totalWeight = 0;
        uint256[] memory weights = new uint256[](validators.length);

        // calculate each validator's weight (based on performance and stake)
        for (uint256 i = 0; i < validators.length; i++) {
            address validator = validators[i];
            address stakeCreditAddress = validatorInfos[validator].stakeCreditAddress;

            if (stakeCreditAddress != address(0)) {
                uint256 stake = _getValidatorCurrentEpochVotingPower(validator);

                // get validator performance data
                (uint64 successfulProposals, uint64 failedProposals,, bool exists) =
                    IValidatorPerformanceTracker(PERFORMANCE_TRACKER_ADDR).getValidatorPerformance(validator);

                if (exists) {
                    uint64 totalProposals = successfulProposals + failedProposals;

                    if (totalProposals > 0) {
                        // directly calculate weight by ratio, validators without proposals don't participate
                        weights[i] = (stake * successfulProposals) / totalProposals;
                        totalWeight += weights[i];
                    }
                }
            }
        }

        // distribute rewards by weight
        if (totalWeight > 0) {
            for (uint256 i = 0; i < validators.length; i++) {
                if (weights[i] > 0) {
                    address validator = validators[i];
                    address stakeCreditAddress = validatorInfos[validator].stakeCreditAddress;

                    // calculate validator's reward
                    uint256 reward = (totalIncoming * weights[i]) / totalWeight;

                    // check if stakeCreditAddress is valid
                    if (stakeCreditAddress == address(0)) {
                        // if stakeCreditAddress is invalid, send reward to system reward contract
                        (bool success,) = SYSTEM_REWARD_ADDR.call{ value: reward }("");
                        if (success) {
                            emit RewardDistributeFailed(validator, "INVALID_STAKECREDIT");
                        }
                    } else {
                        // get commission rate
                        uint64 commissionRate = validatorInfos[validator].commission.rate;

                        // send reward - no need for try-catch, assume call always succeeds
                        StakeCredit(payable(stakeCreditAddress)).distributeReward{ value: reward }(commissionRate);
                        emit RewardsDistributed(validator, reward);
                    }
                }
            }
        } else {
            // if no validators are eligible for rewards, send all rewards to system reward contract
            (bool success,) = SYSTEM_REWARD_ADDR.call{ value: totalIncoming }("");
            if (success) {
                emit RewardDistributeFailed(address(0), "NO_ELIGIBLE_VALIDATORS");
            }
        }

        // reset reward pool
        totalIncoming = 0;
    }

    /**
     * @dev Get validator's current epoch voting power
     * Inherited from StakeReward._getValidatorCurrentEpochVotingPower()
     */
    function _getValidatorCurrentEpochVotingPower(
        address validator
    ) internal view returns (uint256) {
        address stakeCreditAddress = validatorInfos[validator].stakeCreditAddress;
        if (stakeCreditAddress == address(0)) {
            return 0;
        }
        return StakeCredit(payable(stakeCreditAddress)).getCurrentEpochVotingPower();
    }

    /// @inheritdoc IValidatorManager
    function updateOperator(
        address validator,
        address newOperator
    ) external validatorExists(validator) onlyValidatorSelf(validator) validAddress(newOperator) {
        // check if new operator is already used by another validator
        if (operatorToValidator[newOperator] != address(0)) {
            revert AddressAlreadyInUse(newOperator, operatorToValidator[newOperator]);
        }

        if (newOperator == validator) {
            revert NewOperatorIsValidatorSelf();
        }

        address oldOperator = validatorInfos[validator].operator;

        // update reverse mapping
        if (oldOperator != address(0)) {
            delete operatorToValidator[oldOperator];
        }
        operatorToValidator[newOperator] = validator;

        validatorInfos[validator].operator = newOperator;

        emit OperatorUpdated(validator, oldOperator, newOperator);
    }

    /// @inheritdoc IValidatorManager
    function getOperator(
        address validator
    ) external view validatorExists(validator) returns (address) {
        return validatorInfos[validator].operator;
    }

    /// @inheritdoc IValidatorManager
    function isValidator(
        address validator,
        address account
    ) public view returns (bool) {
        return validator == account && validatorInfos[validator].registered;
    }

    /// @inheritdoc IValidatorManager
    function isOperator(
        address validator,
        address account
    ) public view returns (bool) {
        return validatorInfos[validator].registered && validatorInfos[validator].operator == account;
    }

    /// @inheritdoc IValidatorManager
    function hasOperatorPermission(
        address validator,
        address account
    ) public view returns (bool) {
        if (!validatorInfos[validator].registered) return false;

        return account == validator || account == validatorInfos[validator].operator;
    }

    /// @inheritdoc IValidatorManager
    function getValidatorSet() external view returns (ValidatorSet memory) {
        ValidatorInfo[] memory active = _getAllValidatorInfos(activeValidators);
        ValidatorInfo[] memory pendingIn = _getAllValidatorInfos(pendingInactive);
        ValidatorInfo[] memory pendingAct = _getAllValidatorInfos(pendingActive);

        uint256 joiningPower = _calculateTotalVotingPower(pendingAct);

        return ValidatorSet({
            activeValidators: active,
            pendingInactive: pendingIn,
            pendingActive: pendingAct,
            totalVotingPower: validatorSetData.totalVotingPower,
            totalJoiningPower: joiningPower
        });
    }

    function _getAllValidatorInfos(
        EnumerableSet.AddressSet storage validatorSet
    ) private view returns (ValidatorInfo[] memory) {
        uint256 count = validatorSet.length();
        ValidatorInfo[] memory infos = new ValidatorInfo[](count);
        for (uint256 i = 0; i < count; i++) {
            address validator = validatorSet.at(i);
            infos[i] = validatorInfos[validator];
        }
        return infos;
    }

    function _calculateTotalVotingPower(
        ValidatorInfo[] memory validators
    ) private pure returns (uint256) {
        uint256 totalPower = 0;
        for (uint256 i = 0; i < validators.length; i++) {
            totalPower += validators[i].votingPower;
        }
        return totalPower;
    }
}
