## Workshop 3 Assignment:

1. How many sub-accounts does an Ethereum address have on the EVC? How are their addresses calculated?
> 256 and are created by XORing the owning address with the sub-account ID.
2. Does the sub-account system decrease the security of user accounts?
> They provide an option for the sub-account to have operators. Thus, we should be very careful about who we are setting as an operator. It also provides the flexibility by giving up the control of whole account to someone/controller. Thus it improves the security.
3. Provide a couple of use cases for the operator functionality of the EVC.

> Improve private key safety by using multiple hot-wallets for performing DeFi operations.

> Helps in creating roles of Keepers or Watchers.

4. What is the main difference between the operator and the controller?
> The operator has the ability to manage the subaccounts whereas the controller is a vault which controls an account's collateral assets.
5. What does it mean to defer the account and vault status checks? What is the purpose of this deferral?
> Deffered account and vault status checks are required to be satisfied at the end of batch allows them to be temporarily violated mid-batch.
6. Why is it useful to allow re-entrancy for `call` and `batch` functions?
> Allowing re-entrancy for call and batch functions in the Ethereum Vault Connector (EVC) is useful because it facilitates the execution of multiple contract invocations grouped together in batches.
7. How does the simulation feature of the EVC work?
> Normal batch calls do not return any data, but simulations pass through the return data from each item in the batch. This helps the user in predicting the outcome of the batch transaction and saves the user from spending unnecessary gas if the batch transaction was to fail halfway.
8. Provide a couple of use cases for the `permit` functionality of the EVC.

> Creating a dApp with UX such that the contract itself signs the interactions that the user makes, kind of a reverse gas model analogous to the ICP Canisters.

> Can be useful in creating a DEX where users can place limit orders by permitting a batch and they will be executed by the DEX contract when the price feed from the oracle matches the required price.

9. What is the purpose of the nonce namespace?
> Nonce namespaces are Separate “streams” of execution for orders. Also conditions that check for the state of other namespaces can “merge” streams together. This will help in better organization of transactions.
10. Why should the EVC neither be given any privileges nor hold any tokens?
>  Holding tokens could potentially expose the EVC to unauthorized access, manipulation, or vulnerabilities, compromising the integrity and security of the system.
