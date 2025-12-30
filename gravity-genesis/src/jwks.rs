use alloy_sol_macro::sol;
use alloy_sol_types::{SolCall, SolValue};
use revm::{
    db::BundleState,
    primitives::{Env, SpecId, TxEnv},
};
use revm_primitives::{ExecutionResult, hex};
use serde::{Deserialize, Serialize};
use tracing::{debug, error, info, warn};

use crate::{
    post_genesis::handle_execution_result,
    utils::{JWK_MANAGER_ADDR, execute_revm_sequential, new_system_call_txn},
};

// JSON structures for deserialization
#[derive(Debug, Deserialize, Serialize)]
pub struct JsonJWK {
    pub variant: u8,
    pub data: String, // hex string
}

#[derive(Debug, Deserialize, Serialize)]
pub struct JsonProviderJWKs {
    pub issuer: String,
    pub version: u64,
    pub jwks: Vec<JsonJWK>,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct JsonAllProvidersJWKs {
    pub entries: Vec<JsonProviderJWKs>,
}

// JSON structures for OIDC Provider deserialization
#[derive(Debug, Deserialize, Serialize)]
pub struct JsonOIDCProvider {
    pub name: String,
    pub configUrl: String,
    pub active: bool,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct JsonOIDCProviders {
    pub providers: Vec<JsonOIDCProvider>,
}

sol! {
    struct OIDCProvider {
        string name; // Provider name, e.g., "https://accounts.google.com"
        string configUrl; // OpenID configuration URL
        bool active; // Whether the provider is active
        uint64 onchain_block_number; // Onchain block number
    }
    function upsertOIDCProvider(string calldata name, string calldata configUrl) external;
    function getActiveProviders() external view returns (OIDCProvider[] memory);
    struct JWK {
        uint8 variant; // 0: RSA_JWK, 1: UnsupportedJWK
        bytes data; // Encoded JWK data
    }

    /// @dev Provider's JWK collection
    struct ProviderJWKs {
        string issuer; // Issuer
        uint64 version; // Version number
        JWK[] jwks; // JWK array, sorted by kid
    }

    /// @dev All providers' JWK collection
    struct AllProvidersJWKs {
        ProviderJWKs[] entries; // Provider array sorted by issuer
    }

    struct CrossChainParams {
        bytes id;
        address sender;
        address targetAddress;
        uint256 amount;
        uint256 blockNumber;
        string issuer;
        bytes data;
    }

    function upsertObservedJWKs(ProviderJWKs[] calldata providerJWKsArray, CrossChainParams[] calldata crossChainParamsArray) external;
    function getObservedJWKs() external view returns (AllProvidersJWKs memory);
}

/// Create a test RSA JWK
pub fn create_test_rsa_jwk(kid: &str, alg: &str, e: &str, n: &str) -> JWK {
    // Create RSA JWK structure
    let rsa_jwk = RSATestJWK {
        kid: kid.to_string(),
        kty: "RSA".to_string(),
        alg: alg.to_string(),
        e: e.to_string(),
        n: n.to_string(),
    };

    // Encode the RSA JWK
    let encoded_data = rsa_jwk.abi_encode();

    JWK {
        variant: 0, // RSA_JWK
        data: encoded_data.into(),
    }
}

/// Create a test provider JWKs collection
pub fn create_provider_jwks(issuer: &str, version: u64, jwks: Vec<JWK>) -> ProviderJWKs {
    ProviderJWKs {
        issuer: issuer.to_string(),
        version,
        jwks,
    }
}

/// Call upsertObservedJWKs function
pub fn call_upsert_observed_jwks(provider_jwks_array: Vec<ProviderJWKs>, cross_chain_params_array: Vec<CrossChainParams>) -> TxEnv {
    let call_data = upsertObservedJWKsCall {
        providerJWKsArray: provider_jwks_array,
        crossChainParamsArray: cross_chain_params_array,
    }
    .abi_encode();
    new_system_call_txn(JWK_MANAGER_ADDR, call_data.into())
}

/// Call getObservedJWKs function
pub fn call_get_observed_jwks() -> TxEnv {
    let call_data = getObservedJWKsCall {}.abi_encode();
    new_system_call_txn(JWK_MANAGER_ADDR, call_data.into())
}

/// Call upsertOIDCProvider function
pub fn call_upsert_oidc_provider(name: String, config_url: String) -> TxEnv {
    let call_data = upsertOIDCProviderCall {
        name,
        configUrl: config_url,
    }
    .abi_encode();
    new_system_call_txn(JWK_MANAGER_ADDR, call_data.into())
}

/// Call getActiveProviders function
pub fn call_get_active_providers() -> TxEnv {
    let call_data = getActiveProvidersCall {}.abi_encode();
    new_system_call_txn(JWK_MANAGER_ADDR, call_data.into())
}

pub fn read_jwks_from_file(jwks_file_path: &str) -> Result<Vec<ProviderJWKs>, String> {
    let jwks_content = std::fs::read_to_string(jwks_file_path)
        .map_err(|e| format!("Failed to read JWKS file: {}", e))?;

    let jwks: JsonAllProvidersJWKs = serde_json::from_str(&jwks_content)
        .map_err(|e| format!("Failed to parse JWKS file: {}", e))?;

    info!("Successfully loaded JWKs from file");
    info!("Total providers: {}", jwks.entries.len());

    for (i, provider) in jwks.entries.iter().enumerate() {
        info!("Provider {}: {}", i + 1, provider.issuer);
        info!("  Version: {}", provider.version);
        info!("  JWK count: {}", provider.jwks.len());

        for (j, jwk) in provider.jwks.iter().enumerate() {
            info!(
                "    JWK {}: variant={}, data_length={}",
                j + 1,
                jwk.variant,
                jwk.data.len()
            );
        }
    }

    // Convert JSON structure to Solidity structure
    let provider_jwks_array: Result<Vec<ProviderJWKs>, String> = jwks
        .entries
        .into_iter()
        .map(|entry| {
            let jwks: Result<Vec<JWK>, String> = entry
                .jwks
                .into_iter()
                .map(|jwk| {
                    // Convert hex string to bytes
                    let data_bytes = if jwk.data.starts_with("0x") {
                        hex::decode(&jwk.data[2..])
                            .map_err(|e| format!("Failed to decode hex data: {}", e))
                    } else {
                        hex::decode(&jwk.data)
                            .map_err(|e| format!("Failed to decode hex data: {}", e))
                    }?;

                    Ok(JWK {
                        variant: jwk.variant,
                        data: data_bytes.into(),
                    })
                })
                .collect();

            Ok(ProviderJWKs {
                issuer: entry.issuer,
                version: entry.version,
                jwks: jwks?,
            })
        })
        .collect();

    Ok(provider_jwks_array?)
}

/// Read OIDC providers from JSON file
pub fn read_oidc_providers_from_file(
    provider_file_path: &str,
) -> Result<Vec<OIDCProvider>, String> {
    let provider_content = std::fs::read_to_string(provider_file_path)
        .map_err(|e| format!("Failed to read OIDC provider file: {}", e))?;

    let providers: JsonOIDCProviders = serde_json::from_str(&provider_content)
        .map_err(|e| format!("Failed to parse OIDC provider file: {}", e))?;

    info!("Successfully loaded OIDC providers from file");
    info!("Total providers: {}", providers.providers.len());

    for (i, provider) in providers.providers.iter().enumerate() {
        info!("Provider {}: {}", i + 1, provider.name);
        info!("  Config URL: {}", provider.configUrl);
        info!("  Active: {}", provider.active);
    }

    // Convert JSON structure to Solidity structure
    let oidc_providers: Vec<OIDCProvider> = providers
        .providers
        .into_iter()
        .map(|provider| OIDCProvider {
            name: provider.name,
            configUrl: provider.configUrl,
            active: provider.active,
            onchain_block_number: 0,
        })
        .collect();

    Ok(oidc_providers)
}

/// Upsert OIDC providers from file
pub fn upsert_oidc_providers(provider_file_path: &str) -> Result<Vec<TxEnv>, String> {
    info!(
        "=== Loading OIDC providers from file: {} ===",
        provider_file_path
    );

    let oidc_providers = read_oidc_providers_from_file(provider_file_path)?;

    info!("Converted to Solidity structure");
    info!("OIDC providers count: {}", oidc_providers.len());

    // Create transactions for each provider
    let mut transactions = Vec::new();
    for provider in oidc_providers {
        let tx = call_upsert_oidc_provider(provider.name, provider.configUrl);
        transactions.push(tx);
    }

    info!(
        "Created {} upsertOIDCProvider transactions",
        transactions.len()
    );
    for (i, tx) in transactions.iter().enumerate() {
        info!(
            "Transaction {}: data length: {} bytes",
            i + 1,
            tx.data.len()
        );
    }

    info!("OIDC provider upsert transactions prepared successfully");

    Ok(transactions)
}

pub fn upsert_observed_jwks(jwks_file_path: &str) -> Result<TxEnv, String> {
    info!("=== Loading JWKs from file: {} ===", jwks_file_path);

    let provider_jwks_array = read_jwks_from_file(jwks_file_path)?;

    info!("Converted to Solidity structure");
    info!("Provider JWKs array length: {}", provider_jwks_array.len());

    // Create transaction to upsert JWKs with empty crossChainParams array
    let cross_chain_params_array = Vec::<CrossChainParams>::new();
    let upsert_tx = call_upsert_observed_jwks(provider_jwks_array, cross_chain_params_array);

    info!("Created upsertObservedJWKs transaction");
    info!("Transaction data length: {} bytes", upsert_tx.data.len());

    // For now, just return success
    // In a real implementation, you would execute this transaction
    info!("JWK upsert transaction prepared successfully");

    Ok(upsert_tx)
}

pub fn print_jwks_result(result: &ExecutionResult, jwks_file: &str) {
    let provider_jwks_array = read_jwks_from_file(jwks_file).unwrap();

    handle_execution_result(result, "getObservedJWKs", |output_bytes| {
        let solidity_current_epoch_info =
            getObservedJWKsCall::abi_decode_returns(output_bytes, false).unwrap();
        let result_jwks = solidity_current_epoch_info._0.entries;

        // Compare with provider_jwks_array
        for (_i, provider) in result_jwks.iter().enumerate() {
            let provider_jwks = provider_jwks_array
                .iter()
                .find(|p| p.issuer == provider.issuer);
            if let Some(provider_jwks) = provider_jwks {
                assert_eq!(provider_jwks.version, provider.version);
                assert_eq!(provider_jwks.jwks.len(), provider.jwks.len());
                for (j, jwk) in provider_jwks.jwks.iter().enumerate() {
                    assert_eq!(jwk.variant, provider.jwks[j].variant);
                    assert_eq!(jwk.data, provider.jwks[j].data);
                }
            }
        }
    });
}

pub fn print_oidc_providers_result(result: &ExecutionResult, oidc_providers_file: &str) {
    let expected_providers = read_oidc_providers_from_file(oidc_providers_file).unwrap();

    handle_execution_result(result, "getActiveProviders", |output_bytes| {
        let solidity_active_providers =
            getActiveProvidersCall::abi_decode_returns(output_bytes, false).unwrap();
        let result_providers = solidity_active_providers._0;

        info!("Retrieved {} active providers", result_providers.len());
        for (i, provider) in result_providers.iter().enumerate() {
            info!("Provider {}: {}", i + 1, provider.name);
            info!("  Config URL: {}", provider.configUrl);
            info!("  Active: {}", provider.active);

            let expected_provider = expected_providers.iter().find(|p| p.name == provider.name);
            if let Some(expected) = expected_provider {
                assert_eq!(expected.name, provider.name);
                assert_eq!(expected.configUrl, provider.configUrl);
                assert_eq!(expected.active, provider.active);
                info!("  ✓ Provider verified successfully");
            } else {
                info!("  ⚠ Provider not found in expected data");
            }
        }
    });
}

/// Execute JWK management operations
pub fn execute_jwk_operations<DB>(
    db: DB,
    env: Env,
    bundle_state: Option<BundleState>,
) -> Result<(Vec<alloy_primitives::Log>, BundleState), String>
where
    DB: revm::DatabaseRef + Clone,
{
    info!("=== Starting JWK Management Operations ===");

    // Create transaction to get observed JWKs
    let get_tx = call_get_observed_jwks();

    // Execute get transaction
    info!("Executing getObservedJWKs transaction...");
    let get_result = execute_revm_sequential(db, SpecId::LATEST, env, &[get_tx], bundle_state)
        .map_err(|_| "get transaction failed".to_string())?;

    let (get_results, _) = get_result;

    // Check if get was successful and parse the result
    if let Some(result) = get_results.first() {
        if result.is_success() {
            info!("getObservedJWKs transaction successful");

            // Try to decode the result
            if let Some(output) = result.output() {
                match getObservedJWKsCall::abi_decode_returns(output, false) {
                    Ok(decoded_result) => {
                        info!("=== Retrieved JWKs ===");
                        info!("Total providers: {}", decoded_result._0.entries.len());

                        for (i, provider) in decoded_result._0.entries.iter().enumerate() {
                            info!("Provider {}: {}", i + 1, provider.issuer);
                            info!("  Version: {}", provider.version);
                            info!("  JWK count: {}", provider.jwks.len());

                            for (j, jwk) in provider.jwks.iter().enumerate() {
                                info!(
                                    "    JWK {}: variant={}, data_length={}",
                                    j + 1,
                                    jwk.variant,
                                    jwk.data.len()
                                );
                            }
                        }
                    }
                    Err(e) => {
                        warn!("Failed to decode getObservedJWKs result: {:?}", e);
                        debug!("Raw output: {:?}", output);
                    }
                }
            }
        } else {
            return Err(format!("getObservedJWKs failed: {:?}", result));
        }
    }

    todo!()
}

// Helper struct for RSA JWK encoding
sol! {
    struct RSATestJWK {
        string kid;
        string kty;
        string alg;
        string e;
        string n;
    }
}

#[cfg(test)]
mod tests {
    use std::fs;
    use std::path::PathBuf;

