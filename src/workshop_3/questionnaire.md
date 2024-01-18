## Workshop 3 Assignment:

1. How many sub-accounts does an Ethereum address have on the EVC? How are their addresses calculated?


Answer: An ethereum address has 256 sub-accounts on the EVC, which are fully isolated from each other.
The sub-account addresses are created by XORing the owning address with sub-account-ID.

1. Does the sub-account system decrease the security of user accounts?

No, the sub-account system does not decrease the security because the EVC handles the authentication.

1. Provide a couple of use cases for the operator functionality of the EVC.

Answer: - It can be used to allow a hot-wallet to
        perform trades but not withdrawals.
        - It can be used to allow external users to perform specific actions on your account based on market conditions.
        - It can be used as an emergency close-out contract that can be executed by a monitoring service.

1. What is the main difference between the operator and the controller?

Answer: The main difference is that the operators can be disabled by the user at any time, where as controllers can only be disabled by itself( usually when the borrowed assets are returned by the user).

1. What does it mean to defer the account and vault status checks? What is the purpose of this deferral?

Answer: To defer the account and vault check means to perform these checks only at the end of a batch of operations. The purpose of doing this is that it is cheaper on gas as it is done only at the end and more importantly deferring the checks at the end also allows the checks to be violated temporarily mid-batc

1. Why is it useful to allow re-entrancy for `call` and `batch` functions?
Answer: For call, its useful because it allows calls to be made through the EVC which allows vault operations to execute within a checks deferred context which helps in efficient transaction execution.
- For Batch, its useful because it allows multiple operations to be executed together which has advantages like atomicity, gas savings and also with the benefit of status check deferrals.

1. How does the simulation feature of the EVC work?

Answer: Simulations work by actually executing the batch and passing through the return data from each item in the batch.It reverts with error data, uses try-catch to catch any exceptions and return the caught error data.

1. Provide a couple of use cases for the `permit` functionality of the EVC.

Answer: 
- permit an be used to allow users to sign a batch and have someone else execute it on their behalf.They are useful for implementing "gasless" transactions.

- It supports both EOAs with EIP-712 and smart contract wallets with ERC-1271 as keepers.

1. What is the purpose of the nonce namespace?
   Answer: The purpose of nonce namespace is to allow separate streams of execution of orders. This allows users to optionally relax the sequencing restrictions and provides them some flexibility in how they wish to order the sequence of transactions.


1. Why should the EVC neither be given any privileges nor hold any tokens?
   Answer: Beacuse the EVC contract can be made to invoke any arbitrary target contract with any arbitrary calldata.

