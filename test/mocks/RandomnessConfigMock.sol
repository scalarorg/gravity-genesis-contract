// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import "@src/interfaces/IRandomnessConfig.sol";

contract RandomnessConfigMock is IRandomnessConfig {
    // State variables
    RandomnessConfigData private _currentConfig;
    RandomnessConfigData private _pendingConfig;
    bool private _hasPendingConfig;
    bool private _initialized;

    function initialize(
        RandomnessConfigData memory config
    ) external override {
        _currentConfig = config;
        _initialized = true;
    }

    function setForNextEpoch(
        RandomnessConfigData memory newConfig
    ) external override {
        _pendingConfig = newConfig;
        _hasPendingConfig = true;
    }

    function onNewEpoch() external override {
        if (_hasPendingConfig) {
            _currentConfig = _pendingConfig;
            _hasPendingConfig = false;
        }
    }

    function enabled() external view override returns (bool) {
        return true;
    }

    function current() external view override returns (RandomnessConfigData memory) {
        return _currentConfig;
    }

    function pending() external view override returns (bool hasPending, RandomnessConfigData memory config) {
        hasPending = _hasPendingConfig;
        if (hasPending) {
            config = _pendingConfig;
        }
    }

    function isInitialized() external view override returns (bool) {
        return _initialized;
    }

    function newV1(
        IDKG.FixedPoint64 memory secrecyThreshold,
        IDKG.FixedPoint64 memory reconstructionThreshold
    ) external pure override returns (RandomnessConfigData memory) {
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

    function newV2(
        IDKG.FixedPoint64 memory secrecyThreshold,
        IDKG.FixedPoint64 memory reconstructionThreshold,
        IDKG.FixedPoint64 memory fastPathSecrecyThreshold
    ) external pure override returns (RandomnessConfigData memory) {
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

    function toIDKGConfig(
        RandomnessConfigData memory config
    ) external pure override returns (IDKG.Config memory) {
        if (config.variant == ConfigVariant.V2) {
            return IDKG.Config({
                secrecyThreshold: config.configV2.secrecyThreshold,
                reconstructionThreshold: config.configV2.reconstructionThreshold,
                fastPathSecrecyThreshold: config.configV2.fastPathSecrecyThreshold
            });
        } else {
            return IDKG.Config({
                secrecyThreshold: config.configV1.secrecyThreshold,
                reconstructionThreshold: config.configV1.reconstructionThreshold,
                fastPathSecrecyThreshold: IDKG.FixedPoint64({ value: 0 })
            });
        }
    }

    function getVariantName(
        RandomnessConfigData memory config
    ) external pure override returns (string memory) {
        if (config.variant == ConfigVariant.V1) {
            return "ConfigV1";
        } else if (config.variant == ConfigVariant.V2) {
            return "ConfigV2";
        } else {
            return "Unknown";
        }
    }
}