    use tracing::Level;

    use crate::{
        execute,
        genesis::GenesisConfig,
        post_genesis::{verify_jwks, verify_oidc_providers},
    };

    use super::*;

    /// Configuration for test paths
    #[derive(Debug, Clone)]
    struct TestConfig {
        /// Base directory for the project (default: current directory)
        base_dir: PathBuf,
        /// Genesis config file path (relative to base_dir)
        genesis_config_path: PathBuf,
        /// JWK template file path (relative to base_dir)
        jwk_template_path: PathBuf,
        /// OIDC provider file path (relative to base_dir)
        oidc_provider_path: PathBuf,
        /// Output directory for genesis generation (relative to base_dir)
        out_dir: PathBuf,
        /// Final output directory (relative to base_dir)
        final_output_dir: PathBuf,
    }

    impl Default for TestConfig {
        fn default() -> Self {
            let base_dir = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            
            // If we're in the gravity-genesis subdirectory, go up to the project root
            let base_dir = if base_dir.ends_with("gravity-genesis") {
                base_dir.parent().unwrap_or(&base_dir).to_path_buf()
            } else {
                base_dir
            };
            
            Self {
                base_dir,
                genesis_config_path: PathBuf::from("generate/genesis_config.json"),
                jwk_template_path: PathBuf::from("generate/jwks_template.json"),
                oidc_provider_path: PathBuf::from("generate/jwks_provider.json"),
                out_dir: PathBuf::from("out"),
                final_output_dir: PathBuf::from("output"),
            }
        }
    }

