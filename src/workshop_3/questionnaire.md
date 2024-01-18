## Workshop 3 Assignment:

1. How many sub-accounts does an Ethereum address have on the EVC? How are their addresses calculated?
- 256 subaccounts, Which are calculated by XORing the owning address with the sub-account ID
1. Does the sub-account system decrease the security of user accounts?
- No, because the authentication is handled by evc and all subaccounts are isolated from eachother
1. Provide a couple of use cases for the operator functionality of the EVC.
- Stop loss, take-profit, trailing stop-loss, and hot wallet to perform trades without withdrawals, and self-liquidations
1. What is the main difference between the operator and the controller?
- An account can have multiple operators, but an account can have only one Controller enabled at a time unless it's a transient state
- Operators can be disabled at any time by the user, while controller can't be disabled without repaying/passing checks.
1. What does it mean to defer the account and vault status checks? What is the purpose of this deferral?
- It means delaying the execution of specific verification processes related to the validity and health of accounts and vaults within the system.
- Deferral is used to skip account and vault status checks, which allows for a transient violation of the Account solvency or Vault constraints
1. Why is it useful to allow re-entrancy for `call` and `batch` functions?
- For a vault that use re-entrancy guards, when the vault directly invokes the evc without deferring status checks, the EVC immediately calls back into the vault's `check(Account|Vault)Status` function. This creates a re-entrancy scenario, where the vault function re-enters itself indirectly. Using `call` or `batch` can execute with Account and Vault Status Checks deferred, which would eliminate the re-entrancy
1. How does the simulation feature of the EVC work?
- The simulation works by calling `batchSimulation()`, which works by executing batch and returns data.
- batchSimulation returns data by reverting with the executed data as error data, try-catching that exception, and returning the caught error data
1. Provide a couple of use cases for the `permit` functionality of the EVC.
- Gasless transactions, executing batched transactions, 
1. What is the purpose of the nonce namespace?
- It's a value used in conjunction with Nonce to prevent replaying Permit messages and for sequencing.
1. Why should the EVC neither be given any privileges nor hold any tokens?
- Because the EVC contract can be made to invoke any arbitrary target contract with any arbitrary calldata
