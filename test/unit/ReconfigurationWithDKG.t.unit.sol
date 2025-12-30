// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import "forge-std/Test.sol";
import "@src/dkg/ReconfigurationWithDKG.sol";
import "@src/dkg/RandomnessConfig.sol";
import "@test/mocks/DKGMock.sol";
import "@test/mocks/EpochManagerMock.sol";
import "@test/mocks/ValidatorManagerMock.sol";
import "@src/interfaces/IReconfigurationWithDKG.sol";
import "@src/interfaces/IDKG.sol";
import "@test/utils/TestConstants.sol";

contract ReconfigurationWithDKGTest is Test, TestConstants {
    // DKG address constant (copied from System.sol to avoid inheritance conflicts)
    ReconfigurationWithDKG reconfigContract;
    DKGMock dkgMock;
    EpochManagerMock epochManagerMock;
    ValidatorManagerMock validatorManagerMock;
    RandomnessConfig randomnessConfig;

    // Test data
    uint256 constant TEST_CURRENT_EPOCH = 5;
    uint64 constant TEST_DEALER_EPOCH = 5;
    bytes constant TEST_DKG_RESULT = "test_dkg_result";

    function setUp() public {
        // Deploy mock contracts
        dkgMock = new DKGMock();
        epochManagerMock = new EpochManagerMock();
        validatorManagerMock = new ValidatorManagerMock();
        randomnessConfig = new RandomnessConfig();

        // Deploy ReconfigurationWithDKG contract
        reconfigContract = new ReconfigurationWithDKG();

        // Deploy contracts to system addresses
        vm.etch(DKG_ADDR, address(dkgMock).code);
        vm.etch(EPOCH_MANAGER_ADDR, address(epochManagerMock).code);
        vm.etch(VALIDATOR_MANAGER_ADDR, address(validatorManagerMock).code);
        vm.etch(RANDOMNESS_CONFIG_ADDR, address(randomnessConfig).code);
        vm.etch(RECONFIGURATION_WITH_DKG_ADDR, address(reconfigContract).code);

        // Set up mock data
        DKGMock(DKG_ADDR).initialize();
        EpochManagerMock(EPOCH_MANAGER_ADDR).setCanTriggerEpochTransition(true);

        // Initialize RandomnessConfig
        vm.prank(GENESIS_ADDR);
        RandomnessConfig(RANDOMNESS_CONFIG_ADDR)
            .initialize(
                IRandomnessConfig.RandomnessConfigData({
                    variant: IRandomnessConfig.ConfigVariant.V1,
                    configV1: IRandomnessConfig.ConfigV1({
                        secrecyThreshold: IDKG.FixedPoint64({ value: 5001 }),
                        reconstructionThreshold: IDKG.FixedPoint64({ value: 6667 })
                    }),
                    configV2: IRandomnessConfig.ConfigV2({
                        secrecyThreshold: IDKG.FixedPoint64({ value: 0 }),
                        reconstructionThreshold: IDKG.FixedPoint64({ value: 0 }),
                        fastPathSecrecyThreshold: IDKG.FixedPoint64({ value: 0 })
                    })
                })
            );
    }

    function test_initialize_shouldSucceed() public {
        // Arrange
        vm.startPrank(GENESIS_ADDR);

        // Act
        ReconfigurationWithDKG(RECONFIGURATION_WITH_DKG_ADDR).initialize();

        // Assert - Contract should be initialized (no specific state to check)
        assertTrue(true);
    }

    function test_initialize_shouldRevertIfNotGenesis() public {
        // Arrange
        vm.startPrank(address(0x123));

        // Act & Assert
        vm.expectRevert();
        ReconfigurationWithDKG(RECONFIGURATION_WITH_DKG_ADDR).initialize();
    }

    function test_tryStart_shouldSucceedWhenNoDKGInProgress() public {
        // Arrange
        vm.startPrank(GENESIS_ADDR);
        ReconfigurationWithDKG(RECONFIGURATION_WITH_DKG_ADDR).initialize();
        vm.stopPrank();

        // Setup validators
        _setupTestValidators();

        vm.startPrank(SYSTEM_CALLER);

        // Act
        ReconfigurationWithDKG(RECONFIGURATION_WITH_DKG_ADDR).tryStart();

        // Assert
        assertTrue(DKGMock(DKG_ADDR).isDKGInProgress());
    }

    function test_tryStart_shouldReturnEarlyIfSameEpochDKGInProgress() public {
        // Arrange
        vm.startPrank(GENESIS_ADDR);
        ReconfigurationWithDKG(RECONFIGURATION_WITH_DKG_ADDR).initialize();
        vm.stopPrank();

        // Set up incomplete DKG session for same epoch
        IDKG.DKGSessionState memory incompleteSession = _createTestDKGSession(TEST_DEALER_EPOCH);
        DKGMock(DKG_ADDR).setInProgressSession(incompleteSession);

        vm.startPrank(SYSTEM_CALLER);

        // Act
        ReconfigurationWithDKG(RECONFIGURATION_WITH_DKG_ADDR).tryStart();

        // Assert - Should return early without emitting event or starting new DKG
        assertTrue(DKGMock(DKG_ADDR).isDKGInProgress());
    }

    function test_tryStart_shouldStartNewDKGIfDifferentEpoch() public {
        // Arrange
        vm.startPrank(GENESIS_ADDR);
        ReconfigurationWithDKG(RECONFIGURATION_WITH_DKG_ADDR).initialize();
        vm.stopPrank();

        // Setup validators
        _setupTestValidators();

        // Set up incomplete DKG session for different epoch
        IDKG.DKGSessionState memory incompleteSession = _createTestDKGSession(TEST_DEALER_EPOCH - 1);
        DKGMock(DKG_ADDR).setInProgressSession(incompleteSession);

        vm.startPrank(SYSTEM_CALLER);

        // Act
        ReconfigurationWithDKG(RECONFIGURATION_WITH_DKG_ADDR).tryStart();

        // Assert - DKG should still be in progress (new session started)
        assertTrue(DKGMock(DKG_ADDR).isDKGInProgress());
    }

    function test_tryStart_shouldRevertIfNotAuthorized() public {
        // Arrange
        vm.startPrank(GENESIS_ADDR);
        ReconfigurationWithDKG(RECONFIGURATION_WITH_DKG_ADDR).initialize();
        vm.stopPrank();

        vm.startPrank(address(0x123));

        // Act & Assert
        vm.expectRevert(abi.encodeWithSelector(IReconfigurationWithDKG.NotAuthorized.selector, address(0x123)));
        ReconfigurationWithDKG(RECONFIGURATION_WITH_DKG_ADDR).tryStart();
    }

    function test_finish_shouldSucceed() public {
        // Arrange
        vm.startPrank(GENESIS_ADDR);
        ReconfigurationWithDKG(RECONFIGURATION_WITH_DKG_ADDR).initialize();
        vm.stopPrank();

        vm.startPrank(SYSTEM_CALLER);

        // Act
        ReconfigurationWithDKG(RECONFIGURATION_WITH_DKG_ADDR).finish();
    }

    function test_finish_shouldRevertIfNotAuthorized() public {
        // Arrange
        vm.startPrank(GENESIS_ADDR);
        ReconfigurationWithDKG(RECONFIGURATION_WITH_DKG_ADDR).initialize();
        vm.stopPrank();

        vm.startPrank(address(0x123));

        // Act & Assert
        vm.expectRevert(abi.encodeWithSelector(IReconfigurationWithDKG.NotAuthorized.selector, address(0x123)));
        ReconfigurationWithDKG(RECONFIGURATION_WITH_DKG_ADDR).finish();
    }

    function test_finishWithDkgResult_shouldSucceed() public {
        // Arrange
        vm.startPrank(GENESIS_ADDR);
        ReconfigurationWithDKG(RECONFIGURATION_WITH_DKG_ADDR).initialize();
        vm.stopPrank();

        // Set up DKG in progress
        IDKG.DKGSessionState memory inProgressSession = _createTestDKGSession(TEST_DEALER_EPOCH);
        DKGMock(DKG_ADDR).setInProgressSession(inProgressSession);

        vm.startPrank(SYSTEM_CALLER);

        // Act
        ReconfigurationWithDKG(RECONFIGURATION_WITH_DKG_ADDR).finishWithDkgResult(TEST_DKG_RESULT);

        // Assert - DKG should no longer be in progress
        assertFalse(DKGMock(DKG_ADDR).isDKGInProgress());
    }

    function test_finishWithDkgResult_shouldRevertIfNotAuthorized() public {
        // Arrange
        vm.startPrank(GENESIS_ADDR);
        ReconfigurationWithDKG(RECONFIGURATION_WITH_DKG_ADDR).initialize();
        vm.stopPrank();

        vm.startPrank(address(0x123));

        // Act & Assert
        vm.expectRevert(abi.encodeWithSelector(IReconfigurationWithDKG.NotAuthorized.selector, address(0x123)));
        ReconfigurationWithDKG(RECONFIGURATION_WITH_DKG_ADDR).finishWithDkgResult(TEST_DKG_RESULT);
    }

    function test_isReconfigurationInProgress_shouldReturnCorrectStatus() public {
        // Arrange
        vm.startPrank(GENESIS_ADDR);
        ReconfigurationWithDKG(RECONFIGURATION_WITH_DKG_ADDR).initialize();
        vm.stopPrank();

        // Initially should not be in progress
        assertFalse(ReconfigurationWithDKG(RECONFIGURATION_WITH_DKG_ADDR).isReconfigurationInProgress());

        // Set DKG in progress
        IDKG.DKGSessionState memory inProgressSession = _createTestDKGSession(TEST_DEALER_EPOCH);
        DKGMock(DKG_ADDR).setInProgressSession(inProgressSession);

        // Should now be in progress
        assertTrue(ReconfigurationWithDKG(RECONFIGURATION_WITH_DKG_ADDR).isReconfigurationInProgress());
    }

    function test_getCurrentValidatorConsensusInfos_shouldReturnActiveValidators() public {
        // Arrange
        vm.startPrank(GENESIS_ADDR);
        ReconfigurationWithDKG(RECONFIGURATION_WITH_DKG_ADDR).initialize();
        vm.stopPrank();

        // Setup validators
        _setupTestValidators();

        vm.startPrank(SYSTEM_CALLER);

        // Act
        ReconfigurationWithDKG(RECONFIGURATION_WITH_DKG_ADDR).tryStart();

        // The function should have been called internally, we can't directly test the internal function
        // but we can verify that DKG was started which means the function worked
        assertTrue(DKGMock(DKG_ADDR).isDKGInProgress());
    }

    function _setupTestValidators() internal {
        address[] memory activeValidators = new address[](2);
        activeValidators[0] = address(0x100);
        activeValidators[1] = address(0x200);
        ValidatorManagerMock(VALIDATOR_MANAGER_ADDR).setActiveValidators(activeValidators);

        IValidatorManager.ValidatorInfo memory validator1Info = IValidatorManager.ValidatorInfo({
            consensusPublicKey: abi.encodePacked("validator1_pubkey"),
            commission: IValidatorManager.Commission({ rate: 1000, maxRate: 10000, maxChangeRate: 100 }),
            moniker: "Validator 1",
            registered: true,
            stakeCreditAddress: address(0x1001),
            status: IValidatorManager.ValidatorStatus.ACTIVE,
            votingPower: 1000,
            validatorIndex: 0,
            updateTime: block.timestamp,
            operator: address(0x100),
            validatorNetworkAddresses: abi.encodePacked("validator1_net"),
            fullnodeNetworkAddresses: abi.encodePacked("validator1_fullnode"),
            aptosAddress: abi.encodePacked("validator1_aptos")
        });

        IValidatorManager.ValidatorInfo memory validator2Info = IValidatorManager.ValidatorInfo({
            consensusPublicKey: abi.encodePacked("validator2_pubkey"),
            commission: IValidatorManager.Commission({ rate: 1500, maxRate: 10000, maxChangeRate: 100 }),
            moniker: "Validator 2",
            registered: true,
            stakeCreditAddress: address(0x2001),
            status: IValidatorManager.ValidatorStatus.ACTIVE,
            votingPower: 2000,
            validatorIndex: 1,
            updateTime: block.timestamp,
            operator: address(0x200),
            validatorNetworkAddresses: abi.encodePacked("validator2_net"),
            fullnodeNetworkAddresses: abi.encodePacked("validator2_fullnode"),
            aptosAddress: abi.encodePacked("validator2_aptos")
        });

        ValidatorManagerMock(VALIDATOR_MANAGER_ADDR).setValidatorInfo(address(0x100), validator1Info);
        ValidatorManagerMock(VALIDATOR_MANAGER_ADDR).setValidatorInfo(address(0x200), validator2Info);
    }

    function _createTestDKGSession(
        uint64 dealerEpoch
    ) internal view returns (IDKG.DKGSessionState memory) {
        return IDKG.DKGSessionState({
            metadata: IDKG.DKGSessionMetadata({
                dealerEpoch: dealerEpoch,
                randomnessConfig: IRandomnessConfig.RandomnessConfigData({
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
                }),
                dealerValidatorSet: new IDKG.ValidatorConsensusInfo[](0),
                targetValidatorSet: new IDKG.ValidatorConsensusInfo[](0)
            }),
            startTimeUs: uint64(block.timestamp * 1000000),
            transcript: ""
        });
    }
}
