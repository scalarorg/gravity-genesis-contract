use alloy_sol_macro::sol;
use alloy_sol_types::SolCall;
use revm_primitives::{Address, Bytes, ExecutionResult, FixedBytes, TxEnv, U256, hex};
use serde::{Deserialize, Serialize};
use tracing::{error, info};

use crate::{
    post_genesis::handle_execution_result,
    utils::{EPOCH_MANAGER_ADDR, VALIDATOR_MANAGER_ADDR, new_system_call_txn},
};

#[derive(Debug, Deserialize, Serialize)]
pub struct GenesisConfig {
    #[serde(rename = "validatorAddresses")]
    pub validator_addresses: Vec<String>,
    #[serde(rename = "consensusPublicKeys")]
    pub consensus_public_keys: Vec<String>,
    #[serde(rename = "votingPowers")]
    pub voting_powers: Vec<String>,
    #[serde(rename = "validatorNetworkAddresses")]
    pub validator_network_addresses: Vec<String>,
    #[serde(rename = "fullnodeNetworkAddresses")]
    pub fullnode_network_addresses: Vec<String>,
    #[serde(rename = "aptosAddresses")]
    pub aptos_addresses: Vec<String>,
}

pub struct GenesisInitParam {
    pub validator_addresses: Vec<Address>,
    pub consensus_public_keys: Vec<Bytes>,
    pub voting_powers: Vec<U256>,
    pub validator_network_addresses: Vec<Bytes>,
    pub fullnode_network_addresses: Vec<Bytes>,
    pub aptos_addresses: Vec<Bytes>,
}

fn bytes_to_fixed32(bytes: &Bytes) -> Result<FixedBytes<32>, &'static str> {
    if bytes.len() != 32 {
        return Err("bytes length is not 32");
    }

    let fixed = FixedBytes::<32>::try_from(bytes.as_ref())
        .map_err(|_| "failed to convert to FixedBytes<32>")?;

    Ok(fixed)
}

pub fn parse_genesis_config(config: &GenesisConfig) -> GenesisInitParam {
    // Convert string addresses to Address type
    let validator_addresses: Vec<Address> = config
        .validator_addresses
        .iter()
        .map(|addr| addr.parse::<Address>().expect("Invalid validator address"))
        .collect();
    info!("validator addresses: {:?}", validator_addresses);

    // Convert consensus public keys from hex strings to bytes
    let consensus_public_keys: Vec<Bytes> = config
        .consensus_public_keys
        .iter()
        .map(|key| {
            // GApots would use the following code
            // let public_key = bls12381::PublicKey::try_from(
            //     hex::decode(node_config.consensus_public_key.as_bytes()).unwrap().as_slice(),
            // )
            key.as_bytes().to_vec().into()
            // bcs::to_bytes(&key_str).unwrap().into()
        })
        .collect();

    let voting_powers: Vec<U256> = config
        .voting_powers
        .iter()
        .map(|power| {
            let power_ether = power.parse::<U256>().expect("Invalid voting power");
            // Convert from ether to wei (1 ether = 10^18 wei)
            power_ether * U256::from(10).pow(U256::from(18))
        })
        .collect();

    // Convert validator network addresses from hex strings to bytes
    let validator_network_addresses: Vec<Bytes> = config
        .validator_network_addresses
        .iter()
        .map(|addr| {
            if addr.is_empty() {
                Bytes::new()
            } else {
                // GAptos would use the following code
                // let address_string: String = bcs::from_bytes(&address_bytes).unwrap();
                // println!("address_string: {:?}", address_string);
                // let validator_network_address: NetworkAddress =
                //     NetworkAddress::from_str(&address_string).unwrap();
                bcs::to_bytes(&addr).unwrap().into()
            }
        })
        .collect();

    // Convert fullnode network addresses from hex strings to bytes
    let fullnode_network_addresses: Vec<Bytes> = config
        .fullnode_network_addresses
        .iter()
        .map(|addr| {
            if addr.is_empty() {
                Bytes::new()
            } else {
                bcs::to_bytes(&addr).unwrap().into()
            }
        })
        .collect();

    let aptos_addresses: Vec<Bytes> = config
        .aptos_addresses
        .iter()
        .map(|addr| {
            let bytes: [u8; 32] = hex::decode(addr).unwrap().try_into().unwrap();
            bytes.into()
        })
        .collect();

    let address_from_aptos_address: Vec<Address> = aptos_addresses
        .iter()
        .map(|addr| {
            let address = Address::from_word(bytes_to_fixed32(addr).unwrap());
            address
        })
        .collect();

    for i in 0..validator_addresses.len() {
        if validator_addresses[i] != address_from_aptos_address[i] {
            panic!(
                "❌ Validator address mismatch! Expected: {:?}, Actual: {:?}",
                validator_addresses[i], address_from_aptos_address[i]
            );
        }
    }

    GenesisInitParam {
        validator_addresses,
        consensus_public_keys,
        voting_powers,
        validator_network_addresses,
        fullnode_network_addresses,
        aptos_addresses,
    }
}

