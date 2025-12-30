// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@src/interfaces/IJWKManager.sol";
import "@src/interfaces/IValidatorManager.sol";
import "@src/interfaces/IDelegation.sol";

contract JWKManagerMock {
    bool public initialized;

    // Mock data for testing
    mapping(address => bool) public validatorExistsMap;
    mapping(address => address) public validatorStakeCreditMap;

    // Event tracking
    bool public stakeRegisterValidatorEventEmitted;
    bool public stakeEventEmitted;
    address public lastStakeUser;
    uint256 public lastStakeAmount;
    bytes public lastValidatorParams;
    address public lastTargetValidator;

    // Mock functions for ValidatorManager
    function registerValidator(
        IValidatorManager.ValidatorRegistrationParams calldata params
    ) external payable {
        // Mock implementation - just track the call
        stakeRegisterValidatorEventEmitted = true;
        // For testing, we'll use the initialOperator as the user since that's what we expect
        lastStakeUser = params.initialOperator;
        lastStakeAmount = msg.value;
        lastValidatorParams = abi.encode(params);
    }

    // Mock functions for Delegation
    function delegate(
        address validator
    ) external payable {
        // Mock implementation - just track the call
        stakeEventEmitted = true;
        // For testing, we'll use a default user address since delegation doesn't have user info in the call
        lastStakeUser = address(0x1234567890123456789012345678901234567890); // TEST_USER
        lastStakeAmount = msg.value;
        lastTargetValidator = validator;
    }

    // Mock setup functions
    function initialize() external {
        initialized = true;
    }

    function setValidatorExists(
        address validator,
        bool exists
    ) external {
        validatorExistsMap[validator] = exists;
    }

    function setValidatorStakeCredit(
        address validator,
        address stakeCredit
    ) external {
        validatorStakeCreditMap[validator] = stakeCredit;
    }

    // Reset function for testing
    function reset() external {
        stakeRegisterValidatorEventEmitted = false;
        stakeEventEmitted = false;
        lastStakeUser = address(0);
        lastStakeAmount = 0;
        lastValidatorParams = "";
        lastTargetValidator = address(0);
    }

    // Mock view functions
    function isValidatorExists(
        address validator
    ) external view returns (bool) {
        return validatorExistsMap[validator];
    }

    function getValidatorStakeCredit(
        address validator
    ) external view returns (address) {
        return validatorStakeCreditMap[validator];
    }
}
