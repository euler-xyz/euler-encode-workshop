## Workshop 3 Assignment:

1. How many sub-accounts does an Ethereum address have on the EVC? How are their addresses calculated?
    - An Ethereum address can have up to 256 sub-accounts on the EVC, fully isolated from each other. They're created by XORing the owning address with sub-account ID.
1. Does the sub-account system decrease the security of user accounts?
    - No, the isolation of sub-accounts provides a level of safety as actions in one do not directly affect others through compartmentalization.
1. Provide a couple of use cases for the operator functionality of the EVC.
    - Some uses cases: automated trading by allowing a "hot wallet" to perform trades but not withdrawals, emergency close-out contract that can be executed by a monitoring service, allow external users to perform specific actions on your account based on price levels for example (stop-losses).
1. What is the main difference between the operator and the controller?
    - With controllers, an account can only have one controller at a time and it has control over the collateral assets. For the operators, each sub-account can install one or more operators. They can perform actions on behalf of the account and can be disabled at any time.
1. What does it mean to defer the account and vault status checks? What is the purpose of this deferral?
    - This means delaying these verifications until a later point in the transaction process. For gas optimization and computational load during the operations.
1. Why is it useful to allow re-entrancy for `call` and `batch` functions?
    - 
1. How does the simulation feature of the EVC work?
    - 
1. Provide a couple of use cases for the `permit` functionality of the EVC.
    - 
1. What is the purpose of the nonce namespace?
    - 
1. Why should the EVC neither be given any privileges nor hold any tokens?
    - 
