// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title IHashOracle - Hash Oracle Interface
 * @dev POC version: Simplified interface, batch operations removed
 */
interface IHashOracle {
    // Note: timestamp and sourceChain are not stored
    struct HashRecord {
        bytes32 hash; // Hash value
        uint64 blockNumber; // Source chain block number
    }

    /**
     * @dev Record hash (system callers only)
     */
    function recordHash(
        bytes32 hash,
        uint64 blockNumber,
        uint32 sourceChain,
        uint256 sequenceNumber
    ) external;

    /**
     * @dev Verify if hash exists
     */
    function verifyHash(
        bytes32 hash
    ) external view returns (bool exists, uint64 blockNumber);

    /**
     * @dev Get hash record
     */
    function getHashRecord(
        bytes32 hash
    ) external view returns (HashRecord memory);

    /**
     * @dev Check if sequence number has been processed
     */
    function isSequenceProcessed(
        uint32 sourceChain,
        uint256 sequenceNumber
    ) external view returns (bool);

    event HashRecorded(
        bytes32 indexed hash, uint32 indexed sourceChain, uint64 indexed blockNumber, uint256 sequenceNumber
    );
}
