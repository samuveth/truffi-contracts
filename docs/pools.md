# Truffi Pools Contract Documentation

## Overview

### `Pool`

The `Pool` contract manages an individual pool of tokens/inscriptions, allowing for secure transfers and fee withdrawals only to Pools Manager Contract.

#### Constructor

- `constructor(address token_, address manager_)`
  - Initializes a new pool with the specified token and manager addresses.
  - **Parameters:**
    - `token_`: The ERC20 token address.
    - `manager_`: The address of the pool manager.

#### Functions

- `safeTransfer(address to, uint256 amount) returns (bool)`
  - Transfers the specified amount of tokens securely to the specified address.
  - **Modifiers**: `onlyPoolManager`
  - **Parameters**:
    - `to`: Recipient address.
    - `amount`: Amount of tokens to transfer.

- `withdrawFee(uint256 amount) returns (bool)`
  - Withdraws accumulated fees to the pool manager.
  - **Modifiers**: `onlyPoolManager`
  - **Parameters**:
    - `amount`: Amount of ether to withdraw.

### `Pools`

The `Pools` contract manages multiple `Pool` instances, including creation, destruction of the pools and issuing exchange pool permits which allows to exchange the inscription from specific pool.

#### Constructor

- `constructor(address token_)`
  - Initializes the contract with the specified token address.
  - **Parameters**:
    - `token_`: The ERC20 token address used for pools.

#### Modifiers

- `onlyPoolOwner(address addr)`
  - Ensures that the function is called by the owner of the specified pool.

- `onlyWithValidPermit()`
  - Ensures that the function is called by an address with a valid pool permit.

#### Events

- `OnCreate(SPool)`
  - Emitted when a new pool is created.
- `OnDestroy(SPool)`
  - Emitted when a pool is destroyed.
- `OnRefresh(SPool)`
  - Emitted when a pool is refreshed.
- `OnExchange(uint256 indexed, address indexed, SPool, SInscription)`
  - Emitted on successful exchange transactions.
- `OnSwitch(SPermit)`
  - Emitted when a pool switch is performed.

#### Functions

- `changeSettings(SSettings calldata settings_)`
  - Updates the contract settings.
  - **Modifiers**: `onlyOwner`
  - **Parameters**:
    - `settings_`: New settings to apply.

- `withdraw()`
  - Withdraws all tokens and fees from the Pool Manager contract to the owner.
  - **Modifiers**: `onlyOwner`

- `createPool(uint256 amount) returns (bool)`
  - Creates a new pool with a specified amount of tokens by threshold.
  - **Modifiers**: `nonReentrant`
  - **Parameters**:
    - `amount`: Initial amount of tokens for the pool.

- `refreshPool(address addr) returns (bool)`
  - Refreshes the inscriptions in a specified pool.
  - **Modifiers**: `onlyPoolOwner`, `nonReentrant`
  - **Parameters**:
    - `addr`: Address of the pool to refresh.

- `destroyPool(address addr) returns (bool)`
  - Destroys the specified pool and returns its token balance to the creator of the pool.
  - **Modifiers**: `onlyPoolOwner`, `nonReentrant`
  - **Parameters**:
    - `addr`: Address of the pool to destroy.

- `withdrawPoolFees(address addr) returns (bool)`
  - Withdraws accumulated fees from the specified pool.
  - **Modifiers**: `onlyPoolOwner`
  - **Parameters**:
    - `addr`: Address of the pool.

- `exchangeInscription(uint256 amount, uint256 extra) returns (bool)`
  - Exchanges an inscription within the permited pool by amount and extra criteria.
  - **Modifiers**: `onlyWithValidPermit`, `nonReentrant`
  - **Parameters**:
    - `amount`: Token amount representing the inscription for the exchange.
    - `extra`: Optional Additional criteria to ensure the correct inscription.

- `switchPool() returns (SPermit)`
  - Performs a switch of the current pool and issues the permit.

#### View Functions

- `getPool(address addr) returns (SPool)`
  - Retrieves details of a specified pool.
  - **Parameters**:
    - `addr`: Address of the pool.

- `getPoolByIndex(uint256 index) returns (SPool)`
  - Retrieves pool details by its index.
  - **Parameters**:
    - `index`: Index of the pool.

- `getPoolFee(address addr) returns (uint256)`
  - Retrieves the accumulated fees of a specified pool.
  - **Parameters**:
    - `addr`: Address of the pool.

- `getPermit(address addr) returns (SPermit)`
  - Retrieves the permit details for a specified user address.
  - **Parameters**:
    - `addr`: Address of the user to check their pool permit.
