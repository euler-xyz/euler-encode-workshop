## Workshop 3 Assignment:

1. How many sub-accounts does an Ethereum address have on the EVC? How are their addresses calculated?
1. Does the sub-account system decrease the security of user accounts?
1. Provide a couple of use cases for the operator functionality of the EVC.
1. What is the main difference between the operator and the controller?
1. What does it mean to defer the account and vault status checks? What is the purpose of this deferral?
1. Why is it useful to allow re-entrancy for `call` and `batch` functions?
1. How does the simulation feature of the EVC work?
1. Provide a couple of use cases for the `permit` functionality of the EVC.
1. What is the purpose of the nonce namespace?
1. Why should the EVC neither be given any privileges nor hold any tokens?


## Sub-accounts on the EVC:

# Number
 Each Ethereum address can have up to 256 sub-accounts on the EVC.
# Address calculation
 Sub-account addresses are calculated by appending a 2-byte index to the main account address. For example, if your main account address is 0x1234, the first sub-account address would be 0x123401, the second 0x123402, and so on.

## Security implications of sub-accounts

 The sub-account system does not inherently decrease the security of user accounts. Each sub-account has the same level of security as the main account, protected by the same private key.

## Operator functionality use cases:

# DApp interaction
 DApps can designate themselves as operators for user accounts to perform actions on their behalf, streamlining user experience.
# Wallet management
 Wallet providers can use the operator functionality to offer enhanced services like batch transactions and fee optimization.

## Operator vs. controller:

# Operator
 Has limited permissions to execute specific actions on an account, granted by the account owner.
# Controller
 Has full control over an account, including the ability to transfer funds, change settings, and revoke operator permissions.

## Deferred account and vault status checks:

# Meaning
 Delaying the validation of account balances and vault statuses until after transactions are executed.
# Purpose
 Improves efficiency and enables complex interactions that would otherwise be prevented by upfront checks.

## Re-entrancy in call and batch functions:

# Usefulness
 Allows for advanced contract interactions and composability, enabling contracts to call each other recursively.

## Simulation feature:

# Functionality
 Allows users to test transactions and estimate gas costs without actually executing them on-chain.

## permit functionality use cases:

# DeFi interactions
 Permits third-party contracts to spend tokens on behalf of users for decentralized exchange (DEX) trading, lending, and borrowing.
# NFT marketplaces
 Allows for approval of NFT transfers without explicit user confirmation for each transaction.

## Nonce namespace purpose:

# Prevents transaction replay attacks
 Uniquely identifies transactions for a given account and chain ID, ensuring transactions cannot be replayed on a different chain or at a later time.

## EVC security considerations:

Mitigates risk of attacks on the EVC itself.
Enhances security by reducing the potential attack surface.
Promotes trust in the EVC as a neutral and secure execution environment.