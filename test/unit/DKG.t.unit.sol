// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import "forge-std/Test.sol";
import "@src/dkg/DKG.sol";
import "@test/mocks/TimestampMock.sol";
import "@src/interfaces/IDKG.sol";
import "@test/utils/TestConstants.sol";

contract DKGTest is Test, TestConstants {
    DKG dkgContract;
    TimestampMock timestampContract;

    // Test data
    uint64 constant TEST_DEALER_EPOCH = 1;
    uint64 constant TEST_START_TIME = 1000000000; // 1 second in microseconds
    bytes constant TEST_TRANSCRIPT = "test_transcript";

    function setUp() public {
        // Deploy mock contracts
        timestampContract = new TimestampMock();

        // Deploy DKG contract
        dkgContract = new DKG();

        // Deploy mock contracts to system addresses
        vm.etch(TIMESTAMP_ADDR, address(timestampContract).code);

        // Set up mock data
        TimestampMock(TIMESTAMP_ADDR).setNowMicroseconds(TEST_START_TIME);
    }

    function test_initialize_shouldSucceed() public {
        // Arrange
        vm.startPrank(GENESIS_ADDR);

        // Act
        dkgContract.initialize();

        // Assert
        assertFalse(dkgContract.isDKGInProgress());
        (bool hasLastCompleted,) = dkgContract.lastCompletedSession();
        assertFalse(hasLastCompleted);
    }

    function test_initialize_shouldRevertIfNotGenesis() public {
        // Arrange
        vm.startPrank(address(0x123));

        // Act & Assert
        vm.expectRevert();
        dkgContract.initialize();
    }

    function test_start_shouldSucceed() public {
        // Arrange
        vm.startPrank(GENESIS_ADDR);
        dkgContract.initialize();
        vm.stopPrank();

        vm.startPrank(SYSTEM_CALLER);

        IRandomnessConfig.RandomnessConfigData memory randomnessConfig = _createTestRandomnessConfig();
        IDKG.ValidatorConsensusInfo[] memory dealerValidators = _createTestValidators();
        IDKG.ValidatorConsensusInfo[] memory targetValidators = _createTestValidators();

        // Act & Assert
        vm.expectEmit(true, true, true, true);
        emit IDKG.DKGStartEvent(
            IDKG.DKGSessionMetadata({
                dealerEpoch: TEST_DEALER_EPOCH,
                randomnessConfig: randomnessConfig,
                dealerValidatorSet: dealerValidators,
                targetValidatorSet: targetValidators
            }),
            TEST_START_TIME
        );

        dkgContract.start(TEST_DEALER_EPOCH, randomnessConfig, dealerValidators, targetValidators);

        // Assert
        assertTrue(dkgContract.isDKGInProgress());
        (bool hasIncomplete, IDKG.DKGSessionState memory session) = dkgContract.incompleteSession();
        assertTrue(hasIncomplete);
        assertEq(session.metadata.dealerEpoch, TEST_DEALER_EPOCH);
        assertEq(session.startTimeUs, TEST_START_TIME);
    }

    function test_start_shouldRevertIfDKGInProgress() public {
        // Arrange
        vm.startPrank(GENESIS_ADDR);
        dkgContract.initialize();
        vm.stopPrank();

        vm.startPrank(SYSTEM_CALLER);

        IRandomnessConfig.RandomnessConfigData memory randomnessConfig = _createTestRandomnessConfig();
        IDKG.ValidatorConsensusInfo[] memory validators = _createTestValidators();

        dkgContract.start(TEST_DEALER_EPOCH, randomnessConfig, validators, validators);

        // Act & Assert
        vm.expectRevert(IDKG.DKGInProgress.selector);
        dkgContract.start(TEST_DEALER_EPOCH + 1, randomnessConfig, validators, validators);
    }

    function test_start_shouldRevertIfNotAuthorized() public {
        // Arrange
        vm.startPrank(GENESIS_ADDR);
        dkgContract.initialize();
        vm.stopPrank();

        vm.startPrank(address(0x123));

        IRandomnessConfig.RandomnessConfigData memory randomnessConfig = _createTestRandomnessConfig();
        IDKG.ValidatorConsensusInfo[] memory validators = _createTestValidators();

        // Act & Assert
        vm.expectRevert(abi.encodeWithSelector(IDKG.NotAuthorized.selector, address(0x123)));
        dkgContract.start(TEST_DEALER_EPOCH, randomnessConfig, validators, validators);
    }

    function test_finish_shouldSucceed() public {
        // Arrange
        vm.startPrank(GENESIS_ADDR);
        dkgContract.initialize();
        vm.stopPrank();

        vm.startPrank(SYSTEM_CALLER);

        IRandomnessConfig.RandomnessConfigData memory randomnessConfig = _createTestRandomnessConfig();
        IDKG.ValidatorConsensusInfo[] memory validators = _createTestValidators();

        dkgContract.start(TEST_DEALER_EPOCH, randomnessConfig, validators, validators);

        // Act
        dkgContract.finish(TEST_TRANSCRIPT);

        // Assert
        assertFalse(dkgContract.isDKGInProgress());
        (bool hasLastCompleted, IDKG.DKGSessionState memory lastSession) = dkgContract.lastCompletedSession();
        assertTrue(hasLastCompleted);
        assertEq(lastSession.metadata.dealerEpoch, TEST_DEALER_EPOCH);
        assertEq(lastSession.transcript, TEST_TRANSCRIPT);
    }

    function test_finish_shouldRevertIfDKGNotInProgress() public {
        // Arrange
        vm.startPrank(GENESIS_ADDR);
        dkgContract.initialize();
        vm.stopPrank();

        vm.startPrank(SYSTEM_CALLER);

        // Act & Assert
        vm.expectRevert(IDKG.DKGNotInProgress.selector);
        dkgContract.finish(TEST_TRANSCRIPT);
    }

    function test_tryClearIncompleteSession_shouldSucceed() public {
        // Arrange
        vm.startPrank(GENESIS_ADDR);
        dkgContract.initialize();
        vm.stopPrank();

        vm.startPrank(SYSTEM_CALLER);

        IRandomnessConfig.RandomnessConfigData memory randomnessConfig = _createTestRandomnessConfig();
        IDKG.ValidatorConsensusInfo[] memory validators = _createTestValidators();

        dkgContract.start(TEST_DEALER_EPOCH, randomnessConfig, validators, validators);

        // Act
        dkgContract.tryClearIncompleteSession();

        // Assert
        assertFalse(dkgContract.isDKGInProgress());
        (bool hasIncomplete,) = dkgContract.incompleteSession();
        assertFalse(hasIncomplete);
    }

    function test_tryClearIncompleteSession_shouldDoNothingIfNoSession() public {
        // Arrange
        vm.startPrank(GENESIS_ADDR);
        dkgContract.initialize();
        vm.stopPrank();

        vm.startPrank(SYSTEM_CALLER);

        // Act
        dkgContract.tryClearIncompleteSession();

        // Assert
        assertFalse(dkgContract.isDKGInProgress());
    }

    function test_sessionDealerEpoch_shouldReturnCorrectEpoch() public {
        // Arrange
        IDKG.DKGSessionState memory session = IDKG.DKGSessionState({
            metadata: IDKG.DKGSessionMetadata({
                dealerEpoch: TEST_DEALER_EPOCH,
                randomnessConfig: _createTestRandomnessConfig(),
                dealerValidatorSet: new IDKG.ValidatorConsensusInfo[](0),
                targetValidatorSet: new IDKG.ValidatorConsensusInfo[](0)
            }),
            startTimeUs: TEST_START_TIME,
            transcript: ""
        });

        // Act
        uint64 epoch = dkgContract.sessionDealerEpoch(session);

        // Assert
        assertEq(epoch, TEST_DEALER_EPOCH);
    }

    function _createTestRandomnessConfig() internal pure returns (IRandomnessConfig.RandomnessConfigData memory) {
        return IRandomnessConfig.RandomnessConfigData({
            variant: IRandomnessConfig.ConfigVariant.V2,
            configV1: IRandomnessConfig.ConfigV1({
                secrecyThreshold: IDKG.FixedPoint64({ value: 0 }),
                reconstructionThreshold: IDKG.FixedPoint64({ value: 0 })
            }),
            configV2: IRandomnessConfig.ConfigV2({
                secrecyThreshold: IDKG.FixedPoint64({ value: 100 }),
                reconstructionThreshold: IDKG.FixedPoint64({ value: 200 }),
                fastPathSecrecyThreshold: IDKG.FixedPoint64({ value: 50 })
            })
        });
    }

    function _createTestValidators() internal pure returns (IDKG.ValidatorConsensusInfo[] memory) {
        IDKG.ValidatorConsensusInfo[] memory validators = new IDKG.ValidatorConsensusInfo[](2);
        validators[0] = IDKG.ValidatorConsensusInfo({
            aptosAddress: abi.encodePacked(address(0x1)), pkBytes: "validator1_pk", votingPower: 100
        });
        validators[1] = IDKG.ValidatorConsensusInfo({
            aptosAddress: abi.encodePacked(address(0x2)), pkBytes: "validator2_pk", votingPower: 200
        });
        return validators;
    }
}
