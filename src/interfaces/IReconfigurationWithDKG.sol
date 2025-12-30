// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

/**
 * @title IReconfigurationWithDKG
 * @dev Interface for reconfiguration with DKG operations
 */
interface IReconfigurationWithDKG {
    // Errors
    error NotAuthorized(address caller);
    error ReconfigurationNotInProgress();

    /**
     * @dev Initialize the contract
     */
    function initialize() external;

    /**
     * @dev Trigger a reconfiguration with DKG
     * @notice Do nothing if one is already in progress
     */
    function tryStart() external;

    /**
     * @dev Clear incomplete DKG session and apply buffered on-chain configs
     * @notice Apply all necessary configurations for the new epoch
     */
    function finish() external;

    /**
     * @dev Complete the current reconfiguration with DKG result
     * @param dkgResult The DKG result transcript
     * @notice Abort if no DKG is in progress
     */
    function finishWithDkgResult(
        bytes calldata dkgResult
    ) external;

    /**
     * @dev Check if reconfiguration is in progress
     * @return True if reconfiguration is in progress
     */
    function isReconfigurationInProgress() external view returns (bool);
}
