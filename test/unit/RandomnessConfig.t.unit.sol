// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import "forge-std/Test.sol";
import "@src/dkg/RandomnessConfig.sol";
import "@src/interfaces/IRandomnessConfig.sol";
import "@src/interfaces/IDKG.sol";
import "@test/utils/TestConstants.sol";

contract RandomnessConfigTest is Test, TestConstants {
    RandomnessConfig internal randomnessConfigContract;

    // Test constants
    uint128 internal constant SECRECY_THRESHOLD = 100;
    uint128 internal constant RECONSTRUCTION_THRESHOLD = 200;
    uint128 internal constant FAST_PATH_SECRECY_THRESHOLD = 150;

    function setUp() public {
        // Deploy RandomnessConfig contract
        randomnessConfigContract = new RandomnessConfig();
    }

    function test_initialize_shouldSucceedWithConfigV1() public {
        // Arrange
        vm.startPrank(GENESIS_ADDR);
        IRandomnessConfig.RandomnessConfigData memory config = randomnessConfigContract.newV1(
            IDKG.FixedPoint64({ value: SECRECY_THRESHOLD }), IDKG.FixedPoint64({ value: RECONSTRUCTION_THRESHOLD })
        );

        // Act
        randomnessConfigContract.initialize(config);

        // Assert
        assertTrue(randomnessConfigContract.isInitialized());
        assertTrue(randomnessConfigContract.enabled());

        IRandomnessConfig.RandomnessConfigData memory currentConfig = randomnessConfigContract.current();
        assertEq(uint256(currentConfig.variant), uint256(IRandomnessConfig.ConfigVariant.V1));
        assertEq(currentConfig.configV1.secrecyThreshold.value, SECRECY_THRESHOLD);
        assertEq(currentConfig.configV1.reconstructionThreshold.value, RECONSTRUCTION_THRESHOLD);
    }

    function test_initialize_shouldSucceedWithConfigV2() public {
        // Arrange
        vm.startPrank(GENESIS_ADDR);
        IRandomnessConfig.RandomnessConfigData memory config = randomnessConfigContract.newV2(
            IDKG.FixedPoint64({ value: SECRECY_THRESHOLD }),
            IDKG.FixedPoint64({ value: RECONSTRUCTION_THRESHOLD }),
            IDKG.FixedPoint64({ value: FAST_PATH_SECRECY_THRESHOLD })
        );

        // Act
        randomnessConfigContract.initialize(config);

        // Assert
        assertTrue(randomnessConfigContract.isInitialized());
        assertTrue(randomnessConfigContract.enabled());

        IRandomnessConfig.RandomnessConfigData memory currentConfig = randomnessConfigContract.current();
        assertEq(uint256(currentConfig.variant), uint256(IRandomnessConfig.ConfigVariant.V2));
        assertEq(currentConfig.configV2.secrecyThreshold.value, SECRECY_THRESHOLD);
        assertEq(currentConfig.configV2.reconstructionThreshold.value, RECONSTRUCTION_THRESHOLD);
        assertEq(currentConfig.configV2.fastPathSecrecyThreshold.value, FAST_PATH_SECRECY_THRESHOLD);
    }

    function test_initialize_shouldRevertIfNotGenesis() public {
        // Arrange
        vm.startPrank(address(0x123));
        IRandomnessConfig.RandomnessConfigData memory config = randomnessConfigContract.newV1(
            IDKG.FixedPoint64({ value: SECRECY_THRESHOLD }), IDKG.FixedPoint64({ value: RECONSTRUCTION_THRESHOLD })
        );

        // Act & Assert
        vm.expectRevert();
        randomnessConfigContract.initialize(config);
    }

    function test_initialize_shouldRevertIfAlreadyInitialized() public {
        // Arrange
        vm.startPrank(GENESIS_ADDR);
        IRandomnessConfig.RandomnessConfigData memory config = randomnessConfigContract.newV1(
            IDKG.FixedPoint64({ value: SECRECY_THRESHOLD }), IDKG.FixedPoint64({ value: RECONSTRUCTION_THRESHOLD })
        );
        randomnessConfigContract.initialize(config);

        // Act & Assert
        vm.expectRevert(IRandomnessConfig.AlreadyInitialized.selector);
        randomnessConfigContract.initialize(config);
    }

    function test_initialize_shouldRevertWithInvalidV1Config() public {
        // Arrange - reconstruction threshold <= secrecy threshold
        vm.startPrank(GENESIS_ADDR);
        IRandomnessConfig.RandomnessConfigData memory config = randomnessConfigContract.newV1(
            IDKG.FixedPoint64({ value: RECONSTRUCTION_THRESHOLD }), // Higher secrecy
            IDKG.FixedPoint64({ value: SECRECY_THRESHOLD }) // Lower reconstruction
        );

        // Act & Assert
        vm.expectRevert(IRandomnessConfig.InvalidConfigVariant.selector);
        randomnessConfigContract.initialize(config);
    }

    function test_initialize_shouldRevertWithInvalidV2Config() public {
        // Arrange - fast path secrecy threshold <= secrecy threshold (invalid)
        vm.startPrank(GENESIS_ADDR);
        IRandomnessConfig.RandomnessConfigData memory config = randomnessConfigContract.newV2(
            IDKG.FixedPoint64({ value: SECRECY_THRESHOLD }),
            IDKG.FixedPoint64({ value: RECONSTRUCTION_THRESHOLD }),
            IDKG.FixedPoint64({ value: SECRECY_THRESHOLD }) // Invalid: fast path <= secrecy
        );

        // Act & Assert
        vm.expectRevert(IRandomnessConfig.InvalidConfigVariant.selector);
        randomnessConfigContract.initialize(config);
    }

    function test_setForNextEpoch_shouldSucceed() public {
        // Arrange
        vm.startPrank(GENESIS_ADDR);
        IRandomnessConfig.RandomnessConfigData memory initialConfig = randomnessConfigContract.newV1(
            IDKG.FixedPoint64({ value: SECRECY_THRESHOLD }), IDKG.FixedPoint64({ value: RECONSTRUCTION_THRESHOLD })
        );
        randomnessConfigContract.initialize(initialConfig);
        vm.stopPrank();

        vm.startPrank(SYSTEM_CALLER);
        IRandomnessConfig.RandomnessConfigData memory newConfig = randomnessConfigContract.newV1(
            IDKG.FixedPoint64({ value: SECRECY_THRESHOLD }), IDKG.FixedPoint64({ value: RECONSTRUCTION_THRESHOLD })
        );

        // Act
        randomnessConfigContract.setForNextEpoch(newConfig);

        // Assert
        (bool hasPending, IRandomnessConfig.RandomnessConfigData memory pendingConfig) =
            randomnessConfigContract.pending();
        assertTrue(hasPending);
        assertEq(uint256(pendingConfig.variant), uint256(IRandomnessConfig.ConfigVariant.V1));
    }

    function test_setForNextEpoch_shouldRevertIfNotAuthorized() public {
        // Arrange
        vm.startPrank(GENESIS_ADDR);
        IRandomnessConfig.RandomnessConfigData memory initialConfig = randomnessConfigContract.newV1(
            IDKG.FixedPoint64({ value: SECRECY_THRESHOLD }), IDKG.FixedPoint64({ value: RECONSTRUCTION_THRESHOLD })
        );
        randomnessConfigContract.initialize(initialConfig);
        vm.stopPrank();

        vm.startPrank(address(0x123));
        IRandomnessConfig.RandomnessConfigData memory newConfig = randomnessConfigContract.newV1(
            IDKG.FixedPoint64({ value: SECRECY_THRESHOLD }), IDKG.FixedPoint64({ value: RECONSTRUCTION_THRESHOLD })
        );

        // Act & Assert
        vm.expectRevert(abi.encodeWithSelector(IRandomnessConfig.NotAuthorized.selector, address(0x123)));
        randomnessConfigContract.setForNextEpoch(newConfig);
    }

    function test_setForNextEpoch_shouldRevertIfNotInitialized() public {
        // Arrange
        vm.startPrank(SYSTEM_CALLER);
        IRandomnessConfig.RandomnessConfigData memory newConfig = randomnessConfigContract.newV1(
            IDKG.FixedPoint64({ value: SECRECY_THRESHOLD }), IDKG.FixedPoint64({ value: RECONSTRUCTION_THRESHOLD })
        );

        // Act & Assert
        vm.expectRevert(IRandomnessConfig.NotInitialized.selector);
        randomnessConfigContract.setForNextEpoch(newConfig);
    }

    function test_onNewEpoch_shouldApplyPendingConfig() public {
        // Arrange
        vm.startPrank(GENESIS_ADDR);
        IRandomnessConfig.RandomnessConfigData memory initialConfig = randomnessConfigContract.newV1(
            IDKG.FixedPoint64({ value: SECRECY_THRESHOLD }), IDKG.FixedPoint64({ value: RECONSTRUCTION_THRESHOLD })
        );
        randomnessConfigContract.initialize(initialConfig);
        vm.stopPrank();

        vm.startPrank(SYSTEM_CALLER);
        IRandomnessConfig.RandomnessConfigData memory newConfig = randomnessConfigContract.newV1(
            IDKG.FixedPoint64({ value: SECRECY_THRESHOLD }), IDKG.FixedPoint64({ value: RECONSTRUCTION_THRESHOLD })
        );
        randomnessConfigContract.setForNextEpoch(newConfig);

        // Act
        randomnessConfigContract.onNewEpoch();

        // Assert
        assertTrue(randomnessConfigContract.enabled());
        IRandomnessConfig.RandomnessConfigData memory currentConfig = randomnessConfigContract.current();
        assertEq(uint256(currentConfig.variant), uint256(IRandomnessConfig.ConfigVariant.V1));

        (bool hasPending,) = randomnessConfigContract.pending();
        assertFalse(hasPending);
    }

    function test_onNewEpoch_shouldDoNothingIfNoPendingConfig() public {
        // Arrange
        vm.startPrank(GENESIS_ADDR);
        IRandomnessConfig.RandomnessConfigData memory initialConfig = randomnessConfigContract.newV1(
            IDKG.FixedPoint64({ value: SECRECY_THRESHOLD }), IDKG.FixedPoint64({ value: RECONSTRUCTION_THRESHOLD })
        );
        randomnessConfigContract.initialize(initialConfig);
        vm.stopPrank();

        vm.startPrank(SYSTEM_CALLER);

        // Act
        randomnessConfigContract.onNewEpoch();

        // Assert
        assertTrue(randomnessConfigContract.enabled());
        IRandomnessConfig.RandomnessConfigData memory currentConfig = randomnessConfigContract.current();
        assertEq(uint256(currentConfig.variant), uint256(IRandomnessConfig.ConfigVariant.V1));
    }

    function test_enabled_shouldReturnCorrectValue() public {
        // Test ConfigV1
        vm.startPrank(GENESIS_ADDR);
        IRandomnessConfig.RandomnessConfigData memory configV1 = randomnessConfigContract.newV1(
            IDKG.FixedPoint64({ value: SECRECY_THRESHOLD }), IDKG.FixedPoint64({ value: RECONSTRUCTION_THRESHOLD })
        );
        randomnessConfigContract.initialize(configV1);
        assertTrue(randomnessConfigContract.enabled());

        // Test ConfigV2
        vm.startPrank(SYSTEM_CALLER);
        IRandomnessConfig.RandomnessConfigData memory configV2 = randomnessConfigContract.newV2(
            IDKG.FixedPoint64({ value: SECRECY_THRESHOLD }),
            IDKG.FixedPoint64({ value: RECONSTRUCTION_THRESHOLD }),
            IDKG.FixedPoint64({ value: FAST_PATH_SECRECY_THRESHOLD })
        );
        randomnessConfigContract.setForNextEpoch(configV2);
        randomnessConfigContract.onNewEpoch();
        assertTrue(randomnessConfigContract.enabled());
    }

    function test_toIDKGConfig_shouldConvertCorrectly() public {
        // Test ConfigV1
        IRandomnessConfig.RandomnessConfigData memory configV1 = randomnessConfigContract.newV1(
            IDKG.FixedPoint64({ value: SECRECY_THRESHOLD }), IDKG.FixedPoint64({ value: RECONSTRUCTION_THRESHOLD })
        );
        IDKG.Config memory idkgConfigV1 = randomnessConfigContract.toIDKGConfig(configV1);
        assertEq(idkgConfigV1.secrecyThreshold.value, SECRECY_THRESHOLD);
        assertEq(idkgConfigV1.reconstructionThreshold.value, RECONSTRUCTION_THRESHOLD);
        assertEq(idkgConfigV1.fastPathSecrecyThreshold.value, 0);

        // Test ConfigV2
        IRandomnessConfig.RandomnessConfigData memory configV2 = randomnessConfigContract.newV2(
            IDKG.FixedPoint64({ value: SECRECY_THRESHOLD }),
            IDKG.FixedPoint64({ value: RECONSTRUCTION_THRESHOLD }),
            IDKG.FixedPoint64({ value: FAST_PATH_SECRECY_THRESHOLD })
        );
        IDKG.Config memory idkgConfigV2 = randomnessConfigContract.toIDKGConfig(configV2);
        assertEq(idkgConfigV2.secrecyThreshold.value, SECRECY_THRESHOLD);
        assertEq(idkgConfigV2.reconstructionThreshold.value, RECONSTRUCTION_THRESHOLD);
        assertEq(idkgConfigV2.fastPathSecrecyThreshold.value, FAST_PATH_SECRECY_THRESHOLD);
    }

    function test_getVariantName_shouldReturnCorrectNames() public {
        // Test ConfigV1
        IRandomnessConfig.RandomnessConfigData memory configV1 = randomnessConfigContract.newV1(
            IDKG.FixedPoint64({ value: SECRECY_THRESHOLD }), IDKG.FixedPoint64({ value: RECONSTRUCTION_THRESHOLD })
        );
        string memory nameV1 = randomnessConfigContract.getVariantName(configV1);
        assertEq(nameV1, "ConfigV1");

        // Test ConfigV2
        IRandomnessConfig.RandomnessConfigData memory configV2 = randomnessConfigContract.newV2(
            IDKG.FixedPoint64({ value: SECRECY_THRESHOLD }),
            IDKG.FixedPoint64({ value: RECONSTRUCTION_THRESHOLD }),
            IDKG.FixedPoint64({ value: FAST_PATH_SECRECY_THRESHOLD })
        );
        string memory nameV2 = randomnessConfigContract.getVariantName(configV2);
        assertEq(nameV2, "ConfigV2");
    }

    function test_current_shouldReturnCurrentConfig() public {
        // Arrange
        vm.startPrank(GENESIS_ADDR);
        IRandomnessConfig.RandomnessConfigData memory config = randomnessConfigContract.newV1(
            IDKG.FixedPoint64({ value: SECRECY_THRESHOLD }), IDKG.FixedPoint64({ value: RECONSTRUCTION_THRESHOLD })
        );
        randomnessConfigContract.initialize(config);

        // Act
        IRandomnessConfig.RandomnessConfigData memory currentConfig = randomnessConfigContract.current();

        // Assert
        assertEq(uint256(currentConfig.variant), uint256(IRandomnessConfig.ConfigVariant.V1));
        assertEq(currentConfig.configV1.secrecyThreshold.value, SECRECY_THRESHOLD);
        assertEq(currentConfig.configV1.reconstructionThreshold.value, RECONSTRUCTION_THRESHOLD);
    }

    function test_pending_shouldReturnPendingConfig() public {
        // Arrange
        vm.startPrank(GENESIS_ADDR);
        IRandomnessConfig.RandomnessConfigData memory initialConfig = randomnessConfigContract.newV1(
            IDKG.FixedPoint64({ value: SECRECY_THRESHOLD }), IDKG.FixedPoint64({ value: RECONSTRUCTION_THRESHOLD })
        );
        randomnessConfigContract.initialize(initialConfig);
        vm.stopPrank();

        vm.startPrank(SYSTEM_CALLER);
        IRandomnessConfig.RandomnessConfigData memory pendingConfig = randomnessConfigContract.newV1(
            IDKG.FixedPoint64({ value: SECRECY_THRESHOLD }), IDKG.FixedPoint64({ value: RECONSTRUCTION_THRESHOLD })
        );
        randomnessConfigContract.setForNextEpoch(pendingConfig);

        // Act
        (bool hasPending, IRandomnessConfig.RandomnessConfigData memory config) = randomnessConfigContract.pending();

        // Assert
        assertTrue(hasPending);
        assertEq(uint256(config.variant), uint256(IRandomnessConfig.ConfigVariant.V1));
        assertEq(config.configV1.secrecyThreshold.value, SECRECY_THRESHOLD);
        assertEq(config.configV1.reconstructionThreshold.value, RECONSTRUCTION_THRESHOLD);
    }

    function test_pending_shouldReturnFalseIfNoPending() public {
        // Arrange
        vm.startPrank(GENESIS_ADDR);
        IRandomnessConfig.RandomnessConfigData memory config = randomnessConfigContract.newV1(
            IDKG.FixedPoint64({ value: SECRECY_THRESHOLD }), IDKG.FixedPoint64({ value: RECONSTRUCTION_THRESHOLD })
        );
        randomnessConfigContract.initialize(config);

        // Act
        (bool hasPending,) = randomnessConfigContract.pending();

        // Assert
        assertFalse(hasPending);
    }

    function test_isInitialized_shouldReturnCorrectValue() public {
        // Before initialization
        assertFalse(randomnessConfigContract.isInitialized());

        // After initialization
        vm.startPrank(GENESIS_ADDR);
        IRandomnessConfig.RandomnessConfigData memory config = randomnessConfigContract.newV1(
            IDKG.FixedPoint64({ value: SECRECY_THRESHOLD }), IDKG.FixedPoint64({ value: RECONSTRUCTION_THRESHOLD })
        );
        randomnessConfigContract.initialize(config);
        assertTrue(randomnessConfigContract.isInitialized());
    }

    function test_fullWorkflow_shouldWork() public {
        // 1. Initialize with ConfigV1
        vm.startPrank(GENESIS_ADDR);
        IRandomnessConfig.RandomnessConfigData memory configV1 = randomnessConfigContract.newV1(
            IDKG.FixedPoint64({ value: SECRECY_THRESHOLD }), IDKG.FixedPoint64({ value: RECONSTRUCTION_THRESHOLD })
        );
        randomnessConfigContract.initialize(configV1);
        assertTrue(randomnessConfigContract.enabled());
        vm.stopPrank();

        // 2. Set V2 config for next epoch
        vm.startPrank(SYSTEM_CALLER);
        IRandomnessConfig.RandomnessConfigData memory configV2First = randomnessConfigContract.newV2(
            IDKG.FixedPoint64({ value: SECRECY_THRESHOLD + 10 }),
            IDKG.FixedPoint64({ value: RECONSTRUCTION_THRESHOLD + 10 }),
            IDKG.FixedPoint64({ value: FAST_PATH_SECRECY_THRESHOLD })
        );
        randomnessConfigContract.setForNextEpoch(configV2First);

        // Still enabled with old config
        assertTrue(randomnessConfigContract.enabled());

        // 3. Apply new epoch
        randomnessConfigContract.onNewEpoch();
        assertTrue(randomnessConfigContract.enabled());

        // 4. Set V2 config for next epoch
        IRandomnessConfig.RandomnessConfigData memory configV2 = randomnessConfigContract.newV2(
            IDKG.FixedPoint64({ value: SECRECY_THRESHOLD }),
            IDKG.FixedPoint64({ value: RECONSTRUCTION_THRESHOLD }),
            IDKG.FixedPoint64({ value: FAST_PATH_SECRECY_THRESHOLD })
        );
        randomnessConfigContract.setForNextEpoch(configV2);

        // 5. Apply new epoch again
        randomnessConfigContract.onNewEpoch();
        assertTrue(randomnessConfigContract.enabled());

        IRandomnessConfig.RandomnessConfigData memory currentConfig = randomnessConfigContract.current();
        assertEq(uint256(currentConfig.variant), uint256(IRandomnessConfig.ConfigVariant.V2));
        assertEq(currentConfig.configV2.fastPathSecrecyThreshold.value, FAST_PATH_SECRECY_THRESHOLD);
    }
}
