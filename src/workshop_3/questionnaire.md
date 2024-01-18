## Workshop 3 Assignment:

1. How many sub-accounts does an Ethereum address have on the EVC? How are their addresses calculated?
    -> 256 sub-accounts. From 0 to 255. Addresses are created by XOR with their corresponding index
1. Does the sub-account system decrease the security of user accounts?
    -> No they are not. Main address can still be retrieved by checking first 19 bytes of address
1. Provide a couple of use cases for the operator functionality of the EVC.
    -> Allow a hot-wallet to perform trades but not withdrawals 
    -> Allow external user to perform automated action as example of `stop-loss` or `take profit` or `trailing stop` 
1. What is the main difference between the operator and the controller?
    -> You can remove funds from Operator at any time while from a controller there are limitations
1. What does it mean to defer the account and vault status checks? What is the purpose of this deferral?
    -> It means to not perform the checks on time on a batch of transactions but to perform them at the end
    -> It can optimize the efficiency and allow complex interactions among contracts
1. Why is it useful to allow re-entrancy for `call` and `batch` functions?
    -> You can make complex dynamic transaction that are gas efficient
1. How does the simulation feature of the EVC work?
    -> Similar with `batch()` but also collect data, try-catch the errors and return the results at the end
1. Provide a couple of use cases for the `permit` functionality of the EVC.
    -> Allow a user to sign a batch and have someone else to execute it on their behalf
    -> Allow gasless transactions. 
1. What is the purpose of the nonce namespace?
    -> To be able to run separate streams of unrelated transaction and to utilize sub-accounts
1. Why should the EVC neither be given any privileges nor hold any tokens?
    -> It minimize security risks and ensures it's reliability and trust
