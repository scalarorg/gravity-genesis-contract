// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import "@src/System.sol";
import "@src/access/Protectable.sol";
import "@src/interfaces/IRandomnessConfig.sol";

/**
 * @title RandomnessConfig
 * @dev Structs and functions for on-chain randomness configurations
 * @notice This contract manages randomness configuration for the DKG system
 */
contract RandomnessConfig is System, Protectable, IRandomnessConfig {
    // State variables
    RandomnessConfigData private _currentConfig;
    RandomnessConfigData private _pendingConfig;
    bool private _hasPendingConfig;
    bool private _initialized;

    // Modifiers
    modifier onlyInitialized() {
        if (!_initialized) revert NotInitialized();
        _;
    }

    modifier onlyAuthorizedCallers() {
        if (
            msg.sender != SYSTEM_CALLER && msg.sender != GENESIS_ADDR && msg.sender != GOV_HUB_ADDR
                && msg.sender != RECONFIGURATION_WITH_DKG_ADDR
        ) {
            revert NotAuthorized(msg.sender);
        }
        _;
    }

    /// @inheritdoc IRandomnessConfig
    function initialize(
        RandomnessConfigData memory config
    ) external onlyGenesis {
        if (_initialized) revert AlreadyInitialized();

        _validateConfig(config);
        _currentConfig = config;
        _initialized = true;
    }

    /// @inheritdoc IRandomnessConfig
    function setForNextEpoch(
        RandomnessConfigData memory newConfig
    ) external onlyAuthorizedCallers whenNotPaused onlyInitialized {
        _validateConfig(newConfig);
        _pendingConfig = newConfig;
        _hasPendingConfig = true;
    }

    /// @inheritdoc IReconfigurableModule
    function onNewEpoch() external onlyAuthorizedCallers whenNotPaused onlyInitialized {
        if (_hasPendingConfig) {
            _currentConfig = _pendingConfig;
            _hasPendingConfig = false;
        }
    }

    /// @inheritdoc IRandomnessConfig
    function enabled() external view onlyInitialized returns (bool) {
        return true; // Always enabled since Off variant is removed
    }

    /// @inheritdoc IRandomnessConfig
    function current() external view onlyInitialized returns (RandomnessConfigData memory) {
        return _currentConfig;
    }

    /// @inheritdoc IRandomnessConfig
    function pending() external view onlyInitialized returns (bool hasPending, RandomnessConfigData memory config) {
        hasPending = _hasPendingConfig;
        if (hasPending) {
            config = _pendingConfig;
        }
    }

    /// @inheritdoc IRandomnessConfig
    function isInitialized() external view returns (bool) {
        return _initialized;
    }

    /// @inheritdoc IRandomnessConfig
    function newV1(
        IDKG.FixedPoint64 memory secrecyThreshold,
        IDKG.FixedPoint64 memory reconstructionThreshold
    ) external pure returns (RandomnessConfigData memory) {
        return RandomnessConfigData({
            variant: ConfigVariant.V1,
            configV1: ConfigV1({
                secrecyThreshold: secrecyThreshold, reconstructionThreshold: reconstructionThreshold
            }),
            configV2: ConfigV2({
                secrecyThreshold: IDKG.FixedPoint64({ value: 0 }),
                reconstructionThreshold: IDKG.FixedPoint64({ value: 0 }),
                fastPathSecrecyThreshold: IDKG.FixedPoint64({ value: 0 })
            })
        });
    }

    /// @inheritdoc IRandomnessConfig
    function newV2(
        IDKG.FixedPoint64 memory secrecyThreshold,
        IDKG.FixedPoint64 memory reconstructionThreshold,
        IDKG.FixedPoint64 memory fastPathSecrecyThreshold
    ) external pure returns (RandomnessConfigData memory) {
        return RandomnessConfigData({
            variant: ConfigVariant.V2,
            configV1: ConfigV1({
                secrecyThreshold: IDKG.FixedPoint64({ value: 0 }),
                reconstructionThreshold: IDKG.FixedPoint64({ value: 0 })
            }),
            configV2: ConfigV2({
                secrecyThreshold: secrecyThreshold,
                reconstructionThreshold: reconstructionThreshold,
                fastPathSecrecyThreshold: fastPathSecrecyThreshold
            })
        });
    }

    /// @inheritdoc IRandomnessConfig
    function toIDKGConfig(
        RandomnessConfigData memory config
    ) external pure returns (IDKG.Config memory) {
        if (config.variant == ConfigVariant.V2) {
            return IDKG.Config({
                secrecyThreshold: config.configV2.secrecyThreshold,
                reconstructionThreshold: config.configV2.reconstructionThreshold,
                fastPathSecrecyThreshold: config.configV2.fastPathSecrecyThreshold
            });
        } else {
            // ConfigV1
            return IDKG.Config({
                secrecyThreshold: config.configV1.secrecyThreshold,
                reconstructionThreshold: config.configV1.reconstructionThreshold,
                fastPathSecrecyThreshold: IDKG.FixedPoint64({ value: 0 })
            });
        }
    }

    /// @inheritdoc IRandomnessConfig
    function getVariantName(
        RandomnessConfigData memory config
    ) external pure returns (string memory) {
        if (config.variant == ConfigVariant.V1) {
            return "ConfigV1";
        } else if (config.variant == ConfigVariant.V2) {
            return "ConfigV2";
        } else {
            return "Unknown";
        }
    }

    /**
     * @dev Internal function to validate configuration
     * @param config The configuration to validate
     */
    function _validateConfig(
        RandomnessConfigData memory config
    ) internal pure {
        // Validate thresholds for V1 and V2 configurations
        if (config.variant == ConfigVariant.V1) {
            // Ensure reconstruction threshold > secrecy threshold
            if (config.configV1.reconstructionThreshold.value <= config.configV1.secrecyThreshold.value) {
                revert InvalidConfigVariant();
            }
        } else if (config.variant == ConfigVariant.V2) {
            // Ensure reconstruction threshold > secrecy threshold
            if (config.configV2.reconstructionThreshold.value <= config.configV2.secrecyThreshold.value) {
                revert InvalidConfigVariant();
            }
            // Ensure fast path secrecy threshold > secrecy threshold
            if (config.configV2.fastPathSecrecyThreshold.value <= config.configV2.secrecyThreshold.value) {
                revert InvalidConfigVariant();
            }
        }
    }
}