    impl TestConfig {
        /// Create a new TestConfig with custom base directory
        fn new(base_dir: PathBuf) -> Self {
            Self {
                base_dir,
                genesis_config_path: PathBuf::from("generate/genesis_config.json"),
                jwk_template_path: PathBuf::from("generate/jwks_template.json"),
                oidc_provider_path: PathBuf::from("generate/jwks_provider.json"),
                out_dir: PathBuf::from("out"),
                final_output_dir: PathBuf::from("output"),
            }
        }

        /// Get absolute path for genesis config
        fn genesis_config_abs(&self) -> PathBuf {
            self.base_dir.join(&self.genesis_config_path)
        }

        /// Get absolute path for JWK template
        fn jwk_template_abs(&self) -> PathBuf {
            self.base_dir.join(&self.jwk_template_path)
        }

        /// Get absolute path for OIDC provider
        fn oidc_provider_abs(&self) -> PathBuf {
            self.base_dir.join(&self.oidc_provider_path)
        }

        /// Get absolute path for out directory
        fn out_dir_abs(&self) -> PathBuf {
            self.base_dir.join(&self.out_dir)
        }

        /// Get absolute path for final output directory
        fn final_output_dir_abs(&self) -> PathBuf {
            self.base_dir.join(&self.final_output_dir)
        }

