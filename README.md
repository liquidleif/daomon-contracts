# Todo List

## Daomon721a

- toggleLock
  - default locked at mint
  - can only be toggled by owner
  - during lock the token collects staking time
  - at unlock: loosed 20% of staking time
- override beforeTokenTransfer
  - token cannot be transfered if locked
