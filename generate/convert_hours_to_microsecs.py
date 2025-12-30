#!/usr/bin/env python3
"""
Convert hours to microseconds for EpochManager configuration.
This script ensures proper integer conversion for Solidity uint256 compatibility.
"""

import sys
import math

def hours_to_microseconds(hours):
    """
    Convert hours to microseconds.
    
    Args:
        hours (float): Hours as a decimal number
        
    Returns:
        int: Microseconds as an integer
    """
    # Convert hours to seconds, then to microseconds
    seconds = hours * 3600
    microseconds = int(seconds * 1_000_000)
    return microseconds

def main():
    if len(sys.argv) != 2:
        print("Usage: python3 convert_hours_to_microsecs.py <hours>", file=sys.stderr)
        sys.exit(1)
    
    try:
        hours = float(sys.argv[1])
        if hours <= 0:
            print("Error: Hours must be positive", file=sys.stderr)
            sys.exit(1)
        
        microseconds = hours_to_microseconds(hours)
        print(microseconds)
        
    except ValueError:
        print("Error: Invalid number format", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
