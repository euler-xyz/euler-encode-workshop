## Workshop 3 Assignment:

1. How many sub-accounts does an Ethereum address have on the EVC? How are their addresses calculated?
```
EVC gives every Ethereum account 256 sub-accounts. Sub-account addresses are created by XORing the owning address with the sub-account ID.
```
1. Does the sub-account system decrease the security of user accounts?
```
No, the sub-account system does not decrease the security of the user accounts. 
```
1. Provide a couple of use cases for the operator functionality of the EVC.
```
(i) It can allow a hot-wallet to perform trades but not withdrawals. And (ii) It can allow external users to perform specific actions on the account based on market conditions.
```
1. What is the main difference between the operator and the controller?
```
An account can only have one controller at a time, which has control over its collateral assets. On the other hand, each sub-account can install one or more operators. The main difference is that operators can be removed at any time unlike controllers that you have to get the permission of the controller vault to remove them.
```
1. What does it mean to defer the account and vault status checks? What is the purpose of this deferral?
```
Deferring an account and vault status checks in the EVC means placing them in a queue to be verified later. The purpose of this deferral is to reduce the gas costs and it allows the checks to be temporarily violated mid-batch.

```
1. Why is it useful to allow re-entrancy for `call` and `batch` functions?
```
It helps improve the efficiency and flexibility of transaction processing.
```
1. How does the simulation feature of the EVC work?
```
User add operations to the builder and only when the conditions are satisfied the transaction is executed.
```
1. Provide a couple of use cases for the `permit` functionality of the EVC.
```
The permit method allows users to sign the batch and have another entity execute it on their behalf.
Some use cases are (i) it enables user interfaces without onchain transactions (gasless transactions), and (ii) it allows for conditional or contingent orders.
```
1. What is the purpose of the nonce namespace?
```
The nonce namespace is useful to segment streams of execution orders.
```
1. Why should the EVC neither be given any privileges nor hold any tokens?
```
The EVC should not be given any privileges or hold any tokens due to the risks associated with its ability to execute arbitrary calldata.
```
