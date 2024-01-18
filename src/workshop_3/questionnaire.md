## Workshop 3 Assignment:

### 1. How many sub-accounts does an Ethereum address have on the EVC? How are their addresses calculated?
  Ans:- The Ethereum Virtual Machine includes a clever subsystem of 256 sub-accounts for each address. This expands the potential of each account through derived           addresses calculated by XORing the main address with the sub-account ID.

       For eg: Address (and sub-account 0): 315e56e361882129ae4f68038af45bf6ac6b3c2b
               Sub-account 1:  315e56e361882129ae4f68038af45bf6ac6b3c2b ^ 1 = 315e56e361882129ae4f68038af45bf6ac6b3c2a
               Sub-account 2:  315e56e361882129ae4f68038af45bf6ac6b3c2b ^ 2 = 315e56e361882129ae4f68038af45bf6ac6b3c29

  
### 2. Does the sub-account system decrease the security of user accounts?
  Ans: The sub-account system does not necessarily decrease security since each sub-account is still controlled by the owner's private key. However, it does mean that a single compromised private key could affect multiple isolated sub-accounts.


### 3. Provide a couple of use cases for the operator functionality of the EVC.
 Ans: Following are some of the use cases for the operator functionality of the EVC:

     -  Allowing a contract to implement advanced order types like stop-loss or take-profit on a user's position.
     - Letting a regulated exchange custody assets while still allowing trading.
     - Implementing a social recovery wallet controlled by friends.
     
### 4. What is the main difference between the operator and the controller?

  Ans:The main difference is that an operator can be revoked by the owner at any time, but a controller can only disable itself. Also, operators can modify collateral and controllers, but controllers cannot.

Operators are usually assigned specific, restricted permissions tailored for specific tasks or decisions, highlighting adaptability and oversight. whereas 
      Controllers oversee more crucial aspects, such as managing collateral or carrying out essential financial transactions, playing a central role in the core           activities of the account.

### 5. What does it mean to defer the account and vault status checks? What is the purpose of this deferral?
  Ans: Deferring checks allows users to temporarily violate constraints like collateralization ratio, as long as they are fixed by the end of the transaction. 

The purpose behind this deferral lies in optimizing gas usage and providing flexibility in handling temporary violations during the batch processing.

### 6. Why is it useful to allow re-entrancy for `call` and `batch` functions?
  Ans: Allowing re-entrancy enables contracts called through the EVC to also call other contracts through it. This simplifies their logic.

### 7. How does the simulation feature of the EVC work?
   Ans:  the simulation feature allows users to test and observe the expected intermediate state of their actions before executing an actual transaction. The batchSimulation() function is used to simulate a batch of operations, returning data from each operation for analysis without committing the changes to the blockchain. This can be particularly useful for building a flexible, composition-based UI where users can see the potential outcomes of their transactions before finalizing them.


### 8. Provide a couple of use cases for the `permit` functionality of the EVC.
  Ans:  Here are a couple of scenarios where the permit functionality could be applied:

 - One primary use case for the permit functionality is enabling gasless transactions. Users can sign a batch of transactions using the permit method without needing to directly initiate blockchain transactions.
 - The permit feature can be employed to implement a flexible resting order system within the EVC.


### 8. What is the purpose of the nonce namespace?
  Ans:The nonce namespace allows more flexibility in how permit messages are ordered and reused. Setting namespace=0 and incrementing nonce sequentially is like a regular Ethereum transaction - it must be used once, in order.
But users can also set the namespace deterministically based on the message contents (for example namespace=keccak256(message)). This allows permits with different namespaces to be freely reordered or never used.

So the namespace system allows users to choose the sequencing they need - strict ordering like transactions, or more flexibility.

### 9. Why should the EVC neither be given any privileges nor hold any tokens?
  Ans: The EVC executes arbitrary calls on behalf of users, according to its authentication logic. But the target contract just sees msg.sender as the EVC.
So if the EVC held special privileges like an admin role, owned tokens, or had allowances set - these could potentially be exploited by an attacker crafting clever input data.

For example, if EVC held WETH, a malicious permit could call EVC.withdrawWETH() and steal the tokens.

So the EVC is designed to be a generic message passer that holds no authority itself. The only exception is very brief holding of value/tokens within a single batch call.
