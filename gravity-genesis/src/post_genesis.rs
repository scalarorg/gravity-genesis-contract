use revm::{DatabaseRef, InMemoryDB, db::BundleState};
use revm_primitives::{ExecutionResult, SpecId, TxEnv, hex};
use tracing::{error, info};

use crate::{
    execute::prepare_env,
    genesis::{
        GenesisConfig, call_get_current_epoch_info, call_get_validator_set,
        print_current_epoch_info_result, print_validator_set_result,
    },
    jwks::{
        call_get_active_providers, call_get_observed_jwks, print_jwks_result,
        print_oidc_providers_result,
    },
    utils::execute_revm_sequential,
};

/// Generic template for handling execution results
///
/// This function provides a common structure for all print_* functions,
/// reducing code duplication and making the codebase more maintainable.
pub fn handle_execution_result<F>(result: &ExecutionResult, function_name: &str, success_handler: F)
where
    F: FnOnce(&[u8]),
{
    match result {
        ExecutionResult::Success { output, .. } => {
            let output_bytes = match output {
                revm_primitives::Output::Call(bytes) => bytes,
                revm_primitives::Output::Create(bytes, _) => bytes,
            };

            info!("=== {} call successful ===", function_name);
            info!("Output length: {} bytes", output_bytes.len());
            info!("Raw output: 0x{}", hex::encode(output_bytes));

            success_handler(output_bytes);
        }
        ExecutionResult::Revert { output, .. } => {
            error!("{} call reverted", function_name);
            error!("Revert output: 0x{}", hex::encode(output));
        }
        ExecutionResult::Halt { reason, .. } => {
            error!("{} call halted: {:?}", function_name, reason);
        }
    }
}

/// Generic template for verification functions
///
/// This function provides a common structure for all verify_* functions,
/// reducing code duplication and making the codebase more maintainable.
fn execute_verification<F>(
    db: impl DatabaseRef,
    bundle_state: BundleState,
    transaction: TxEnv,
    verification_name: &str,
    result_handler: F,
) where
    F: FnOnce(&ExecutionResult),
{
    let env = prepare_env();
    let r = execute_revm_sequential(db, SpecId::LATEST, env, &[transaction], Some(bundle_state));
    
    match r {
        Ok((result, _)) => {
            if let Some(execution_result) = result.get(0) {
                result_handler(execution_result);
            }
        }
        Err(e) => {
            error!(
                "verify {} error: {:?}",
                verification_name,
                e.map_db_err(|_| "Database error".to_string())
            );
        }
    }
}

fn verify_validator_set(db: impl DatabaseRef, bundle_state: BundleState, config: &GenesisConfig) {
    let get_validator_set_txn = call_get_validator_set();
    execute_verification(
        db,
        bundle_state,
        get_validator_set_txn,
        "validator set",
        |result| print_validator_set_result(result, config),
    );
}

fn verify_epoch_info(db: impl DatabaseRef, bundle_state: BundleState) {
    let get_epoch_info_txn = call_get_current_epoch_info();
    execute_verification(
        db,
        bundle_state,
        get_epoch_info_txn,
        "epoch info",
        |result| print_current_epoch_info_result(result),
    );
}

pub fn verify_jwks(db: impl DatabaseRef, bundle_state: BundleState, jwks_file: &str) {
    let get_jwks_txn = call_get_observed_jwks();
    execute_verification(
        db,
        bundle_state,
        get_jwks_txn,
        "jwks",
        |result| print_jwks_result(result, jwks_file),
    );
}

pub fn verify_oidc_providers(
    db: impl DatabaseRef,
    bundle_state: BundleState,
    oidc_providers_file: &str,
) {
    let get_oidc_providers_txn = call_get_active_providers();
    execute_verification(
        db,
        bundle_state,
        get_oidc_providers_txn,
        "oidc providers",
        |result| print_oidc_providers_result(result, oidc_providers_file),
    );
}

pub fn verify_result(
    db: InMemoryDB,
    bundle_state: BundleState,
    config: &GenesisConfig,
    jwks_file: Option<String>,
    oidc_providers_file: Option<String>,
) {
    verify_validator_set(db.clone(), bundle_state.clone(), config);
    verify_epoch_info(db.clone(), bundle_state.clone());
    if let Some(jwks_file) = jwks_file {
        verify_jwks(db.clone(), bundle_state.clone(), &jwks_file);
    }
    if let Some(oidc_providers_file) = oidc_providers_file {
        verify_oidc_providers(db.clone(), bundle_state.clone(), &oidc_providers_file);
    }
}