pub fn validate_genesis_data_consistency(
    config: &GenesisConfig,
    active_validators: &[IValidatorManager::ValidatorInfo],
) {
    info!("=== Validating Genesis Initial Data Consistency with ValidatorSet Return Data ===");

    let GenesisInitParam {
        validator_addresses,
        consensus_public_keys,
        voting_powers,
        validator_network_addresses,
        fullnode_network_addresses,
        aptos_addresses,
    } = parse_genesis_config(config);
    let expected_count = validator_addresses.len();
    let actual_count = active_validators.len();

    info!("Expected validator count: {}", expected_count);
    info!("Actual validator count: {}", actual_count);

    if expected_count != actual_count {
        error!(
            "❌ Validator count mismatch! Expected: {}, Actual: {}",
            expected_count, actual_count
        );
        return;
    }

    let mut all_match = true;

    for (i, validator) in active_validators.iter().enumerate() {
        info!("--- Validating Validator {} ---", i + 1);

        // Validate operator address
        let expected_operator = validator_addresses[i];
        let actual_operator = validator.operator;

        if expected_operator == actual_operator {
            info!("✅ Operator address matches: {:?}", actual_operator);
        } else {
            error!(
                "❌ Operator address mismatch! Expected: {:?}, Actual: {:?}",
                expected_operator, actual_operator
            );
            all_match = false;
        }

        let expected_aptos_address = aptos_addresses[i].clone();
        let actual_aptos_address = validator.aptosAddress.to_vec();
        if expected_aptos_address == actual_aptos_address {
            info!(
                "✅ Aptos address matches: 0x{}",
                hex::encode(&actual_aptos_address)
            );
        } else {
            error!("❌ Aptos address mismatch!");
            error!("Expected: 0x{}", hex::encode(&expected_aptos_address));
            error!("Actual: 0x{}", hex::encode(&actual_aptos_address));
            all_match = false;
        }

        // Validate consensus public key
        let expected_consensus_key = consensus_public_keys[i].clone();
        let actual_consensus_key = validator.consensusPublicKey.to_vec();

        if expected_consensus_key == actual_consensus_key {
            info!(
                "✅ Consensus public key matches (length: {} bytes)",
                expected_consensus_key.len()
            );
        } else {
            error!("❌ Consensus public key mismatch!");
            error!("Expected: 0x{}", hex::encode(&expected_consensus_key));
            error!("Actual: 0x{}", hex::encode(&actual_consensus_key));
            all_match = false;
        }

        // Validate voting power
        let expected_voting_power = voting_powers[i];
        let actual_voting_power = validator.votingPower;

        if expected_voting_power == actual_voting_power {
            info!("✅ Voting power matches: {}", actual_voting_power);
        } else {
            error!(
                "❌ Voting power mismatch! Expected: {}, Actual: {}",
                expected_voting_power, actual_voting_power
            );
            all_match = false;
        }

        // Validate validator network addresses
        let expected_validator_network_addr = validator_network_addresses[i].clone();
        let actual_validator_network_addr = validator.validatorNetworkAddresses.to_vec();

        if expected_validator_network_addr == actual_validator_network_addr {
            info!(
                "✅ Validator network addresses match (length: {} bytes)",
                expected_validator_network_addr.len()
            );
        } else {
            error!("❌ Validator network addresses mismatch!");
            error!(
                "Expected: {:?}",
                String::from_utf8_lossy(&expected_validator_network_addr)
            );
            error!(
                "Actual: {:?}",
                String::from_utf8_lossy(&actual_validator_network_addr)
            );
            all_match = false;
        }

        // Validate fullnode network addresses
        let expected_fullnode_network_addr = fullnode_network_addresses[i].clone();
        let actual_fullnode_network_addr = validator.fullnodeNetworkAddresses.to_vec();

        if expected_fullnode_network_addr == actual_fullnode_network_addr {
            info!(
                "✅ Fullnode network addresses match (length: {} bytes)",
                expected_fullnode_network_addr.len()
            );
        } else {
            error!("❌ Fullnode network addresses mismatch!");
            error!(
                "Expected: {:?}",
                String::from_utf8_lossy(&expected_fullnode_network_addr)
            );
            error!(
                "Actual: {:?}",
                String::from_utf8_lossy(&actual_fullnode_network_addr)
            );
            all_match = false;
        }

        info!(""); // Empty line separator
    }

    if all_match {
        info!(
            "🎉 All validator data validation passed! Genesis initialization data is completely consistent with ValidatorSet return data."
        );
    } else {
        error!("⚠️  Data inconsistency found, please check the error messages above.");
    }
}

