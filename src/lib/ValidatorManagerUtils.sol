// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "../System.sol";
import "@src/interfaces/IStakeConfig.sol";
import "@src/interfaces/IValidatorManager.sol";
import "@src/interfaces/IValidatorManagerUtils.sol";

/**
 * @title ValidatorManagerUtils
 * @dev Contract containing helper functions for ValidatorManager
 * @notice This contract is deployed at address 0x000000000000000000000000000000000000200c
 */
contract ValidatorManagerUtils is System, IValidatorManagerUtils {
    uint256 private constant BLS_PUBKEY_LENGTH = 48;
    uint256 private constant BLS_SIG_LENGTH = 96;

    /// @inheritdoc IValidatorManagerUtils
    function validateConsensusKey(
        address operatorAddress,
        bytes calldata consensusPublicKey,
        bytes calldata blsProof
    ) external view override {
        // check lengths
        if (consensusPublicKey.length != BLS_PUBKEY_LENGTH || blsProof.length != BLS_SIG_LENGTH) {
            revert IValidatorManager.InvalidVoteAddress();
        }

        // generate message hash
        bytes32 msgHash = keccak256(abi.encodePacked(operatorAddress, consensusPublicKey, block.chainid));
        bytes memory msgBz = new bytes(32);
        assembly {
            mstore(add(msgBz, 32), msgHash)
        }

        // call precompiled contract to verify BLS signature
        // precompiled contract address is 0x66
        bytes memory input = bytes.concat(msgBz, blsProof, consensusPublicKey); // length: 32 + 96 + 48 = 176
        bytes memory output = new bytes(1);
        assembly {
            let len := mload(input)
            if iszero(staticcall(not(0), 0x66, add(input, 0x20), len, add(output, 0x20), 0x01)) {
                revert(0, 0)
            }
        }
        uint8 result = uint8(output[0]);
        if (result != uint8(1)) {
            revert IValidatorManager.InvalidVoteAddress();
        }
    }

    /// @inheritdoc IValidatorManagerUtils
    function validateMoniker(
        string memory moniker
    ) external pure override {
        bytes memory bz = bytes(moniker);

        // 1. moniker length should be between 3 and 9
        if (bz.length < 3 || bz.length > 9) {
            revert IValidatorManager.InvalidMoniker(moniker);
        }

        // 2. first character should be uppercase
        if (uint8(bz[0]) < 65 || uint8(bz[0]) > 90) {
            revert IValidatorManager.InvalidMoniker(moniker);
        }

        // 3. only alphanumeric characters are allowed
        for (uint256 i = 1; i < bz.length; ++i) {
            // Check if the ASCII value of the character falls outside the range of alphanumeric characters
            if (
                (uint8(bz[i]) < 48 || uint8(bz[i]) > 57) && (uint8(bz[i]) < 65 || uint8(bz[i]) > 90)
                    && (uint8(bz[i]) < 97 || uint8(bz[i]) > 122)
            ) {
                // Character is a special character
                revert IValidatorManager.InvalidMoniker(moniker);
            }
        }
    }

    /// @inheritdoc IValidatorManagerUtils
    function checkVotingPowerIncrease(
        uint256 increaseAmount,
        uint256 totalVotingPower,
        uint256 currentPendingPower
    ) external view override {
        uint256 votingPowerIncreaseLimit = IStakeConfig(STAKE_CONFIG_ADDR).votingPowerIncreaseLimit();

        if (totalVotingPower > 0) {
            uint256 currentJoining = currentPendingPower + increaseAmount;

            if (currentJoining * 100 > totalVotingPower * votingPowerIncreaseLimit) {
                revert IValidatorManager.VotingPowerIncreaseExceedsLimit();
            }
        }
    }

    /// @inheritdoc IValidatorManagerUtils
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
    ) external view override {
        if (isValidatorRegistered) {
            revert IValidatorManager.ValidatorAlreadyExists(validator);
        }

        // check address validity first
        if (initialOperator == address(0)) {
            revert IValidatorManager.InvalidAddress(address(0));
        }

        // check address conflict
        if (isOperatorUsed) {
            revert IValidatorManager.AddressAlreadyInUse(initialOperator, address(0)); // We don't have the conflicted validator address here
        }

        // check consensus address
        if (consensusPublicKey.length > 0 && isConsensusKeyUsed) {
            revert IValidatorManager.DuplicateConsensusAddress(consensusPublicKey);
        }

        // check validator name
        this.validateMoniker(moniker);

        if (isMonikerUsed) {
            revert IValidatorManager.DuplicateMoniker(moniker);
        }

        // check commission settings
        uint256 maxCommissionRate = IStakeConfig(STAKE_CONFIG_ADDR).MAX_COMMISSION_RATE();
        if (
            commission.maxRate > maxCommissionRate || commission.rate > commission.maxRate
                || commission.maxChangeRate > commission.maxRate
        ) {
            revert IValidatorManager.InvalidCommission();
        }

        // check BLS proof only if consensus key is provided
        // TODO(jaxon & Alex)
        // if (consensusPublicKey.length > 0) {
        //     this.validateConsensusKey(validator, consensusPublicKey, blsProof);
        // }
    }
}
