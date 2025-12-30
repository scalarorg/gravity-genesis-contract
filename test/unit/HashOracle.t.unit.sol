// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "@src/oracle/HashOracle.sol";
import "@src/interfaces/IHashOracle.sol";
import "../utils/TestConstants.sol";

contract HashOracleTest is Test, TestConstants {
    HashOracle public hashOracle;

    address public systemCaller = SYSTEM_CALLER;
    address public notSystemCaller = address(0x123);

    event HashRecorded(
        bytes32 indexed hash, uint32 indexed sourceChain, uint64 indexed blockNumber, uint256 sequenceNumber
    );

    function setUp() public {
        hashOracle = new HashOracle();
    }

    function test_RecordHash_Success() public {
        bytes32 testHash = keccak256("test document");
        uint64 sourceBlockNumber = 12345;
        uint32 sourceChain = 1; // Ethereum
        uint256 sequenceNumber = 1;

        vm.startPrank(systemCaller);
        vm.roll(block.number + 1);

        vm.expectEmit(true, true, true, true);
        emit HashRecorded(testHash, sourceChain, sourceBlockNumber, sequenceNumber);

        hashOracle.recordHash(testHash, sourceBlockNumber, sourceChain, sequenceNumber);

        vm.stopPrank();

        // Verify the hash was recorded
        (bool exists, uint64 blockNumber) = hashOracle.verifyHash(testHash);

        assertTrue(exists);
        assertEq(blockNumber, sourceBlockNumber);

        // Check total count
        assertEq(hashOracle.totalHashesRecorded(), 1);

        // Check sequence processed
        assertTrue(hashOracle.isSequenceProcessed(sourceChain, sequenceNumber));
    }

    function test_RecordHash_Fails_NotSystemCaller() public {
        bytes32 testHash = keccak256("test document");

        vm.startPrank(notSystemCaller);
        vm.expectRevert();
        hashOracle.recordHash(testHash, 12345, 1, 1);
        vm.stopPrank();
    }

    function test_RecordHash_Fails_DuplicateSequence() public {
        bytes32 testHash1 = keccak256("test document 1");
        bytes32 testHash2 = keccak256("test document 2");
        uint256 sequenceNumber = 1;

        vm.startPrank(systemCaller);

        // First record should succeed
        hashOracle.recordHash(testHash1, 12345, 1, sequenceNumber);

        // Second record with same sequence should fail
        vm.expectRevert("HashOracle: Already processed");
        hashOracle.recordHash(testHash2, 12346, 1, sequenceNumber);

        vm.stopPrank();
    }

    function test_VerifyHash_NotExists() public {
        bytes32 testHash = keccak256("non-existent hash");

        (bool exists, uint64 blockNumber) = hashOracle.verifyHash(testHash);

        // Note: verifyHash always returns true, but blockNumber will be 0 if record doesn't exist
        assertTrue(exists);
        assertEq(blockNumber, 0);
    }

    function test_GetHashRecord_Success() public {
        bytes32 testHash = keccak256("test document");
        uint64 sourceBlockNumber = 12345;
        uint32 sourceChain = 1;
        uint256 sequenceNumber = 1;

        vm.startPrank(systemCaller);
        vm.roll(block.number + 1);
        hashOracle.recordHash(testHash, sourceBlockNumber, sourceChain, sequenceNumber);
        vm.stopPrank();

        IHashOracle.HashRecord memory record = hashOracle.getHashRecord(testHash);

        assertEq(record.hash, testHash);
        assertEq(record.blockNumber, sourceBlockNumber);
    }

    function test_GetHashRecord_NotExists() public {
        bytes32 testHash = keccak256("non-existent hash");

        IHashOracle.HashRecord memory record = hashOracle.getHashRecord(testHash);

        assertEq(record.hash, bytes32(0));
        assertEq(record.blockNumber, 0);
    }

    function test_IsSequenceProcessed() public {
        uint32 sourceChain = 1;
        uint256 sequenceNumber = 1;

        // Initially should be false
        assertFalse(hashOracle.isSequenceProcessed(sourceChain, sequenceNumber));

        vm.startPrank(systemCaller);
        hashOracle.recordHash(keccak256("test"), 12345, sourceChain, sequenceNumber);
        vm.stopPrank();

        // Should be true after recording
        assertTrue(hashOracle.isSequenceProcessed(sourceChain, sequenceNumber));
    }

    function test_GetStatistics() public {
        // Initially should be 0
        (uint256 total) = hashOracle.getStatistics();
        assertEq(total, 0);

        // Record multiple hashes
        vm.startPrank(systemCaller);
        for (uint256 i = 1; i <= 5; i++) {
            hashOracle.recordHash(keccak256(abi.encodePacked(i)), uint64(i), 1, i);
        }
        vm.stopPrank();

        // Should be 5
        (uint256 totalAfter) = hashOracle.getStatistics();
        assertEq(totalAfter, 5);

        // Check public variable
        assertEq(hashOracle.totalHashesRecorded(), 5);
    }

    function test_MultipleChains() public {
        bytes32 testHash1 = keccak256("test1");
        bytes32 testHash2 = keccak256("test2");

        vm.startPrank(systemCaller);
        vm.roll(block.number + 1);

        // Record on different chains with same sequence number
        hashOracle.recordHash(testHash1, 100, 1, 1); // Ethereum
        hashOracle.recordHash(testHash2, 200, 137, 1); // Polygon

        vm.stopPrank();

        // Both should exist
        assertTrue(hashOracle.isSequenceProcessed(1, 1));
        assertTrue(hashOracle.isSequenceProcessed(137, 1));

        // Verify both hashes
        (bool exists1, uint64 blockNumber1) = hashOracle.verifyHash(testHash1);
        (bool exists2, uint64 blockNumber2) = hashOracle.verifyHash(testHash2);

        assertTrue(exists1);
        assertEq(blockNumber1, 100);
        assertTrue(exists2);
        assertEq(blockNumber2, 200);
    }

    function test_RecordHash_DifferentBlockNumber() public {
        bytes32 testHash = keccak256("test");
        uint64 sourceBlockNumber = 12345;

        vm.startPrank(systemCaller);

        vm.roll(block.number + 1);
        hashOracle.recordHash(testHash, sourceBlockNumber, 1, 1);

        IHashOracle.HashRecord memory record = hashOracle.getHashRecord(testHash);
        assertEq(record.hash, testHash);
        assertEq(record.blockNumber, sourceBlockNumber);

        vm.stopPrank();
    }
}
