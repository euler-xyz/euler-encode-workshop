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
    - This means delaying these verifications until a later point in the transaction process. For gas optimization and temporary violations of checks during the batch of operations.
1. Why is it useful to allow re-entrancy for `call` and `batch` functions?
    - It's useful for enabling more complex interactions with other contract within batches. This allows a contract to call others and possibly itself in a recursive manner during a single transaction.
1. How does the simulation feature of the EVC work?
    - The simulation mechanics: It calls batchSimulation() instead of batch() because normal batch calls waste gas and don't return any data. However, simulations collect the return data, reverting with this data as error data, try-catching that execption, and returns the caught error data.
1. Provide a couple of use cases for the `permit` functionality of the EVC.
    - This method allows these use cases: delegated transactions allowing another party/address to execute transactions on their behalf without transfering the actual assets. It also streamlines approvals by enabling one-step approval process enhancing UX and saving on transaction costs.
1. What is the purpose of the nonce namespace?
    - They're separate streams of execution orders, check for the state of other namespaces and if they can merge together.
1. Why should the EVC neither be given any privileges nor hold any tokens?
    - This ensures a high level of security and risk management. This way, the EVC cannot autonomously perform actions that might compromise the funds it handles. Moreover, not holding tokens prevents it from becoming a target for theft or hacking.