## Workshop 3 Assignment:

1. How many sub-accounts does an Ethereum address have on the EVC? How are their addresses calculated?
Total 256 sub-account can have for a ethereum address on the EVC, it's basically calculated by doing XOR operation owning address with a unique sub-account ID. These sub-account id's range from 1 to 255, doing xor with the last byte.

1. Does the sub-account system decrease the security of user accounts?
No the sub-accounts are isolated with each other, it's internal within the EVC.So it doesnt decreases security of users account. In fact, it provides a convenient solution for managing multiple positions within a single Ethereum address

1. Provide a couple of use cases for the operator functionality of the EVC.
Each sub-account can install one or more operators also these Operators can perform actions on behalf of the account through authorisation.Can allow external users to perform specific actions on your account based on market conditions.

1. What is the main difference between the operator and the controller?
Operator is just like controller but we cant disable any time we wish for, each sub account can have more than one operators but only one controller vault exists.We can disable the controller only when users account repay his borrowed amount.

1. What does it mean to defer the account and vault status checks? What is the purpose of this deferral?
During multi call batch, the checks made at the end of the batch which is known as deferring checks, main purpose of this deferral is to save gas also preventing transient violations from causing a failure.Vault status checks are for verifying global vault properties like initial state.

1. Why is it useful to allow re-entrancy for `call` and `batch` functions?
Re-entrancy is crucial for preserving the msg.sender in certain situations. For example, when the target contract is the EVC itself, a self-called delegatecall is used to preserve msg.sender. Similarly, when the target contract is not msg.sender, the EVC ensures that the caller has the necessary privileges, and then creates a context to call into the target contract with the provided calldata and onBehalfOfAccount.

1. How does the simulation feature of the EVC work?
 EVC enhances the capabilities of batch calls by allowing the collection and analysis of return data from each item in the batch, even though standard batch calls don't provide such data to the caller. This approach helps users to gain more insights into the success or failure of individual operations within a batch.

1. Provide a couple of use cases for the `permit` functionality of the EVC.
permit simplifies interfaces by enabling users to sign permit messages instead of engaging in direct blockchain transactions, enhancing user experience.Batches can be configured to include items that send tips (ETH, tokens, etc.) to an address chosen by the executor, offering flexibility in rewarding service providers without built-in tip functionality.

1. What is the purpose of the nonce namespace?
 purpose of the nonce namespace is to create separate and distinct "streams" of execution for orders or transactions. Each nonce represents a unique identifier for a transaction within a specific namespace. This separation ensures that transactions from different nonces are distinct and do not interfere with each other. Conditions can be set to check the state of other namespaces, allowing for the merging of streams under certain conditions.

1. Why should the EVC neither be given any privileges nor hold any tokens?
Granting privileges to the EVC poses a security risk, as it could potentially be exploited if it has special privileges. By keeping the EVC without any elevated permissions, the overall security of the system is enhanced, and trust is maintained.By avoiding the holding of tokens or special privileges, the EVC minimizes potential attack vectors.EVC is for crucial for maintaining the security, integrity, and decentralization of the lending market.