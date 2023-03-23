# Todo List

## Daomon721a.sol

-   ✅ toggleLock
    -   ✅ default locked at mint
    -   ✅ can only be toggled by owner
    -   ✅ during lock the token collects staking time
    -   ✅ at unlock: loose X% of staking time
-   ✅ override beforeTokenTransfer
    -   ✅ token cannot be transfered if locked
-   mint method with access control
