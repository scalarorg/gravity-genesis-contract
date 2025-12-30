// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "forge-std/Test.sol";
import "@src/jwk/JWKManager.sol";
import "@src/interfaces/IJWKManager.sol";
import "@src/interfaces/IValidatorManager.sol";
import "@src/interfaces/IDelegation.sol";
import "@test/utils/TestConstants.sol";
import "@test/mocks/JWKManagerMock.sol";
import "@test/mocks/EpochManagerMock.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// Simple receiver contract for testing
contract SimpleReceiver {
    receive() external payable { }
}

contract JWKManagerTest is Test, TestConstants {
    JWKManager public jwkManager;
    JWKManager public implementation;
    JWKManagerMock public validatorManagerMock;
    JWKManagerMock public delegationMock;
    EpochManagerMock public epochManagerMock;

    // Test constants
    address private constant TEST_USER = 0x1234567890123456789012345678901234567890;
    address private constant TEST_VALIDATOR = 0x2234567890123456789012345678901234567890;
    address private constant TEST_TARGET_ADDRESS = 0x3334567890123456789012345678901234567890;

    uint256 private constant TEST_DEPOSIT_AMOUNT = 1 ether;

    bytes private constant TEST_CONSENSUS_KEY =
        hex"123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456";
    bytes private constant TEST_BLS_PROOF =
        hex"12345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456";

    string private constant TEST_MONIKER = "TestValidator";
    string private constant TEST_ISSUER = "https://test.issuer.com";

    function setUp() public {
        // Deploy mock contracts
        validatorManagerMock = new JWKManagerMock();
        delegationMock = new JWKManagerMock();
        epochManagerMock = new EpochManagerMock();

        // Deploy JWKManager implementation
        implementation = new JWKManager();

        // Deploy proxy
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), "");
        jwkManager = JWKManager(address(proxy));

        // Deploy mock contracts to system addresses
        vm.etch(VALIDATOR_MANAGER_ADDR, address(validatorManagerMock).code);
        vm.etch(DELEGATION_ADDR, address(delegationMock).code);
        vm.etch(EPOCH_MANAGER_ADDR, address(epochManagerMock).code);

        // Initialize JWKManager
        vm.prank(GENESIS_ADDR);
        jwkManager.initialize();

        // Add OIDC providers for testing
        vm.prank(GOV_HUB_ADDR);
        jwkManager.upsertOIDCProvider(TEST_ISSUER, "https://test.issuer.com/.well-known/openid_configuration");
        vm.prank(GOV_HUB_ADDR);
        jwkManager.upsertOIDCProvider("https://provider1.com", "https://provider1.com/.well-known/openid_configuration");
        vm.prank(GOV_HUB_ADDR);
        jwkManager.upsertOIDCProvider("https://provider2.com", "https://provider2.com/.well-known/openid_configuration");

        // Provide ETH to JWKManager for transfer operations
        vm.deal(address(jwkManager), 100 ether);

        // Set up mock data
        _getValidatorManagerMock().setValidatorExists(TEST_TARGET_ADDRESS, true);
        _getValidatorManagerMock().setValidatorStakeCredit(TEST_TARGET_ADDRESS, address(0x123));
    }

    // ============ CROSS CHAIN DEPOSIT EVENT TESTS ============

    /// @notice Test processing CrossChainDepositEvent, should transfer funds
    function test_processCrossChainDepositEvent_shouldTransferFunds() public {
        // Arrange
        uint256 initialBalance = TEST_TARGET_ADDRESS.balance;

        IJWKManager.ProviderJWKs[] memory providerJWKsArray = new IJWKManager.ProviderJWKs[](0);

        // Create CrossChainParams for deposit event
        IJWKManager.CrossChainParams[] memory crossChainParams = new IJWKManager.CrossChainParams[](1);
        crossChainParams[0] = IJWKManager.CrossChainParams({
            id: bytes("1"), // CrossChainDepositEvent
            sender: TEST_USER,
            targetAddress: TEST_TARGET_ADDRESS,
            amount: TEST_DEPOSIT_AMOUNT,
            blockNumber: block.number,
            issuer: TEST_ISSUER,
            data: ""
        });

        // Act
        vm.prank(SYSTEM_CALLER);
        jwkManager.upsertObservedJWKs(providerJWKsArray, crossChainParams);

        // Assert
        assertEq(TEST_TARGET_ADDRESS.balance, initialBalance + TEST_DEPOSIT_AMOUNT);
    }

    /// @notice Test processing normal JWK (non-deposit event), should not process
    function test_processNormalJWK_shouldNotProcess() public {
        // Arrange - Create a normal RSA JWK (variant = 0)
        IJWKManager.RSA_JWK memory rsaJWK =
            IJWKManager.RSA_JWK({ kid: "test-key-id", kty: "RSA", alg: "RS256", e: "AQAB", n: "test-modulus" });

        IJWKManager.JWK memory normalJWK = IJWKManager.JWK({
            variant: 0, // RSA_JWK
            data: abi.encode(rsaJWK)
        });

        IJWKManager.ProviderJWKs memory providerJWKs =
            IJWKManager.ProviderJWKs({ issuer: TEST_ISSUER, version: 1, jwks: new IJWKManager.JWK[](1) });
        providerJWKs.jwks[0] = normalJWK;

        IJWKManager.ProviderJWKs[] memory providerJWKsArray = new IJWKManager.ProviderJWKs[](1);
        providerJWKsArray[0] = providerJWKs;

        // Act
        vm.prank(SYSTEM_CALLER);
        jwkManager.upsertObservedJWKs(providerJWKsArray, new IJWKManager.CrossChainParams[](0));

        // Assert - Should not emit any events or transfer funds
        assertFalse(_getValidatorManagerMock().stakeRegisterValidatorEventEmitted());
        assertFalse(_getDelegationMock().stakeEventEmitted());
    }

    /// @notice Test processing provider with multiple JWKs
    function test_processMultipleJWKs_shouldNotProcess() public {
        // Arrange - Create provider with multiple JWKs (should not process)
        IJWKManager.RSA_JWK memory rsaJWK =
            IJWKManager.RSA_JWK({ kid: "test-key-id", kty: "RSA", alg: "RS256", e: "AQAB", n: "test-modulus" });

        IJWKManager.JWK memory normalJWK = IJWKManager.JWK({
            variant: 0, // RSA_JWK
            data: abi.encode(rsaJWK)
        });

        IJWKManager.ProviderJWKs memory providerJWKs =
            IJWKManager.ProviderJWKs({ issuer: TEST_ISSUER, version: 1, jwks: new IJWKManager.JWK[](2) });
        providerJWKs.jwks[0] = normalJWK;
        providerJWKs.jwks[1] = normalJWK;

        IJWKManager.ProviderJWKs[] memory providerJWKsArray = new IJWKManager.ProviderJWKs[](1);
        providerJWKsArray[0] = providerJWKs;

        // Act
        vm.prank(SYSTEM_CALLER);
        jwkManager.upsertObservedJWKs(providerJWKsArray, new IJWKManager.CrossChainParams[](0));

        // Assert - Should not process because array has more than 1 element
        assertFalse(_getValidatorManagerMock().stakeRegisterValidatorEventEmitted());
        assertFalse(_getDelegationMock().stakeEventEmitted());
    }

    /// @notice Test processing unsupported JWK type, should not process
    function test_processUnsupportedJWK_shouldNotProcess() public {
        // Arrange - Create an unsupported JWK (variant = 1)
        IJWKManager.UnsupportedJWK memory unsupportedJWK =
            IJWKManager.UnsupportedJWK({ id: "unsupported-id", payload: "unsupported-payload" });

        IJWKManager.JWK memory unsupportedJWKStruct = IJWKManager.JWK({
            variant: 1, // UnsupportedJWK
            data: abi.encode(unsupportedJWK)
        });

        IJWKManager.ProviderJWKs memory providerJWKs =
            IJWKManager.ProviderJWKs({ issuer: TEST_ISSUER, version: 1, jwks: new IJWKManager.JWK[](1) });
        providerJWKs.jwks[0] = unsupportedJWKStruct;

        IJWKManager.ProviderJWKs[] memory providerJWKsArray = new IJWKManager.ProviderJWKs[](1);
        providerJWKsArray[0] = providerJWKs;

        // Act
        vm.prank(SYSTEM_CALLER);
        jwkManager.upsertObservedJWKs(providerJWKsArray, new IJWKManager.CrossChainParams[](0));

        // Assert - Should not process
        assertFalse(_getValidatorManagerMock().stakeRegisterValidatorEventEmitted());
        assertFalse(_getDelegationMock().stakeEventEmitted());
    }

    /// @notice Test processing multiple CrossChainDepositEvents
    function test_processMultipleDepositEvents_shouldTransferAll() public {
        // Arrange
        address target1 = address(0x1111);
        address target2 = address(0x2222);
        uint256 amount1 = 1 ether;
        uint256 amount2 = 2 ether;

        IJWKManager.ProviderJWKs[] memory providerJWKsArray = new IJWKManager.ProviderJWKs[](0);

        // Create CrossChainParams for two deposit events
        IJWKManager.CrossChainParams[] memory crossChainParams = new IJWKManager.CrossChainParams[](2);
        crossChainParams[0] = IJWKManager.CrossChainParams({
            id: bytes("1"), // CrossChainDepositEvent
            sender: TEST_USER,
            targetAddress: target1,
            amount: amount1,
            blockNumber: block.number,
            issuer: TEST_ISSUER,
            data: ""
        });
        crossChainParams[1] = IJWKManager.CrossChainParams({
            id: bytes("1"), // CrossChainDepositEvent
            sender: TEST_USER,
            targetAddress: target2,
            amount: amount2,
            blockNumber: block.number,
            issuer: TEST_ISSUER,
            data: ""
        });

        // Act
        vm.prank(SYSTEM_CALLER);
        jwkManager.upsertObservedJWKs(providerJWKsArray, crossChainParams);

        // Assert - Both transfers should succeed
        assertEq(target1.balance, amount1);
        assertEq(target2.balance, amount2);
    }

    // ============ ACCESS CONTROL TESTS ============

    /// @notice Test non-system caller calling upsertObservedJWKs, should revert
    function test_upsertObservedJWKs_nonSystemCaller_shouldRevert() public {
        // Arrange
        IJWKManager.ProviderJWKs[] memory providerJWKsArray = new IJWKManager.ProviderJWKs[](0);

        // Act & Assert
        vm.expectRevert();
        jwkManager.upsertObservedJWKs(providerJWKsArray, new IJWKManager.CrossChainParams[](0));
    }

    // ============ EDGE CASE TESTS ============

    /// @notice Test processing empty provider array, should not process anything
    function test_processEmptyProviderArray_shouldNotProcess() public {
        // Arrange
        IJWKManager.ProviderJWKs[] memory providerJWKsArray = new IJWKManager.ProviderJWKs[](0);

        // Act
        vm.prank(SYSTEM_CALLER);
        jwkManager.upsertObservedJWKs(providerJWKsArray, new IJWKManager.CrossChainParams[](0));

        // Assert - Should not emit any events
        assertFalse(_getValidatorManagerMock().stakeRegisterValidatorEventEmitted());
        assertFalse(_getDelegationMock().stakeEventEmitted());
    }

    /// @notice Test processing JWK with invalid variant, should not process
    function test_processInvalidVariantJWK_shouldNotProcess() public {
        // Arrange - Create JWK with invalid variant (4)
        bytes memory testData = abi.encode(TEST_USER, TEST_DEPOSIT_AMOUNT, TEST_TARGET_ADDRESS);

        IJWKManager.JWK memory invalidJWK = IJWKManager.JWK({
            variant: 4, // Invalid variant
            data: testData
        });

        IJWKManager.ProviderJWKs memory providerJWKs =
            IJWKManager.ProviderJWKs({ issuer: TEST_ISSUER, version: 1, jwks: new IJWKManager.JWK[](1) });
        providerJWKs.jwks[0] = invalidJWK;

        IJWKManager.ProviderJWKs[] memory providerJWKsArray = new IJWKManager.ProviderJWKs[](1);
        providerJWKsArray[0] = providerJWKs;

        // Act
        vm.prank(SYSTEM_CALLER);
        jwkManager.upsertObservedJWKs(providerJWKsArray, new IJWKManager.CrossChainParams[](0));

        // Assert - Should not process
        assertFalse(_getValidatorManagerMock().stakeRegisterValidatorEventEmitted());
        assertFalse(_getDelegationMock().stakeEventEmitted());
    }

    /// @notice Test insufficient contract balance, should emit event with error
    function test_processCrossChainDepositEvent_insufficientBalance_shouldEmitError() public {
        // Arrange - Set contract balance to 0
        vm.deal(address(jwkManager), 0);

        IJWKManager.ProviderJWKs[] memory providerJWKsArray = new IJWKManager.ProviderJWKs[](0);

        // Create CrossChainParams for deposit event
        IJWKManager.CrossChainParams[] memory crossChainParams = new IJWKManager.CrossChainParams[](1);
        crossChainParams[0] = IJWKManager.CrossChainParams({
            id: bytes("1"), // CrossChainDepositEvent
            sender: TEST_USER,
            targetAddress: TEST_TARGET_ADDRESS,
            amount: TEST_DEPOSIT_AMOUNT,
            blockNumber: block.number,
            issuer: TEST_ISSUER,
            data: ""
        });

        // Act & Assert - Expect event with error message
        vm.prank(SYSTEM_CALLER);
        vm.expectEmit(true, true, false, true);
        emit IJWKManager.CrossChainDepositProcessed(
            TEST_USER,
            TEST_TARGET_ADDRESS,
            TEST_DEPOSIT_AMOUNT,
            block.number,
            false,
            "InsufficientContractBalance",
            TEST_ISSUER,
            block.number
        );
        jwkManager.upsertObservedJWKs(providerJWKsArray, crossChainParams);
    }

    /// @notice Test event emission when processing CrossChainDepositEvent
    function test_processCrossChainDepositEvent_shouldEmitEvent() public {
        // Arrange
        IJWKManager.ProviderJWKs[] memory providerJWKsArray = new IJWKManager.ProviderJWKs[](0);

        IJWKManager.CrossChainParams[] memory crossChainParams = new IJWKManager.CrossChainParams[](1);
        crossChainParams[0] = IJWKManager.CrossChainParams({
            id: bytes("1"),
            sender: TEST_USER,
            targetAddress: TEST_TARGET_ADDRESS,
            amount: TEST_DEPOSIT_AMOUNT,
            blockNumber: block.number,
            issuer: TEST_ISSUER,
            data: ""
        });

        // Act & Assert - Expect event to be emitted
        vm.prank(SYSTEM_CALLER);
        vm.expectEmit(true, true, false, true);
        emit IJWKManager.CrossChainDepositProcessed(
            TEST_USER, TEST_TARGET_ADDRESS, TEST_DEPOSIT_AMOUNT, block.number, true, "", TEST_ISSUER, block.number
        );
        jwkManager.upsertObservedJWKs(providerJWKsArray, crossChainParams);
    }

    /// @notice Test onchain block number is updated
    function test_processCrossChainDepositEvent_shouldUpdateBlockNumber() public {
        // Arrange
        uint256 newBlockNumber = block.number + 100;
        IJWKManager.ProviderJWKs[] memory providerJWKsArray = new IJWKManager.ProviderJWKs[](0);

        IJWKManager.CrossChainParams[] memory crossChainParams = new IJWKManager.CrossChainParams[](1);
        crossChainParams[0] = IJWKManager.CrossChainParams({
            id: bytes("1"),
            sender: TEST_USER,
            targetAddress: TEST_TARGET_ADDRESS,
            amount: TEST_DEPOSIT_AMOUNT,
            blockNumber: newBlockNumber,
            issuer: TEST_ISSUER,
            data: ""
        });

        // Act
        vm.prank(SYSTEM_CALLER);
        jwkManager.upsertObservedJWKs(providerJWKsArray, crossChainParams);

        // Assert - Check block number was updated
        (,,, uint256 onchainBlockNumber) = jwkManager.supportedProviders(0);
        assertEq(onchainBlockNumber, newBlockNumber);
    }

    /// @notice Test processing deposit to contract address
    function test_processCrossChainDepositEvent_toContractAddress_shouldSucceed() public {
        // Arrange - Deploy a simple contract
        SimpleReceiver receiver = new SimpleReceiver();
        uint256 initialBalance = address(receiver).balance;

        IJWKManager.ProviderJWKs[] memory providerJWKsArray = new IJWKManager.ProviderJWKs[](0);

        IJWKManager.CrossChainParams[] memory crossChainParams = new IJWKManager.CrossChainParams[](1);
        crossChainParams[0] = IJWKManager.CrossChainParams({
            id: bytes("1"),
            sender: TEST_USER,
            targetAddress: address(receiver),
            amount: TEST_DEPOSIT_AMOUNT,
            blockNumber: block.number,
            issuer: TEST_ISSUER,
            data: ""
        });

        // Act
        vm.prank(SYSTEM_CALLER);
        jwkManager.upsertObservedJWKs(providerJWKsArray, crossChainParams);

        // Assert
        assertEq(address(receiver).balance, initialBalance + TEST_DEPOSIT_AMOUNT);
    }

    /// @notice Test processing deposit with zero amount
    function test_processCrossChainDepositEvent_zeroAmount_shouldSucceed() public {
        // Arrange
        uint256 initialBalance = TEST_TARGET_ADDRESS.balance;

        IJWKManager.ProviderJWKs[] memory providerJWKsArray = new IJWKManager.ProviderJWKs[](0);

        IJWKManager.CrossChainParams[] memory crossChainParams = new IJWKManager.CrossChainParams[](1);
        crossChainParams[0] = IJWKManager.CrossChainParams({
            id: bytes("1"),
            sender: TEST_USER,
            targetAddress: TEST_TARGET_ADDRESS,
            amount: 0,
            blockNumber: block.number,
            issuer: TEST_ISSUER,
            data: ""
        });

        // Act
        vm.prank(SYSTEM_CALLER);
        jwkManager.upsertObservedJWKs(providerJWKsArray, crossChainParams);

        // Assert - Balance should remain the same
        assertEq(TEST_TARGET_ADDRESS.balance, initialBalance);
    }

    /// @notice Test processing deposit with maximum amount
    function test_processCrossChainDepositEvent_maxAmount_shouldSucceed() public {
        // Arrange
        uint256 maxAmount = 100 ether;
        address richTarget = address(0x9999);
        uint256 initialBalance = richTarget.balance;

        IJWKManager.ProviderJWKs[] memory providerJWKsArray = new IJWKManager.ProviderJWKs[](0);

        IJWKManager.CrossChainParams[] memory crossChainParams = new IJWKManager.CrossChainParams[](1);
        crossChainParams[0] = IJWKManager.CrossChainParams({
            id: bytes("1"),
            sender: TEST_USER,
            targetAddress: richTarget,
            amount: maxAmount,
            blockNumber: block.number,
            issuer: TEST_ISSUER,
            data: ""
        });

        // Act
        vm.prank(SYSTEM_CALLER);
        jwkManager.upsertObservedJWKs(providerJWKsArray, crossChainParams);

        // Assert
        assertEq(richTarget.balance, initialBalance + maxAmount);
    }

    /// @notice Test processing deposit with non-existent issuer should still revert in _updateOnchainBlockNumber
    function test_processCrossChainDepositEvent_nonExistentIssuer_shouldRevert() public {
        // Arrange
        IJWKManager.ProviderJWKs[] memory providerJWKsArray = new IJWKManager.ProviderJWKs[](0);

        IJWKManager.CrossChainParams[] memory crossChainParams = new IJWKManager.CrossChainParams[](1);
        crossChainParams[0] = IJWKManager.CrossChainParams({
            id: bytes("1"),
            sender: TEST_USER,
            targetAddress: TEST_TARGET_ADDRESS,
            amount: TEST_DEPOSIT_AMOUNT,
            blockNumber: block.number,
            issuer: "https://non-existent-issuer.com",
            data: ""
        });

        // Act & Assert - This should still revert because _updateOnchainBlockNumber checks the issuer
        vm.prank(SYSTEM_CALLER);
        vm.expectRevert(IJWKManager.IssuerNotFound.selector);
        jwkManager.upsertObservedJWKs(providerJWKsArray, crossChainParams);
    }

    /// @notice Test processing deposit ignores non-"1" event IDs
    function test_processCrossChainDepositEvent_nonOneId_shouldIgnore() public {
        // Arrange
        uint256 initialBalance = TEST_TARGET_ADDRESS.balance;

        IJWKManager.ProviderJWKs[] memory providerJWKsArray = new IJWKManager.ProviderJWKs[](0);

        IJWKManager.CrossChainParams[] memory crossChainParams = new IJWKManager.CrossChainParams[](1);
        crossChainParams[0] = IJWKManager.CrossChainParams({
            id: bytes("99"), // Non-"1" ID
            sender: TEST_USER,
            targetAddress: TEST_TARGET_ADDRESS,
            amount: TEST_DEPOSIT_AMOUNT,
            blockNumber: block.number,
            issuer: TEST_ISSUER,
            data: ""
        });

        // Act
        vm.prank(SYSTEM_CALLER);
        jwkManager.upsertObservedJWKs(providerJWKsArray, crossChainParams);

        // Assert - Balance should not change
        assertEq(TEST_TARGET_ADDRESS.balance, initialBalance);
    }

    // Helper functions to avoid type conversion issues
    function _getValidatorManagerMock() internal pure returns (JWKManagerMock) {
        return JWKManagerMock(payable(VALIDATOR_MANAGER_ADDR));
    }

    function _getDelegationMock() internal pure returns (JWKManagerMock) {
        return JWKManagerMock(payable(DELEGATION_ADDR));
    }
}