        /// Validate that all required files exist
        fn validate(&self) -> Result<(), Box<dyn std::error::Error>> {
            let required_files = [
                self.genesis_config_abs(),
                self.jwk_template_abs(),
                self.oidc_provider_abs(),
            ];

            for file_path in &required_files {
                if !file_path.exists() {
                    return Err(format!("Required file not found: {}", file_path.display()).into());
                }
            }

            Ok(())
        }
    }

    #[test]
    fn test_after_genesis() {
        let _ = tracing_subscriber::fmt()
            .with_max_level(Level::DEBUG)
            .try_init();

        // Use environment variable to override base directory if needed
        let config = if let Ok(base_dir) = std::env::var("GRAVITY_GENESIS_BASE_DIR") {
            TestConfig::new(PathBuf::from(base_dir))
        } else {
            TestConfig::default()
        };

        // Validate configuration
        if let Err(e) = config.validate() {
            panic!("Test configuration validation failed: {}", e);
        }

        let config_content = fs::read_to_string(config.genesis_config_abs()).unwrap();
        let genesis_config: GenesisConfig = serde_json::from_str(&config_content).unwrap();
        
        let jwk_file_path = config.jwk_template_abs().to_string_lossy().to_string();
        let oidc_file_path = config.oidc_provider_abs().to_string_lossy().to_string();
        
        let (db, bundle_state) = execute::genesis_generate(
            &config.out_dir_abs().to_string_lossy(),
            &config.final_output_dir_abs().to_string_lossy(),
            &genesis_config,
            Some(jwk_file_path.clone()),
            Some(oidc_file_path.clone()),
        );
        
        verify_jwks(db.clone(), bundle_state.clone(), &jwk_file_path);
        verify_oidc_providers(db.clone(), bundle_state.clone(), &oidc_file_path);
    }

