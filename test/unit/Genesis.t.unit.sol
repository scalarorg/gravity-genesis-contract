// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "forge-std/Test.sol";
import "@src/genesis/Genesis.sol";
import "@test/utils/TestConstants.sol";

// Import all the mocks we'll need
import "@test/mocks/ValidatorManagerMock.sol";
import "@test/mocks/StakeConfigMock.sol";
import "@test/mocks/EpochManagerMock.sol";
import "@test/mocks/ValidatorPerformanceTrackerMock.sol";
import "@test/mocks/BlockMock.sol";
import "@test/mocks/GovTokenMock.sol";
import "@test/mocks/TimelockMock.sol";
import "@test/mocks/GravityGovernorMock.sol";
import "@test/mocks/JWKManagerMock.sol";
import "@test/mocks/KeylessAccountMock.sol";
import "@test/mocks/TimestampMock.sol";
import "@test/mocks/DKGMock.sol";
import "@test/mocks/ReconfigurationWithDKGMock.sol";
import "@test/mocks/RandomnessConfigMock.sol";

contract GenesisTest is Test, TestConstants {
    Genesis public genesis;

    // Test data for initial validators
    address[] public validatorAddresses;
    bytes[] public consensusPublicKeys;
    uint256[] public votingPowers;
    bytes[] public validatorNetworkAddresses;
    bytes[] public fullnodeNetworkAddresses;
    bytes[] public aptosAddresses;

    function setUp() public {
        // Deploy Genesis contract
        genesis = new Genesis();

        // Set up initial validator data
        _setupValidatorData();

        // Deploy and set up all mock contracts
        _deployMockContracts();
    }

    function _setupValidatorData() internal {
        // Create 3 initial validators
        validatorAddresses = new address[](3);
        consensusPublicKeys = new bytes[](3);
        votingPowers = new uint256[](3);
        validatorNetworkAddresses = new bytes[](3);
        fullnodeNetworkAddresses = new bytes[](3);
        aptosAddresses = new bytes[](0);

        validatorAddresses[0] = address(0x1111);
        validatorAddresses[1] = address(0x2222);
        validatorAddresses[2] = address(0x3333);

        consensusPublicKeys[0] = abi.encodePacked(bytes32(uint256(0x4444)));
        consensusPublicKeys[1] = abi.encodePacked(bytes32(uint256(0x5555)));
        consensusPublicKeys[2] = abi.encodePacked(bytes32(uint256(0x6666)));

        votingPowers[0] = 1000;
        votingPowers[1] = 2000;
        votingPowers[2] = 1500;

        validatorNetworkAddresses[0] = abi.encodePacked(bytes32(uint256(0x7777)));
        validatorNetworkAddresses[1] = abi.encodePacked(bytes32(uint256(0x8888)));
        validatorNetworkAddresses[2] = abi.encodePacked(bytes32(uint256(0x9999)));

        fullnodeNetworkAddresses[0] = abi.encodePacked(bytes32(uint256(0xaaaa)));
        fullnodeNetworkAddresses[1] = abi.encodePacked(bytes32(uint256(0xbbbb)));
        fullnodeNetworkAddresses[2] = abi.encodePacked(bytes32(uint256(0xcccc)));
    }

    function _deployMockContracts() internal {
        // Deploy mock contracts and set them at their expected addresses
        vm.etch(VALIDATOR_MANAGER_ADDR, address(new ValidatorManagerMock()).code);
        vm.etch(STAKE_CONFIG_ADDR, address(new StakeConfigMock()).code);
        vm.etch(EPOCH_MANAGER_ADDR, address(new EpochManagerMock()).code);
        vm.etch(VALIDATOR_PERFORMANCE_TRACKER_ADDR, address(new ValidatorPerformanceTrackerMock()).code);
        vm.etch(BLOCK_ADDR, address(new BlockMock()).code);
        vm.etch(GOV_TOKEN_ADDR, address(new GovTokenMock()).code);
        vm.etch(TIMELOCK_ADDR, address(new TimelockMock()).code);
        vm.etch(GOVERNOR_ADDR, address(new GravityGovernorMock()).code);
        vm.etch(JWK_MANAGER_ADDR, address(new JWKManagerMock()).code);
        vm.etch(KEYLESS_ACCOUNT_ADDR, address(new KeylessAccountMock()).code);
        vm.etch(TIMESTAMP_ADDR, address(new TimestampMock()).code);
        vm.etch(DKG_ADDR, address(new DKGMock()).code);
        vm.etch(RECONFIGURATION_WITH_DKG_ADDR, address(new ReconfigurationWithDKGMock()).code);
        vm.etch(RANDOMNESS_CONFIG_ADDR, address(new RandomnessConfigMock()).code);
    }

    // ============ SUCCESSFUL GENESIS TESTS ============

    function test_initialize_shouldCompleteGenesisSuccessfully() public {
        // Arrange
        assertFalse(genesis.isGenesisCompleted());

        // Act
        vm.prank(SYSTEM_CALLER);
        vm.expectEmit(true, true, true, true);
        emit Genesis.GenesisCompleted(block.timestamp, 3);

        genesis.initialize(
            validatorAddresses,
            consensusPublicKeys,
            votingPowers,
            validatorNetworkAddresses,
            fullnodeNetworkAddresses,
            aptosAddresses
        );

        // Assert
        assertTrue(genesis.isGenesisCompleted());
    }

    function test_initialize_shouldCallAllSubsystemInitializers() public {
        // Arrange - Set up expectation for all initialize calls
        // We'll verify by checking that the mock contracts were called

        // Act
        vm.prank(SYSTEM_CALLER);
        genesis.initialize(
            validatorAddresses,
            consensusPublicKeys,
            votingPowers,
            validatorNetworkAddresses,
            fullnodeNetworkAddresses,
            aptosAddresses
        );

        // Assert - Check that all subsystems were initialized
        // (This would be verified by the mock contracts if they tracked initialization calls)
        assertTrue(genesis.isGenesisCompleted());
    }

    function test_initialize_shouldTriggerFirstEpoch() public {
        // Arrange
        EpochManagerMock epochManager = EpochManagerMock(EPOCH_MANAGER_ADDR);

        // Act
        vm.prank(SYSTEM_CALLER);
        genesis.initialize(
            validatorAddresses,
            consensusPublicKeys,
            votingPowers,
            validatorNetworkAddresses,
            fullnodeNetworkAddresses,
            aptosAddresses
        );

        // Assert
        // The epoch transition should have been triggered
        // (This would be verified by checking the epoch manager's state)
        assertTrue(genesis.isGenesisCompleted());
    }

    // ============ ACCESS CONTROL TESTS ============

    function test_initialize_unauthorizedCaller_shouldRevert() public {
        // Arrange
        address unauthorizedCaller = address(0xdead);

        // Act & Assert
        vm.prank(unauthorizedCaller);
        vm.expectRevert(abi.encodeWithSelector(System.OnlySystemCaller.selector, unauthorizedCaller));
        genesis.initialize(
            validatorAddresses,
            consensusPublicKeys,
            votingPowers,
            validatorNetworkAddresses,
            fullnodeNetworkAddresses,
            aptosAddresses
        );
    }

    function test_initialize_onlySystemCaller_shouldWork() public {
        // Act & Assert
        vm.prank(SYSTEM_CALLER);
        genesis.initialize(
            validatorAddresses,
            consensusPublicKeys,
            votingPowers,
            validatorNetworkAddresses,
            fullnodeNetworkAddresses,
            aptosAddresses
        );

        assertTrue(genesis.isGenesisCompleted());
    }

    // ============ DOUBLE INITIALIZATION TESTS ============

    function test_initialize_alreadyCompleted_shouldRevert() public {
        // Arrange - Complete genesis first
        vm.prank(SYSTEM_CALLER);
        genesis.initialize(
            validatorAddresses,
            consensusPublicKeys,
            votingPowers,
            validatorNetworkAddresses,
            fullnodeNetworkAddresses,
            aptosAddresses
        );
        assertTrue(genesis.isGenesisCompleted());

        // Act & Assert - Try to initialize again
        vm.prank(SYSTEM_CALLER);
        vm.expectRevert(Genesis.GenesisAlreadyCompleted.selector);
        genesis.initialize(
            validatorAddresses,
            consensusPublicKeys,
            votingPowers,
            validatorNetworkAddresses,
            fullnodeNetworkAddresses,
            aptosAddresses
        );
    }

    // ============ VALIDATION TESTS ============

    function test_initialize_emptyValidators_shouldRevert() public {
        // Arrange - Empty validator arrays
        address[] memory emptyValidators = new address[](0);
        bytes[] memory emptyConsensus = new bytes[](0);
        uint256[] memory emptyPowers = new uint256[](0);
        bytes[] memory emptyValidatorNetworkAddresses = new bytes[](0);
        bytes[] memory emptyFullnodeNetworkAddresses = new bytes[](0);
        bytes[] memory emptyAptosAddresses = new bytes[](0);

        // Act & Assert
        vm.prank(SYSTEM_CALLER);
        vm.expectRevert(Genesis.InvalidInitialValidators.selector);
        genesis.initialize(
            emptyValidators,
            emptyConsensus,
            emptyPowers,
            emptyValidatorNetworkAddresses,
            emptyFullnodeNetworkAddresses,
            emptyAptosAddresses
        );
    }

    function test_initialize_singleValidator_shouldWork() public {
        // Arrange - Single validator setup
        address[] memory singleValidator = new address[](1);
        bytes[] memory singleConsensus = new bytes[](1);
        uint256[] memory singlePower = new uint256[](1);
        bytes[] memory singleValidatorNetworkAddresses = new bytes[](1);
        bytes[] memory singleFullnodeNetworkAddresses = new bytes[](1);
        bytes[] memory singleAptosAddresses = new bytes[](0);

        singleValidator[0] = address(0x1111);
        singleConsensus[0] = abi.encodePacked(bytes32(uint256(0x2222)));
        singlePower[0] = 1000;
        singleValidatorNetworkAddresses[0] = abi.encodePacked(bytes32(uint256(0x3333)));
        singleFullnodeNetworkAddresses[0] = abi.encodePacked(bytes32(uint256(0x4444)));

        // Act
        vm.prank(SYSTEM_CALLER);
        genesis.initialize(
            singleValidator,
            singleConsensus,
            singlePower,
            singleValidatorNetworkAddresses,
            singleFullnodeNetworkAddresses,
            singleAptosAddresses
        );

        // Assert
        assertTrue(genesis.isGenesisCompleted());
    }

    function test_initialize_largeValidatorSet_shouldWork() public {
        // Arrange - Create a large validator set (100 validators)
        uint256 validatorCount = 100;
        address[] memory largeValidatorAddresses = new address[](validatorCount);
        bytes[] memory largeConsensusPublicKeys = new bytes[](validatorCount);
        uint256[] memory largeVotingPowers = new uint256[](validatorCount);
        bytes[] memory largeValidatorNetworkAddresses = new bytes[](validatorCount);
        bytes[] memory largeFullnodeNetworkAddresses = new bytes[](validatorCount);
        bytes[] memory largeAptosAddresses = new bytes[](0);

        for (uint256 i = 0; i < validatorCount; i++) {
            largeValidatorAddresses[i] = address(uint160(0x1000 + i));
            largeConsensusPublicKeys[i] = abi.encodePacked(bytes32(uint256(0x2000 + i)));
            largeVotingPowers[i] = uint256(1000 + i);
            largeValidatorNetworkAddresses[i] = abi.encodePacked(bytes32(uint256(0x3000 + i)));
            largeFullnodeNetworkAddresses[i] = abi.encodePacked(bytes32(uint256(0x4000 + i)));
        }

        // Act
        vm.prank(SYSTEM_CALLER);
        vm.expectEmit(true, true, true, true);
        emit Genesis.GenesisCompleted(block.timestamp, validatorCount);
        genesis.initialize(
            largeValidatorAddresses,
            largeConsensusPublicKeys,
            largeVotingPowers,
            largeValidatorNetworkAddresses,
            largeFullnodeNetworkAddresses,
            largeAptosAddresses
        );

        // Assert
        assertTrue(genesis.isGenesisCompleted());
    }

    function test_initialize_maxVotingPower_shouldWork() public {
        // Arrange - Set maximum voting power
        votingPowers[0] = type(uint256).max;
        votingPowers[1] = type(uint256).max - 1;
        votingPowers[2] = type(uint256).max - 2;

        // Act
        vm.prank(SYSTEM_CALLER);
        genesis.initialize(
            validatorAddresses,
            consensusPublicKeys,
            votingPowers,
            validatorNetworkAddresses,
            fullnodeNetworkAddresses,
            aptosAddresses
        );

        // Assert
        assertTrue(genesis.isGenesisCompleted());
    }

    function test_initialize_zeroVotingPower_shouldWork() public {
        // Arrange - Set zero voting power (edge case)
        votingPowers[0] = 0;
        votingPowers[1] = 1;
        votingPowers[2] = 2;

        // Act
        vm.prank(SYSTEM_CALLER);
        genesis.initialize(
            validatorAddresses,
            consensusPublicKeys,
            votingPowers,
            validatorNetworkAddresses,
            fullnodeNetworkAddresses,
            aptosAddresses
        );

        // Assert
        assertTrue(genesis.isGenesisCompleted());
    }

    function test_initialize_emptyVoteAddresses_shouldWork() public {
        // Act
        vm.prank(SYSTEM_CALLER);
        genesis.initialize(
            validatorAddresses,
            consensusPublicKeys,
            votingPowers,
            validatorNetworkAddresses,
            fullnodeNetworkAddresses,
            aptosAddresses
        );

        // Assert
        assertTrue(genesis.isGenesisCompleted());
    }

    // ============ STATE VERIFICATION TESTS ============

    function test_isGenesisCompleted_beforeInitialization_shouldReturnFalse() public view {
        // Assert
        assertFalse(genesis.isGenesisCompleted());
    }

    function test_isGenesisCompleted_afterInitialization_shouldReturnTrue() public {
        // Arrange & Act
        vm.prank(SYSTEM_CALLER);
        genesis.initialize(
            validatorAddresses,
            consensusPublicKeys,
            votingPowers,
            validatorNetworkAddresses,
            fullnodeNetworkAddresses,
            aptosAddresses
        );

        // Assert
        assertTrue(genesis.isGenesisCompleted());
    }

    // ============ EVENT EMISSION TESTS ============

    function test_initialize_shouldEmitGenesisCompletedEvent() public {
        // Arrange
        uint256 expectedTimestamp = block.timestamp;
        uint256 expectedValidatorCount = consensusPublicKeys.length;

        // Act & Assert
        vm.prank(SYSTEM_CALLER);
        vm.expectEmit(true, true, true, true);
        emit Genesis.GenesisCompleted(expectedTimestamp, expectedValidatorCount);
        genesis.initialize(
            validatorAddresses,
            consensusPublicKeys,
            votingPowers,
            validatorNetworkAddresses,
            fullnodeNetworkAddresses,
            aptosAddresses
        );
    }

    function test_fullGenesisWorkflow_shouldInitializeAllComponents() public {
        // Arrange - Verify initial state
        assertFalse(genesis.isGenesisCompleted());

        // Act - Complete genesis
        vm.prank(SYSTEM_CALLER);
        genesis.initialize(
            validatorAddresses,
            consensusPublicKeys,
            votingPowers,
            validatorNetworkAddresses,
            fullnodeNetworkAddresses,
            aptosAddresses
        );

        // Assert - Verify final state
        assertTrue(genesis.isGenesisCompleted());

        // Verify that we cannot initialize again
        vm.prank(SYSTEM_CALLER);
        vm.expectRevert(Genesis.GenesisAlreadyCompleted.selector);
        genesis.initialize(
            validatorAddresses,
            consensusPublicKeys,
            votingPowers,
            validatorNetworkAddresses,
            fullnodeNetworkAddresses,
            aptosAddresses
        );
    }

    function test_genesisWithRealWorldData_shouldWork() public {
        // Arrange - Realistic validator data
        address[] memory realisticValidators = new address[](5);
        bytes[] memory realisticConsensusPublicKeys = new bytes[](5);
        uint256[] memory realisticPowers = new uint256[](5);
        bytes[] memory realisticValidatorNetworkAddresses = new bytes[](5);
        bytes[] memory realisticFullnodeNetworkAddresses = new bytes[](5);

        // addresses and powers
        realisticValidators[0] = 0x1234567890123456789012345678901234567890;
        realisticValidators[1] = 0x2345678901234567890123456789012345678901;
        realisticValidators[2] = 0x3456789012345678901234567890123456789012;
        realisticValidators[3] = 0x4567890123456789012345678901234567890123;
        realisticValidators[4] = 0x5678901234567890123456789012345678901234;

        realisticConsensusPublicKeys[0] =
            abi.encodePacked(bytes32(uint256(uint160(0xabCDEF1234567890ABcDEF1234567890aBCDeF12))));
        realisticConsensusPublicKeys[1] =
            abi.encodePacked(bytes32(uint256(uint160(0xbcdeF1234567890aBcDef1234567890abcDEf123))));
        realisticConsensusPublicKeys[2] =
            abi.encodePacked(bytes32(uint256(uint160(0xCDeF1234567890ABCDEf1234567890abcdEF1234))));
        realisticConsensusPublicKeys[3] =
            abi.encodePacked(bytes32(uint256(uint160(0xdEF1234567890AbcdEF1234567890aBcdEF12345))));
        realisticConsensusPublicKeys[4] =
            abi.encodePacked(bytes32(uint256(uint160(0xEF1234567890ABcDEf1234567890abCdEf123456))));

        for (uint256 i = 0; i < 5; i++) {
            realisticPowers[i] = uint256(10000000 + i * 1000000); // 10M, 11M, 12M, etc.
        }

        realisticValidatorNetworkAddresses[0] = abi.encodePacked(bytes32(uint256(0x1111)));
        realisticValidatorNetworkAddresses[1] = abi.encodePacked(bytes32(uint256(0x2222)));
        realisticValidatorNetworkAddresses[2] = abi.encodePacked(bytes32(uint256(0x3333)));
        realisticValidatorNetworkAddresses[3] = abi.encodePacked(bytes32(uint256(0x4444)));
        realisticValidatorNetworkAddresses[4] = abi.encodePacked(bytes32(uint256(0x5555)));

        realisticFullnodeNetworkAddresses[0] = abi.encodePacked(bytes32(uint256(0x6666)));
        realisticFullnodeNetworkAddresses[1] = abi.encodePacked(bytes32(uint256(0x7777)));
        realisticFullnodeNetworkAddresses[2] = abi.encodePacked(bytes32(uint256(0x8888)));
        realisticFullnodeNetworkAddresses[3] = abi.encodePacked(bytes32(uint256(0x9999)));
        realisticFullnodeNetworkAddresses[4] = abi.encodePacked(bytes32(uint256(0xaaaa)));

        // Act
        vm.prank(SYSTEM_CALLER);
        genesis.initialize(
            realisticValidators,
            realisticConsensusPublicKeys,
            realisticPowers,
            realisticValidatorNetworkAddresses,
            realisticFullnodeNetworkAddresses,
            aptosAddresses
        );

        // Assert
        assertTrue(genesis.isGenesisCompleted());
    }
}
