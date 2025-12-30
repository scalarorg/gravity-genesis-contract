// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import "@src/System.sol";
import "@src/access/Protectable.sol";
import "@src/interfaces/IReconfigurationWithDKG.sol";
import "@src/interfaces/IDKG.sol";
import "@src/interfaces/IEpochManager.sol";
import "@src/interfaces/IValidatorManager.sol";
import "@src/interfaces/IStakeConfig.sol";
import "@src/interfaces/IStakeCredit.sol";
import "@src/interfaces/IValidatorPerformanceTracker.sol";
import "@src/interfaces/IRandomnessConfig.sol";

/**
 * @title ReconfigurationWithDKG
 * @dev Reconfiguration with DKG helper functions
 * @notice This contract manages reconfiguration processes that involve DKG operations
 */
contract ReconfigurationWithDKG is System, Protectable, IReconfigurationWithDKG {
    // DKG contract address - using system constant
    // address public constant DKG_ADDR = 0x000000000000000000000000000000000000200E;

    // State variables
    bool private _initialized;

    // Modifiers
    modifier onlyAuthorizedCallers() {
        if (msg.sender != SYSTEM_CALLER && msg.sender != BLOCK_ADDR && msg.sender != GENESIS_ADDR) {
            revert NotAuthorized(msg.sender);
        }
        _;
    }

    modifier onlyInitialized() {
        if (!_initialized) revert ReconfigurationNotInProgress();
        _;
    }

    /// @inheritdoc IReconfigurationWithDKG
    function initialize() external onlyGenesis {
        if (_initialized) revert ReconfigurationNotInProgress();
        _initialized = true;
        // Contract initialization logic
    }

    /// @inheritdoc IReconfigurationWithDKG
    function finishWithDkgResult(
        bytes calldata dkgResult
    ) external onlyAuthorizedCallers whenNotPaused onlyInitialized {
        // Finish the DKG session with the provided result
        IDKG(DKG_ADDR).finish(dkgResult);

        // Complete the reconfiguration process
        _finishReconfiguration();
    }

    /// @inheritdoc IReconfigurationWithDKG
    function tryStart() external onlyAuthorizedCallers whenNotPaused onlyInitialized {
        uint256 currentEpoch = IEpochManager(EPOCH_MANAGER_ADDR).currentEpoch();

        // Check if there's an incomplete DKG session
        (bool hasIncompleteSession, IDKG.DKGSessionState memory session) = IDKG(DKG_ADDR).incompleteSession();

        if (hasIncompleteSession) {
            uint64 sessionDealerEpoch = IDKG(DKG_ADDR).sessionDealerEpoch(session);

            // If the incomplete session is for the current epoch, return without starting new one
            if (sessionDealerEpoch == currentEpoch) {
                return;
            }

            // Clear the old session if it's for a different epoch
            IDKG(DKG_ADDR).tryClearIncompleteSession();
        }

        // Get current and next validator consensus infos
        IDKG.ValidatorConsensusInfo[] memory currentValidators = _getCurrentValidatorConsensusInfos();
        IDKG.ValidatorConsensusInfo[] memory nextValidators = _getNextValidatorConsensusInfos();

        // Get current randomness config
        IRandomnessConfig.RandomnessConfigData memory randomnessConfig = _getCurrentRandomnessConfig();

        // Start DKG session
        IDKG(DKG_ADDR).start(uint64(currentEpoch), randomnessConfig, currentValidators, nextValidators);
    }

    /// @inheritdoc IReconfigurationWithDKG
    function finish() external onlyAuthorizedCallers whenNotPaused onlyInitialized {
        _finishReconfiguration();
    }

    /// @inheritdoc IReconfigurationWithDKG
    function isReconfigurationInProgress() external view onlyInitialized returns (bool) {
        return IDKG(DKG_ADDR).isDKGInProgress();
    }

    /**
     * @dev Internal function to finish reconfiguration
     */
    function _finishReconfiguration() internal {
        // Clear incomplete DKG session if it exists
        IDKG(DKG_ADDR).tryClearIncompleteSession();

        // Apply buffered on-chain configs for new epoch
        _applyOnNewEpochConfigs();

        // Trigger epoch transition
        IEpochManager(EPOCH_MANAGER_ADDR).triggerEpochTransition();
    }

    /**
     * @dev Apply all necessary configurations for the new epoch
     */
    function _applyOnNewEpochConfigs() internal {
        // Apply various on-chain configurations for the new epoch
        // This includes:
        // - Consensus config updates
        // - Execution config updates
        // - Gas schedule updates
        // - Version updates
        // - Feature updates
        // - JWK consensus config updates
        // - JWKs updates
        // - Keyless account updates
        // - Randomness config updates
        IRandomnessConfig(RANDOMNESS_CONFIG_ADDR).onNewEpoch();
        // - Randomness API config updates

        // For now, we'll implement a placeholder that can be extended
        // based on the specific requirements of each module
    }

    /**
     * @dev Get current validator consensus infos
     * @return Array of current validator consensus information
     */
    function _getCurrentValidatorConsensusInfos() internal view returns (IDKG.ValidatorConsensusInfo[] memory) {
        // Get active validators from ValidatorManager
        address[] memory activeValidators = IValidatorManager(VALIDATOR_MANAGER_ADDR).getActiveValidators();
        IDKG.ValidatorConsensusInfo[] memory consensusInfos = new IDKG.ValidatorConsensusInfo[](activeValidators.length);

        for (uint256 i = 0; i < activeValidators.length; i++) {
            IValidatorManager.ValidatorInfo memory validatorInfo =
                IValidatorManager(VALIDATOR_MANAGER_ADDR).getValidatorInfo(activeValidators[i]);

            consensusInfos[i] = IDKG.ValidatorConsensusInfo({
                aptosAddress: validatorInfo.aptosAddress,
                pkBytes: validatorInfo.consensusPublicKey,
                votingPower: uint64(validatorInfo.votingPower / 1e18)
            });
        }

        return consensusInfos;
    }

    /**
     * @dev Get next validator consensus infos
     * @return Array of next validator consensus information
     */
    function _getNextValidatorConsensusInfos() internal view returns (IDKG.ValidatorConsensusInfo[] memory) {
        // Get current validator set information
        IValidatorManager.ValidatorSet memory validatorSet = IValidatorManager(VALIDATOR_MANAGER_ADDR).getValidatorSet();

        // Get active validators addresses
        address[] memory activeValidatorAddrs = IValidatorManager(VALIDATOR_MANAGER_ADDR).getActiveValidators();

        // Build a mapping-like check for pending_inactive validators using consensus public key
        // Since we can't use mapping in memory, we'll use nested loops

        // Calculate next epoch validator count:
        // next_validators = (active_validators - pending_inactive) + pending_active
        uint256 nextValidatorCount =
            activeValidatorAddrs.length - validatorSet.pendingInactive.length + validatorSet.pendingActive.length;

        IDKG.ValidatorConsensusInfo[] memory consensusInfos = new IDKG.ValidatorConsensusInfo[](nextValidatorCount);
        uint256 index = 0;

        // Add active validators that are not in pending_inactive
        for (uint256 i = 0; i < activeValidatorAddrs.length; i++) {
            bool isPendingInactive = false;

            // Check if this validator is in pending_inactive by comparing consensus public key
            bytes memory activeConsensusPk = validatorSet.activeValidators[i].consensusPublicKey;

            for (uint256 j = 0; j < validatorSet.pendingInactive.length; j++) {
                if (keccak256(activeConsensusPk) == keccak256(validatorSet.pendingInactive[j].consensusPublicKey)) {
                    isPendingInactive = true;
                    break;
                }
            }

            // If not pending inactive, add to next validator set
            if (!isPendingInactive) {
                consensusInfos[index] = IDKG.ValidatorConsensusInfo({
                    aptosAddress: validatorSet.activeValidators[i].aptosAddress,
                    pkBytes: activeConsensusPk,
                    votingPower: uint64(validatorSet.activeValidators[i].votingPower / 1e18)
                });
                index++;
            }
        }

        // Add pending_active validators
        for (uint256 i = 0; i < validatorSet.pendingActive.length; i++) {
            consensusInfos[index] = IDKG.ValidatorConsensusInfo({
                aptosAddress: validatorSet.pendingActive[i].aptosAddress,
                pkBytes: validatorSet.pendingActive[i].consensusPublicKey,
                votingPower: uint64(validatorSet.pendingActive[i].votingPower / 1e18)
            });
            index++;
        }

        return consensusInfos;
    }

    /**
     * @dev Get current randomness config
     * @return Current randomness configuration
     */
    function _getCurrentRandomnessConfig() internal view returns (IRandomnessConfig.RandomnessConfigData memory) {
        // Get current config from RandomnessConfig contract
        return IRandomnessConfig(RANDOMNESS_CONFIG_ADDR).current();
    }
}
