// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@src/System.sol";
import "@src/interfaces/IHashOracle.sol";

/**
 * @title HashOracle - Gravity Chain Hash Oracle Contract (POC Version)
 * @notice Stores and verifies cross-chain hash data
 * @dev Only allows system callers (via PoS consensus) to write
 * @dev POC version: Simplified implementation without expiration/deletion functionality
 */
contract HashOracle is System, IHashOracle {
    // Stores all hash records
    mapping(bytes32 => HashRecord) public hashRecords;

    // Prevents duplicate processing of sequence numbers (maintained independently per source chain)
    mapping(uint32 => mapping(uint256 => bool)) public processedSequences;

    // Statistics
    uint256 public totalHashesRecorded;

    /**
     * @dev System call: Record hash (called by Gravity nodes after PoS consensus)
     * @notice Allows SYSTEM_CALLER or JWK_MANAGER_ADDR to call
     */
    function recordHash(
        bytes32 hash,
        uint64 blockNumber,
        uint32 sourceChain,
        uint256 sequenceNumber
    ) external onlySystemJWKCaller {
        // Prevent duplicate processing
        require(!processedSequences[sourceChain][sequenceNumber], "HashOracle: Already processed");

        // Mark sequence number as processed
        processedSequences[sourceChain][sequenceNumber] = true;

        // Store hash record
        hashRecords[hash] = HashRecord({ hash: hash, blockNumber: blockNumber });

        // Update statistics
        totalHashesRecorded++;

        emit HashRecorded(hash, sourceChain, blockNumber, sequenceNumber);
    }

    /**
     * @dev Verify if hash exists
     */
    function verifyHash(
        bytes32 hash
    ) external view returns (bool exists, uint64 blockNumber) {
        HashRecord memory record = hashRecords[hash];

        return (true, record.blockNumber);
    }

    /**
     * @dev Get hash record
     */
    function getHashRecord(
        bytes32 hash
    ) external view returns (HashRecord memory) {
        return hashRecords[hash];
    }

    /**
     * @dev Check if sequence number has been processed
     */
    function isSequenceProcessed(
        uint32 sourceChain,
        uint256 sequenceNumber
    ) external view returns (bool) {
        return processedSequences[sourceChain][sequenceNumber];
    }

    /**
     * @dev Get statistics
     */
    function getStatistics() external view returns (uint256 total) {
        return (totalHashesRecorded);
    }
}
