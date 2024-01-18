## Workshop 3 Assignment:

1. How many sub-accounts does an Ethereum address have on the EVC? How are their addresses calculated?
- Each account has 255 sub accounts and their addresses are calculated by treating the account address as a uint and XORing the last byte with the sub account id with it.

1. Does the sub-account system decrease the security of user accounts?
- No it does not. The sub accounts are completely isolated from each other and interna to the evc. Collateral assets are not accessible in a inter-sub-account manner as well as from the outside, and the user can only access them through the EVC. If funds are sent to a sub account, they are burned.

1. Provide a couple of use cases for the operator functionality of the EVC.
- Some use cases are maybe an EOA or Mulisig that needs to get many approvals before excuting a transaction. You could also have aas an operator, a company wallet to perform operations on behalf of a company or DAO. The most useful use case it to have smart contracts as operators that act as hot wallets and limit the trading operations they can do. Maybe it can open positions based on price movement but not withdraw funds, to ensure security.

1. What is the main difference between the operator and the controller?
- Similar to controlers , operator are other addresses that you give permission to do actions/operations on your behalf. The main difference is that operators can be disabled/removed at any time unlike controllers that you have to get the permission of the controller vault to remove them.

1. What does it mean to defer the account and vault status checks? What is the purpose of this deferral?
- To defer account and vault status checks means to postpone them until the end of a batch transaction to make sure that all the steps in the batch transaction are executed before finally decideing to allow or revert the operation. For example, a user can set up leveraged positions without having all the required collateral by excecuting a batch transaction that first borrows a token, swaps it for an amount of other tokens and puths those tokens against the first borrow position aas collateraal. If the checks were not deferred, the transaction would revert because the user does not initially have enough collateral to open the position.


1. Why is it useful to allow re-entrancy for `call` and `batch` functions?
- It allows for coomplex tx to be excecuted and for status checks to be deferred. It can be avoided by calling through the callThroughEvc modifier. A user calls a batch tx on a vault through the evc, and the evc performs a status check on the vault both on the beginning and in the end allowing for extra security. It also allows features such as atomic operations,  and conditional checks.


1. How does the simulation feature of the EVC work?
- A user calls batchSimulation() on the evc , the evc actually excecutes the given operations in the batch, but just before completing the tx, the tx reverts with error values the values representing the state of the contract during those operations. With this information the user can build a simulation of the batch transaction and see the results before actually executing it.  


1. Provide a couple of use cases for the `permit` functionality of the EVC.
- By signing a permit, a user can give permission to another address to perform a specific action or a batch on their behalf for a tip. This is useful for:

- Gasless transactions --> Users can sign transactions allowing others to pay for gas on their behalf for a tip. Users can also pay with tokens instead of ETH or with LP tokens of other vaults.

- Delegated Transaction Execution --> users can allow others counterparties to excecute transactions on their behalf when certain conditions are met. The counterparty can monitor for example the state of a token and exceute the signed batch when the token reaches a certain price.

1. What is the purpose of the nonce namespace?
- Since we use sub accounts and in ethereum , each account gets a nonce to keep track of the index of the transactions sent from that account, we need to keep track of the nonces of the sub accounts as well. The nonce namespace is useful for the sequencing of transactions in batches and while using permit. For example , you would want to deposit before you borrow in a batch tx. But for unrelated operations, we might want to use random namesapces to avoid nonce collisions. If the nonce namespace for a sub account begins with 0, then sequencing acts just like an EOA. In addtition, we can merge work from different sub accounts into one batch transaction by looking up the namespace of the sub accounts and wait for contidions to be met before excecuting a last mile operation. 


1. Why should the EVC neither be given any privileges nor hold any tokens?
- The core of the evc is to allow authentication accross vaults, not handle any tokens or have any privilages. In addtition, with the batch operation, it allows for complex , potenially malicious txs to be excecuted using calldata so it also becomes a security risk to give it any privilages.
