use crate::{
    genesis::{GenesisConfig, call_genesis_initialize},
    jwks::{upsert_observed_jwks, upsert_oidc_providers},
    utils::{
        CONTRACTS, GENESIS_ADDR, SYSTEM_ACCOUNT_INFO, SYSTEM_CALLER, analyze_txn_result,
        execute_revm_sequential, read_hex_from_file,
    },
};

use alloy_chains::NamedChain;

use revm::{
    InMemoryDB,
    db::{BundleState, PlainAccount},
    primitives::{AccountInfo, Env, SpecId, U256},
};
use revm_primitives::{Bytecode, Bytes, TxEnv, hex};
use std::{collections::HashMap, fs::File, io::BufWriter};
use tracing::{debug, error, info, warn};

// Alternative approach: Use BSC-style direct bytecode deployment
fn deploy_bsc_style(byte_code_dir: &str) -> InMemoryDB {
    let mut db = InMemoryDB::default();

    // Add system address with balance
    db.insert_account_info(SYSTEM_CALLER, SYSTEM_ACCOUNT_INFO);

    for (contract_name, target_address) in CONTRACTS {
        let hex_path = format!("{}/{}.hex", byte_code_dir, contract_name);
        let bytecode_hex = read_hex_from_file(&hex_path);

        // For BSC style, we need to extract runtime bytecode from constructor bytecode
        // This is a simplified approach - in reality, we'd need to execute the constructor
        // and extract the returned bytecode
        let runtime_bytecode = extract_runtime_bytecode(&bytecode_hex);

        // Set large balance for JWK Manager and Validator Manager
        let balance = if contract_name == "JwkManager" || contract_name == "ValidatorManager" || contract_name == "Genesis" {
            // Set 1 million ETH balance (1e6 * 1e18 wei)
            U256::from(1_000_000) * U256::from(10).pow(U256::from(18))
        } else {
            U256::ZERO
        };

        db.insert_account_info(
            target_address,
            AccountInfo {
                code: Some(Bytecode::new_raw(Bytes::from(runtime_bytecode))),
                balance,
                ..AccountInfo::default()
            },
        );

        if balance > U256::ZERO {
            info!(
                "Deployed {} runtime bytecode to {:?} with balance {} ETH",
                contract_name, target_address, balance / U256::from(10).pow(U256::from(18))
            );
        } else {
            info!(
                "Deployed {} runtime bytecode to {:?}",
                contract_name, target_address
            );
        }
    }

    db
}

// Extract runtime bytecode from constructor bytecode
// This is a simplified implementation - in reality, we'd need to execute the constructor
fn extract_runtime_bytecode(constructor_bytecode: &str) -> Vec<u8> {
    // For now, we'll try to detect if this is constructor bytecode or runtime bytecode
    let bytes = hex::decode(constructor_bytecode).unwrap_or_default();

    // Simple heuristic: if the bytecode starts with typical constructor patterns,
    // we need to extract the runtime part
    if bytes.len() > 100 && (bytes[0] == 0x60 || bytes[0] == 0x61) {
        // This looks like constructor bytecode
        // For now, we'll use a simplified approach and return the original bytecode
        // In a real implementation, we'd execute the constructor and extract the returned bytecode
        warn!("   [!] Warning: Using constructor bytecode as runtime bytecode");
        bytes
    } else {
        // This looks like runtime bytecode already
        bytes
    }
}

pub fn prepare_env() -> Env {
    let mut env = Env::default();
    env.cfg.chain_id = NamedChain::Mainnet.into();
    env.tx.gas_limit = 30_000_000;
    env
}

/// Transaction builder for genesis initialization
struct GenesisTransactionBuilder {
    transactions: Vec<TxEnv>,
}

impl GenesisTransactionBuilder {
    fn new(config: &GenesisConfig) -> Self {
        let transactions = vec![call_genesis_initialize(GENESIS_ADDR, config)];
        Self { transactions }
    }

    fn with_jwks(mut self, jwks_file: Option<String>) -> Self {
        if let Some(jwks_file) = jwks_file {
            let jwks_tx = upsert_observed_jwks(&jwks_file).expect("Failed to upsert observed JWKs");
            self.transactions.push(jwks_tx);
            info!("Added JWKs transaction from file: {}", jwks_file);
        }
        self
    }

    fn with_oidc_providers(mut self, oidc_providers_file: Option<String>) -> Self {
        if let Some(oidc_providers_file) = oidc_providers_file {
            let oidc_txs = upsert_oidc_providers(&oidc_providers_file)
                .expect("Failed to upsert OIDC providers");
            let oidc_txs_count = oidc_txs.len();
            self.transactions.extend(oidc_txs);
            info!(
                "Added {} OIDC provider transactions from file: {}",
                oidc_txs_count, oidc_providers_file
            );
        }
        self
    }

