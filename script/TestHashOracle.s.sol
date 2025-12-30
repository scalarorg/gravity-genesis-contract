// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "@src/oracle/HashOracle.sol";
import "@src/interfaces/IHashOracle.sol";
import "@src/System.sol";
import "@test/utils/TestConstants.sol";

contract TestHashOracle is Test, TestConstants {
    function run() external {
        HashOracle hashOracle = new HashOracle();

        // Test 1: Record hash as system caller
        bytes32 testHash = keccak256("test document");
        vm.startPrank(SYSTEM_CALLER);
        hashOracle.recordHash(testHash, 12345, 1, 1);
        vm.stopPrank();

        // Test 2: Verify hash exists
        (bool exists, uint64 sourceBlockNumber) = hashOracle.verifyHash(testHash);

        require(exists, "Hash should exist");
        require(sourceBlockNumber == 12345, "Block number should match");

        // Test 3: Check total count
        require(hashOracle.totalHashesRecorded() == 1, "Total should be 1");

        // Test 4: Check sequence processed
        require(hashOracle.isSequenceProcessed(1, 1), "Sequence should be processed");

        console.log("All HashOracle tests passed!");
    }
}
