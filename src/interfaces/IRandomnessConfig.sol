// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import "@src/interfaces/IDKG.sol";
import "@src/interfaces/IReconfigurableModule.sol";

/**
 * @title IRandomnessConfig
 * @dev Interface for RandomnessConfig contract - manages on-chain randomness configurations
 */
interface IRandomnessConfig is IReconfigurableModule {
    // ======== Configuration Variants ========
    enum ConfigVariant {
        V1, // Basic configuration
        V2 // Configuration with fast path
    }

    // ======== Configuration Structs ========
    struct ConfigV1 {
        IDKG.FixedPoint64 secrecyThreshold;
        IDKG.FixedPoint64 reconstructionThreshold;
    }

    struct ConfigV2 {
        IDKG.FixedPoint64 secrecyThreshold;
        IDKG.FixedPoint64 reconstructionThreshold;
        IDKG.FixedPoint64 fastPathSecrecyThreshold;
    }

    // Main configuration struct
    struct RandomnessConfigData {
        ConfigVariant variant;
        ConfigV1 configV1;
        ConfigV2 configV2;
    }

    // ======== Events ========
    event RandomnessConfigInitialized(RandomnessConfigData config);
    event RandomnessConfigUpdated(RandomnessConfigData newConfig);
    event RandomnessConfigApplied(RandomnessConfigData config);

    // ======== Errors ========
    error InvalidConfigVariant();
    error NotInitialized();
    error AlreadyInitialized();
    error NotAuthorized(address caller);

    // ======== Core Functions ========

    /**
     * @dev Initialize the configuration. Used in genesis or governance.
     * @param config The initial randomness configuration
     */
    function initialize(
        RandomnessConfigData memory config
    ) external;

    /**
     * @dev This can be called by on-chain governance to update on-chain consensus configs for the next epoch.
     * @param newConfig The new randomness configuration
     */
    function setForNextEpoch(
        RandomnessConfigData memory newConfig
    ) external;

    /**
     * @dev Check whether on-chain randomness main logic is enabled.
     * @return Always true since Off variant is removed
     */
    function enabled() external view returns (bool);

    /**
     * @dev Get the currently effective randomness configuration object.
     * @return The current randomness configuration
     */
    function current() external view returns (RandomnessConfigData memory);

    /**
     * @dev Get the pending randomness configuration object.
     * @return hasPending Whether there is a pending configuration
     * @return config The pending randomness configuration
     */
    function pending() external view returns (bool hasPending, RandomnessConfigData memory config);

    /**
     * @dev Check if the contract is initialized
     * @return True if initialized
     */
    function isInitialized() external view returns (bool);

    // ======== Factory Functions ========

    /**
     * @dev Create a ConfigV1 variant.
     * @param secrecyThreshold The secrecy threshold
     * @param reconstructionThreshold The reconstruction threshold
     * @return The randomness configuration V1
     */
    function newV1(
        IDKG.FixedPoint64 memory secrecyThreshold,
        IDKG.FixedPoint64 memory reconstructionThreshold
    ) external pure returns (RandomnessConfigData memory);

    /**
     * @dev Create a ConfigV2 variant.
     * @param secrecyThreshold The secrecy threshold
     * @param reconstructionThreshold The reconstruction threshold
     * @param fastPathSecrecyThreshold The fast path secrecy threshold
     * @return The randomness configuration V2
     */
    function newV2(
        IDKG.FixedPoint64 memory secrecyThreshold,
        IDKG.FixedPoint64 memory reconstructionThreshold,
        IDKG.FixedPoint64 memory fastPathSecrecyThreshold
    ) external pure returns (RandomnessConfigData memory);

    // ======== Utility Functions ========

    /**
     * @dev Convert RandomnessConfigData to IDKG.Config for compatibility
     * @param config The RandomnessConfigData to convert
     * @return The IDKG.Config
     */
    function toIDKGConfig(
        RandomnessConfigData memory config
    ) external pure returns (IDKG.Config memory);

    /**
     * @dev Get configuration variant as string for debugging
     * @param config The configuration to get variant for
     * @return The variant name
     */
    function getVariantName(
        RandomnessConfigData memory config
    ) external pure returns (string memory);
}
