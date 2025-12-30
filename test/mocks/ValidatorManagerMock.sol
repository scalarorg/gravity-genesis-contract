// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@src/interfaces/IValidatorManager.sol";

contract ValidatorManagerMock {
    mapping(address => bool) public isCurrentEpochValidatorMap;
    mapping(address => uint64) public validatorIndexMap;
    mapping(address => bool) public validatorExistsMap;
    mapping(address => address) public validatorStakeCreditMap;
    mapping(address => IValidatorManager.ValidatorStatus) public validatorStatusMap;
    mapping(address => uint256) public validatorStakeMap;
    bool public initialized;

    function initialize(
        IValidatorManager.InitializationParams calldata params
    ) external {
        initialized = true;
        // Store the validators for testing
        for (uint256 i = 0; i < params.validatorAddresses.length; i++) {
            isCurrentEpochValidatorMap[params.validatorAddresses[i]] = true;
            validatorIndexMap[params.validatorAddresses[i]] = uint64(i);
            validatorExistsMap[params.validatorAddresses[i]] = true;
            validatorStatusMap[params.validatorAddresses[i]] = IValidatorManager.ValidatorStatus.ACTIVE;
        }
    }

    function setIsCurrentEpochValidator(
        address validator,
        bool isValidator
    ) external {
        isCurrentEpochValidatorMap[validator] = isValidator;
    }

    function setValidatorIndex(
        address validator,
        uint64 index
    ) external {
        validatorIndexMap[validator] = index;
    }

    function isCurrentEpochValidator(
        address validator
    ) external view returns (bool) {
        return isCurrentEpochValidatorMap[validator];
    }

    function isCurrentEpochValidator(
        bytes calldata /* validator */
    ) external pure returns (bool) {
        // Mock implementation - always return true for testing
        return true;
    }

    function getValidatorIndex(
        address validator
    ) external view returns (uint64) {
        require(isCurrentEpochValidatorMap[validator], "ValidatorNotActive");
        return validatorIndexMap[validator];
    }

    function getValidatorByProposer(
        bytes calldata proposer
    ) external view returns (address validatorAddress, uint64 validatorIndex) {
        // Convert bytes to address (take last 20 bytes)
        require(proposer.length >= 20, "Invalid proposer length");
        address addr;
        assembly {
            // Load from offset+12 to skip the first 12 bytes of padding, then shift to get address
            addr := shr(96, calldataload(add(proposer.offset, 12)))
        }
        require(isCurrentEpochValidatorMap[addr], "ValidatorNotActive");
        return (addr, validatorIndexMap[addr]);
    }

    function setIsValidatorExists(
        address validator,
        bool exists
    ) external {
        validatorExistsMap[validator] = exists;
    }

    function isValidatorExists(
        address validator
    ) external view returns (bool) {
        return validatorExistsMap[validator];
    }

    function setValidatorStakeCredit(
        address validator,
        address stakeCredit
    ) external {
        validatorStakeCreditMap[validator] = stakeCredit;
    }

    function getValidatorStakeCredit(
        address validator
    ) external view returns (address) {
        return validatorStakeCreditMap[validator];
    }

    function setValidatorStatus(
        address validator,
        IValidatorManager.ValidatorStatus status
    ) external {
        validatorStatusMap[validator] = status;
    }

    function getValidatorStatus(
        address validator
    ) external view returns (IValidatorManager.ValidatorStatus) {
        return validatorStatusMap[validator];
    }

    function setValidatorStake(
        address validator,
        uint256 stake
    ) external {
        validatorStakeMap[validator] = stake;
    }

    function getValidatorStake(
        address validator
    ) external view returns (uint256) {
        return validatorStakeMap[validator];
    }

    function checkVotingPowerIncrease(
        uint256 /* amount */
    ) external pure {
        // Do nothing - mock implementation
    }

    function checkValidatorMinStake(
        address /* validator */
    ) external pure {
        // Do nothing - mock implementation
    }

    function getTotalStake() external pure returns (uint256) {
        return 1000 ether; // Mock value
    }

    function getValidatorCount() external pure returns (uint256) {
        return 10; // Mock value
    }

    function getActiveValidatorCount() external pure returns (uint256) {
        return 8; // Mock value
    }

    function setupValidator(
        address validator,
        address stakeCredit,
        IValidatorManager.ValidatorStatus status,
        uint256 stake
    ) external {
        validatorExistsMap[validator] = true;
        validatorStakeCreditMap[validator] = stakeCredit;
        validatorStatusMap[validator] = status;
        validatorStakeMap[validator] = stake;
        isCurrentEpochValidatorMap[validator] = (status == IValidatorManager.ValidatorStatus.ACTIVE);
    }

    function removeValidator(
        address validator
    ) external {
        validatorExistsMap[validator] = false;
        validatorStakeCreditMap[validator] = address(0);
        validatorStatusMap[validator] = IValidatorManager.ValidatorStatus.INACTIVE;
        validatorStakeMap[validator] = 0;
        isCurrentEpochValidatorMap[validator] = false;
    }

    function getValidatorSet() external view returns (IValidatorManager.ValidatorSet memory) {
        // Build active validators array
        IValidatorManager.ValidatorInfo[] memory activeValidatorInfos =
            new IValidatorManager.ValidatorInfo[](_activeValidators.length);
        for (uint256 i = 0; i < _activeValidators.length; i++) {
            activeValidatorInfos[i] = _validatorInfos[_activeValidators[i]];
        }

        // Build pending active validators array
        IValidatorManager.ValidatorInfo[] memory pendingActiveInfos =
            new IValidatorManager.ValidatorInfo[](_pendingActiveValidators.length);
        for (uint256 i = 0; i < _pendingActiveValidators.length; i++) {
            pendingActiveInfos[i] = _validatorInfos[_pendingActiveValidators[i]];
        }

        return IValidatorManager.ValidatorSet({
            activeValidators: activeValidatorInfos,
            pendingInactive: _pendingInactiveValidators,
            pendingActive: pendingActiveInfos,
            totalVotingPower: 0,
            totalJoiningPower: 0
        });
    }

    function onNewEpoch() external {
        // Mock implementation - do nothing
    }

    // Additional mock state for new functions
    address[] private _activeValidators;
    address[] private _pendingActiveValidators;
    IValidatorManager.ValidatorInfo[] private _pendingInactiveValidators;
    mapping(address => IValidatorManager.ValidatorInfo) private _validatorInfos;

    function setActiveValidators(
        address[] memory validators
    ) external {
        _activeValidators = validators;
    }

    function setPendingActiveValidators(
        address[] memory validators
    ) external {
        _pendingActiveValidators = validators;
    }

    function setPendingInactiveValidators(
        IValidatorManager.ValidatorInfo[] memory validators
    ) external {
        delete _pendingInactiveValidators;
        for (uint256 i = 0; i < validators.length; i++) {
            _pendingInactiveValidators.push(validators[i]);
        }
    }

    // For backward compatibility - map to existing function
    function getPendingValidators() external view returns (address[] memory) {
        return _pendingActiveValidators;
    }

    function setValidatorInfo(
        address validator,
        IValidatorManager.ValidatorInfo memory info
    ) external {
        _validatorInfos[validator] = info;
    }

    function getActiveValidators() external view returns (address[] memory) {
        return _activeValidators;
    }

    function getPendingActiveValidators() external view returns (address[] memory) {
        return _pendingActiveValidators;
    }

    function getValidatorInfo(
        address validator
    ) external view returns (IValidatorManager.ValidatorInfo memory) {
        return _validatorInfos[validator];
    }
}
