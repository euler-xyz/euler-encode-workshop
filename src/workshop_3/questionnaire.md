## Workshop 3 Assignment:

1. How many sub-accounts does an Ethereum address have on the EVC? How are their addresses calculated?
A total of 256 subaccounts exists for a particular Ethereum address; these are calculated through the XOR operation with the top subaccountID of the last byte (or two hexadecimal).

1. Does the sub-account system decrease the security of user accounts?
All these subaccounts are tied to the user's Ethereum address. In terms of security, they are fully isolated from one another.But if one private key is exploited through computation of last byte can unlock the private key of orginal account.

1. Provide a couple of use cases for the operator functionality of the EVC.
Each subaccount can have multiple operators. These operators perform on behalf of the owner and allow external users to execute specific actions on the account based on market conditions (profit or loss margin). It also allows the execution of trades from a hot wallet.


1. What is the main difference between the operator and the controller?
For any subaccount, we have total control to disable the operator. In the case of a controller, we don't have this ability because we give limited permissions. We can only disable it until we have a good health factor. Once the debt reaches the threshold of collateral, it becomes impossible to disable the controller.

1. What does it mean to defer the account and vault status checks? What is the purpose of this deferral?
The main purpose of deferral is to reduce gas fees by checking account status at the end of a batch call. During the EVC batch call, all checks are put into a queue and deferred to the end of the batch. Vault status checks are useful for verifying supply and borrow caps, and they depend on the initial state by taking an old snapshot.

1. Why is it useful to allow re-entrancy for `call` and `batch` functions?
By allowing re-entrancy for call and batch functions, the system acknowledges the possibility of contracts calling back into the original caller (e.g., vault calling its own address). The design ensures that when such re-entrancy occurs, it is handled in a controlled manner with the creation of a new context, helping prevent unexpected behavior and potential security vulnerabilities.

1. How does the simulation feature of the EVC work?
The main simulation of EVC uses batchSimulation(). After every call, it returns data and reverts with wrong error data. Try-catching the exception also works with nodes that get mangled errors.

1. Provide a couple of use cases for the `permit` functionality of the EVC.
This is a very standard practice used in ERC-4262, mainly for gasless transactions. Instead of directly triggering the EVC, it's possible to supply signed messages known as permits. Permits, accessible to anyone, execute actions on behalf of the individual who signed the permit message.

1. What is the purpose of the nonce namespace?
NonceNamespace is used to prevent replaying permit messages and for sequencing transactions so that they cannot be executed multiple times. It follows a particular order.

1. Why should the EVC neither be given any privileges nor hold any tokens?
EVC is primarily used for calling the controller. Users can create vaults with any assets; EVC is just the top layer for building any vaults. If we grant privileges since it interacts with every vault, it's dangerous to the assets and distribution of vaults. There is also a chance of leading to the theft of someone else's assets.