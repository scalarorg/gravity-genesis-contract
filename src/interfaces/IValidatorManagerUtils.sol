// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@src/interfaces/IValidatorManager.sol";

/**
 * @title IValidatorManagerUtils
 * @dev Interface for ValidatorManagerUtils helper contract
 */
interface IValidatorManagerUtils {
    /**
     * @dev Verify BLS consensus public key and proof
     * @param operatorAddress Operator address
     * @param consensusPublicKey BLS consensus public key
     * @param blsProof BLS proof
     * Reverts with InvalidVoteAddress if verification fails
     */
    function validateConsensusKey(
        address operatorAddress,
        bytes calldata consensusPublicKey,
        bytes calldata blsProof
    ) external view;

    /**
     * @dev Check if validator name is valid
     * @param moniker Validator name
     * Reverts with InvalidMoniker if validation fails
     */
    function validateMoniker(
        string memory moniker
    ) external pure;

    /**
     * @dev Check voting power increase limit
     * @param increaseAmount Amount to increase
     * @param totalVotingPower Current total voting power
     * @param currentPendingPower Total pending power from all pending validators
     * Reverts with VotingPowerIncreaseExceedsLimit if limit exceeded
     */
    function checkVotingPowerIncrease(
        uint256 increaseAmount,
        uint256 totalVotingPower,
        uint256 currentPendingPower
    ) external view;

    /**
     * @dev Validate basic registration params (consensus key and moniker)
     * @param validator Validator address
     * @param consensusPublicKey Consensus public key
     * @param blsProof BLS proof
     * @param moniker Validator moniker
     * @param commission Commission settings
     * @param initialOperator Initial operator address
     * @param isConsensusKeyUsed Whether consensus key is already used
     * @param isMonikerUsed Whether moniker is already used
     * @param isOperatorUsed Whether operator is already used
     * @param isValidatorRegistered Whether validator is already registered
     * Reverts with appropriate errors if validation fails
     */
    function validateRegistrationParams(
        address validator,
        bytes calldata consensusPublicKey,
        bytes calldata blsProof,
        string calldata moniker,
        IValidatorManager.Commission calldata commission,
        address initialOperator,
        bool isConsensusKeyUsed,
        bool isMonikerUsed,
        bool isOperatorUsed,
        bool isValidatorRegistered
    ) external view;
}
