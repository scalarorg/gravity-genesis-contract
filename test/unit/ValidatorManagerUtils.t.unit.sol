// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "forge-std/Test.sol";
import "@src/lib/ValidatorManagerUtils.sol";
import "@src/interfaces/IValidatorManagerUtils.sol";
import "@src/interfaces/IValidatorManager.sol";
import "@test/utils/TestConstants.sol";
import "@test/mocks/StakeConfigMock.sol";

contract ValidatorManagerUtilsTest is Test, TestConstants {
    ValidatorManagerUtils public validatorManagerUtils;
    StakeConfigMock public mockStakeConfig;

    // Test constants
    address private constant TEST_OPERATOR = 0x1234567890123456789012345678901234567890;
    address private constant TEST_VALIDATOR = 0x2234567890123456789012345678901234567890;
    bytes private constant VALID_CONSENSUS_KEY =
        hex"123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456";
    bytes private constant INVALID_CONSENSUS_KEY =
        hex"1234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234"; // Too short
    bytes private constant VALID_BLS_PROOF =
        hex"12345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456";
    bytes private constant INVALID_BLS_PROOF =
        hex"123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234"; // Too short

    string private constant VALID_MONIKER = "TestVal1";
    string private constant INVALID_MONIKER_SHORT = "Te"; // Too short
    string private constant INVALID_MONIKER_LONG = "TestValidator"; // Too long
    string private constant INVALID_MONIKER_LOWERCASE = "testVal1"; // Doesn't start with uppercase
    string private constant INVALID_MONIKER_SPECIAL = "Test@Val"; // Contains special character

    function setUp() public {
        // Deploy mock stake config
        mockStakeConfig = new StakeConfigMock();

        // Deploy ValidatorManagerUtils
        validatorManagerUtils = new ValidatorManagerUtils();

        // Set up mock stake config
        vm.etch(STAKE_CONFIG_ADDR, address(mockStakeConfig).code);
        StakeConfigMock(STAKE_CONFIG_ADDR).setVotingPowerIncreaseLimit(20); // 20%
        StakeConfigMock(STAKE_CONFIG_ADDR).setMAX_COMMISSION_RATE(10000); // 100%
    }

    // ============ VALIDATE MONIKER TESTS ============

    function test_validateMoniker_validMoniker_shouldNotRevert() public view {
        // Should not revert for valid moniker
        validatorManagerUtils.validateMoniker(VALID_MONIKER);
    }

    function test_validateMoniker_shortMoniker_shouldRevert() public {
        // Arrange & Act & Assert
        vm.expectRevert(abi.encodeWithSelector(IValidatorManager.InvalidMoniker.selector, INVALID_MONIKER_SHORT));
        validatorManagerUtils.validateMoniker(INVALID_MONIKER_SHORT);
    }

    function test_validateMoniker_longMoniker_shouldRevert() public {
        // Arrange & Act & Assert
        vm.expectRevert(abi.encodeWithSelector(IValidatorManager.InvalidMoniker.selector, INVALID_MONIKER_LONG));
        validatorManagerUtils.validateMoniker(INVALID_MONIKER_LONG);
    }

    function test_validateMoniker_lowercaseStart_shouldRevert() public {
        // Arrange & Act & Assert
        vm.expectRevert(abi.encodeWithSelector(IValidatorManager.InvalidMoniker.selector, INVALID_MONIKER_LOWERCASE));
        validatorManagerUtils.validateMoniker(INVALID_MONIKER_LOWERCASE);
    }

    function test_validateMoniker_specialCharacter_shouldRevert() public {
        // Arrange & Act & Assert
        vm.expectRevert(abi.encodeWithSelector(IValidatorManager.InvalidMoniker.selector, INVALID_MONIKER_SPECIAL));
        validatorManagerUtils.validateMoniker(INVALID_MONIKER_SPECIAL);
    }

    // ============ VALIDATE CONSENSUS KEY TESTS ============

    function test_validateConsensusKey_invalidKeyLength_shouldRevert() public {
        // Arrange & Act & Assert
        vm.expectRevert(IValidatorManager.InvalidVoteAddress.selector);
        validatorManagerUtils.validateConsensusKey(TEST_OPERATOR, INVALID_CONSENSUS_KEY, VALID_BLS_PROOF);
    }

    function test_validateConsensusKey_invalidProofLength_shouldRevert() public {
        // Arrange & Act & Assert
        vm.expectRevert(IValidatorManager.InvalidVoteAddress.selector);
        validatorManagerUtils.validateConsensusKey(TEST_OPERATOR, VALID_CONSENSUS_KEY, INVALID_BLS_PROOF);
    }

    function test_validateConsensusKey_invalidBLSSignature_shouldRevert() public {
        // Since we don't have the actual BLS precompile in tests, this will revert
        // because the assembly call to 0x66 will fail
        vm.expectRevert(IValidatorManager.InvalidVoteAddress.selector);
        validatorManagerUtils.validateConsensusKey(TEST_OPERATOR, VALID_CONSENSUS_KEY, VALID_BLS_PROOF);
    }

    // ============ CHECK VOTING POWER INCREASE TESTS ============

    function test_checkVotingPowerIncrease_zeroTotalPower_shouldNotRevert() public view {
        // When total voting power is 0, should not revert regardless of increase
        validatorManagerUtils.checkVotingPowerIncrease(1000 ether, 0, 0);
    }

    function test_checkVotingPowerIncrease_withinLimit_shouldNotRevert() public view {
        // Arrange
        uint256 totalVotingPower = 1000 ether;
        uint256 currentPendingPower = 100 ether; // 10%
        uint256 increaseAmount = 50 ether; // 5% more, total 15% < 20% limit

        // Act - should not revert
        validatorManagerUtils.checkVotingPowerIncrease(increaseAmount, totalVotingPower, currentPendingPower);
    }

    function test_checkVotingPowerIncrease_exceedsLimit_shouldRevert() public {
        // Arrange
        uint256 totalVotingPower = 1000 ether;
        uint256 currentPendingPower = 150 ether; // 15%
        uint256 increaseAmount = 100 ether; // 10% more, total 25% > 20% limit

        // Act & Assert
        vm.expectRevert(IValidatorManager.VotingPowerIncreaseExceedsLimit.selector);
        validatorManagerUtils.checkVotingPowerIncrease(increaseAmount, totalVotingPower, currentPendingPower);
    }

    function test_checkVotingPowerIncrease_exactLimit_shouldNotRevert() public view {
        // Arrange
        uint256 totalVotingPower = 1000 ether;
        uint256 currentPendingPower = 100 ether; // 10%
        uint256 increaseAmount = 100 ether; // 10% more, total exactly 20%

        // Act - should not revert
        validatorManagerUtils.checkVotingPowerIncrease(increaseAmount, totalVotingPower, currentPendingPower);
    }

    // ============ VALIDATE REGISTRATION PARAMS TESTS ============

    function test_validateRegistrationParams_validParams_shouldNotRevert() public view {
        // Arrange
        IValidatorManager.Commission memory commission = IValidatorManager.Commission({
            rate: 1000, // 10%
            maxRate: 5000, // 50%
            maxChangeRate: 500 // 5%
        });

        // Act - should not revert (use empty consensus key to avoid BLS verification in tests)
        validatorManagerUtils.validateRegistrationParams(
            TEST_VALIDATOR,
            "", // empty consensus key to avoid BLS verification
            "",
            VALID_MONIKER,
            commission,
            TEST_OPERATOR,
            false, // consensus key not used
            false, // moniker not used
            false, // operator not used
            false // validator not registered
        );
    }

    function test_validateRegistrationParams_alreadyRegistered_shouldRevert() public {
        // Arrange
        IValidatorManager.Commission memory commission =
            IValidatorManager.Commission({ rate: 1000, maxRate: 5000, maxChangeRate: 500 });

        // Act & Assert
        vm.expectRevert(abi.encodeWithSelector(IValidatorManager.ValidatorAlreadyExists.selector, TEST_VALIDATOR));
        validatorManagerUtils.validateRegistrationParams(
            TEST_VALIDATOR,
            VALID_CONSENSUS_KEY,
            VALID_BLS_PROOF,
            VALID_MONIKER,
            commission,
            TEST_OPERATOR,
            false,
            false,
            false,
            true // validator already registered
        );
    }

    function test_validateRegistrationParams_consensusKeyUsed_shouldRevert() public {
        // Arrange
        IValidatorManager.Commission memory commission =
            IValidatorManager.Commission({ rate: 1000, maxRate: 5000, maxChangeRate: 500 });

        // Act & Assert
        vm.expectRevert(
            abi.encodeWithSelector(IValidatorManager.DuplicateConsensusAddress.selector, VALID_CONSENSUS_KEY)
        );
        validatorManagerUtils.validateRegistrationParams(
            TEST_VALIDATOR,
            VALID_CONSENSUS_KEY,
            VALID_BLS_PROOF,
            VALID_MONIKER,
            commission,
            TEST_OPERATOR,
            true, // consensus key already used
            false,
            false,
            false
        );
    }

    function test_validateRegistrationParams_monikerUsed_shouldRevert() public {
        // Arrange
        IValidatorManager.Commission memory commission =
            IValidatorManager.Commission({ rate: 1000, maxRate: 5000, maxChangeRate: 500 });

        // Act & Assert
        vm.expectRevert(abi.encodeWithSelector(IValidatorManager.DuplicateMoniker.selector, VALID_MONIKER));
        validatorManagerUtils.validateRegistrationParams(
            TEST_VALIDATOR,
            VALID_CONSENSUS_KEY,
            VALID_BLS_PROOF,
            VALID_MONIKER,
            commission,
            TEST_OPERATOR,
            false,
            true, // moniker already used
            false,
            false
        );
    }

    function test_validateRegistrationParams_operatorUsed_shouldRevert() public {
        // Arrange
        IValidatorManager.Commission memory commission =
            IValidatorManager.Commission({ rate: 1000, maxRate: 5000, maxChangeRate: 500 });

        // Act & Assert
        vm.expectRevert(
            abi.encodeWithSelector(IValidatorManager.AddressAlreadyInUse.selector, TEST_OPERATOR, address(0))
        );
        validatorManagerUtils.validateRegistrationParams(
            TEST_VALIDATOR,
            "", // empty consensus key to avoid BLS verification
            "",
            VALID_MONIKER,
            commission,
            TEST_OPERATOR,
            false,
            false,
            true, // operator already used
            false
        );
    }

    function test_validateRegistrationParams_invalidCommission_shouldRevert() public {
        // Arrange
        IValidatorManager.Commission memory commission = IValidatorManager.Commission({
            rate: 6000, // 60%
            maxRate: 5000, // 50% - rate > maxRate
            maxChangeRate: 500
        });

        // Act & Assert
        vm.expectRevert(IValidatorManager.InvalidCommission.selector);
        validatorManagerUtils.validateRegistrationParams(
            TEST_VALIDATOR,
            VALID_CONSENSUS_KEY,
            VALID_BLS_PROOF,
            VALID_MONIKER,
            commission,
            TEST_OPERATOR,
            false,
            false,
            false,
            false
        );
    }

    function test_validateRegistrationParams_zeroOperator_shouldRevert() public {
        // Arrange
        IValidatorManager.Commission memory commission =
            IValidatorManager.Commission({ rate: 1000, maxRate: 5000, maxChangeRate: 500 });

        // Act & Assert
        vm.expectRevert(abi.encodeWithSelector(IValidatorManager.InvalidAddress.selector, address(0)));
        validatorManagerUtils.validateRegistrationParams(
            TEST_VALIDATOR,
            "", // empty consensus key to avoid BLS verification
            "",
            VALID_MONIKER,
            commission,
            address(0), // zero operator
            false,
            false,
            false,
            false
        );
    }
}
