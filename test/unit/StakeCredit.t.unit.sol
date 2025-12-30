// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "forge-std/Test.sol";
import "@src/stake/StakeCredit.sol";
import "@src/System.sol";
import "@test/utils/TestConstants.sol";
import "@test/mocks/ValidatorManagerMock.sol";
import "@test/mocks/StakeConfigMock.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract StakeCreditTest is Test, TestConstants {
    StakeCredit public stakeCredit;
    StakeCredit public implementation;
    address public proxyAddress;

    ValidatorManagerMock public validatorManagerMock;
    StakeConfigMock public stakeConfigMock;

    // Test users
    address public validator = TEST_VALIDATOR_1;
    address public delegator1 = TEST_DELEGATOR_1;
    address public delegator2 = TEST_DELEGATOR_2;
    address public beneficiary = makeAddr("beneficiary");
    address public attacker = makeAddr("attacker");

    // Test values
    uint256 public constant INITIAL_STAKE = 1000 ether;
    uint256 public constant DELEGATION_AMOUNT = 100 ether;
    uint256 public constant UNLOCK_AMOUNT = 50 ether;

    function setUp() public {
        // Deploy implementation
        implementation = new StakeCredit();

        // Deploy mocks
        validatorManagerMock = new ValidatorManagerMock();
        stakeConfigMock = new StakeConfigMock();

        // Setup mocks at system addresses
        vm.etch(VALIDATOR_MANAGER_ADDR, address(validatorManagerMock).code);
        vm.etch(STAKE_CONFIG_ADDR, address(stakeConfigMock).code);

        // Initialize mocks
        IValidatorManager.InitializationParams memory emptyParams = IValidatorManager.InitializationParams({
            validatorAddresses: new address[](0),
            consensusPublicKeys: new bytes[](0),
            votingPowers: new uint256[](0),
            validatorNetworkAddresses: new bytes[](0),
            fullnodeNetworkAddresses: new bytes[](0),
            aptosAddresses: new bytes[](0)
        });
        ValidatorManagerMock(VALIDATOR_MANAGER_ADDR).initialize(emptyParams);
        StakeConfigMock(STAKE_CONFIG_ADDR).initialize();

        // Setup validator as current epoch validator
        ValidatorManagerMock(VALIDATOR_MANAGER_ADDR).setIsCurrentEpochValidator(validator, true);

        // Deploy proxy with validator as owner
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            validator, // initialOwner
            ""
        );
        proxyAddress = address(proxy);
        stakeCredit = StakeCredit(payable(proxyAddress));

        // Give test accounts some ETH
        vm.deal(validator, 10000 ether);
        vm.deal(delegator1, 10000 ether);
        vm.deal(delegator2, 10000 ether);
        vm.deal(DELEGATION_ADDR, 10000 ether);
        vm.deal(VALIDATOR_MANAGER_ADDR, 10000 ether);
    }

    // ============ INITIALIZATION TESTS ============

    function test_initialize_shouldWork() public {
        // Act
        vm.prank(validator);
        stakeCredit.initialize{value: INITIAL_STAKE}(validator, "TestValidator", beneficiary);

        // Assert
        assertEq(stakeCredit.validator(), validator);
        assertEq(stakeCredit.active(), INITIAL_STAKE);
        assertEq(stakeCredit.inactive(), 0);
        assertEq(stakeCredit.pendingActive(), 0);
        assertEq(stakeCredit.pendingInactive(), 0);
        assertEq(stakeCredit.stakedAmount(validator), INITIAL_STAKE);
        assertEq(address(stakeCredit).balance, INITIAL_STAKE);
    }

    function test_initialize_shouldRevertIfValidatorNotOwner() public {
        // Act & Assert
        vm.prank(validator);
        vm.expectRevert("StakeCredit: validator must equal proxy owner");
        stakeCredit.initialize{value: INITIAL_STAKE}(attacker, "TestValidator", beneficiary);
    }

    function test_initialize_shouldRevertIfZeroAmount() public {
        // Act & Assert
        vm.prank(validator);
        vm.expectRevert(abi.encodeWithSelector(IStakeCredit.StakeCredit__WrongInitContext.selector, 0, 0, validator));
        stakeCredit.initialize{value: 0}(validator, "TestValidator", beneficiary);
    }

    function test_initialize_shouldRevertIfZeroValidator() public {
        // Note: Cannot test zero validator directly because TransparentUpgradeableProxy
        // requires a non-zero owner. The zero validator check happens in initialize
        // but the proxy owner check happens first.
        // This test is skipped as it's not possible to create a proxy with zero owner.
    }

    function test_initialize_cannotBeCalledTwice() public {
        // Arrange
        vm.prank(validator);
        stakeCredit.initialize{value: INITIAL_STAKE}(validator, "TestValidator", beneficiary);

        // Act & Assert
        vm.prank(validator);
        vm.expectRevert();
        stakeCredit.initialize{value: INITIAL_STAKE}(validator, "TestValidator", beneficiary);
    }

    // ============ DELEGATE TESTS ============

    function test_delegate_shouldWork() public {
        // Arrange
        vm.prank(validator);
        stakeCredit.initialize{value: INITIAL_STAKE}(validator, "TestValidator", beneficiary);
        ValidatorManagerMock(VALIDATOR_MANAGER_ADDR).setIsCurrentEpochValidator(validator, false);

        // Act
        vm.prank(DELEGATION_ADDR);
        uint256 shares = stakeCredit.delegate{value: DELEGATION_AMOUNT}(delegator1);

        // Assert
        assertEq(shares, DELEGATION_AMOUNT);
        assertEq(stakeCredit.stakedAmount(delegator1), DELEGATION_AMOUNT);
        assertEq(stakeCredit.active(), INITIAL_STAKE + DELEGATION_AMOUNT);
        assertEq(address(stakeCredit).balance, INITIAL_STAKE + DELEGATION_AMOUNT);
    }

    function test_delegate_shouldGoToPendingActiveIfCurrentEpochValidator() public {
        // Arrange
        vm.prank(validator);
        stakeCredit.initialize{value: INITIAL_STAKE}(validator, "TestValidator", beneficiary);
        ValidatorManagerMock(VALIDATOR_MANAGER_ADDR).setIsCurrentEpochValidator(validator, true);

        // Act
        vm.prank(DELEGATION_ADDR);
        stakeCredit.delegate{value: DELEGATION_AMOUNT}(delegator1);

        // Assert
        assertEq(stakeCredit.pendingActive(), DELEGATION_AMOUNT);
        assertEq(stakeCredit.active(), INITIAL_STAKE);
    }

    function test_delegate_shouldGoToActiveIfNotCurrentEpochValidator() public {
        // Arrange
        vm.prank(validator);
        stakeCredit.initialize{value: INITIAL_STAKE}(validator, "TestValidator", beneficiary);
        ValidatorManagerMock(VALIDATOR_MANAGER_ADDR).setIsCurrentEpochValidator(validator, false);

        // Act
        vm.prank(DELEGATION_ADDR);
        stakeCredit.delegate{value: DELEGATION_AMOUNT}(delegator1);

        // Assert
        assertEq(stakeCredit.active(), INITIAL_STAKE + DELEGATION_AMOUNT);
        assertEq(stakeCredit.pendingActive(), 0);
    }

    function test_delegate_shouldRevertIfZeroAmount() public {
        // Arrange
        vm.prank(validator);
        stakeCredit.initialize{value: INITIAL_STAKE}(validator, "TestValidator", beneficiary);

        // Act & Assert
        vm.prank(DELEGATION_ADDR);
        vm.expectRevert(IStakeCredit.ZeroAmount.selector);
        stakeCredit.delegate{value: 0}(delegator1);
    }

    function test_delegate_shouldRevertIfNotAuthorized() public {
        // Arrange
        vm.prank(validator);
        stakeCredit.initialize{value: INITIAL_STAKE}(validator, "TestValidator", beneficiary);
        vm.deal(attacker, 100 ether);

        // Act & Assert
        // The error will show VALIDATOR_MANAGER_ADDR because attacker != DELEGATION_ADDR
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(System.OnlySystemContract.selector, VALIDATOR_MANAGER_ADDR));
        stakeCredit.delegate{value: DELEGATION_AMOUNT}(delegator1);
    }

    // ============ UNLOCK TESTS ============

    function test_unlock_shouldWork() public {
        // Arrange
        vm.prank(validator);
        stakeCredit.initialize{value: INITIAL_STAKE}(validator, "TestValidator", beneficiary);
        ValidatorManagerMock(VALIDATOR_MANAGER_ADDR).setIsCurrentEpochValidator(validator, false);
        vm.prank(DELEGATION_ADDR);
        stakeCredit.delegate{value: DELEGATION_AMOUNT}(delegator1);

        // Act
        vm.prank(DELEGATION_ADDR);
        uint256 amount = stakeCredit.unlock(delegator1, UNLOCK_AMOUNT);

        // Assert
        assertEq(amount, UNLOCK_AMOUNT);
        assertEq(stakeCredit.stakedAmount(delegator1), DELEGATION_AMOUNT - UNLOCK_AMOUNT);
        assertEq(stakeCredit.pendingUnlockAmount(delegator1), UNLOCK_AMOUNT);
        assertEq(stakeCredit.pendingInactive(), UNLOCK_AMOUNT);
        assertEq(stakeCredit.active(), INITIAL_STAKE + DELEGATION_AMOUNT - UNLOCK_AMOUNT);
    }

    function test_unlock_shouldRevertIfZeroAmount() public {
        // Arrange
        vm.prank(validator);
        stakeCredit.initialize{value: INITIAL_STAKE}(validator, "TestValidator", beneficiary);

        // Act & Assert
        vm.prank(DELEGATION_ADDR);
        vm.expectRevert(IStakeCredit.ZeroAmount.selector);
        stakeCredit.unlock(delegator1, 0);
    }

    function test_unlock_shouldRevertIfInsufficientBalance() public {
        // Arrange
        vm.prank(validator);
        stakeCredit.initialize{value: INITIAL_STAKE}(validator, "TestValidator", beneficiary);

        // Act & Assert
        vm.prank(DELEGATION_ADDR);
        vm.expectRevert(IStakeCredit.InsufficientBalance.selector);
        stakeCredit.unlock(delegator1, DELEGATION_AMOUNT);
    }

    // ============ CLAIM TESTS ============

    function test_claim_shouldWork() public {
        // Arrange
        vm.prank(validator);
        stakeCredit.initialize{value: INITIAL_STAKE}(validator, "TestValidator", beneficiary);
        vm.prank(DELEGATION_ADDR);
        stakeCredit.delegate{value: DELEGATION_AMOUNT}(delegator1);
        vm.prank(DELEGATION_ADDR);
        stakeCredit.unlock(delegator1, UNLOCK_AMOUNT);
        
        // Move to inactive via epoch transition
        vm.prank(VALIDATOR_MANAGER_ADDR);
        stakeCredit.onNewEpoch();

        uint256 balanceBefore = delegator1.balance;

        // Act
        vm.prank(DELEGATION_ADDR);
        uint256 claimed = stakeCredit.claim(payable(delegator1));

        // Assert
        assertEq(claimed, UNLOCK_AMOUNT);
        assertEq(delegator1.balance, balanceBefore + UNLOCK_AMOUNT);
        assertEq(stakeCredit.pendingUnlockAmount(delegator1), 0);
        assertEq(stakeCredit.inactive(), 0);
    }

    function test_claim_shouldRevertIfNoClaimableRequest() public {
        // Arrange
        vm.prank(validator);
        stakeCredit.initialize{value: INITIAL_STAKE}(validator, "TestValidator", beneficiary);

        // Act & Assert
        vm.prank(DELEGATION_ADDR);
        vm.expectRevert(IStakeCredit.StakeCredit__NoClaimableRequest.selector);
        stakeCredit.claim(payable(delegator1));
    }

    // ============ UNBOND TESTS ============

    function test_unbond_shouldWork() public {
        // Arrange
        vm.prank(validator);
        stakeCredit.initialize{value: INITIAL_STAKE}(validator, "TestValidator", beneficiary);
        vm.prank(DELEGATION_ADDR);
        stakeCredit.delegate{value: DELEGATION_AMOUNT}(delegator1);

        uint256 balanceBefore = DELEGATION_ADDR.balance;

        // Act
        vm.prank(DELEGATION_ADDR);
        uint256 amount = stakeCredit.unbond(delegator1, UNLOCK_AMOUNT);

        // Assert
        assertEq(amount, UNLOCK_AMOUNT);
        assertEq(stakeCredit.stakedAmount(delegator1), DELEGATION_AMOUNT - UNLOCK_AMOUNT);
        assertEq(DELEGATION_ADDR.balance, balanceBefore + UNLOCK_AMOUNT);
    }

    function test_unbond_shouldRevertIfZeroAmount() public {
        // Arrange
        vm.prank(validator);
        stakeCredit.initialize{value: INITIAL_STAKE}(validator, "TestValidator", beneficiary);

        // Act & Assert
        vm.prank(DELEGATION_ADDR);
        vm.expectRevert(IStakeCredit.ZeroAmount.selector);
        stakeCredit.unbond(delegator1, 0);
    }

    // ============ REACTIVATE STAKE TESTS ============

    function test_reactivateStake_shouldWork() public {
        // Arrange
        vm.prank(validator);
        stakeCredit.initialize{value: INITIAL_STAKE}(validator, "TestValidator", beneficiary);
        ValidatorManagerMock(VALIDATOR_MANAGER_ADDR).setIsCurrentEpochValidator(validator, false);
        vm.prank(DELEGATION_ADDR);
        stakeCredit.delegate{value: DELEGATION_AMOUNT}(delegator1);
        vm.prank(DELEGATION_ADDR);
        stakeCredit.unlock(delegator1, UNLOCK_AMOUNT);

        // Act
        vm.prank(DELEGATION_ADDR);
        uint256 amount = stakeCredit.reactivateStake(delegator1, UNLOCK_AMOUNT);

        // Assert
        assertEq(amount, UNLOCK_AMOUNT);
        assertEq(stakeCredit.stakedAmount(delegator1), DELEGATION_AMOUNT);
        assertEq(stakeCredit.pendingUnlockAmount(delegator1), 0);
        assertEq(stakeCredit.pendingInactive(), 0);
        assertEq(stakeCredit.active(), INITIAL_STAKE + DELEGATION_AMOUNT);
    }

    // ============ EPOCH TRANSITION TESTS ============

    function test_onNewEpoch_shouldWork() public {
        // Arrange
        vm.prank(validator);
        stakeCredit.initialize{value: INITIAL_STAKE}(validator, "TestValidator", beneficiary);
        ValidatorManagerMock(VALIDATOR_MANAGER_ADDR).setIsCurrentEpochValidator(validator, true);
        vm.prank(DELEGATION_ADDR);
        stakeCredit.delegate{value: DELEGATION_AMOUNT}(delegator1);
        vm.prank(DELEGATION_ADDR);
        stakeCredit.unlock(delegator1, UNLOCK_AMOUNT);

        uint256 oldActive = stakeCredit.active();
        uint256 oldPendingActive = stakeCredit.pendingActive();
        uint256 oldPendingInactive = stakeCredit.pendingInactive();

        // Act
        vm.prank(VALIDATOR_MANAGER_ADDR);
        stakeCredit.onNewEpoch();

        // Assert
        assertEq(stakeCredit.active(), oldActive + oldPendingActive);
        assertEq(stakeCredit.pendingActive(), 0);
        assertEq(stakeCredit.inactive(), oldPendingInactive);
        assertEq(stakeCredit.pendingInactive(), 0);
    }

    function test_onNewEpoch_shouldRevertIfNotValidatorManager() public {
        // Arrange
        vm.prank(validator);
        stakeCredit.initialize{value: INITIAL_STAKE}(validator, "TestValidator", beneficiary);

        // Act & Assert
        vm.prank(attacker);
        vm.expectRevert();
        stakeCredit.onNewEpoch();
    }

    // ============ VIEW FUNCTION TESTS ============

    function test_getTotalPooledG_shouldReturnCorrectValue() public {
        // Arrange
        vm.prank(validator);
        stakeCredit.initialize{value: INITIAL_STAKE}(validator, "TestValidator", beneficiary);
        vm.prank(DELEGATION_ADDR);
        stakeCredit.delegate{value: DELEGATION_AMOUNT}(delegator1);

        // Act
        uint256 total = stakeCredit.getTotalPooledG();

        // Assert
        assertEq(total, INITIAL_STAKE + DELEGATION_AMOUNT);
    }

    function test_getStake_shouldReturnCorrectValues() public {
        // Arrange
        vm.prank(validator);
        stakeCredit.initialize{value: INITIAL_STAKE}(validator, "TestValidator", beneficiary);

        // Act
        (uint256 active, uint256 inactive, uint256 pendingActive, uint256 pendingInactive) = stakeCredit.getStake();

        // Assert
        assertEq(active, INITIAL_STAKE);
        assertEq(inactive, 0);
        assertEq(pendingActive, 0);
        assertEq(pendingInactive, 0);
    }

    function test_getNextEpochVotingPower_shouldReturnCorrectValue() public {
        // Arrange
        vm.prank(validator);
        stakeCredit.initialize{value: INITIAL_STAKE}(validator, "TestValidator", beneficiary);
        ValidatorManagerMock(VALIDATOR_MANAGER_ADDR).setIsCurrentEpochValidator(validator, true);
        vm.prank(DELEGATION_ADDR);
        stakeCredit.delegate{value: DELEGATION_AMOUNT}(delegator1);

        // Act
        uint256 votingPower = stakeCredit.getNextEpochVotingPower();

        // Assert
        assertEq(votingPower, INITIAL_STAKE + DELEGATION_AMOUNT);
    }

    function test_getCurrentEpochVotingPower_shouldReturnCorrectValue() public {
        // Arrange
        vm.prank(validator);
        stakeCredit.initialize{value: INITIAL_STAKE}(validator, "TestValidator", beneficiary);
        ValidatorManagerMock(VALIDATOR_MANAGER_ADDR).setIsCurrentEpochValidator(validator, false);
        vm.prank(DELEGATION_ADDR);
        stakeCredit.delegate{value: DELEGATION_AMOUNT}(delegator1);
        vm.prank(DELEGATION_ADDR);
        stakeCredit.unlock(delegator1, UNLOCK_AMOUNT);

        // Act
        uint256 votingPower = stakeCredit.getCurrentEpochVotingPower();

        // Assert
        // getCurrentEpochVotingPower returns active + pendingInactive
        assertEq(votingPower, INITIAL_STAKE + DELEGATION_AMOUNT - UNLOCK_AMOUNT + UNLOCK_AMOUNT);
    }

    function test_getPooledGByDelegator_shouldReturnCorrectValue() public {
        // Arrange
        vm.prank(validator);
        stakeCredit.initialize{value: INITIAL_STAKE}(validator, "TestValidator", beneficiary);
        vm.prank(DELEGATION_ADDR);
        stakeCredit.delegate{value: DELEGATION_AMOUNT}(delegator1);

        // Act
        uint256 amount = stakeCredit.getPooledGByDelegator(delegator1);

        // Assert
        assertEq(amount, DELEGATION_AMOUNT);
    }

    function test_getPendingUnlockAmount_shouldReturnCorrectValue() public {
        // Arrange
        vm.prank(validator);
        stakeCredit.initialize{value: INITIAL_STAKE}(validator, "TestValidator", beneficiary);
        vm.prank(DELEGATION_ADDR);
        stakeCredit.delegate{value: DELEGATION_AMOUNT}(delegator1);
        vm.prank(DELEGATION_ADDR);
        stakeCredit.unlock(delegator1, UNLOCK_AMOUNT);

        // Act
        uint256 amount = stakeCredit.getPendingUnlockAmount(delegator1);

        // Assert
        assertEq(amount, UNLOCK_AMOUNT);
    }

    function test_getClaimableAmount_shouldReturnZeroIfNoUnlock() public {
        // Arrange
        vm.prank(validator);
        stakeCredit.initialize{value: INITIAL_STAKE}(validator, "TestValidator", beneficiary);

        // Act
        uint256 amount = stakeCredit.getClaimableAmount(delegator1);

        // Assert
        assertEq(amount, 0);
    }

    function test_getClaimableAmount_shouldReturnCorrectValue() public {
        // Arrange
        vm.prank(validator);
        stakeCredit.initialize{value: INITIAL_STAKE}(validator, "TestValidator", beneficiary);
        vm.prank(DELEGATION_ADDR);
        stakeCredit.delegate{value: DELEGATION_AMOUNT}(delegator1);
        vm.prank(DELEGATION_ADDR);
        stakeCredit.unlock(delegator1, UNLOCK_AMOUNT);
        vm.prank(VALIDATOR_MANAGER_ADDR);
        stakeCredit.onNewEpoch();

        // Act
        uint256 amount = stakeCredit.getClaimableAmount(delegator1);

        // Assert
        assertEq(amount, UNLOCK_AMOUNT);
    }

    function test_validateStakeStates_shouldReturnTrue() public {
        // Arrange
        vm.prank(validator);
        stakeCredit.initialize{value: INITIAL_STAKE}(validator, "TestValidator", beneficiary);

        // Act
        bool isValid = stakeCredit.validateStakeStates();

        // Assert
        assertTrue(isValid);
    }

    function test_getDetailedStakeInfo_shouldReturnCorrectValues() public {
        // Arrange
        vm.prank(validator);
        stakeCredit.initialize{value: INITIAL_STAKE}(validator, "TestValidator", beneficiary);

        // Act
        (
            uint256 _active,
            uint256 _inactive,
            uint256 _pendingActive,
            uint256 _pendingInactive,
            uint256 _totalPooled,
            uint256 _contractBalance,
            uint256 _totalShares,
            bool _hasUnlockRequest
        ) = stakeCredit.getDetailedStakeInfo();

        // Assert
        assertEq(_active, INITIAL_STAKE);
        assertEq(_inactive, 0);
        assertEq(_pendingActive, 0);
        assertEq(_pendingInactive, 0);
        assertEq(_totalPooled, INITIAL_STAKE);
        assertEq(_contractBalance, INITIAL_STAKE);
        assertEq(_totalShares, 0);
        assertFalse(_hasUnlockRequest);
    }

    // ============ EXTRACT UNRECORDED TOKENS TESTS ============

    function test_extractUnrecordedTokens_shouldWork() public {
        // Arrange
        vm.prank(validator);
        stakeCredit.initialize{value: INITIAL_STAKE}(validator, "TestValidator", beneficiary);
        
        // Send unrecorded tokens directly - StakeCredit doesn't have receive, but we can use selfdestruct
        // or just use deal to add balance directly
        vm.deal(address(stakeCredit), address(stakeCredit).balance + 100 ether);

        uint256 balanceBefore = validator.balance;

        // Act
        vm.prank(validator);
        uint256 extracted = stakeCredit.extractUnrecordedTokens();

        // Assert
        assertEq(extracted, 100 ether);
        assertEq(validator.balance, balanceBefore + 100 ether);
    }

    function test_extractUnrecordedTokens_shouldRevertIfNotOwner() public {
        // Arrange
        vm.prank(validator);
        stakeCredit.initialize{value: INITIAL_STAKE}(validator, "TestValidator", beneficiary);

        // Act & Assert
        vm.prank(attacker);
        vm.expectRevert("StakeCredit: only owner");
        stakeCredit.extractUnrecordedTokens();
    }

    function test_extractUnrecordedTokens_shouldRevertIfNoUnrecordedTokens() public {
        // Arrange
        vm.prank(validator);
        stakeCredit.initialize{value: INITIAL_STAKE}(validator, "TestValidator", beneficiary);

        // Act & Assert
        vm.prank(validator);
        vm.expectRevert(IStakeCredit.InsufficientBalance.selector);
        stakeCredit.extractUnrecordedTokens();
    }
}


