## Workshop 3 Assignment:

1. How many sub-accounts does an Ethereum address have on the EVC?
   - How are their addresses calculated? We have 256 sub-accounts per main address. Addresses are calculated by XORing the subaccount ID (0-255) with the main address, changing only the last byte.
   
1. Does the sub-account system decrease the security of user accounts?
   - No, sub-accounts are isolated within the EVC and remain secure unless compromised by allowing malicious operators access.
   
1. Provide a couple of use cases for the operator functionality of the EVC.
   - Automated Trading: Execute trades based on pre-defined conditions like stop-losses for seamless management.
   - Security Measures: Enable automated withdrawal in case of security issues or code vulnerabilities.
   
1. What is the main difference between the operator and the controller?
   - Operators can be removed anytime, while the controller (managed by the vault) cannot be removed unless no debt exists. The controller also has more control, managing vaults and seizing collateral to repay debt if necessary.
   
1. What does it mean to defer the account and vault status checks? What is the purpose of this deferral?
   - Deferring checks means performing them at the end of batch requests instead of individually. This saves gas, especially for leveraged positions reliant on delayed checks.
   
1. Why is it useful to allow re-entrancy for `call` and `batch` functions?
   - Re-entrancy allows efficient multi-call operations within a single transaction, ensuring atomic execution and preventing transaction breaks.
   
1. How does the simulation feature of the EVC work?
   - Simulations work by running batch operations in a simulated environment without affecting the blockchain. This provides insights into potential outcomes and reveals errors without committing real transactions.
   
1. Provide a couple of use cases for the `permit` functionality of the EVC.
   - Authorized Execution: Users can sign a batch and grant permission for execution by third parties on their behalf.
   - Gasless Transactions: Enable gasless transactions, improving user experience for DeFi applications.
   
1. What is the purpose of the nonce namespace?
   - The nonce namespace allows flexible transaction management within sub-accounts. Transactions can be sequenced, executed in any order, and even merged.
   
1. Why should the EVC neither be given any privileges nor hold any tokens?
   - The EVC focuses on providing core functionality for lending-borrowing markets, not holding assets or controlling them directly. The permit function enables granular access management for authorized users and resources.
