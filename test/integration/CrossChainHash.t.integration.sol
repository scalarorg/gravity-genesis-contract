// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "@src/oracle/HashOracle.sol";
import "@src/jwk/JWKManager.sol";
import "@src/interfaces/IJWKManager.sol";
import "@src/interfaces/IHashOracle.sol";
import "../utils/TestConstants.sol";
import "../mocks/EpochManagerMock.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract CrossChainHashTest is Test, TestConstants {
    HashOracle public hashOracle;
    JWKManager public jwkManager;

    address public constant HASH_ORACLE_ADDR = 0x0000000000000000000000000000000000002023;
    address public systemCaller = SYSTEM_CALLER;
    address public validator = address(0x1001);

    // Test issuer for hash record events
    string public constant TEST_ISSUER = "https://hash-oracle.test.com";

    bytes32 public constant HASH_1 = keccak256("Document 1");
    bytes32 public constant HASH_2 = keccak256("Document 2");

    event HashRecorded(
        bytes32 indexed hash, uint32 indexed sourceChain, uint64 indexed blockNumber, uint256 sequenceNumber
    );

    function setUp() public {
        // Deploy HashOracle to system address using vm.etch
        HashOracle tempOracle = new HashOracle();
        vm.etch(HASH_ORACLE_ADDR, address(tempOracle).code);
        hashOracle = HashOracle(HASH_ORACLE_ADDR);

        // Deploy EpochManagerMock to EPOCH_MANAGER_ADDR
        EpochManagerMock epochManagerMock = new EpochManagerMock();
        vm.etch(EPOCH_MANAGER_ADDR, address(epochManagerMock).code);

        // Deploy JWKManager implementation
        JWKManager implementation = new JWKManager();

        // Deploy proxy code to JWK_MANAGER_ADDR system address
        ERC1967Proxy tempProxy = new ERC1967Proxy(address(implementation), "");
        vm.etch(JWK_MANAGER_ADDR, address(tempProxy).code);

        // Manually store the implementation address in ERC1967 slot
        // ERC1967 implementation slot from proxy bytecode
        bytes32 implSlot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        vm.store(JWK_MANAGER_ADDR, implSlot, bytes32(uint256(uint160(address(implementation)))));

        jwkManager = JWKManager(JWK_MANAGER_ADDR);

        // Initialize JWKManager through proxy at system address
        vm.prank(GENESIS_ADDR);
        jwkManager.initialize();

        // Register test issuer for hash record events
        vm.prank(GOV_HUB_ADDR);
        jwkManager.upsertOIDCProvider(TEST_ISSUER, "https://hash-oracle.test.com/.well-known/openid_configuration");

        // Register issuer for deposit events
        vm.prank(GOV_HUB_ADDR);
        jwkManager.upsertOIDCProvider(
            "https://accounts.google.com", "https://accounts.google.com/.well-known/openid_configuration"
        );

        // Fund JWKManager for potential ETH transfers
        vm.deal(address(jwkManager), 10 ether);
    }

    function test_CrossChainHashFlow() public {
        uint32 sourceChain = 1; // Ethereum
        uint64 sourceBlockNumber = 18500000;
        uint256 sequenceNumber = 12345;

        // Prepare the hash record data
        bytes memory hashRecordData = abi.encodePacked(HASH_1, sourceBlockNumber, sourceChain, sequenceNumber);

        // Create CrossChainParams array with hash record event
        IJWKManager.CrossChainParams[] memory crossChainParams = new IJWKManager.CrossChainParams[](1);
        crossChainParams[0] = IJWKManager.CrossChainParams({
            id: "2", // HashRecordEvent ID
            sender: address(0x1234),
            targetAddress: address(0),
            amount: 0,
            blockNumber: uint256(sourceBlockNumber),
            issuer: TEST_ISSUER,
            data: hashRecordData
        });

        // Mock upsertObservedJWKs call (normally done by consensus)
        vm.startPrank(systemCaller);
        vm.roll(block.number + 1);

        // Expect HashRecorded event from HashOracle
        vm.expectEmit(true, true, true, true);
        emit HashRecorded(HASH_1, sourceChain, sourceBlockNumber, sequenceNumber);

        // Call upsertObservedJWKs with empty providerJWKs and our crossChainParams
        jwkManager.upsertObservedJWKs(new IJWKManager.ProviderJWKs[](0), crossChainParams);

        vm.stopPrank();

        // Verify hash was recorded in HashOracle
        (bool exists, uint64 returnedBlockNumber) = hashOracle.verifyHash(HASH_1);

        assertTrue(exists, "Hash should exist");
        assertEq(returnedBlockNumber, sourceBlockNumber, "Source block number should match");

        // Check that sequence is marked as processed
        assertTrue(hashOracle.isSequenceProcessed(sourceChain, sequenceNumber), "Sequence should be processed");

        // Verify total count
        assertEq(hashOracle.totalHashesRecorded(), 1, "Total hashes recorded should be 1");
    }

    function test_MultipleHashRecords() public {
        // Create two hash records
        IJWKManager.CrossChainParams[] memory crossChainParams = new IJWKManager.CrossChainParams[](2);

        // First hash record
        crossChainParams[0] = IJWKManager.CrossChainParams({
            id: "2",
            sender: address(0x1234),
            targetAddress: address(0),
            amount: 0,
            blockNumber: 18500000,
            issuer: TEST_ISSUER,
            data: abi.encodePacked(HASH_1, uint64(18500000), uint32(1), uint256(100))
        });

        // Second hash record
        crossChainParams[1] = IJWKManager.CrossChainParams({
            id: "2",
            sender: address(0x5678),
            targetAddress: address(0),
            amount: 0,
            blockNumber: 18500001,
            issuer: TEST_ISSUER,
            data: abi.encodePacked(HASH_2, uint64(18500001), uint32(1), uint256(101))
        });

        vm.startPrank(systemCaller);
        vm.roll(block.number + 1);

        jwkManager.upsertObservedJWKs(new IJWKManager.ProviderJWKs[](0), crossChainParams);

        vm.stopPrank();

        // Verify both hashes
        (bool exists1, uint64 blockNumber1) = hashOracle.verifyHash(HASH_1);
        (bool exists2, uint64 blockNumber2) = hashOracle.verifyHash(HASH_2);
        assertTrue(exists1, "Hash 1 should exist");
        assertEq(blockNumber1, 18500000, "Hash 1 block number should match");
        assertTrue(exists2, "Hash 2 should exist");
        assertEq(blockNumber2, 18500001, "Hash 2 block number should match");

        // Check total count
        assertEq(hashOracle.totalHashesRecorded(), 2, "Total hashes recorded should be 2");
    }

    function test_MixedCrossChainEvents() public {
        // Create mixed events: one deposit, one hash record
        IJWKManager.CrossChainParams[] memory crossChainParams = new IJWKManager.CrossChainParams[](2);

        // Deposit event
        crossChainParams[0] = IJWKManager.CrossChainParams({
            id: "1", // CrossChainDepositEvent
            sender: address(0x1234),
            targetAddress: validator,
            amount: 1 ether,
            blockNumber: 18500000,
            issuer: "https://accounts.google.com",
            data: ""
        });

        // Hash record event
        crossChainParams[1] = IJWKManager.CrossChainParams({
            id: "2", // HashRecordEvent
            sender: address(0x5678),
            targetAddress: address(0),
            amount: 0,
            blockNumber: 18500001,
            issuer: TEST_ISSUER,
            data: abi.encodePacked(HASH_1, uint64(18500001), uint32(1), uint256(100))
        });

        vm.startPrank(systemCaller);
        vm.roll(block.number + 1);

        // Expect both events to be processed
        vm.expectEmit(true, true, true, false);
        emit IJWKManager.CrossChainDepositProcessed(
            address(0x1234), validator, 1 ether, 18500000, true, "", "https://accounts.google.com", block.number
        );

        vm.expectEmit(true, true, true, true);
        emit HashRecorded(HASH_1, 1, 18500001, 100);

        jwkManager.upsertObservedJWKs(new IJWKManager.ProviderJWKs[](0), crossChainParams);

        vm.stopPrank();

        // Verify deposit was processed
        assertEq(validator.balance, 1 ether, "Validator should receive ETH");

        // Verify hash was recorded
        (bool exists, uint64 blockNumber) = hashOracle.verifyHash(HASH_1);
        assertTrue(exists, "Hash should exist");
        assertEq(blockNumber, 18500001, "Block number should match");
    }

    function test_InvalidHashRecordData() public {
        // Create hash record with invalid data length
        bytes memory invalidData = abi.encodePacked(HASH_1, uint64(18500000)); // Missing sourceChain and sequenceNumber

        IJWKManager.CrossChainParams[] memory crossChainParams = new IJWKManager.CrossChainParams[](1);
        crossChainParams[0] = IJWKManager.CrossChainParams({
            id: "2",
            sender: address(0x1234),
            targetAddress: address(0),
            amount: 0,
            blockNumber: 18500000,
            issuer: TEST_ISSUER,
            data: invalidData
        });

        vm.startPrank(systemCaller);

        // Should revert due to invalid data length
        vm.expectRevert("Invalid hash record data length");
        jwkManager.upsertObservedJWKs(new IJWKManager.ProviderJWKs[](0), crossChainParams);

        vm.stopPrank();
    }

    function test_DuplicateSequenceNumber() public {
        uint32 sourceChain = 1;
        uint256 sequenceNumber = 12345;

        // Create two hash records with same sequence number
        IJWKManager.CrossChainParams[] memory crossChainParams1 = new IJWKManager.CrossChainParams[](1);
        crossChainParams1[0] = IJWKManager.CrossChainParams({
            id: "2",
            sender: address(0x1234),
            targetAddress: address(0),
            amount: 0,
            blockNumber: 18500000,
            issuer: TEST_ISSUER,
            data: abi.encodePacked(HASH_1, uint64(18500000), sourceChain, sequenceNumber)
        });

        IJWKManager.CrossChainParams[] memory crossChainParams2 = new IJWKManager.CrossChainParams[](1);
        crossChainParams2[0] = IJWKManager.CrossChainParams({
            id: "2",
            sender: address(0x5678),
            targetAddress: address(0),
            amount: 0,
            blockNumber: 18500001,
            issuer: TEST_ISSUER,
            data: abi.encodePacked(HASH_2, uint64(18500001), sourceChain, sequenceNumber)
        });

        vm.startPrank(systemCaller);
        vm.roll(block.number + 1);

        // First record should succeed
        jwkManager.upsertObservedJWKs(new IJWKManager.ProviderJWKs[](0), crossChainParams1);

        // Second record should fail due to duplicate sequence
        vm.expectRevert("HashOracle: Already processed");
        jwkManager.upsertObservedJWKs(new IJWKManager.ProviderJWKs[](0), crossChainParams2);

        vm.stopPrank();

        // Only first hash should exist
        (bool exists1, uint64 blockNumber1) = hashOracle.verifyHash(HASH_1);
        (bool exists2, uint64 blockNumber2) = hashOracle.verifyHash(HASH_2);
        assertTrue(exists1, "Hash 1 should exist");
        assertEq(blockNumber1, 18500000, "Hash 1 block number should match");
        // Hash 2 should not exist (blockNumber will be 0)
        assertTrue(exists2, "verifyHash always returns true");
        assertEq(blockNumber2, 0, "Hash 2 should not exist (blockNumber is 0)");

        // Total count should be 1
        assertEq(hashOracle.totalHashesRecorded(), 1, "Total hashes recorded should be 1");
    }

    function test_MultipleChainsSameSequence() public {
        uint256 sequenceNumber = 12345;

        // Create hash records on different chains with same sequence number
        IJWKManager.CrossChainParams[] memory crossChainParams = new IJWKManager.CrossChainParams[](2);

        // Ethereum
        crossChainParams[0] = IJWKManager.CrossChainParams({
            id: "2",
            sender: address(0x1234),
            targetAddress: address(0),
            amount: 0,
            blockNumber: 18500000,
            issuer: TEST_ISSUER,
            data: abi.encodePacked(HASH_1, uint64(18500000), uint32(1), sequenceNumber)
        });

        // Polygon
        crossChainParams[1] = IJWKManager.CrossChainParams({
            id: "2",
            sender: address(0x5678),
            targetAddress: address(0),
            amount: 0,
            blockNumber: 50000000,
            issuer: TEST_ISSUER,
            data: abi.encodePacked(HASH_2, uint64(50000000), uint32(137), sequenceNumber)
        });

        vm.startPrank(systemCaller);
        vm.roll(block.number + 1);

        jwkManager.upsertObservedJWKs(new IJWKManager.ProviderJWKs[](0), crossChainParams);

        vm.stopPrank();

        // Both hashes should exist (different chains)
        (bool exists1, uint64 blockNumber1) = hashOracle.verifyHash(HASH_1);
        (bool exists2, uint64 blockNumber2) = hashOracle.verifyHash(HASH_2);
        assertTrue(exists1, "Hash 1 should exist");
        assertEq(blockNumber1, 18500000, "Hash 1 block number should match");
        assertTrue(exists2, "Hash 2 should exist");
        assertEq(blockNumber2, 50000000, "Hash 2 block number should match");

        // Both sequences should be marked as processed
        assertTrue(hashOracle.isSequenceProcessed(1, sequenceNumber), "Ethereum sequence should be processed");
        assertTrue(hashOracle.isSequenceProcessed(137, sequenceNumber), "Polygon sequence should be processed");

        // Total count should be 2
        assertEq(hashOracle.totalHashesRecorded(), 2, "Total hashes recorded should be 2");
    }
}
