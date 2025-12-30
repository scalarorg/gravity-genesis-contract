#!/usr/bin/env python3
"""
Ethereum Account Generator
Generate Ethereum accounts according to mnemonic requirements, output public key, private key and address
"""

import argparse
import json
from eth_account import Account
from eth_keys import keys
import os

def generate_accounts(num_accounts=4):
    """
    Generate specified number of Ethereum accounts
    
    Args:
        num_accounts (int): Number of accounts to generate, default 4
    
    Returns:
        list: List containing account information
    """
    accounts = []
    
    for i in range(num_accounts):
        # Generate new account
        account = Account.create()
        
        # Get private key (hex format, remove 0x prefix)
        private_key = account.key.hex()[2:]
        
        # Generate public key from private key
        private_key_bytes = account.key
        public_key_bytes = keys.PrivateKey(private_key_bytes).public_key
        public_key = public_key_bytes.to_hex()[2:]  # Remove 0x prefix
        
        # Get address
        address = account.address
        
        account_info = {
            "account_index": i + 1,
            "address": address,
            "public_key": public_key,
            "private_key": private_key,
            "mnemonic": account.mnemonic if hasattr(account, 'mnemonic') else None
        }
        
        accounts.append(account_info)
    
    return accounts

def save_accounts_to_file(accounts, filename="account_info.json"):
    """
    Save account information to file
    
    Args:
        accounts (list): List of account information
        filename (str): Output filename
    """
    output_data = {
        "total_accounts": len(accounts),
        "accounts": accounts
    }
    
    with open(filename, 'w', encoding='utf-8') as f:
        json.dump(output_data, f, indent=2, ensure_ascii=False)
    
    print(f"Account information saved to: {filename}")

def print_accounts_summary(accounts):
    """
    Print account information summary
    
    Args:
        accounts (list): List of account information
    """
    print(f"\n=== Generated {len(accounts)} Ethereum accounts ===")
    print("=" * 60)
    
    for i, account in enumerate(accounts, 1):
        print(f"\nAccount {i}:")
        print(f"  Address: {account['address']}")
        print(f"  Public Key: {account['public_key'][:20]}...{account['public_key'][-20:]}")
        print(f"  Private Key: {account['private_key'][:20]}...{account['private_key'][-20:]}")
        print("-" * 40)

def main():
    parser = argparse.ArgumentParser(description='Generate Ethereum account information')
    parser.add_argument(
        '-n', '--num_accounts', 
        type=int, 
        default=4, 
        help='Number of accounts to generate (default: 4)'
    )
    parser.add_argument(
        '-o', '--output', 
        type=str, 
        default='account_info.json', 
        help='Output filename (default: account_info.json)'
    )
    parser.add_argument(
        '--no-save', 
        action='store_true', 
        help='Do not save to file, only display in console'
    )
    
    args = parser.parse_args()
    
    # Validate parameters
    if args.num_accounts <= 0:
        print("Error: Number of accounts must be greater than 0")
        return
    
    if args.num_accounts > 100:
        print("Warning: Generating many accounts may take some time...")
    
    print(f"Generating {args.num_accounts} Ethereum accounts...")
    
    try:
        # Generate accounts
        accounts = generate_accounts(args.num_accounts)
        
        # Print summary
        print_accounts_summary(accounts)
        
        # Save to file (unless specified not to save)
        if not args.no_save:
            save_accounts_to_file(accounts, args.output)
        
        print(f"\n✅ Successfully generated {len(accounts)} accounts!")
        
    except Exception as e:
        print(f"❌ Error occurred while generating accounts: {e}")
        return

if __name__ == "__main__":
    main()