pub fn call_genesis_initialize(genesis_address: Address, config: &GenesisConfig) -> TxEnv {
    let param = parse_genesis_config(config);

    info!("=== Genesis Initialize Parameters ===");
    info!("Genesis address: {:?}", genesis_address);
    info!("Validator addresses: {:?}", param.validator_addresses);
    info!(
        "Consensus public keys count: {}",
        param.consensus_public_keys.len()
    );
    info!("Voting powers: {:?}", param.voting_powers);
    info!(
        "Validator network addresses count: {}",
        param.validator_network_addresses.len()
    );
    info!(
        "Fullnode network addresses count: {}",
        param.fullnode_network_addresses.len()
    );
    info!("Aptos addresses count: {}", param.aptos_addresses.len());

    sol! {
        contract Genesis {
            function initialize(
                address[] calldata validatorAddresses,
                bytes[] calldata consensusPublicKeys,
                uint256[] calldata votingPowers,
                bytes[] calldata validatorNetworkAddresses,
                bytes[] calldata fullnodeNetworkAddresses,
                bytes[] calldata aptosAddresses
            ) external;
        }
    }

    let call_data = Genesis::initializeCall {
        validatorAddresses: param.validator_addresses,
        consensusPublicKeys: param.consensus_public_keys,
        votingPowers: param.voting_powers,
        validatorNetworkAddresses: param.validator_network_addresses,
        fullnodeNetworkAddresses: param.fullnode_network_addresses,
        aptosAddresses: param.aptos_addresses,
    }
    .abi_encode();

    info!("Call data length: {}", call_data.len());
    info!("Call data: 0x{}", hex::encode(&call_data));

    let txn = new_system_call_txn(genesis_address, call_data.into());
    txn
}

sol! {
    interface IValidatorManager {
        #[derive(Debug)]
        enum ValidatorStatus {
            PENDING_ACTIVE, // 0
            ACTIVE, // 1
            PENDING_INACTIVE, // 2
            INACTIVE // 3
        }

        // Commission structure
        struct Commission {
            uint64 rate; // the commission rate charged to delegators(10000 is 100%)
            uint64 maxRate; // maximum commission rate which validator can ever charge
            uint64 maxChangeRate; // maximum daily increase of the validator commission
        }

        /// Complete validator information (merged from multiple contracts)
        struct ValidatorInfo {
            // Basic information (from ValidatorManager)
            bytes consensusPublicKey;
            Commission commission;
            string moniker;
            bool registered;
            address stakeCreditAddress;
            ValidatorStatus status;
            uint256 votingPower; // Changed from uint64 to uint256 to prevent overflow
            uint256 validatorIndex;
            uint256 updateTime;
            address operator;
            bytes validatorNetworkAddresses; // BCS serialized Vec<NetworkAddress>
            bytes fullnodeNetworkAddresses; // BCS serialized Vec<NetworkAddress>
            bytes aptosAddress; // Aptos validator address
        }

        struct ValidatorSet {
            ValidatorInfo[] activeValidators; // Active validators for the current epoch
            ValidatorInfo[] pendingInactive; // Pending validators to leave in next epoch (still active)
            ValidatorInfo[] pendingActive; // Pending validators to join in next epoch
            uint256 totalVotingPower; // Current total voting power
            uint256 totalJoiningPower; // Total voting power waiting to join in the next epoch
        }

        function getValidatorSet() external view returns (ValidatorSet memory);
    }
}

sol! {
    contract IEpochManager {
        function getCurrentEpochInfo() external view returns (uint256 epoch, uint256 lastTransitionTime, uint256 duration);
    }
}
pub fn call_get_validator_set() -> TxEnv {
    let call_data = IValidatorManager::getValidatorSetCall {}.abi_encode();
    new_system_call_txn(VALIDATOR_MANAGER_ADDR, call_data.into())
}

pub fn call_get_current_epoch_info() -> TxEnv {
    let call_data = IEpochManager::getCurrentEpochInfoCall {}.abi_encode();
    new_system_call_txn(EPOCH_MANAGER_ADDR, call_data.into())
}

pub fn print_validator_set_result(result: &ExecutionResult, config: &GenesisConfig) {
    handle_execution_result(result, "getValidatorSet", |output_bytes| {
        let solidity_validator_set =
            IValidatorManager::getValidatorSetCall::abi_decode_returns(output_bytes, false)
                .unwrap();

        let active_validators = &solidity_validator_set._0.activeValidators;
        info!("Active validators count: {}", active_validators.len());

        // Validate consistency between initial data and returned data
        validate_genesis_data_consistency(config, active_validators);
    });
}

pub fn print_current_epoch_info_result(result: &ExecutionResult) {
    handle_execution_result(result, "getCurrentEpochInfo", |output_bytes| {
        let solidity_current_epoch_info =
            IEpochManager::getCurrentEpochInfoCall::abi_decode_returns(output_bytes, false)
                .unwrap();

        info!(
            "Current epoch info: {:?}",
            solidity_current_epoch_info.epoch
        );
    });
}
