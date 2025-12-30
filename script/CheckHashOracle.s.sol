// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "@src/oracle/HashOracle.sol";
import "@src/interfaces/IHashOracle.sol";

contract CheckHashOracle is Script {
    address constant HASH_ORACLE_ADDR = 0x0000000000000000000000000000000000002023;
    bytes32 constant TEST_HASH = 0x9c22ff5f21f0b81b113e63f7db6da94fedef11b2119b4088b89664fb9a3cb658;
    uint32 constant SOURCE_CHAIN = 31337;
    uint256 constant SEQUENCE_NUMBER = 1;

    function run() external view {
        HashOracle hashOracle = HashOracle(HASH_ORACLE_ADDR);
        IHashOracle iHashOracle = IHashOracle(HASH_ORACLE_ADDR);

        console.log("=== HashOracle Status Check ===");
        console.log("HashOracle Address:", HASH_ORACLE_ADDR);
        console.log("");

        // 1. Check statistics
        uint256 total = hashOracle.getStatistics();
        console.log("1. Total Records (getStatistics):", total);
        console.log("");

        // 2. Check if sequence is processed
        bool isProcessed = iHashOracle.isSequenceProcessed(SOURCE_CHAIN, SEQUENCE_NUMBER);
        console.log("2. Sequence Processed (isSequenceProcessed):");
        console.log("   SourceChain:", SOURCE_CHAIN);
        console.log("   SequenceNumber:", SEQUENCE_NUMBER);
        console.log("   Result:", isProcessed);
        console.log("");

        // 3. Verify hash exists
        (bool exists, uint64 sourceBlockNumber) = iHashOracle.verifyHash(TEST_HASH);
        console.log("3. Hash Verification (verifyHash):");
        console.log("   Hash:", vm.toString(TEST_HASH));
        console.log("   Exists:", exists);
        if (exists && sourceBlockNumber != 0) {
            console.log("   SourceBlockNumber:", sourceBlockNumber);
        } else {
            console.log("   Hash not found (blockNumber is 0)");
        }
        console.log("");

        // 4. Get hash record details
        IHashOracle.HashRecord memory record = iHashOracle.getHashRecord(TEST_HASH);
        console.log("4. Hash Record Details (getHashRecord):");
        console.log("   Hash:", vm.toString(record.hash));
        console.log("   BlockNumber:", record.blockNumber);
        console.log("");

        console.log("=== Check Complete ===");
    }
}