    fn build(self) -> Vec<TxEnv> {
        info!(
            "Built {} total genesis transactions",
            self.transactions.len()
        );
        self.transactions
    }
}

/// Build genesis transactions using builder pattern
fn build_genesis_transactions(
    config: &GenesisConfig,
    jwks_file: Option<String>,
    oidc_providers_file: Option<String>,
) -> Vec<TxEnv> {
    GenesisTransactionBuilder::new(config)
        .with_jwks(jwks_file)
        .with_oidc_providers(oidc_providers_file)
        .build()
}

pub fn genesis_generate(
    byte_code_dir: &str,
    output_dir: &str,
    config: &GenesisConfig,
    jwks_file: Option<String>,
    oidc_providers_file: Option<String>,
) -> (InMemoryDB, BundleState) {
    info!("=== Starting Genesis deployment and initialization ===");

    let db = deploy_bsc_style(byte_code_dir);

    let env = prepare_env();

    let txs = build_genesis_transactions(config, jwks_file, oidc_providers_file);

    let r = execute_revm_sequential(db.clone(), SpecId::LATEST, env.clone(), &txs, None);
    let (result, mut bundle_state) = match r {
        Ok((result, bundle_state)) => {
            info!("=== Genesis initialization successful ===");
            (result, bundle_state)
        }
        Err(e) => {
            panic!(
                "Error: {}",
                format!("{:?}", e.map_db_err(|_| "Database error".to_string()))
            );
        }
    };
    debug!("the bundle state is {:?}", bundle_state);
    let ret = (db, bundle_state.clone());

    for (i, r) in result.iter().enumerate() {
        if !r.is_success() {
            error!("=== Transaction {} failed ===", i + 1);
            println!("Detailed analysis: {}", analyze_txn_result(r));
            panic!("Genesis transaction {} failed", i + 1);
        } else {
            info!("Detailed analysis: {}", analyze_txn_result(r));
        }
    }
    info!(
        "=== All {} transactions completed successfully ===",
        result.len()
    );

    // Add deployed contracts to the final state
    let mut genesis_state = HashMap::new();

    for (contract_name, contract_address) in CONTRACTS {
        let hex_path = format!("{}/{}.hex", byte_code_dir, contract_name);
        let bytecode_hex = read_hex_from_file(&hex_path);
        let runtime_bytecode = extract_runtime_bytecode(&bytecode_hex);

        genesis_state.insert(
            contract_address,
            PlainAccount {
                info: AccountInfo {
                    code: Some(Bytecode::new_raw(Bytes::from(runtime_bytecode))),
                    ..AccountInfo::default()
                },
                storage: Default::default(),
            },
        );

        info!(
            "Added {} to genesis state at {:?}",
            contract_name, contract_address
        );
    }

    // Add any state changes from the bundle_state (from the initialize transaction)
    bundle_state.state.remove(&SYSTEM_CALLER);
    // write bundle state into one json file named bundle_state.json
    serde_json::to_writer_pretty(
        BufWriter::new(File::create(format!("{output_dir}/bundle_state.json")).unwrap()),
        &bundle_state,
    )
    .unwrap();

    info!(
        "bundle state size is {:?}, contracts size {:?}",
        bundle_state.state.len(),
        CONTRACTS.len()
    );
    for (address, account) in bundle_state.state.into_iter() {
        debug!("Address: {:?}, account: {:?}", address, account);
        if let Some(info) = account.info {
            let storage = account
                .storage
                .into_iter()
                .map(|(k, v)| (k, v.present_value()))
                .collect();

            // If this address already exists in genesis_state, merge the storage
            if let Some(existing) = genesis_state.get_mut(&address) {
                existing.storage.extend(storage);
                existing.info = info;
            } else {
                genesis_state.insert(address, PlainAccount { info, storage });
            }
        }
    }

    serde_json::to_writer_pretty(
        BufWriter::new(File::create(format!("{output_dir}/genesis_accounts.json")).unwrap()),
        &genesis_state,
    )
    .unwrap();

    // Create contracts JSON with bytecode
    let contracts_json: HashMap<_, _> = genesis_state
        .iter()
        .filter_map(|(addr, account)| {
            account
                .info
                .code
                .as_ref()
                .map(|code| (*addr, code.bytecode()))
        })
        .collect();

    serde_json::to_writer_pretty(
        BufWriter::new(File::create(format!("{output_dir}/genesis_contracts.json")).unwrap()),
        &contracts_json,
    )
    .unwrap();
    ret
}
