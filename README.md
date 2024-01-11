# Euler <> Encode Educate

## Usage

Install Foundry:

```sh
curl -L https://foundry.paradigm.xyz | bash
```

This will download foundryup. To start Foundry, run:

```sh
foundryup
```

Clone the repo and install dependencies:

```sh
git clone https://github.com/euler-xyz/euler-encode-workshop.git && cd euler-encode-workshop && forge install && forge update
```

## Slides

Workshop presentation slides can be found here:

* [Workshop 1](https://docs.google.com/presentation/d/1nQfDXEJFMHLgT8JYrPZxzeVS3b5mPBwLhJOuTntjzyo/edit?usp=sharing)
* [Workshop 2](https://docs.google.com/presentation/d/1cYceiIXRDbtpzzimj0QuOh4wY53ZfSjKYaugQz_cql0/edit?usp=sharing)
* [Workshop 3]()

## Assignments

Fork this repository and complete the assignments. Create a PR to merge your solution with the `master` branch of this repository. To do that, follow the instructions:

1. Fork the Repository

First, you need to fork this repository on GitHub. Go to the [repository](https://github.com/euler-xyz/euler-encode-workshop.git) and click the "Fork" button in the upper right corner.

2. Clone and navigate to the Forked Repository

Now, clone the forked repository to your local machine. Replace `your-username` with your GitHub username.

```sh
git clone https://github.com/your-username/euler-encode-workshop.git && cd euler-encode-workshop && forge install && forge update
```

3. Create a New Branch

Create a new branch for your assignment. Replace `branch-name` with the name relevant to the assignment you wish to complete:

|Assignment|`branch-name`|Prize|
|---|---|---|
|Workshop 2 Questionnaire|`assignment-q2`|$500|
|Workshop 3 Questionnaire|`assignment-q3`|$500|
|Workshop 2/3 Coding Assignment|`assignment-c`|$2000|

```sh
git checkout master && git checkout -b branch-name
```

4. Complete the Assignment

At this point, you can start working on the assignment. Make changes to the files as necessary. For details look below.

5. Stage, Commit and Push Your Changes

Once you've completed the assignments, stage and commit your changes. Push your changes to your forked repository on GitHub. Replace `branch-name` accordingly.

```sh
git add . && git commit -m "assignment completed" && git push origin branch-name
```

6. Create a Pull Request

Finally, go back to your forked repository on the GitHub website and click "Pull requests" at the top and then click "New pull request". From the dropdown menu, select the relevant branch of your forked repository and `master` branch of the original repository, then click "Create pull request".

7. Repeat

If you are completing more than one assignment, repeat steps 3-6 for each assignment using different branch names and creating new PRs. If you wish to complete all the assignments, you should have at most 3 PRs. Coding Assignment from both Workshop 2 and 3 should be submitted in the same PR.

### Workshop 2

#### Questionnaire
Answer the EVC related questions tagged with `[ASSIGNMENT]` which can be found in the source [file](./src/workshop_2/WorkshopVault.sol). The questions should be answered inline in the source file.

#### Coding Assignment
Add borrowing functionality to the workshop [vault](./src/workshop_2/WorkshopVault.sol) as per additional instructions in the interface [file](./src/workshop_2/IWorkshopVault.sol). You should not modify the vault constructor, otherwise the tests will not compile. Run `forge compile` or `forge test` before submitting to check if everything's in order.

### Workshop 3

#### Questionnaire
Answer the EVC related questions which can be found in the assignment [file](./src/workshop_3/questionnaire.md). The questions should be answered inline in the file.

#### Coding Assignment
Taking from the EVC operator concept, and using `VaultRegularBorrowable` [contract](https://github.com/euler-xyz/evc-playground/blob/master/src/vaults/VaultRegularBorrowable.sol) from the [evc-playground repository](https://github.com/euler-xyz/evc-playground), build a simple position manager that allows keepers to rebalance assets between multiple vaults of user's choice. Whether the assets should be rebalanced or not should be determined based on a predefined condition, i.e. deposit everything into a vault with the highest APY at the moment, but rebalance no more often than every day. The solution should be provided in the dedicated source [file](./src/workshop_3/PositionManager.sol).

### Resources

1. [EVC docs](https://www.evc.wtf)
1. [EVC repository](https://github.com/euler-xyz/ethereum-vault-connector)
1. [EVC playground repository](https://github.com/euler-xyz/evc-playground)