    #[test]
    fn test_jwk_creation() {
        let jwk = create_test_rsa_jwk("test-key", "RS256", "AQAB", "test-modulus");
        assert_eq!(jwk.variant, 0);
        assert!(!jwk.data.is_empty());
    }

    #[test]
    fn test_provider_jwks_creation() {
        let jwk = create_test_rsa_jwk("test-key", "RS256", "AQAB", "test-modulus");
        let provider = create_provider_jwks("https://test.com", 1, vec![jwk]);
        assert_eq!(provider.issuer, "https://test.com");
        assert_eq!(provider.version, 1);
        assert_eq!(provider.jwks.len(), 1);
    }

    #[test]
    fn test_json_parsing() {
        // Test JSON parsing with a simple structure
        let json_content = r#"{
            "entries": [
                {
                    "issuer": "https://test.com",
                    "version": 1,
                    "jwks": [
                        {
                            "variant": 1,
                            "data": "0x0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20"
                        }
                    ]
                }
            ]
        }"#;

        let jwks: JsonAllProvidersJWKs = serde_json::from_str(json_content).unwrap();
        assert_eq!(jwks.entries.len(), 1);
        assert_eq!(jwks.entries[0].issuer, "https://test.com");
        assert_eq!(jwks.entries[0].version, 1);
        assert_eq!(jwks.entries[0].jwks.len(), 1);
        assert_eq!(jwks.entries[0].jwks[0].variant, 1);
        assert_eq!(
            jwks.entries[0].jwks[0].data,
            "0x0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20"
        );
    }

    #[test]
    fn test_upsert_observed_jwks() {
        // This test would require a real file, so we'll just test the function signature
        // In a real scenario, you would create a temporary file and test with it
        let result = upsert_observed_jwks("nonexistent_file.json");
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("Failed to read JWKS file"));
    }

    #[test]
    fn test_oidc_provider_parsing() {
        // Test JSON parsing with a simple OIDC provider structure
        let json_content = r#"{
            "providers": [
                {
                    "name": "https://test.com",
                    "configUrl": "https://test.com/.well-known/openid_configuration",
                    "active": true
                },
                {
                    "name": "https://test2.com",
                    "configUrl": "https://test2.com/.well-known/openid_configuration",
                    "active": false
                }
            ]
        }"#;

        let providers: JsonOIDCProviders = serde_json::from_str(json_content).unwrap();
        assert_eq!(providers.providers.len(), 2);
        assert_eq!(providers.providers[0].name, "https://test.com");
        assert_eq!(
            providers.providers[0].configUrl,
            "https://test.com/.well-known/openid_configuration"
        );
        assert_eq!(providers.providers[0].active, true);
        assert_eq!(providers.providers[1].name, "https://test2.com");
        assert_eq!(providers.providers[1].active, false);
    }

    #[test]
    fn test_upsert_oidc_providers() {
        // This test would require a real file, so we'll just test the function signature
        let result = upsert_oidc_providers("nonexistent_provider_file.json");
        assert!(result.is_err());
        assert!(
            result
                .unwrap_err()
                .contains("Failed to read OIDC provider file")
        );
    }
}

// Example usage:
//
// ```rust
// use crate::jwks::upsert_observed_jwks;
//
// // Load and process JWKs from JSON file
// upsert_observed_jwks("path/to/jwks_template.json").expect("Failed to process JWKs");
// ```
