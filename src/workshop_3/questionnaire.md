## Workshop 3 Assignment:

1. How many sub-accounts does an Ethereum address have on the EVC? How are their addresses calculated?
```
The EVC gives every Ethereum address 256 sub-accounts. The sub-accounts are calculated by taking the first 19 bytes of the Ethereum address and appending the sub-account ID. Or in other words, by XORing the main address with the sub-account ID.
```

1. Does the sub-account system decrease the security of user accounts?
```
 No, it doesn't. Security is handled by the EVC. Also, sub-account addresses should never
escape into any other system as they're internal to the EVC.
```
1. Provide a couple of use cases for the operator functionality of the EVC.
```
They allow a hot wallet to perform certain actions on behalf of the user like trades but doesn't include withdrawals. 
Sub-accounts also make it possible to implement social recovery mechanisms.
```
1. What is the main difference between the operator and the controller?
```
An operator can interact with vaults for the specified account (withdraw/borrow funds, enable as collateral, etc).

A controller on the other hand has ultimate control over the account's collateral. It can manage any vault in the collateral set, including seizing collateral to repay debt. It cannot change the account's controller set. 
```
1. What does it mean to defer the account and vault status checks? What is the purpose of this deferral?
```
Deferred checks in the EVC are a mechanism that allows certain account and vault status checks to be postponed until the very end of a transaction. 
Deferred checks allow temporary violation of vault constraints during a transaction, as long as everything aligns with the rules when the transaction finalizes.
```
1. Why is it useful to allow re-entrancy for `call` and `batch` functions?
```
Re-entrancy for call and batch functions enables complex interactions and strategies that require recursive or interdependent actions within a single transaction.
```
1. How does the simulation feature of the EVC work?
```
The EVC simulates batch execution by temporarily performing operations and then reverting, allowing for outcome previews without committing state changes.
```
1. Provide a couple of use cases for the `permit` functionality of the EVC.
```
Gasless transactions is a major use case of the permit functionality of the EVC. 
Another use case is the implementation of smart contract wallets.
```
1. What is the purpose of the nonce namespace?
```
The purpose of the nonce namespace in permit messages is to provide flexibility and control over transaction sequencing.
```
1. Why should the EVC neither be given any privileges nor hold any tokens?
```
The EVC can be instructed to invoke any arbitrary target contract with any arbitrary calldata. As such, if compromised, an attacker could exploit this feature to execute malicious code, potentially stealing funds or disrupting operations.
```